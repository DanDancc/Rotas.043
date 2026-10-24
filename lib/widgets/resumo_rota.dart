import 'package:flutter/material.dart';

import '../core/geo_utils.dart';
import '../models/ponto.dart';
import '../models/rota.dart';
import '../services/otimizador_rota_service.dart';
import 'estados.dart';

/// Cor do marcador conforme a posição na ordem de visita.
///
/// Verde marca a partida, azul as paradas intermediárias e vermelho o destino
/// final. Em um circuito não existe destino final — o percurso fecha de volta
/// na partida —, por isso nenhuma parada recebe a cor de destino quando o
/// [tipo] é [TipoRota.circuito].
Color corDaParada(int indice, int total, {TipoRota? tipo}) {
  if (indice == 0) return const Color(0xFF2E7D32);
  final ehDestino = tipo != TipoRota.circuito && indice == total - 1;
  if (ehDestino) return const Color(0xFFC62828);
  return const Color(0xFF1565C0);
}

/// Cartão com as métricas de uma rota: distância, duração, paradas, modo e
/// origem do cálculo, além do ganho obtido com a otimização quando houver.
class CartaoResumoRota extends StatelessWidget {
  const CartaoResumoRota({
    super.key,
    required this.rota,
    this.otimizacao,
  });

  final Rota rota;

  /// Resultado da ordenação, quando a rota acabou de ser calculada.
  final ResultadoOtimizacao? otimizacao;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final ganho = otimizacao;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: MetricaRota(
                    icone: Icons.straighten,
                    rotulo: 'Distância',
                    valor: rota.distanciaFormatada,
                  ),
                ),
                Expanded(
                  child: MetricaRota(
                    icone: Icons.schedule,
                    rotulo: 'Duração estimada',
                    valor: rota.duracaoFormatada,
                  ),
                ),
                Expanded(
                  child: MetricaRota(
                    icone: Icons.pin_drop_outlined,
                    rotulo: 'Paradas',
                    valor: '${rota.quantidadePontos}',
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  rota.tipo == TipoRota.circuito
                      ? Icons.loop
                      : Icons.trending_flat,
                  size: 18,
                  color: esquema.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(rota.tipo.rotulo)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.source_outlined, size: 18, color: esquema.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(rota.fonteCalculo.rotulo)),
              ],
            ),
            if (ganho != null && ganho.houveRefinamento) ...[
              const SizedBox(height: 12),
              CaixaAviso(
                icone: Icons.auto_awesome,
                cor: esquema.primary,
                mensagem: 'O refinamento 2-opt reduziu o percurso em '
                    '${GeoUtils.formatarDistancia(ganho.ganhoKm)} '
                    '(${ganho.ganhoPercentual.toStringAsFixed(1)}%), '
                    'com ${ganho.movimentos2Opt} ajuste(s) na ordem de visita.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Uma métrica do resumo, com ícone, valor em destaque e rótulo.
class MetricaRota extends StatelessWidget {
  const MetricaRota({
    super.key,
    required this.icone,
    required this.rotulo,
    required this.valor,
  });

  final IconData icone;
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: esquema.primary),
        const SizedBox(height: 6),
        Text(valor, style: Theme.of(context).textTheme.titleMedium),
        Text(
          rotulo,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: esquema.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Lista numerada com a ordem de visita, indicando partida, destino e o
/// retorno ao início nos circuitos.
class ListaOrdemVisita extends StatelessWidget {
  const ListaOrdemVisita({
    super.key,
    required this.pontos,
    required this.tipo,
    this.indiceAtual,
  });

  final List<Ponto> pontos;
  final TipoRota tipo;

  /// Durante a navegação, destaca o ponto que está sendo perseguido.
  final int? indiceAtual;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final itens = <Widget>[];

    for (var i = 0; i < pontos.length; i++) {
      final ponto = pontos[i];
      final primeiro = i == 0;
      final ultimo = i == pontos.length - 1;
      final emFoco = indiceAtual == i;
      final rotulo = primeiro
          ? 'Partida'
          : ((ultimo && tipo == TipoRota.pontoAPonto) ? 'Destino' : null);

      itens.add(
        Container(
          decoration: emFoco
              ? BoxDecoration(
                  color: esquema.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: corDaParada(i, pontos.length, tipo: tipo),
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(ponto.nome),
            subtitle: Text(ponto.endereco),
            trailing: rotulo == null
                ? (emFoco ? const Icon(Icons.navigation, size: 18) : null)
                : Chip(
                    label: Text(rotulo, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: esquema.surfaceContainerHighest,
                  ),
          ),
        ),
      );
    }

    if (tipo == TipoRota.circuito && pontos.isNotEmpty) {
      itens.add(
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: const CircleAvatar(
            radius: 14,
            backgroundColor: Color(0xFF2E7D32),
            child: Icon(Icons.replay, size: 14, color: Colors.white),
          ),
          title: Text('Retorno a ${pontos.first.nome}'),
          subtitle: const Text('Fecha o circuito'),
        ),
      );
    }

    return Column(children: itens);
  }
}
