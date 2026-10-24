import 'package:flutter/material.dart';

import '../core/dependencias.dart';
import '../core/excecoes.dart';
import '../data/repositories/rota_repository.dart';
import '../models/ponto.dart';
import '../models/rota.dart';
import '../widgets/avisos.dart';
import '../widgets/estados.dart';
import '../widgets/mapa_base.dart';
import '../widgets/resumo_rota.dart';

/// Montagem de uma rota (caso de uso UC02 — Gerar Rotas).
///
/// A tela tem dois passos. No primeiro, o usuário escolhe os pontos, o modo de
/// operação e, se quiser, a origem e o destino. No segundo, vê a prévia
/// calculada — ordem de visita otimizada, traçado no mapa, distância e duração
/// — e decide se salva a rota com um nome.
class RotaFormPage extends StatefulWidget {
  const RotaFormPage({super.key, this.rotaParaEditar, this.idUsuario});

  /// Rota a editar; nulo quando se está criando uma nova.
  final Rota? rotaParaEditar;

  final int? idUsuario;

  @override
  State<RotaFormPage> createState() => _RotaFormPageState();
}

class _RotaFormPageState extends State<RotaFormPage> {
  final _nomeController = TextEditingController();

  List<Ponto> _todosPontos = const [];
  final Set<int> _selecionados = <int>{};

  TipoRota _tipo = TipoRota.pontoAPonto;
  int? _origemId;
  int? _destinoId;

  PreviaRota? _previa;

  bool _carregandoPontos = true;
  bool _calculando = false;
  bool _salvando = false;

  bool get _editando => widget.rotaParaEditar != null;

  @override
  void initState() {
    super.initState();
    _prepararEdicao();
    _carregarPontos();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    super.dispose();
  }

  void _prepararEdicao() {
    final rota = widget.rotaParaEditar;
    if (rota == null) return;
    _nomeController.text = rota.nome;
    _tipo = rota.tipo;
    for (final ponto in rota.pontos) {
      final id = ponto.id;
      if (id != null) _selecionados.add(id);
    }
    _origemId = rota.pontos.isNotEmpty ? rota.pontos.first.id : null;
    if (rota.tipo == TipoRota.pontoAPonto && rota.pontos.length > 1) {
      _destinoId = rota.pontos.last.id;
    }
  }

  Future<void> _carregarPontos() async {
    try {
      final lista = await Dependencias.instance.pontos
          .listar(idUsuario: widget.idUsuario);
      if (!mounted) return;
      setState(() {
        _todosPontos = lista;
        _carregandoPontos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoPontos = false);
      Avisos.erro(context, 'Não foi possível carregar os pontos cadastrados.');
    }
  }

  /// Pontos selecionados, na ordem em que aparecem na lista carregada.
  List<Ponto> get _pontosSelecionados => _todosPontos
      .where((ponto) => ponto.id != null && _selecionados.contains(ponto.id))
      .toList(growable: false);

  List<Ponto> get _pontosUtilizaveis =>
      _pontosSelecionados.where((p) => p.temCoordenadas).toList(growable: false);

  void _alternarSelecao(Ponto ponto, bool selecionado) {
    final id = ponto.id;
    if (id == null) return;
    setState(() {
      if (selecionado) {
        _selecionados.add(id);
        _origemId ??= id;
      } else {
        _selecionados.remove(id);
        if (_origemId == id) _origemId = null;
        if (_destinoId == id) _destinoId = null;
      }
      // Qualquer mudança na seleção invalida a prévia já calculada, para que
      // o usuário nunca salve uma rota diferente da que está vendo.
      _previa = null;
    });
  }

  void _alterarTipo(TipoRota tipo) {
    setState(() {
      _tipo = tipo;
      _previa = null;
      if (tipo == TipoRota.circuito) _destinoId = null;
    });
  }

  Ponto? _pontoPorId(int? id) {
    if (id == null) return null;
    for (final ponto in _todosPontos) {
      if (ponto.id == id) return ponto;
    }
    return null;
  }

  Future<void> _calcular() async {
    final utilizaveis = _pontosUtilizaveis;
    if (utilizaveis.length < 2) {
      Avisos.atencao(
        context,
        'Selecione ao menos dois pontos com endereço localizado no mapa.',
      );
      return;
    }

    final origem = _pontoPorId(_origemId);
    final destino =
        _tipo == TipoRota.pontoAPonto ? _pontoPorId(_destinoId) : null;
    if (_tipo == TipoRota.pontoAPonto &&
        origem != null &&
        destino != null &&
        origem.id == destino.id) {
      Avisos.atencao(context, 'A origem e o destino devem ser pontos diferentes.');
      return;
    }

    setState(() => _calculando = true);
    try {
      final previa = await Dependencias.instance.rotas.calcular(
        pontos: utilizaveis,
        tipo: _tipo,
        origem: origem,
        destino: destino,
      );
      if (!mounted) return;
      setState(() {
        _previa = previa;
        _calculando = false;
      });

      if (previa.aviso != null) {
        Avisos.atencao(context, previa.aviso!);
      } else if (previa.otimizacao.houveRefinamento) {
        Avisos.sucesso(
          context,
          'Rota calculada com economia de '
          '${previa.otimizacao.ganhoPercentual.toStringAsFixed(1)}% '
          'em relação à primeira ordem encontrada.',
        );
      } else {
        Avisos.sucesso(context, 'Rota calculada com sucesso.');
      }
    } on FalhaApp catch (falha) {
      if (!mounted) return;
      setState(() => _calculando = false);
      Avisos.erro(context, falha.mensagem);
    } catch (_) {
      if (!mounted) return;
      setState(() => _calculando = false);
      Avisos.erro(context, 'Não foi possível calcular a rota.');
    }
  }

  Future<void> _salvar() async {
    final previa = _previa;
    if (previa == null) {
      Avisos.atencao(context, 'Calcule a rota antes de salvar.');
      return;
    }
    if (_nomeController.text.trim().isEmpty) {
      Avisos.atencao(context, 'Dê um nome para identificar esta rota.');
      return;
    }

    setState(() => _salvando = true);
    try {
      await Dependencias.instance.rotas.salvar(
        previa: previa,
        nome: _nomeController.text,
        idUsuario: widget.idUsuario,
        idRota: widget.rotaParaEditar?.id,
      );
      if (!mounted) return;
      Avisos.sucesso(
        context,
        _editando ? 'Rota atualizada com sucesso!' : 'Rota salva com sucesso!',
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _salvando = false);
      Avisos.erro(context, 'Não foi possível salvar a rota.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar rota' : 'Nova rota'),
      ),
      body: _carregandoPontos
          ? const TelaCarregando(mensagem: 'Carregando os pontos...')
          : _previa == null
              ? _construirSelecao()
              : _construirPrevia(_previa!),
      bottomNavigationBar: _previa == null ? null : _construirBarraSalvar(),
    );
  }

  // --- Passo 1: seleção ---------------------------------------------------

  Widget _construirSelecao() {
    if (_todosPontos.isEmpty) {
      return const EstadoVazio(
        icone: Icons.place_outlined,
        titulo: 'Nenhum ponto cadastrado',
        descricao: 'Cadastre pontos de interesse na aba "Pontos" antes de '
            'montar uma rota.',
      );
    }

    final utilizaveis =
        _todosPontos.where((ponto) => ponto.temCoordenadas).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_editando)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: CaixaAviso(
              icone: Icons.edit_outlined,
              cor: Theme.of(context).colorScheme.primary,
              mensagem: 'Você está editando "${widget.rotaParaEditar!.nome}". '
                  'Ajuste os pontos e recalcule para atualizar a rota.',
            ),
          ),
        Text('Modo da rota', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<TipoRota>(
          segments: const [
            ButtonSegment(
              value: TipoRota.pontoAPonto,
              icon: Icon(Icons.trending_flat),
              label: Text('Ponto a ponto'),
            ),
            ButtonSegment(
              value: TipoRota.circuito,
              icon: Icon(Icons.loop),
              label: Text('Circuito'),
            ),
          ],
          selected: {_tipo},
          onSelectionChanged: (selecao) => _alterarTipo(selecao.first),
        ),
        const SizedBox(height: 4),
        Text(
          _tipo == TipoRota.circuito
              ? 'O trajeto retorna ao ponto de partida.'
              : 'O trajeto termina no último ponto visitado.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text('Pontos da rota',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            Text(
              '${_selecionados.length} selecionado(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (utilizaveis.isEmpty)
          const CaixaAviso(
            mensagem: 'Nenhum ponto possui coordenadas localizadas. Edite os '
                'pontos na aba "Pontos" para localizá-los no mapa.',
          ),
        ..._todosPontos.map(_construirItemPonto),
        const SizedBox(height: 20),
        if (_selecionados.length >= 2) ...[
          Text('Origem da rota', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _origemId,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.trip_origin),
              border: OutlineInputBorder(),
            ),
            items: _pontosUtilizaveis
                .map((ponto) => DropdownMenuItem(
                      value: ponto.id,
                      child: Text(ponto.nome, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (valor) => setState(() {
              _origemId = valor;
              _previa = null;
            }),
          ),
          if (_tipo == TipoRota.pontoAPonto) ...[
            const SizedBox(height: 16),
            Text('Destino da rota',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _destinoId,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.flag_outlined),
                helperText: 'Opcional: sem destino, a rota termina no ponto '
                    'mais distante da origem.',
                border: OutlineInputBorder(),
              ),
              items: _pontosUtilizaveis
                  .where((ponto) => ponto.id != _origemId)
                  .map((ponto) => DropdownMenuItem(
                        value: ponto.id,
                        child: Text(ponto.nome, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (valor) => setState(() {
                _destinoId = valor;
                _previa = null;
              }),
            ),
          ],
        ],
        const SizedBox(height: 28),
        _calculando
            ? const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Otimizando a ordem e buscando o trajeto...'),
                  ],
                ),
              )
            : FilledButton.icon(
                onPressed: _calcular,
                icon: const Icon(Icons.alt_route),
                label: const Text('Calcular rota'),
              ),
      ],
    );
  }

  Widget _construirItemPonto(Ponto ponto) {
    final id = ponto.id;
    final selecionado = id != null && _selecionados.contains(id);
    final disponivel = ponto.temCoordenadas;

    return Card(
      child: CheckboxListTile(
        value: selecionado,
        onChanged: disponivel
            ? (valor) => _alternarSelecao(ponto, valor ?? false)
            : null,
        title: Text(ponto.nome),
        subtitle: Text(
          disponivel
              ? ponto.endereco
              : '${ponto.endereco}\nSem coordenadas — não pode entrar na rota',
          style: disponivel
              ? null
              : TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        secondary: Icon(
          disponivel ? Icons.place : Icons.location_off_outlined,
          color: disponivel
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        controlAffinity: ListTileControlAffinity.trailing,
      ),
    );
  }

  // --- Passo 2: prévia ----------------------------------------------------

  Widget _construirPrevia(PreviaRota previa) {
    final rota = previa.rota;
    final centro = rota.centroMapa;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        SizedBox(
          height: 300,
          child: centro == null
              ? const Center(child: Text('Sem coordenadas para exibir.'))
              : MapaBase(
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
              if (previa.aviso != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: CaixaAviso(mensagem: previa.aviso!),
                ),
              CartaoResumoRota(rota: rota, otimizacao: previa.otimizacao),
              const SizedBox(height: 20),
              Text('Ordem de visita otimizada',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ListaOrdemVisita(pontos: rota.pontos, tipo: rota.tipo),
              const SizedBox(height: 20),
              Text('Nome da rota',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _nomeController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ex.: Entregas do centro — manhã',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => setState(() => _previa = null),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.tune),
                label: const Text('Ajustar pontos e recalcular'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _construirBarraSalvar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: _salvando
            ? const Center(child: CircularProgressIndicator())
            : FilledButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.save_outlined),
                label: Text(_editando ? 'Salvar alterações' : 'Salvar rota'),
              ),
      ),
    );
  }
}
