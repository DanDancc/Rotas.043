import 'package:flutter/material.dart';

import '../models/rota.dart';
import '../widgets/estados.dart';
import '../widgets/mapa_base.dart';
import '../widgets/resumo_rota.dart';
import 'navegacao_page.dart';

/// Exibição de uma rota salva no mapa (caso de uso UC03).
///
/// Mostra o traçado, os marcadores numerados na ordem de visita, o resumo do
/// percurso e o ponto de partida para a navegação assistida.
class RotaMapaPage extends StatelessWidget {
  const RotaMapaPage({super.key, required this.rota});

  final Rota rota;

  @override
  Widget build(BuildContext context) {
    final centro = rota.centroMapa;

    if (centro == null) {
      return Scaffold(
        appBar: AppBar(title: Text(rota.nome)),
        body: const EstadoVazio(
          icone: Icons.location_off_outlined,
          titulo: 'Rota sem coordenadas',
          descricao: 'Os pontos desta rota não possuem coordenadas localizadas. '
              'Edite os pontos para localizá-los no mapa.',
        ),
      );
    }

    final podeNavegar = rota.pontos.length >= 2;

    return Scaffold(
      appBar: AppBar(title: Text(rota.nome)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SizedBox(
            height: 320,
            child: MapaBase(
              centro: centro,
              zoom: 13,
              linha: rota.geometria.isNotEmpty
                  ? rota.geometria
                  : rota.coordenadasDosPontos,
              marcadores: [
                for (var i = 0; i < rota.pontos.length; i++)
                  if (rota.pontos[i].coordenada != null)
                    marcadorNumerado(
                      rota.pontos[i].coordenada!,
                      i + 1,
                      cor: corDaParada(i, rota.pontos.length, tipo: rota.tipo),
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rota.fonteCalculo == FonteCalculo.local)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: CaixaAviso(
                      mensagem: 'Este percurso foi estimado em linha reta, '
                          'sem seguir as vias. Recalcule a rota com conexão '
                          'para obter o traçado pelas ruas.',
                    ),
                  ),
                CartaoResumoRota(rota: rota),
                const SizedBox(height: 20),
                Text('Ordem de visita',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                ListaOrdemVisita(pontos: rota.pontos, tipo: rota.tipo),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: podeNavegar
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NavegacaoPage(rota: rota),
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Iniciar navegação assistida'),
                ),
                if (!podeNavegar) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'São necessários ao menos dois pontos para navegar.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
