import '../../models/ponto.dart';
import '../../services/geocodificacao_service.dart';
import '../dao/ponto_dao.dart';

/// Resultado da gravação de um ponto, com eventual aviso ao usuário.
class ResultadoSalvarPonto {
  const ResultadoSalvarPonto({
    required this.ponto,
    this.aviso,
    this.detalheTecnico,
  });

  final Ponto ponto;

  /// Mensagem a exibir quando o ponto foi gravado, mas sem coordenadas.
  final String? aviso;

  /// Motivo técnico da falha de geocodificação, para registro em log.
  final String? detalheTecnico;

  bool get semCoordenadas => !ponto.temCoordenadas;
}

/// Regras de negócio dos pontos de interesse (caso de uso UC01).
///
/// Fica entre a interface e o banco: as telas não conhecem SQL nem a API de
/// geocodificação, e o DAO não conhece regra de negócio.
class PontoRepository {
  PontoRepository({
    required PontoDao dao,
    required GeocodificacaoService geocodificacao,
  })  : _dao = dao,
        _geocodificacao = geocodificacao;

  final PontoDao _dao;
  final GeocodificacaoService _geocodificacao;

  Future<List<Ponto>> listar({int? idUsuario}) => _dao.listar(idUsuario: idUsuario);

  Future<Ponto?> buscarPorId(int id) => _dao.buscarPorId(id);

  Future<int> contar({int? idUsuario}) => _dao.contar(idUsuario: idUsuario);

  /// Cria ou atualiza um ponto, resolvendo as suas coordenadas.
  ///
  /// Quando o endereço não mudou em uma edição, as coordenadas já gravadas são
  /// aproveitadas e nenhuma consulta externa é feita — o que torna a edição do
  /// nome instantânea e evita chamadas desnecessárias ao Nominatim.
  ///
  /// Se a geocodificação falhar (por exemplo, sem internet), o ponto é gravado
  /// mesmo assim, sem coordenadas, e o aviso correspondente é devolvido. Essa
  /// decisão preserva a premissa de operação com rede instável registrada na
  /// Visão do produto: o cadastro nunca é perdido por causa da conexão.
  Future<ResultadoSalvarPonto> salvar({
    required String nome,
    required String endereco,
    Ponto? existente,
    int? idUsuario,
  }) async {
    final nomeLimpo = nome.trim();
    final enderecoLimpo = endereco.trim();
    if (nomeLimpo.isEmpty || enderecoLimpo.isEmpty) {
      throw ArgumentError('Nome e endereço são obrigatórios.');
    }

    double? latitude;
    double? longitude;
    String? aviso;
    String? detalheTecnico;

    final reaproveitaCoordenadas = existente != null &&
        existente.endereco.trim().toLowerCase() ==
            enderecoLimpo.toLowerCase() &&
        existente.temCoordenadas;

    if (reaproveitaCoordenadas) {
      latitude = existente.latitude;
      longitude = existente.longitude;
    } else {
      try {
        final encontrada = await _geocodificacao.buscarCoordenadas(enderecoLimpo);
        latitude = encontrada.latitude;
        longitude = encontrada.longitude;
      } on Exception catch (erro) {
        aviso = 'O ponto foi salvo, mas o endereço não pôde ser localizado '
            'no mapa agora. Edite o ponto quando houver conexão para '
            'buscar as coordenadas.';
        detalheTecnico = erro.toString();
      }
    }

    final ponto = Ponto(
      id: existente?.id,
      nome: nomeLimpo,
      endereco: enderecoLimpo,
      latitude: latitude,
      longitude: longitude,
      idUsuario: existente?.idUsuario ?? idUsuario,
    );

    if (ponto.id == null) {
      final id = await _dao.inserir(ponto);
      return ResultadoSalvarPonto(
        ponto: ponto.copyWith(id: id),
        aviso: aviso,
        detalheTecnico: detalheTecnico,
      );
    }
    await _dao.atualizar(ponto);
    return ResultadoSalvarPonto(
      ponto: ponto,
      aviso: aviso,
      detalheTecnico: detalheTecnico,
    );
  }

  Future<void> excluir(int id) => _dao.excluir(id);
}
