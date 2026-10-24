import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Funções geográficas puras, sem dependência de widgets do Flutter.
///
/// Manter esses cálculos fora das telas permite testá-los isoladamente
/// (ver `test/geo_utils_test.dart`) e reaproveitá-los nos serviços de
/// roteamento e de otimização.
class GeoUtils {
  const GeoUtils._();

  /// Raio médio da Terra em quilômetros (padrão IUGG).
  static const double raioTerraKm = 6371.0088;

  /// Velocidade média urbana assumida quando o cálculo precisa ser feito
  /// localmente, em km/h. Usada apenas como estimativa de fallback.
  static const double velocidadeUrbanaKmH = 30.0;

  static double _radianos(double graus) => graus * math.pi / 180.0;

  /// Distância em quilômetros entre dois pares de coordenadas, pela
  /// fórmula de Haversine (distância em linha reta sobre a superfície).
  static double distanciaKm(double lat1, double lon1, double lat2, double lon2) {
    final dLat = _radianos(lat2 - lat1);
    final dLon = _radianos(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radianos(lat1)) *
            math.cos(_radianos(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return raioTerraKm * c;
  }

  /// Distância em quilômetros entre dois pontos geográficos.
  static double distanciaEntre(LatLng a, LatLng b) =>
      distanciaKm(a.latitude, a.longitude, b.latitude, b.longitude);

  /// Soma das distâncias entre pontos consecutivos de uma sequência.
  ///
  /// Se [fecharCircuito] for verdadeiro, soma também o trecho de volta do
  /// último ponto ao primeiro.
  static double distanciaTotalKm(List<LatLng> percurso,
      {bool fecharCircuito = false}) {
    if (percurso.length < 2) return 0.0;
    var total = 0.0;
    for (var i = 0; i < percurso.length - 1; i++) {
      total += distanciaEntre(percurso[i], percurso[i + 1]);
    }
    if (fecharCircuito) {
      total += distanciaEntre(percurso.last, percurso.first);
    }
    return total;
  }

  /// Comprimento total de uma geometria vinda de uma API de roteamento.
  static double comprimentoGeometriaKm(List<LatLng> geometria) =>
      distanciaTotalKm(geometria);

  /// Formata uma distância em quilômetros para exibição em português.
  ///
  /// Abaixo de 1 km o valor é apresentado em metros.
  static String formatarDistancia(double km) {
    if (km.isNaN || km.isInfinite || km < 0) return '—';
    if (km < 1.0) {
      final metros = (km * 1000).round();
      return '$metros m';
    }
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  /// Formata uma duração em segundos para exibição em português.
  static String formatarDuracao(double segundos) {
    if (segundos.isNaN || segundos.isInfinite || segundos < 0) return '—';
    final totalMinutos = segundos.round() ~/ 60;
    if (totalMinutos < 1) return 'menos de 1 min';
    if (totalMinutos < 60) return '$totalMinutos min';
    final horas = totalMinutos ~/ 60;
    final minutos = totalMinutos % 60;
    if (minutos == 0) return '${horas}h';
    return '${horas}h ${minutos}min';
  }

  /// Converte uma lista de coordenadas em texto JSON, para persistência na
  /// coluna `geometria` da tabela `rotas`.
  static String geometriaParaTexto(List<LatLng> geometria) {
    final lista = geometria
        .map((p) => [p.latitude, p.longitude])
        .toList(growable: false);
    return jsonEncode(lista);
  }

  /// Lê a geometria gravada por [geometriaParaTexto].
  ///
  /// Retorna lista vazia quando o conteúdo é nulo, vazio ou ilegível. Itens
  /// individuais malformados são descartados sem invalidar os demais, para que
  /// um único registro corrompido não apague o traçado inteiro da rota.
  static List<LatLng> geometriaDeTexto(String? texto) {
    if (texto == null || texto.trim().isEmpty) return const [];

    final List<dynamic> bruto;
    try {
      final decodificado = jsonDecode(texto);
      if (decodificado is! List) return const [];
      bruto = decodificado;
    } on FormatException {
      return const [];
    }

    final saida = <LatLng>[];
    for (final item in bruto) {
      if (item is! List || item.length < 2) continue;
      final latitude = item[0];
      final longitude = item[1];
      if (latitude is! num || longitude is! num) continue;
      saida.add(LatLng(latitude.toDouble(), longitude.toDouble()));
    }
    return saida;
  }

  /// Ponto médio de uma lista de coordenadas, útil para centralizar o mapa
  /// quando a rota ainda não foi calculada.
  static LatLng? centro(List<LatLng> pontos) {
    if (pontos.isEmpty) return null;
    var somaLat = 0.0;
    var somaLon = 0.0;
    for (final p in pontos) {
      somaLat += p.latitude;
      somaLon += p.longitude;
    }
    return LatLng(somaLat / pontos.length, somaLon / pontos.length);
  }

  /// Direção (rumo) de [de] para [para], em graus de 0 a 360, onde 0 é o norte.
  static double rumoGraus(LatLng de, LatLng para) {
    final dLon = _radianos(para.longitude - de.longitude);
    final lat1 = _radianos(de.latitude);
    final lat2 = _radianos(para.latitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final graus = math.atan2(y, x) * 180.0 / math.pi;
    return (graus + 360.0) % 360.0;
  }

  /// Converte um rumo em ponto cardeal abreviado (N, NE, L, SE, S, SO, O, NO).
  static String pontoCardeal(double graus) {
    const direcoes = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];
    final indice = (((graus % 360) / 45.0).round()) % 8;
    return direcoes[indice];
  }
}
