import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rotas_app/data/dao/geocache_dao.dart';
import 'package:rotas_app/data/dao/ponto_dao.dart';
import 'package:rotas_app/data/dao/preferencias_dao.dart';
import 'package:rotas_app/data/dao/rota_dao.dart';
import 'package:rotas_app/data/dao/usuario_dao.dart';
import 'package:rotas_app/data/database/database_helper.dart';
import 'package:rotas_app/data/repositories/ponto_repository.dart';
import 'package:rotas_app/data/repositories/rota_repository.dart';
import 'package:rotas_app/models/rota.dart';
import 'package:rotas_app/services/geocodificacao_service.dart';
import 'package:rotas_app/services/otimizador_rota_service.dart';
import 'package:rotas_app/services/roteamento_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'apoio/banco_teste.dart';

/// Resposta simulada do Nominatim, no formato devolvido pelo serviço.
String _respostaNominatim(String lat, String lon) => jsonEncode([
      {
        'lat': lat,
        'lon': lon,
        'display_name': 'Endereço simulado, Londrina - PR, Brasil',
      }
    ]);

/// Resposta simulada do OSRM para um trajeto de 2,5 km em 5 minutos.
String _respostaOsrm() => jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'distance': 2500.0,
          'duration': 300.0,
          'geometry': {
            'type': 'LineString',
            // O GeoJSON usa [longitude, latitude].
            'coordinates': [
              [-51.1628, -23.3103],
              [-51.1650, -23.3150],
              [-51.1700, -23.3200],
            ],
          },
        }
      ],
    });

void main() {
  setUpAll(prepararSqflite);

  group('esquema do banco', () {
    late Database db;

    setUp(() async => db = await abrirBancoEmMemoria());
    tearDown(() async => db.close());

    test('cria todas as tabelas do sistema', () async {
      final linhas = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name");
      final tabelas = linhas.map((linha) => linha['name'] as String).toSet();

      expect(
        tabelas,
        containsAll(<String>[
          'pontos',
          'rotas',
          'rota_pontos',
          'usuarios',
          'sessao',
          'geocache',
          'preferencias',
        ]),
      );
    });

    test('a tabela de pontos já nasce com o vínculo ao usuário', () async {
      final colunas = await db.rawQuery('PRAGMA table_info(pontos)');
      expect(
        colunas.map((coluna) => coluna['name']),
        containsAll(<String>['id', 'nome', 'endereco', 'latitude', 'longitude', 'id_usuario']),
      );
    });

    test('a versão do esquema é a esperada', () async {
      expect(DatabaseHelper.versaoAtual, 4);
    });
  });

  group('migração de um banco na versão 1', () {
    late Database db;

    setUp(() async {
      // Recria exatamente o esquema da primeira entrega do projeto.
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (banco, _) async {
            await banco.execute('''
              CREATE TABLE pontos (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                nome TEXT NOT NULL,
                endereco TEXT NOT NULL,
                latitude REAL,
                longitude REAL
              )
            ''');
          },
        ),
      );
    });

    tearDown(() async => db.close());

    test('preserva os pontos cadastrados e acrescenta as novas tabelas',
        () async {
      await db.insert('pontos', {
        'nome': 'Ponto anterior',
        'endereco': 'Rua Antiga, 100',
        'latitude': -23.31,
        'longitude': -51.16,
      });

      await DatabaseHelper.aplicarMigracoes(db, 1, 4);

      // Os dados continuam lá, agora com a coluna nova sem valor.
      final pontos = await db.query('pontos');
      expect(pontos, hasLength(1));
      expect(pontos.first['nome'], 'Ponto anterior');
      expect(pontos.first['id_usuario'], isNull);

      final colunas = await db.rawQuery('PRAGMA table_info(pontos)');
      expect(colunas.map((coluna) => coluna['name']), contains('id_usuario'));

      final linhas = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      final tabelas = linhas.map((linha) => linha['name'] as String).toSet();
      expect(
        tabelas,
        containsAll(<String>[
          'rotas',
          'rota_pontos',
          'usuarios',
          'sessao',
          'geocache',
          'preferencias',
        ]),
      );
    });

    test('pode ser aplicada sem banco anterior (instalação nova)', () async {
      await DatabaseHelper.aplicarMigracoes(db, 0, 4);

      final linhas = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'");
      final tabelas = linhas.map((linha) => linha['name'] as String).toSet();
      // A tabela pontos já existia neste cenário, então não é recriada; as
      // novas precisam existir.
      expect(
        tabelas,
        containsAll(<String>['rotas', 'rota_pontos', 'usuarios', 'preferencias']),
      );
    });
  });

  group('PontoDao e GeocacheDao', () {
    late Database db;
    late PontoDao pontoDao;
    late GeocacheDao geocacheDao;
    late UsuarioDao usuarioDao;

    setUp(() async {
      db = await abrirBancoEmMemoria();
      pontoDao = PontoDao(() async => db);
      geocacheDao = GeocacheDao(() async => db);
      usuarioDao = UsuarioDao(() async => db);
    });

    tearDown(() async => db.close());

    test('insere, consulta, atualiza e exclui', () async {
      final id = await pontoDao.inserir(pontoComCoordenada('Mercado', -23.31, -51.16));
      expect(id, greaterThan(0));

      final encontrado = await pontoDao.buscarPorId(id);
      expect(encontrado?.nome, 'Mercado');

      await pontoDao.atualizar(encontrado!.copyWith(nome: 'Mercado Central'));
      expect((await pontoDao.buscarPorId(id))?.nome, 'Mercado Central');

      expect(await pontoDao.contar(), 1);
      await pontoDao.excluir(id);
      expect(await pontoDao.contar(), 0);
    });

    test('lista por usuário incluindo os registros ainda sem dono', () async {
      final idUsuario = await usuarioDao.inserir(
        usuarioDeTeste('Ana', 'ana@exemplo.com'),
      );
      await pontoDao.inserir(pontoComCoordenada('Da Ana', 0, 0, idUsuario: idUsuario));
      await pontoDao.inserir(pontoComCoordenada('Legado', 0, 1));

      final daAna = await pontoDao.listar(idUsuario: idUsuario);
      expect(daAna.map((ponto) => ponto.nome), containsAll(['Da Ana', 'Legado']));
    });

    test('vincula os pontos sem dono a um usuário', () async {
      final idUsuario = await usuarioDao.inserir(
        usuarioDeTeste('Ana', 'ana@exemplo.com'),
      );
      await pontoDao.inserir(pontoComCoordenada('Legado', 0, 0));

      final vinculados = await pontoDao.vincularPontosLegados(idUsuario);

      expect(vinculados, 1);
      expect((await pontoDao.listar(idUsuario: idUsuario)).first.idUsuario,
          idUsuario);
    });

    test('o cache de endereços ignora diferenças de caixa e espaços', () async {
      await geocacheDao.salvar('Av.  Maringá,  134', -23.31, -51.16);

      final achado = await geocacheDao.buscar('av. maringá, 134');
      expect(achado, isNotNull);
      expect(achado!.latitude, closeTo(-23.31, 1e-9));
      expect(await geocacheDao.contar(), 1);
    });

    test('devolve nulo para endereço não consultado', () async {
      expect(await geocacheDao.buscar('nunca visto'), isNull);
    });
  });

  group('PreferenciasDao', () {
    late Database db;
    late PreferenciasDao dao;

    setUp(() async {
      db = await abrirBancoEmMemoria();
      dao = PreferenciasDao(() async => db);
    });

    tearDown(() async => db.close());

    test('grava, lê e sobrescreve um valor', () async {
      expect(await dao.ler(PreferenciasDao.chaveUltimoEmail), isNull);

      await dao.gravar(PreferenciasDao.chaveUltimoEmail, 'ana@exemplo.com');
      expect(
        await dao.ler(PreferenciasDao.chaveUltimoEmail),
        'ana@exemplo.com',
      );

      await dao.gravar(PreferenciasDao.chaveUltimoEmail, 'bruno@exemplo.com');
      expect(
        await dao.ler(PreferenciasDao.chaveUltimoEmail),
        'bruno@exemplo.com',
      );
      // A gravação substitui o valor, sem criar uma segunda linha.
      expect(await db.query(DatabaseHelper.tabelaPreferencias), hasLength(1));
    });

    test('remove um valor', () async {
      await dao.gravar(PreferenciasDao.chaveManterConectado, '0');
      await dao.remover(PreferenciasDao.chaveManterConectado);
      expect(await dao.ler(PreferenciasDao.chaveManterConectado), isNull);
    });
  });

  group('RotaDao', () {
    late Database db;
    late PontoDao pontoDao;
    late RotaDao rotaDao;

    setUp(() async {
      db = await abrirBancoEmMemoria();
      pontoDao = PontoDao(() async => db);
      rotaDao = RotaDao(() async => db);
    });

    tearDown(() async => db.close());

    test('grava a rota e recupera os pontos na ordem de visita', () async {
      final p1 = pontoComCoordenada('P1', 0, 0);
      final p2 = pontoComCoordenada('P2', 0, 1);
      final p3 = pontoComCoordenada('P3', 0, 2);
      for (final ponto in [p1, p2, p3]) {
        ponto.id = await pontoDao.inserir(ponto);
      }

      final rota = Rota(
        nome: 'Rota do dia',
        tipo: TipoRota.circuito,
        distanciaTotal: 3.5,
        duracaoTotal: 600,
        geometria: const [],
        pontos: [p3, p1, p2], // ordem deliberadamente fora de sequência
      );
      final id = await rotaDao.inserir(rota);

      final carregada = await rotaDao.buscarPorId(id);
      expect(carregada, isNotNull);
      expect(carregada!.nome, 'Rota do dia');
      expect(carregada.tipo, TipoRota.circuito);
      expect(carregada.distanciaTotal, closeTo(3.5, 1e-9));
      expect(carregada.duracaoTotal, closeTo(600, 1e-9));
      expect(
        carregada.pontos.map((ponto) => ponto.nome).toList(),
        ['P3', 'P1', 'P2'],
      );
    });

    test('carrega várias rotas em uma única consulta agrupada', () async {
      final p1 = pontoComCoordenada('P1', 0, 0);
      p1.id = await pontoDao.inserir(p1);
      final p2 = pontoComCoordenada('P2', 0, 1);
      p2.id = await pontoDao.inserir(p2);

      await rotaDao.inserir(Rota(nome: 'A', pontos: [p1, p2]));
      await rotaDao.inserir(Rota(nome: 'B', pontos: [p2, p1]));

      final rotas = await rotaDao.listar();
      expect(rotas, hasLength(2));
      expect(rotas.every((rota) => rota.pontos.length == 2), isTrue);
    });

    test('ao atualizar, substitui a lista de pontos', () async {
      final p1 = pontoComCoordenada('P1', 0, 0);
      p1.id = await pontoDao.inserir(p1);
      final p2 = pontoComCoordenada('P2', 0, 1);
      p2.id = await pontoDao.inserir(p2);
      final p3 = pontoComCoordenada('P3', 0, 2);
      p3.id = await pontoDao.inserir(p3);

      final id = await rotaDao.inserir(Rota(nome: 'Rota', pontos: [p1, p2]));
      final rota = (await rotaDao.buscarPorId(id))!;

      await rotaDao.atualizar(rota.copyWith(
        nome: 'Rota revisada',
        pontos: [p3, p1],
      ));

      final atualizada = (await rotaDao.buscarPorId(id))!;
      expect(atualizada.nome, 'Rota revisada');
      expect(
        atualizada.pontos.map((ponto) => ponto.nome).toList(),
        ['P3', 'P1'],
      );
    });

    test('excluir um ponto remove o vínculo dele com as rotas', () async {
      final p1 = pontoComCoordenada('P1', 0, 0);
      p1.id = await pontoDao.inserir(p1);
      final p2 = pontoComCoordenada('P2', 0, 1);
      p2.id = await pontoDao.inserir(p2);

      final id = await rotaDao.inserir(Rota(nome: 'Rota', pontos: [p1, p2]));
      await pontoDao.excluir(p1.id!);

      final carregada = (await rotaDao.buscarPorId(id))!;
      expect(carregada.pontos, hasLength(1));
      expect(carregada.pontos.first.nome, 'P2');
    });

    test('excluir uma rota remove os seus vínculos', () async {
      final p1 = pontoComCoordenada('P1', 0, 0);
      p1.id = await pontoDao.inserir(p1);
      final p2 = pontoComCoordenada('P2', 0, 1);
      p2.id = await pontoDao.inserir(p2);
      final id = await rotaDao.inserir(Rota(nome: 'Rota', pontos: [p1, p2]));

      await rotaDao.excluir(id);

      final vinculos = await db.query(DatabaseHelper.tabelaRotaPontos);
      expect(vinculos, isEmpty);
      expect(await rotaDao.contar(), 0);
    });
  });

  group('PontoRepository', () {
    late Database db;
    late PontoDao pontoDao;
    late GeocacheDao geocacheDao;
    int requisicoes = 0;

    PontoRepository repositorioCom(MockClient cliente) {
      return PontoRepository(
        dao: pontoDao,
        geocodificacao: GeocodificacaoService(
          cache: geocacheDao,
          cliente: cliente,
          intervaloMinimoEntreConsultas: Duration.zero,
        ),
      );
    }

    setUp(() async {
      db = await abrirBancoEmMemoria();
      pontoDao = PontoDao(() async => db);
      geocacheDao = GeocacheDao(() async => db);
      requisicoes = 0;
    });

    tearDown(() async => db.close());

    test('geocodifica o endereço e grava as coordenadas', () async {
      final cliente = MockClient((requisicao) async {
        requisicoes++;
        expect(requisicao.url.host, 'nominatim.openstreetmap.org');
        expect(requisicao.headers['User-Agent'], isNotNull);
        return http.Response(_respostaNominatim('-23.3103', '-51.1628'), 200);
      });

      final resultado = await repositorioCom(cliente).salvar(
        nome: 'Mercado',
        endereco: 'Av. Maringá, 134, Londrina',
      );

      expect(resultado.aviso, isNull);
      expect(resultado.ponto.temCoordenadas, isTrue);
      expect(resultado.ponto.latitude, closeTo(-23.3103, 1e-9));
      expect(resultado.ponto.longitude, closeTo(-51.1628, 1e-9));
      expect(requisicoes, 1);
    });

    test('reaproveita o cache e não repete a consulta externa', () async {
      final cliente = MockClient((_) async {
        requisicoes++;
        return http.Response(_respostaNominatim('-23.31', '-51.16'), 200);
      });
      final repositorio = repositorioCom(cliente);

      await repositorio.salvar(
          nome: 'Mercado', endereco: 'Av. Maringá, 134, Londrina');
      await repositorio.salvar(
          nome: 'Mercado 2', endereco: 'av. maringá, 134, londrina');

      expect(requisicoes, 1);
    });

    test('não consulta o serviço quando o endereço não mudou na edição',
        () async {
      final cliente = MockClient((_) async {
        requisicoes++;
        return http.Response(_respostaNominatim('-23.31', '-51.16'), 200);
      });
      final repositorio = repositorioCom(cliente);

      final primeiro = await repositorio.salvar(
          nome: 'Mercado', endereco: 'Av. Maringá, 134, Londrina');
      final segundo = await repositorio.salvar(
        nome: 'Mercado Central',
        endereco: 'Av. Maringá, 134, Londrina',
        existente: primeiro.ponto,
      );

      expect(requisicoes, 1);
      expect(segundo.ponto.nome, 'Mercado Central');
      expect(segundo.ponto.latitude, closeTo(-23.31, 1e-9));
    });

    test('grava o ponto sem coordenadas quando não há conexão', () async {
      final cliente = MockClient((_) async {
        throw const SocketException('sem rede');
      });

      final resultado = await repositorioCom(cliente).salvar(
        nome: 'Mercado',
        endereco: 'Av. Maringá, 134, Londrina',
      );

      expect(resultado.aviso, isNotNull);
      expect(resultado.semCoordenadas, isTrue);
      expect(resultado.ponto.id, isNotNull);
      // O cadastro não é perdido por falha de rede.
      expect(await pontoDao.contar(), 1);
    });

    test('avisa quando o endereço não é encontrado', () async {
      final cliente = MockClient((_) async => http.Response('[]', 200));

      final resultado = await repositorioCom(cliente).salvar(
        nome: 'Lugar inexistente',
        endereco: 'Rua que não existe, 999',
      );

      expect(resultado.semCoordenadas, isTrue);
      expect(resultado.detalheTecnico, contains('localizar o endereço'));
    });

    test('respeita o intervalo mínimo entre consultas externas', () async {
      const intervalo = Duration(milliseconds: 120);
      final cliente = MockClient((_) async {
        requisicoes++;
        return http.Response(_respostaNominatim('-23.31', '-51.16'), 200);
      });
      final servico = GeocodificacaoService(
        cache: geocacheDao,
        cliente: cliente,
        intervaloMinimoEntreConsultas: intervalo,
      );

      final cronometro = Stopwatch()..start();
      await servico.buscarCoordenadas('Primeiro endereço');
      await servico.buscarCoordenadas('Segundo endereço');
      cronometro.stop();

      expect(requisicoes, 2);
      expect(cronometro.elapsedMilliseconds,
          greaterThanOrEqualTo(intervalo.inMilliseconds - 10));
    });
  });

  group('RotaRepository', () {
    late Database db;
    late RotaDao rotaDao;

    RotaRepository repositorioCom(MockClient cliente) => RotaRepository(
          dao: rotaDao,
          otimizador: const OtimizadorRotaService(),
          roteamento: RoteamentoService(
            cliente: cliente,
            tempoLimiteResposta: const Duration(seconds: 2),
          ),
        );

    setUp(() async {
      db = await abrirBancoEmMemoria();
      rotaDao = RotaDao(() async => db);
    });

    tearDown(() async => db.close());

    test('usa a distância e a geometria devolvidas pelo OSRM', () async {
      final cliente = MockClient((requisicao) async {
        expect(requisicao.url.host, 'router.project-osrm.org');
        expect(requisicao.url.path, contains('/driving/'));
        return http.Response(_respostaOsrm(), 200);
      });

      final previa = await repositorioCom(cliente).calcular(
        pontos: [
          pontoComCoordenada('P1', -23.3103, -51.1628),
          pontoComCoordenada('P2', -23.3200, -51.1700),
        ],
        tipo: TipoRota.pontoAPonto,
      );

      expect(previa.rota.fonteCalculo, FonteCalculo.osrm);
      expect(previa.aviso, isNull);
      expect(previa.rota.distanciaTotal, closeTo(2.5, 1e-9));
      expect(previa.rota.duracaoTotal, closeTo(300, 1e-9));
      expect(previa.rota.geometria, hasLength(3));
      // A latitude e a longitude não podem sair trocadas do GeoJSON.
      expect(previa.rota.geometria.first.latitude, closeTo(-23.3103, 1e-9));
      expect(previa.rota.geometria.first.longitude, closeTo(-51.1628, 1e-9));
    });

    test('recua para a estimativa local quando o OSRM falha', () async {
      final cliente = MockClient((_) async => http.Response('erro', 500));

      final previa = await repositorioCom(cliente).calcular(
        pontos: [
          pontoComCoordenada('P1', 0, 0),
          pontoComCoordenada('P2', 0.009, 0),
        ],
        tipo: TipoRota.pontoAPonto,
      );

      expect(previa.rota.fonteCalculo, FonteCalculo.local);
      expect(previa.estimadoLocalmente, isTrue);
      expect(previa.aviso, isNotNull);
      // Cerca de 1 km em linha reta e 2 minutos a 30 km/h.
      expect(previa.rota.distanciaTotal, closeTo(1.0, 0.02));
      expect(previa.rota.duracaoTotal, closeTo(120, 15));
      // A geometria de recuo é a própria sequência de pontos.
      expect(previa.rota.geometria, hasLength(2));
    });

    test('fecha o circuito acrescentando o retorno ao primeiro ponto', () async {
      final cliente = MockClient((requisicao) async {
        // Três coordenadas enviadas: A, B e o retorno a A.
        final trecho = requisicao.url.pathSegments.last;
        expect(trecho.split(';'), hasLength(3));
        return http.Response(_respostaOsrm(), 200);
      });

      final previa = await repositorioCom(cliente).calcular(
        pontos: [
          pontoComCoordenada('P1', 0, 0),
          pontoComCoordenada('P2', 0, 1),
        ],
        tipo: TipoRota.circuito,
      );

      expect(previa.rota.tipo, TipoRota.circuito);
      expect(previa.rota.fonteCalculo, FonteCalculo.osrm);
    });

    test('salva a prévia calculada e a recupera do banco', () async {
      final cliente = MockClient((_) async => http.Response(_respostaOsrm(), 200));
      final repositorio = repositorioCom(cliente);
      final pontoDao = PontoDao(() async => db);
      final p1 = pontoComCoordenada('P1', -23.3103, -51.1628);
      p1.id = await pontoDao.inserir(p1);
      final p2 = pontoComCoordenada('P2', -23.3200, -51.1700);
      p2.id = await pontoDao.inserir(p2);

      final previa = await repositorio.calcular(
        pontos: [p1, p2],
        tipo: TipoRota.pontoAPonto,
      );
      final id = await repositorio.salvar(
        previa: previa,
        nome: 'Entregas da manhã',
      );

      final rotas = await repositorio.listar();
      expect(rotas, hasLength(1));
      expect(rotas.first.id, id);
      expect(rotas.first.nome, 'Entregas da manhã');
      expect(rotas.first.fonteCalculo, FonteCalculo.osrm);
      expect(rotas.first.pontos, hasLength(2));
    });
  });

  group('UsuarioDao - sessão', () {
    late Database db;
    late UsuarioDao usuarioDao;

    setUp(() async {
      db = await abrirBancoEmMemoria();
      usuarioDao = UsuarioDao(() async => db);
    });

    tearDown(() async => db.close());

    test('abre, consulta e encerra a sessão', () async {
      final id = await usuarioDao.inserir(
        usuarioDeTeste('Ana', 'ana@exemplo.com'),
      );

      await usuarioDao.abrirSessao(id);
      expect((await usuarioDao.usuarioDaSessao())?.id, id);

      await usuarioDao.encerrarSessao();
      expect(await usuarioDao.usuarioDaSessao(), isNull);
    });

    test('mantém uma única linha de sessão, mesmo com vários logins', () async {
      final ana = await usuarioDao.inserir(usuarioDeTeste('Ana', 'ana@exemplo.com'));
      final bruno =
          await usuarioDao.inserir(usuarioDeTeste('Bruno', 'bruno@exemplo.com'));

      await usuarioDao.abrirSessao(ana);
      await usuarioDao.abrirSessao(bruno);

      expect(await usuarioDao.usuarioDaSessao(), isNotNull);
      expect((await usuarioDao.usuarioDaSessao())!.id, bruno);
      expect(await usuarioDao.contar(), 2);
    });

    test('impõe e-mail único', () async {
      await usuarioDao.inserir(usuarioDeTeste('Ana', 'ana@exemplo.com'));
      expect(
        () => usuarioDao.inserir(usuarioDeTeste('Outra', 'ana@exemplo.com')),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
