import 'package:flutter/material.dart';

import '../core/dependencias.dart';
import '../models/ponto.dart';
import '../widgets/avisos.dart';
import '../widgets/estados.dart';
import '../widgets/mapa_base.dart';

/// Exibição de um único ponto no mapa (fluxo alternativo FA03 do UC01).
class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.ponto});

  final Ponto ponto;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late Ponto _ponto;
  bool _localizando = false;

  @override
  void initState() {
    super.initState();
    _ponto = widget.ponto;
  }

  /// Tenta novamente a geocodificação de um ponto que ficou sem coordenadas.
  Future<void> _localizarEndereco() async {
    setState(() => _localizando = true);
    try {
      final resultado = await Dependencias.instance.pontos.salvar(
        nome: _ponto.nome,
        endereco: _ponto.endereco,
        existente: _ponto,
        idUsuario: _ponto.idUsuario,
      );
      if (!mounted) return;
      setState(() {
        _ponto = resultado.ponto;
        _localizando = false;
      });
      if (resultado.aviso != null) {
        Avisos.atencao(context, resultado.aviso!);
      } else {
        Avisos.sucesso(context, 'Endereço localizado no mapa!');
      }
    } on Exception catch (erro) {
      if (!mounted) return;
      setState(() => _localizando = false);
      Avisos.erro(context, 'Não foi possível localizar o endereço. $erro');
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordenada = _ponto.coordenada;

    return Scaffold(
      appBar: AppBar(title: Text(_ponto.nome)),
      body: coordenada == null
          ? EstadoVazio(
              icone: Icons.location_off_outlined,
              titulo: 'Coordenadas não encontradas',
              descricao: 'O endereço "${_ponto.endereco}" ainda não foi '
                  'localizado no mapa. Verifique a conexão e tente novamente.',
              rotuloAcao: _localizando ? null : 'Localizar endereço',
              aoAcionar: _localizando ? null : _localizarEndereco,
            )
          : Column(
              children: [
                Expanded(
                  child: MapaBase(
                    centro: coordenada,
                    zoom: 16,
                    marcadores: [marcadorSimples(coordenada)],
                  ),
                ),
                _CartaoDetalhes(ponto: _ponto),
              ],
            ),
    );
  }
}

/// Cartão com os dados gravados do ponto.
class _CartaoDetalhes extends StatelessWidget {
  const _CartaoDetalhes({required this.ponto});

  final Ponto ponto;

  @override
  Widget build(BuildContext context) {
    final lat = ponto.latitude ?? 0;
    final lon = ponto.longitude ?? 0;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.place, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ponto.nome,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(ponto.endereco),
            const Divider(height: 24),
            Text(
              'Latitude: ${lat.toStringAsFixed(6)}\n'
              'Longitude: ${lon.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
