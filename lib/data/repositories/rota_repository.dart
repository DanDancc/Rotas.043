import 'package:latlong2/latlong.dart';

import '../../models/ponto.dart';
import '../../models/rota.dart';
import '../../services/otimizador_rota_service.dart';
import '../../services/roteamento_service.dart';
import '../dao/rota_dao.dart';

/// Resultado do cálculo de uma rota antes de ela ser gravada.
///
/// Separar o cálculo da gravação permite mostrar a prévia no mapa, com a
/// ordem otimizada e as distâncias, e só persistir depois que o usuário
/// confirmar o nome da rota — evitando consultas repetidas ao serviço de
/// trajetos.
class PreviaRota {
  const PreviaRota({
    required this.rota,
    required this.otimizacao,
    required this.trajeto,
  });

  /// Rota montada com a ordem de visita otimizada, ainda sem nome e sem id.
  final Rota rota;

  /// Detalhes da ordenação, incluindo o ganho obtido com o 2-opt.
  final ResultadoOtimizacao otimizacao;

  /// Trajeto devolvido pelo serviço de roteamento.
  final ResultadoTrajeto trajeto;

  /// Aviso a exibir quando o traçado foi estimado localmente.
  String? get aviso => trajeto.aviso;

  bool get estimadoLocalmente => trajeto.estimadoLocalmente;
}

/// Regras de negócio das rotas (casos de uso UC02 — Gerar Rotas e
/// UC03 — Gerenciar Rotas Salvas).
class RotaRepository {
  RotaRepository({
    required RotaDao dao,
    required OtimizadorRotaService otimizador,
    required RoteamentoService roteamento,
  })  : _dao = dao,
        _otimizador = otimizador,
        _roteamento = roteamento;

  final RotaDao _dao;
  final OtimizadorRotaService _otimizador;
  final RoteamentoService _roteamento;

  /// Ordena os pontos, calcula o trajeto e devolve a prévia da rota.
  Future<PreviaRota> calcular({
    required List<Ponto> pontos,
    required TipoRota tipo,
    Ponto? origem,
    Ponto? destino,
  }) async {
    final otimizacao = _otimizador.otimizar(
      pontos: pontos,
      tipo: tipo,
      origem: origem,
      destino: destino,
    );

    final coordenadas = otimizacao.pontos
        .map((ponto) => ponto.coordenada)
        .whereType<LatLng>()
        .toList(growable: false);

    final trajeto = await _roteamento.calcular(coordenadas, tipo: tipo);

    final rota = Rota(
      tipo: tipo,
      nome: '',
      distanciaTotal: trajeto.distanciaKm,
      duracaoTotal: trajeto.duracaoSegundos,
      geometria: trajeto.geometria,
      fonteCalculo: trajeto.fonte,
      pontos: otimizacao.pontos,
    );

    return PreviaRota(rota: rota, otimizacao: otimizacao, trajeto: trajeto);
  }

  /// Grava a prévia calculada com o nome informado.
  ///
  /// Devolve o identificador da rota; quando [idRota] é informado, a rota
  /// existente é atualizada em vez de criar outra.
  Future<int> salvar({
    required PreviaRota previa,
    required String nome,
    int? idUsuario,
    int? idRota,
  }) async {
    final nomeLimpo = nome.trim();
    if (nomeLimpo.isEmpty) {
      throw ArgumentError('Informe um nome para a rota.');
    }

    final rota = previa.rota.copyWith(
      id: idRota,
      nome: nomeLimpo,
      idUsuario: idUsuario,
    );

    if (idRota == null) {
      return _dao.inserir(rota);
    }
    await _dao.atualizar(rota);
    return idRota;
  }

  Future<List<Rota>> listar({int? idUsuario}) => _dao.listar(idUsuario: idUsuario);

  Future<Rota?> buscarPorId(int id) => _dao.buscarPorId(id);

  Future<void> excluir(int id) => _dao.excluir(id);

  Future<int> contar({int? idUsuario}) => _dao.contar(idUsuario: idUsuario);
}
