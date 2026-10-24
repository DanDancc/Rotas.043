import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/excecoes.dart';
import '../data/dao/geocache_dao.dart';

/// Resultado de uma conversão de endereço em coordenadas.
class CoordenadaEncontrada {
  const CoordenadaEncontrada({
    required this.latitude,
    required this.longitude,
    required this.veioDoCache,
    this.enderecoFormatado,
  });

  final double latitude;
  final double longitude;

  /// Indica que a resposta foi lida do cache local, sem acesso à rede.
  final bool veioDoCache;

  /// Endereço completo devolvido pelo serviço, quando disponível.
  final String? enderecoFormatado;
}

/// Converte endereços em coordenadas usando a API Nominatim do OpenStreetMap.
///
/// Duas preocupações guiam esta classe:
///
/// 1. **Desempenho** — o requisito de tempo de resposta abaixo de 30 segundos
///    é folgado para uma única consulta, mas o aplicativo consulta o serviço
///    várias vezes ao montar uma rota. Por isso o resultado é guardado na
///    tabela `geocache`, e uma repetição do mesmo endereço não sai para a rede.
/// 2. **Uso justo do serviço** — a política de uso do Nominatim recomenda no
///    máximo uma requisição por segundo por aplicação. O intervalo entre
///    chamadas é controlado explicitamente em [intervaloMinimoEntreConsultas].
class GeocodificacaoService {
  GeocodificacaoService({
    required GeocacheDao cache,
    http.Client? cliente,
    this.intervaloMinimoEntreConsultas = const Duration(milliseconds: 1100),
    this.tempoLimiteResposta = const Duration(seconds: 15),
  })  : _cache = cache,
        _cliente = cliente ?? http.Client();

  final GeocacheDao _cache;
  final http.Client _cliente;

  /// Intervalo mínimo respeitado entre duas consultas ao serviço externo.
  final Duration intervaloMinimoEntreConsultas;

  /// Tempo máximo de espera pela resposta do serviço.
  final Duration tempoLimiteResposta;

  static const String _urlBase = 'https://nominatim.openstreetmap.org/search';

  /// Identificação exigida pela política de uso do Nominatim.
  static const Map<String, String> _cabecalhos = {
    'User-Agent': 'RotasApp/1.0 (projeto academico Unifil - Sistema de Rotas Inteligentes)',
    'Accept': 'application/json',
  };

  DateTime? _ultimaConsulta;

  /// Consulta o endereço no cache e, se não houver, no serviço externo.
  ///
  /// Lança [DadosInvalidos] quando o endereço é vazio, [EnderecoNaoEncontrado]
  /// quando o serviço não devolve resultado e [FalhaGeocodificacao] em caso de
  /// erro de rede ou resposta inesperada.
  Future<CoordenadaEncontrada> buscarCoordenadas(String endereco) async {
    final texto = endereco.trim();
    if (texto.isEmpty) {
      throw const DadosInvalidos('Informe o endereço para localizar no mapa.');
    }

    final cacheado = await _cache.buscar(texto);
    if (cacheado != null) {
      return CoordenadaEncontrada(
        latitude: cacheado.latitude,
        longitude: cacheado.longitude,
        veioDoCache: true,
      );
    }

    await _respeitarIntervalo();
    final json = await _consultarServico(texto);
    if (json.isEmpty) {
      throw EnderecoNaoEncontrado(texto);
    }

    final primeiro = json.first as Map<String, dynamic>;
    final latitude = double.tryParse('${primeiro['lat']}');
    final longitude = double.tryParse('${primeiro['lon']}');
    if (latitude == null || longitude == null) {
      throw FalhaGeocodificacao(
        'O serviço de mapas devolveu uma coordenada inválida para "$texto".',
        detalheTecnico: 'payload: $primeiro',
      );
    }

    await _cache.salvar(texto, latitude, longitude);
    return CoordenadaEncontrada(
      latitude: latitude,
      longitude: longitude,
      veioDoCache: false,
      enderecoFormatado: primeiro['display_name'] as String?,
    );
  }

  Future<List<dynamic>> _consultarServico(String endereco) async {
    final uri = Uri.parse(_urlBase).replace(queryParameters: {
      'q': endereco,
      'format': 'jsonv2',
      'limit': '1',
      'addressdetails': '0',
    });

    try {
      final resposta =
          await _cliente.get(uri, headers: _cabecalhos).timeout(tempoLimiteResposta);

      if (resposta.statusCode != 200) {
        throw FalhaGeocodificacao(
          'O serviço de mapas respondeu com o código ${resposta.statusCode}. '
          'Tente novamente em instantes.',
          detalheTecnico: 'GET $uri',
        );
      }

      final decodificado = jsonDecode(resposta.body);
      if (decodificado is! List) {
        throw FalhaGeocodificacao(
          'Resposta inesperada do serviço de mapas.',
          detalheTecnico: 'tipo: ${decodificado.runtimeType}',
        );
      }
      return decodificado;
    } on FalhaApp {
      rethrow;
    } on TimeoutException {
      throw FalhaGeocodificacao(
        'O serviço de mapas demorou demais para responder. '
        'Verifique a conexão e tente novamente.',
        detalheTecnico: 'timeout após ${tempoLimiteResposta.inSeconds}s',
      );
    } on SocketException catch (erro) {
      throw FalhaGeocodificacao(
        'Sem conexão com a internet. O endereço não pôde ser localizado.',
        detalheTecnico: erro.message,
      );
    } on FormatException catch (erro) {
      throw FalhaGeocodificacao(
        'Não foi possível interpretar a resposta do serviço de mapas.',
        detalheTecnico: erro.message,
      );
    }
  }

  /// Aguarda o intervalo mínimo desde a última chamada externa.
  Future<void> _respeitarIntervalo() async {
    final anterior = _ultimaConsulta;
    if (anterior != null) {
      final decorrido = DateTime.now().difference(anterior);
      final restante = intervaloMinimoEntreConsultas - decorrido;
      if (restante > Duration.zero) {
        await Future<void>.delayed(restante);
      }
    }
    _ultimaConsulta = DateTime.now();
  }

  /// Libera os recursos do cliente HTTP.
  void dispose() => _cliente.close();
}
