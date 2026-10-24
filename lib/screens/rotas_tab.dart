import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/dependencias.dart';
import '../models/rota.dart';
import '../widgets/avisos.dart';
import '../widgets/estados.dart';
import 'rota_form_page.dart';
import 'rota_mapa_page.dart';

/// Lista das rotas salvas (caso de uso UC03 — Gerenciar Rotas Salvas).
class RotasTab extends StatefulWidget {
  const RotasTab({
    super.key,
    required this.idUsuario,
    required this.gatilhoAtualizacao,
  });

  final int? idUsuario;
  final ValueListenable<int> gatilhoAtualizacao;

  @override
  State<RotasTab> createState() => _RotasTabState();
}

class _RotasTabState extends State<RotasTab> {
  List<Rota> _rotas = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    widget.gatilhoAtualizacao.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    widget.gatilhoAtualizacao.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    if (mounted) setState(() => _erro = null);
    try {
      final lista =
          await Dependencias.instance.rotas.listar(idUsuario: widget.idUsuario);
      if (!mounted) return;
      setState(() {
        _rotas = lista;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar as rotas salvas.';
        _carregando = false;
      });
    }
  }

  Future<void> _abrirMapa(Rota rota) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RotaMapaPage(rota: rota)),
    );
    if (!mounted) return;
    await _carregar();
  }

  Future<void> _editar(Rota rota) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RotaFormPage(
          rotaParaEditar: rota,
          idUsuario: widget.idUsuario,
        ),
      ),
    );
    if (!mounted) return;
    if (salvou ?? false) await _carregar();
  }

  Future<void> _excluir(Rota rota) async {
    final confirmou = await Avisos.confirmar(
      context,
      titulo: 'Excluir rota',
      mensagem: 'Remover a rota "${rota.nome}"? Os pontos cadastrados '
          'continuam salvos.',
      rotuloConfirmar: 'Excluir',
      destrutivo: true,
    );
    if (!confirmou) return;

    try {
      await Dependencias.instance.rotas.excluir(rota.id!);
      if (!mounted) return;
      Avisos.sucesso(context, 'Rota excluída com sucesso!');
      await _carregar();
    } catch (_) {
      if (!mounted) return;
      Avisos.erro(context, 'Não foi possível excluir a rota.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const TelaCarregando(mensagem: 'Carregando as suas rotas...');
    }
    if (_erro != null) {
      return EstadoVazio(
        icone: Icons.cloud_off_outlined,
        titulo: 'Falha ao carregar',
        descricao: _erro!,
        rotuloAcao: 'Tentar novamente',
        aoAcionar: _carregar,
      );
    }
    if (_rotas.isEmpty) {
      return EstadoVazio(
        icone: Icons.route_outlined,
        titulo: 'Nenhuma rota salva ainda',
        descricao: 'Monte uma rota escolhendo os pontos cadastrados. '
            'O sistema calcula a melhor ordem de visita e você pode salvá-la '
            'para reutilizar depois.',
        rotuloAcao: 'Montar a primeira rota',
        aoAcionar: () async {
          final salvou = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => RotaFormPage(idUsuario: widget.idUsuario),
            ),
          );
          if (!mounted) return;
          if (salvou ?? false) await _carregar();
        },
      );
    }

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _rotas.length,
        itemBuilder: (context, indice) {
          final rota = _rotas[indice];
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _abrirMapa(rota),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rota.nome,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Editar rota',
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.blue),
                          onPressed: () => _editar(rota),
                        ),
                        IconButton(
                          tooltip: 'Excluir rota',
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () => _excluir(rota),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Etiqueta(
                          icone: rota.tipo == TipoRota.circuito
                              ? Icons.loop
                              : Icons.trending_flat,
                          texto: rota.tipo.rotulo,
                        ),
                        _Etiqueta(
                          icone: Icons.pin_drop_outlined,
                          texto: '${rota.quantidadePontos} paradas',
                        ),
                        _Etiqueta(
                          icone: Icons.straighten,
                          texto: rota.distanciaFormatada,
                        ),
                        _Etiqueta(
                          icone: Icons.schedule,
                          texto: rota.duracaoFormatada,
                        ),
                      ],
                    ),
                    if (rota.fonteCalculo == FonteCalculo.local) ...[
                      const SizedBox(height: 10),
                      const CaixaAviso(
                        mensagem: 'Distância estimada em linha reta para esta '
                            'rota salva.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: esquema.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: esquema.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(texto, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
