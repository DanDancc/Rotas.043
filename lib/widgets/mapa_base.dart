import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Mapa base reaproveitado pelas telas de ponto e de rota.
///
/// Concentrar aqui a configuração do `flutter_map` — camada de blocos do
/// OpenStreetMap, traçado e marcadores — evita repetir a mesma montagem em
/// cada tela e garante que todas usem a mesma identificação de cliente,
/// exigida pela política de uso do servidor de blocos.
class MapaBase extends StatelessWidget {
  const MapaBase({
    super.key,
    required this.centro,
    this.zoom = 15,
    this.marcadores = const [],
    this.linha = const [],
    this.aoTocarMapa,
    this.controlador,
  });

  /// Coordenada inicial do mapa.
  final LatLng centro;

  /// Aproximação inicial.
  final double zoom;

  /// Marcadores a exibir.
  final List<Marker> marcadores;

  /// Traçado a desenhar, quando houver rota calculada.
  final List<LatLng> linha;

  final void Function(LatLng)? aoTocarMapa;
  final MapController? controlador;

  static const String identificacaoCliente = 'com.example.rotas_app';

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controlador,
      options: MapOptions(
        initialCenter: centro,
        initialZoom: zoom,
        onTap: aoTocarMapa == null ? null : (_, ponto) => aoTocarMapa!(ponto),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: identificacaoCliente,
        ),
        if (linha.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: linha,
                strokeWidth: 5,
                color: Theme.of(context).colorScheme.primary,
                borderStrokeWidth: 1.5,
                borderColor: Colors.white70,
              ),
            ],
          ),
        if (marcadores.isNotEmpty) MarkerLayer(markers: marcadores),
        const _AtribuicaoOpenStreetMap(),
      ],
    );
  }
}

/// Aviso de atribuição exigido pela licença do OpenStreetMap.
class _AtribuicaoOpenStreetMap extends StatelessWidget {
  const _AtribuicaoOpenStreetMap();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '© OpenStreetMap',
          style: TextStyle(fontSize: 10, color: Colors.black87),
        ),
      ),
    );
  }
}

/// Marcador em forma de pino com um número, usado na ordem de visita da rota.
Marker marcadorNumerado(
  LatLng ponto,
  int numero, {
  Color cor = const Color(0xFF1565C0),
  double largura = 46,
  double altura = 46,
}) {
  return Marker(
    point: ponto,
    width: largura,
    height: altura,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: Text(
            '$numero',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Icon(Icons.arrow_drop_down, color: Colors.black54, size: 18),
      ],
    ),
  );
}

/// Marcador simples de pino vermelho, ainda usado para um ponto isolado.
Marker marcadorSimples(LatLng ponto, {Color cor = Colors.red}) {
  return Marker(
    point: ponto,
    width: 60,
    height: 60,
    child: Icon(Icons.location_on, color: cor, size: 50),
  );
}

/// Marcador da posição atual do veículo durante a navegação.
Marker marcadorPosicaoAtual(LatLng ponto) {
  return Marker(
    point: ponto,
    width: 44,
    height: 44,
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0).withValues(alpha: 0.25),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.navigation, color: Color(0xFF0D47A1), size: 26),
    ),
  );
}
