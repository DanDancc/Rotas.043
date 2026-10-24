import 'package:flutter_test/flutter_test.dart';
import 'package:rotas_app/core/excecoes.dart';
import 'package:rotas_app/data/dao/ponto_dao.dart';
import 'package:rotas_app/data/dao/preferencias_dao.dart';
import 'package:rotas_app/data/dao/usuario_dao.dart';
import 'package:rotas_app/services/autenticacao_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'apoio/banco_teste.dart';

void main() {
  setUpAll(prepararSqflite);

  group('derivação e comparação de senha', () {
    test('gera sais diferentes a cada chamada', () {
      final primeiro = AutenticacaoService.gerarSalt();
      final segundo = AutenticacaoService.gerarSalt();
      expect(primeiro, isNot(equals(segundo)));
      expect(primeiro, isNotEmpty);
    });

    test('é determinística para o mesmo sal e a mesma senha', () {
      const salt = 'sal-fixo';
      expect(
        AutenticacaoService.derivarSenha('senha123', salt),
        AutenticacaoService.derivarSenha('senha123', salt),
      );
    });

    test('muda quando o sal muda', () {
      expect(
        AutenticacaoService.derivarSenha('senha123', 'sal-a'),
        isNot(equals(AutenticacaoService.derivarSenha('senha123', 'sal-b'))),
      );
    });

    test('muda quando a senha muda', () {
      const salt = 'sal-fixo';
      expect(
        AutenticacaoService.derivarSenha('senha123', salt),
        isNot(equals(AutenticacaoService.derivarSenha('senha124', salt))),
      );
    });

    test('não devolve a senha em texto claro', () {
      final derivada = AutenticacaoService.derivarSenha('senha123', 'sal');
      expect(derivada, isNot(contains('senha123')));
    });

    test('compara valores sem parar na primeira diferença', () {
      expect(AutenticacaoService.compararSeguro('abc', 'abc'), isTrue);
      expect(AutenticacaoService.compararSeguro('abc', 'abd'), isFalse);
      expect(AutenticacaoService.compararSeguro('abc', 'ab'), isFalse);
      expect(AutenticacaoService.compararSeguro('', ''), isTrue);
    });
  });

  group('validações de cadastro', () {
    test('aceita e recusa formatos de e-mail', () {
      expect(AutenticacaoService.validarEmail('ana@exemplo.com'), isNull);
      expect(AutenticacaoService.validarEmail('ana.silva+teste@exemplo.com.br'),
          isNull);
      expect(AutenticacaoService.validarEmail(''), isNotNull);
      expect(AutenticacaoService.validarEmail('ana'), isNotNull);
      expect(AutenticacaoService.validarEmail('ana@'), isNotNull);
      expect(AutenticacaoService.validarEmail('ana@exemplo'), isNotNull);
    });

    test('exige senha com ao menos seis caracteres', () {
      expect(AutenticacaoService.validarSenha('123456'), isNull);
      expect(AutenticacaoService.validarSenha('12345'), isNotNull);
    });

    test('exige nome com ao menos três caracteres', () {
      expect(AutenticacaoService.validarNome('Ana'), isNull);
      expect(AutenticacaoService.validarNome('An'), isNotNull);
    });
  });

  group('AutenticacaoService com banco em memória', () {
    late Database db;
    late AutenticacaoService servico;
    late UsuarioDao usuarioDao;
    late PontoDao pontoDao;
    late PreferenciasDao preferenciasDao;

    setUp(() async {
      db = await abrirBancoEmMemoria();
      usuarioDao = UsuarioDao(() async => db);
      pontoDao = PontoDao(() async => db);
      preferenciasDao = PreferenciasDao(() async => db);
      servico = AutenticacaoService(
        usuarioDao: usuarioDao,
        pontoDao: pontoDao,
        preferencias: preferenciasDao,
      );
    });

    tearDown(() async => db.close());

    test('cadastra, abre a sessão e permite entrar novamente', () async {
      final criado = await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'Ana@Exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );

      expect(criado.id, isNotNull);
      // O e-mail é normalizado para minúsculas.
      expect(criado.email, 'ana@exemplo.com');
      expect(criado.senhaHash, isNot(contains('segredo1')));

      final daSessao = await servico.usuarioAtual();
      expect(daSessao?.id, criado.id);

      await servico.sair();
      expect(await servico.usuarioAtual(), isNull);

      final entrou = await servico.entrar(
        email: 'ana@exemplo.com',
        senha: 'segredo1',
      );
      expect(entrou.id, criado.id);
    });

    test('recusa cadastro com e-mail já existente', () async {
      await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );

      expect(
        () => servico.cadastrar(
          nome: 'Outra Pessoa',
          email: 'ANA@exemplo.com',
          senha: 'segredo2',
          confirmacaoSenha: 'segredo2',
        ),
        throwsA(isA<FalhaAutenticacao>()),
      );
    });

    test('recusa confirmação de senha divergente', () async {
      expect(
        () => servico.cadastrar(
          nome: 'Ana Souza',
          email: 'ana@exemplo.com',
          senha: 'segredo1',
          confirmacaoSenha: 'segredo2',
        ),
        throwsA(isA<FalhaAutenticacao>()),
      );
    });

    test('usa a mesma mensagem para e-mail inexistente e senha errada', () async {
      await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );
      await servico.sair();

      late String mensagemSenhaErrada;
      late String mensagemEmailInexistente;

      try {
        await servico.entrar(email: 'ana@exemplo.com', senha: 'errada');
      } on FalhaAutenticacao catch (falha) {
        mensagemSenhaErrada = falha.mensagem;
      }
      try {
        await servico.entrar(email: 'ninguem@exemplo.com', senha: 'segredo1');
      } on FalhaAutenticacao catch (falha) {
        mensagemEmailInexistente = falha.mensagem;
      }

      // Mensagens iguais impedem descobrir quais e-mails estão cadastrados.
      expect(mensagemSenhaErrada, mensagemEmailInexistente);
    });

    test('vincula os pontos cadastrados antes da conta ao primeiro usuário',
        () async {
      final legado = pontoComCoordenada('Ponto legado', -23.31, -51.16);
      await pontoDao.inserir(legado);

      final usuario = await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );

      final pontos = await pontoDao.listar(idUsuario: usuario.id);
      expect(pontos, hasLength(1));
      expect(pontos.first.idUsuario, usuario.id);
    });

    test('altera a senha e invalida a anterior', () async {
      final usuario = await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );

      await servico.alterarSenha(
        usuario: usuario,
        senhaAtual: 'segredo1',
        novaSenha: 'novasenha',
        confirmacaoNovaSenha: 'novasenha',
      );

      await expectLater(
        servico.entrar(email: 'ana@exemplo.com', senha: 'segredo1'),
        throwsA(isA<FalhaAutenticacao>()),
      );
      final entrou =
          await servico.entrar(email: 'ana@exemplo.com', senha: 'novasenha');
      expect(entrou.id, usuario.id);
    });

    test('recusa a troca de senha quando a senha atual está errada', () async {
      final usuario = await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );

      expect(
        () => servico.alterarSenha(
          usuario: usuario,
          senhaAtual: 'errada',
          novaSenha: 'novasenha',
          confirmacaoNovaSenha: 'novasenha',
        ),
        throwsA(isA<FalhaAutenticacao>()),
      );
    });

    test('atualiza o perfil e recusa e-mail já usado por outra conta', () async {
      final ana = await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );
      await servico.cadastrar(
        nome: 'Bruno Lima',
        email: 'bruno@exemplo.com',
        senha: 'segredo2',
        confirmacaoSenha: 'segredo2',
      );

      final atualizado = await servico.atualizarPerfil(
        usuario: ana,
        nome: 'Ana Souza Silva',
        email: 'ana.silva@exemplo.com',
      );
      expect(atualizado.nome, 'Ana Souza Silva');

      expect(
        () => servico.atualizarPerfil(
          usuario: atualizado,
          nome: 'Ana Souza Silva',
          email: 'bruno@exemplo.com',
        ),
        throwsA(isA<FalhaAutenticacao>()),
      );
    });

    test('exclui a conta e os dados que pertencem a ela', () async {
      final usuario = await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );
      await pontoDao.inserir(
        pontoComCoordenada('Ponto da Ana', -23.31, -51.16, idUsuario: usuario.id),
      );

      await servico.excluirConta(usuario);

      expect(await usuarioDao.contar(), 0);
      expect(await pontoDao.contar(), 0);
      expect(await servico.usuarioAtual(), isNull);
      // A conta lembrada deixa de existir junto com a conta.
      expect(await servico.contaLembrada(), isNull);
    });

    test('lembra o e-mail e o nome do último acesso', () async {
      await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );

      final lembrada = await servico.contaLembrada();
      expect(lembrada, isNotNull);
      expect(lembrada!.email, 'ana@exemplo.com');
      expect(lembrada.primeiroNome, 'Ana');
    });

    test('não há conta lembrada antes do primeiro acesso', () async {
      expect(await servico.contaLembrada(), isNull);
    });

    test('mantém a sessão gravada por padrão', () async {
      final usuario = await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );

      // Simula a reabertura do aplicativo: a sessão deve ser retomada.
      expect((await servico.usuarioAtual())?.id, usuario.id);
      expect(await servico.manterConectadoPadrao(), isTrue);
    });

    test('sem manter conectado, não grava sessão para a próxima abertura',
        () async {
      await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );
      await servico.sair();

      final usuario = await servico.entrar(
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        manterConectado: false,
      );
      expect(usuario.id, isNotNull);

      // A sessão não é retomada na próxima abertura...
      expect(await servico.usuarioAtual(), isNull);
      // ...mas o e-mail continua lembrado, para o usuário digitar só a senha.
      expect((await servico.contaLembrada())?.email, 'ana@exemplo.com');
      expect(await servico.manterConectadoPadrao(), isFalse);
    });

    test('marcar manter conectado novamente volta a gravar a sessão', () async {
      await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );
      await servico.sair();
      await servico.entrar(
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        manterConectado: false,
      );
      await servico.sair();

      final usuario = await servico.entrar(
        email: 'ana@exemplo.com',
        senha: 'segredo1',
      );

      expect((await servico.usuarioAtual())?.id, usuario.id);
      expect(await servico.manterConectadoPadrao(), isTrue);
    });

    test('encerrar a sessão preserva a conta lembrada', () async {
      await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );

      await servico.sair();

      expect(await servico.usuarioAtual(), isNull);
      expect((await servico.contaLembrada())?.email, 'ana@exemplo.com');
    });

    test('atualizar o perfil mantém a conta lembrada coerente', () async {
      final usuario = await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );

      await servico.atualizarPerfil(
        usuario: usuario,
        nome: 'Ana Souza Silva',
        email: 'ana.silva@exemplo.com',
      );

      final lembrada = await servico.contaLembrada();
      expect(lembrada!.email, 'ana.silva@exemplo.com');
      expect(lembrada.nome, 'Ana Souza Silva');
    });
  });
}
