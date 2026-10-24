import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/geo_utils.dart';
import '../models/rota.dart';

/// Trajeto calculado entre uma sequência de coordenadas.
class ResultadoTrajeto {
  const ResultadoTrajeto({
    required this.geometria,
    required this.distanciaKm,
    required this.duracaoSegundos,
    required this.fonte,
    this.aviso,
  });

  /// Traçado a desenhar no mapa, já seguindo as vias quando [fonte] é
  /// [FonteCalculo.osrm].
  final List<LatLng> geometria;

  /// Distância total do percurso, em quilômetros.
  final double distanciaKm;

  /// Duração estimada, em segundos.
  final double duracaoSegundos;

  /// Indica se o cálculo veio da API de roteamento ou foi estimado localmente.
  final FonteCalculo fonte;

  /// Explicação a ser mostrada ao usuário quando houve recuo para a
  /// estimativa local, para que ele saiba que o traçado não segue as vias.
  final String? aviso;

  bool get estimadoLocalmente => fonte == FonteCalculo.local;
}

/// Calcula o trajeto entre pontos usando a API pública do OSRM, que devolve o
/// caminho seguindo as vias reais, com distância e duração.
///
/// O aplicativo precisa funcionar também quando a rede falha — premissa
/// registrada na Visão do produto. Por isso todo cálculo tem um caminho
/// alternativo: quando o OSRM não responde, o serviço devolve a estimativa
/// local em linha reta, marcada como tal, e o restante do aplicativo continua
/// operando normalmente, sem travar a interface do usuário.
class RoteamentoService {
  RoteamentoService({
    http.Client? cliente,
    this.tempoLimiteResposta = const Duration(seconds: 20),
    this.maximoCoordenadas = 25,
  }) : _cliente = cliente ?? http.Client();

  final http.Client _cliente;

  /// Tempo máximo de espera pelo OSRM.
  ///
  /// Fica abaixo dos 30 segundos exigidos na Especificação Complementar para
  /// que, mesmo no pior caso, o recuo para a estimativa local ainda aconteça
  /// dentro do prazo aceitável de resposta.
  final Duration tempoLimiteResposta;

  /// Limite de coordenadas enviadas em uma única requisição.
  ///
  /// O serviço público do OSRM é limitado e a URL tem tamanho finito, então
  /// rotas muito longas caem direto na estimativa local.
  final int maximoCoordenadas;

  static const String _urlBase =
      'https://router.project-osrm.org/route/v1/driving';

  static const Map<String, String> _cabecalhos = {
    'User-Agent': 'RotasApp/1.0 (projeto academico Unifil - Sistema de Rotas Inteligentes)',
    'Accept': 'application/json',
  };

  /// Calcula o trajeto que passa por [pontos] na ordem informada.
  ///
  /// Quando [tipo] é [TipoRota.circuito], o trajeto é fechado retornando ao
  /// primeiro ponto.
  Future<ResultadoTrajeto> calcular(
    List<LatLng> pontos, {
    required TipoRota tipo,
  }) async {
    if (pontos.length < 2) {
      return ResultadoTrajeto(
        geometria: List<LatLng>.from(pontos),
        distanciaKm: 0,
        duracaoSegundos: 0,
        fonte: FonteCalculo.local,
        aviso: 'São necessários ao menos dois pontos para calcular um trajeto.',
      );
    }

    final circuito = tipo == TipoRota.circuito;
    final percurso = circuito
        ? <LatLng>[...pontos, pontos.first]
        : List<LatLng>.from(pontos);

    if (percurso.length > maximoCoordenadas) {
      return _estimativaLocal(
        percurso,
        circuito: circuito,
        aviso: 'A rota tem mais de ${maximoCoordenadas - (circuito ? 1 : 0)} '
            'paradas; o traçado foi estimado localmente.',
      );
    }

    final daApi = await _tentarOsrm(percurso);
    if (daApi != null) return daApi;

    return _estimativaLocal(
      percurso,
      circuito: circuito,
      aviso: 'Não foi possível consultar o serviço de trajetos. '
          'O percurso foi estimado em linha reta e pode não seguir as vias.',
    );
  }

  /// Consulta o OSRM e devolve nulo quando qualquer etapa falha, deixando a
  /// decisão de recuo para quem chamou.
  Future<ResultadoTrajeto?> _tentarOsrm(List<LatLng> percurso) async {
    final coordenadas = percurso
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    final uri = Uri.parse('$_urlBase/$coordenadas').replace(queryParameters: {
      'overview': 'full',
      'geometries': 'geojson',
      'alternatives': 'false',
      'steps': 'false',
    });

    try {
      final resposta =
          await _cliente.get(uri, headers: _cabecalhos).timeout(tempoLimiteResposta);
      if (resposta.statusCode != 200) return null;

      final corpo = jsonDecode(resposta.body);
      if (corpo is! Map<String, dynamic>) return null;
      if (corpo['code'] != 'Ok') return null;

      final rotas = corpo['routes'];
      if (rotas is! List || rotas.isEmpty) return null;

      final primeira = rotas.first as Map<String, dynamic>;
      final geometria = _lerGeometria(primeira['geometry']);
      if (geometria.length < 2) return null;

      final distanciaMetros = (primeira['distance'] as num?)?.toDouble() ?? 0;
      final duracaoSegundos = (primeira['duration'] as num?)?.toDouble() ?? 0;

      return ResultadoTrajeto(
        geometria: geometria,
        distanciaKm: distanciaMetros / 1000.0,
        duracaoSegundos: duracaoSegundos,
        fonte: FonteCalculo.osrm,
      );
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on http.ClientException {
      return null;
    } on FormatException {
      return null;
    } catch (_) {
      // Qualquer falha inesperada no serviço externo não pode impedir o uso
      // do aplicativo; o recuo local cobre esse caso.
      return null;
    }
  }

  static List<LatLng> _lerGeometria(dynamic geometria) {
    if (geometria is! Map<String, dynamic>) return const [];
    final coordenadas = geometria['coordinates'];
    if (coordenadas is! List) return const [];
    final saida = <LatLng>[];
    for (final item in coordenadas) {
      if (item is List && item.length >= 2) {
        // O GeoJSON devolve [longitude, latitude]; a inversão é obrigatória.
        saida.add(LatLng(
          (item[1] as num).toDouble(),
          (item[0] as num).toDouble(),
        ));
      }
    }
    return saida;
  }

  /// Estimativa em linha reta, usada quando o serviço externo não responde.
  ResultadoTrajeto _estimativaLocal(
    List<LatLng> percurso, {
    required bool circuito,
    required String aviso,
  }) {
    final distancia =
        GeoUtils.distanciaTotalKm(percurso, fecharCircuito: false);
    final horas = distancia / GeoUtils.velocidadeUrbanaKmH;
    return ResultadoTrajeto(
      geometria: percurso,
      distanciaKm: distancia,
      duracaoSegundos: horas * 3600.0,
      fonte: FonteCalculo.local,
      aviso: aviso,
    );
  }

  void dispose() => _cliente.close();
}
