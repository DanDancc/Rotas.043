import 'package:flutter/material.dart';

/// Indicador de carregamento em tela cheia, com mensagem opcional.
class TelaCarregando extends StatelessWidget {
  const TelaCarregando({super.key, this.mensagem});

  final String? mensagem;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (mensagem != null) ...[
            const SizedBox(height: 16),
            Text(mensagem!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Estado de lista vazia, com ícone, título, explicação e ação opcional.
class EstadoVazio extends StatelessWidget {
  const EstadoVazio({
    super.key,
    required this.icone,
    required this.titulo,
    required this.descricao,
    this.rotuloAcao,
    this.aoAcionar,
  });

  final IconData icone;
  final String titulo;
  final String descricao;
  final String? rotuloAcao;
  final VoidCallback? aoAcionar;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 64, color: esquema.outline),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              descricao,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: esquema.onSurfaceVariant),
            ),
            if (rotuloAcao != null && aoAcionar != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: aoAcionar,
                icon: const Icon(Icons.add),
                label: Text(rotuloAcao!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Caixa de aviso reutilizável, usada para mostrar o recuo para a estimativa
/// local ou instruções ao usuário.
class CaixaAviso extends StatelessWidget {
  const CaixaAviso({
    super.key,
    required this.mensagem,
    this.icone = Icons.warning_amber_outlined,
    this.cor,
  });

  final String mensagem;
  final IconData icone;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final tonalidade = cor ?? const Color(0xFFEF6C00);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tonalidade.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tonalidade.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: tonalidade, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensagem,
              style: TextStyle(color: tonalidade, fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
