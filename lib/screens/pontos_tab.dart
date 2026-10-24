import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/dependencias.dart';
import '../models/ponto.dart';
import '../widgets/avisos.dart';
import '../widgets/estados.dart';
import 'form_page.dart';
import 'map_page.dart';

/// Lista de pontos cadastrados (caso de uso UC01 — Gerenciar Locais).
class PontosTab extends StatefulWidget {
  const PontosTab({
    super.key,
    required this.idUsuario,
    required this.gatilhoAtualizacao,
  });

  final int? idUsuario;

  /// Incrementado pela tela inicial quando um ponto é criado em outra tela.
  final ValueListenable<int> gatilhoAtualizacao;

  @override
  State<PontosTab> createState() => _PontosTabState();
}

class _PontosTabState extends State<PontosTab> {
  List<Ponto> _pontos = const [];
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
          await Dependencias.instance.pontos.listar(idUsuario: widget.idUsuario);
      if (!mounted) return;
      setState(() {
        _pontos = lista;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os pontos salvos.';
        _carregando = false;
      });
    }
  }

  Future<void> _abrirFormulario({Ponto? ponto}) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FormPage(
          pontoParaEditar: ponto,
          idUsuario: widget.idUsuario,
        ),
      ),
    );
    if (!mounted) return;
    if (salvou ?? false) await _carregar();
  }

  Future<void> _abrirMapa(Ponto ponto) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MapPage(ponto: ponto)),
    );
  }

  Future<void> _excluir(Ponto ponto) async {
    final confirmou = await Avisos.confirmar(
      context,
      titulo: 'Excluir ponto',
      mensagem: 'Remover "${ponto.nome}"? O ponto também sai das rotas que '
          'o utilizam.',
      rotuloConfirmar: 'Excluir',
      destrutivo: true,
    );
    if (!confirmou) return;

    try {
      await Dependencias.instance.pontos.excluir(ponto.id!);
      if (!mounted) return;
      Avisos.sucesso(context, 'Ponto excluído com sucesso!');
      await _carregar();
    } catch (_) {
      if (!mounted) return;
      Avisos.erro(context, 'Não foi possível excluir o ponto.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const TelaCarregando(mensagem: 'Carregando os seus pontos...');
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
    if (_pontos.isEmpty) {
      return EstadoVazio(
        icone: Icons.place_outlined,
        titulo: 'Nenhum ponto salvo ainda',
        descricao: 'Cadastre os locais que você visita com frequência para '
            'depois montar as suas rotas.',
        rotuloAcao: 'Cadastrar o primeiro ponto',
        aoAcionar: () => _abrirFormulario(),
      );
    }

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _pontos.length,
        itemBuilder: (context, indice) {
          final ponto = _pontos[indice];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: ponto.temCoordenadas
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  ponto.temCoordenadas
                      ? Icons.place
                      : Icons.location_off_outlined,
                  color: ponto.temCoordenadas
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
              title: Text(ponto.nome),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ponto.endereco),
                  if (!ponto.temCoordenadas)
                    Text(
                      'Sem coordenadas — toque para tentar localizar',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Editar ponto',
                    icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                    onPressed: () => _abrirFormulario(ponto: ponto),
                  ),
                  IconButton(
                    tooltip: 'Excluir ponto',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _excluir(ponto),
                  ),
                ],
              ),
              onTap: () => _abrirMapa(ponto),
            ),
          );
        },
      ),
    );
  }
}
