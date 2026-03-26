import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; // Pack mapa
import 'package:latlong2/latlong.dart'; // Pack Lat e Long
import '../models/local_map.dart';

class MapPage extends StatelessWidget {
  final LocalMap ponto; // Recebe o ponto inteiro para ter o nome e as coordenadas

  const MapPage({super.key, required this.ponto});

  @override
  Widget build(BuildContext context) {
    // Verificação de segurança
    if (ponto.latitude == null || ponto.longitude == null) {
      return Scaffold(
        appBar: AppBar(title: Text(ponto.nome)),
        body: const Center(
          child: Text('Coordenadas não encontradas para este endereço.'),
        ),
      );
    }

    // Criamos o item de localização para o mapa
    final localizacao = LatLng(ponto.latitude!, ponto.longitude!);

    return Scaffold(
      appBar: AppBar(
        title: Text(ponto.nome),
      ),
      body: FlutterMap(
        // Configurações iniciais do mapa
        options: MapOptions(
          initialCenter: localizacao, // Centraliza no ponto
          initialZoom: 16.0, // Aproximação
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.rotas_app',
          ),
          // Marcadores
          MarkerLayer(
            markers: [
              Marker(
                point: localizacao,
                width: 60,
                height: 60,
                child: const Icon(
                  Icons.location_on, // Pino de mapa
                  color: Colors.red,
                  size: 50,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}