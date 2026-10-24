import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/dependencias.dart';
import '../core/excecoes.dart';
import '../core/geo_utils.dart';
import '../models/rota.dart';
import '../services/navegacao_service.dart';
import '../widgets/avisos.dart';
import '../widgets/estados.dart';
import '../widgets/mapa_base.dart';
import '../widgets/resumo_rota.dart';

/// Navegação assistida ao longo de uma rota.
///
/// O aplicativo acompanha a posição do veículo pelo GPS, mantém em destaque o
/// próximo ponto da ordem de visita, mostra a distância e o sentido até ele e
/// avança sozinho para a próxima parada quando o veículo entra no raio de
/// chegada. A tela também permite avançar manualmente, o que cobre imprecisão
/// do sinal em área urbana densa.
///
/// Esta é uma navegação assistida, não uma navegação curva a curva: o sistema
/// não recalcula a cada desvio nem emite comandos de voz. O que ele resolve é
/// o problema levantado nos requisitos — manter o motorista informado sobre
/// qual é a próxima entrega e quanto falta —, aproveitando a ordem de visita
/// já otimizada e o traçado gravado.
class NavegacaoPage extends StatefulWidget {
  const NavegacaoPage({super.key, required this.rota});

  final Rota rota;

  @override
  State<NavegacaoPage> createState() => _NavegacaoPageState();
}

class _NavegacaoPageState extends State<NavegacaoPage> {
  final MapController _controladorMapa = MapController();

  StreamSubscription<Position>? _assinaturaPosicao;
  LatLng? _posicaoAtual;
  int _indiceAtual = 0;
  bool _carregando = true;
  bool _mapaPronto = false;
  bool _seguindoVeiculo = true;
  bool _conclusaoAvisada = false;
  String? _erro;

  NavegacaoService get _navegacao => Dependencias.instance.navegacao;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _mapaPronto = true);
    });
    _iniciar();
  }

  @override
  void dispose() {
    _assinaturaPosicao?.cancel();
    super.dispose();
  }

  Future<void> _iniciar() async {
    try {
      final posicao = await Dependencias.instance.localizacao.posicaoAtual();
      if (!mounted) return;
      setState(() {
        _posicaoAtual = LatLng(posicao.latitude, posicao.longitude);
        _indiceAtual = _navegacao.proximoIndice(
          widget.rota.pontos,
          _posicaoAtual!,
        );
        _carregando = false;
      });
      _centralizarNoVeiculo();

      _assinaturaPosicao = Dependencias.instance.localizacao
          .acompanhar()
          .listen(_aoAtualizarPosicao, onError: _aoFalharPosicao);
    } on FalhaApp catch (falha) {
      if (!mounted) return;
      setState(() {
        _erro = falha.mensagem;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível iniciar o acompanhamento por GPS.';
        _carregando = false;
      });
    }
  }

  void _aoAtualizarPosicao(Position posicao) {
    if (!mounted) return;
    final novaPosicao = LatLng(posicao.latitude, posicao.longitude);
    final anterior = _indiceAtual;
    final novo = _navegacao.proximoIndice(
      widget.rota.pontos,
      novaPosicao,
      aPartirDe: _indiceAtual,
    );

    setState(() {
      _posicaoAtual = novaPosicao;
      _indiceAtual = novo;
    });

    // O índice só avança quando o veículo entra no raio de chegada do ponto,
    // então a mudança é o próprio aviso de que a parada foi cumprida.
    if (novo > anterior) {
      Avisos.sucesso(
        context,
        'Ponto alcançado: ${widget.rota.pontos[anterior].nome}',
      );
    }

    if (_seguindoVeiculo) _centralizarNoVeiculo();
    _verificarConclusao(novaPosicao);
  }

  void _aoFalharPosicao(Object erro) {
    if (!mounted) return;
    Avisos.erro(context, 'O sinal de GPS foi interrompido.');
  }

  void _centralizarNoVeiculo() {
    final posicao = _posicaoAtual;
    if (posicao == null || !_mapaPronto) return;
    // O controlador pode ainda não estar ligado ao mapa em uma reconstrução
    // intermediária; nesse caso a centralização é simplesmente ignorada.
    try {
      _controladorMapa.move(posicao, 17);
    } catch (_) {
      // Sem ação: o mapa será centralizado na próxima atualização de posição.
    }
  }

  void _verificarConclusao(LatLng posicao) {
    if (_conclusaoAvisada) return;
    if (!_navegacao.navegacaoConcluida(widget.rota, posicao)) return;

    _conclusaoAvisada = true;
    Avisos.sucesso(context, 'Você chegou ao último ponto da rota!');
  }

  void _avancarManualmente() {
    final pontos = widget.rota.pontos;
    if (_indiceAtual >= pontos.length - 1) {
      Avisos.informacao(context, 'Este já é o último ponto da rota.');
      return;
    }
    setState(() => _indiceAtual++);
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.rota.nome)),
        body: const TelaCarregando(mensagem: 'Obtendo a sua posição...'),
      );
    }

    if (_erro != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.rota.nome)),
        body: EstadoVazio(
          icone: Icons.gps_off,
          titulo: 'Navegação indisponível',
          descricao: _erro!,
          rotuloAcao: 'Tentar novamente',
          aoAcionar: () {
            setState(() {
              _erro = null;
              _carregando = true;
            });
            _iniciar();
          },
        ),
      );
    }

    final posicao = _posicaoAtual;
    final passo = posicao == null
        ? null
        : _navegacao.passoAtual(
            widget.rota,
            posicao,
            indiceAtual: _indiceAtual,
          );
    final centro = posicao ?? widget.rota.centroMapa;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rota.nome),
        actions: [
          IconButton(
            tooltip: _seguindoVeiculo
                ? 'Deixar de seguir o veículo'
                : 'Centralizar no veículo',
            onPressed: () {
              setState(() => _seguindoVeiculo = !_seguindoVeiculo);
              if (_seguindoVeiculo) _centralizarNoVeiculo();
            },
            icon: Icon(_seguindoVeiculo ? Icons.gps_fixed : Icons.gps_not_fixed),
          ),
        ],
      ),
      body: Column(
        children: [
          if (passo != null) _FaixaInstrucao(passo: passo),
          Expanded(
            child: centro == null
                ? const EstadoVazio(
                    icone: Icons.map_outlined,
                    titulo: 'Rota sem coordenadas',
                    descricao: 'Não há pontos localizados para exibir no mapa.',
                  )
                : MapaBase(
                    controlador: _controladorMapa,
                    centro: centro,
                    zoom: 16,
                    linha: widget.rota.geometria,
                    marcadores: [
                      for (var i = 0; i < widget.rota.pontos.length; i++)
                        if (widget.rota.pontos[i].coordenada != null)
                          marcadorNumerado(
                            widget.rota.pontos[i].coordenada!,
                            i + 1,
                            cor: corDaParada(i, widget.rota.pontos.length,
                                tipo: widget.rota.tipo),
                          ),
                      if (posicao != null) marcadorPosicaoAtual(posicao),
                    ],
                  ),
          ),
          if (posicao != null) _PainelInferior(
            rota: widget.rota,
            indiceAtual: passo?.indice ?? _indiceAtual,
            distanciaRestante: _navegacao.distanciaRestanteKm(
              widget.rota,
              posicao,
              indiceAtual: _indiceAtual,
            ),
            progresso: _navegacao.progresso(
              widget.rota,
              posicao,
              indiceAtual: _indiceAtual,
            ),
            aoAvancar: _avancarManualmente,
            aoCentralizar: () {
              setState(() => _seguindoVeiculo = true);
              _centralizarNoVeiculo();
            },
          ),
        ],
      ),
    );
  }
}

/// Faixa superior com a instrução do próximo ponto.
class _FaixaInstrucao extends StatelessWidget {
  const _FaixaInstrucao({required this.passo});

  final PassoNavegacao passo;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: esquema.primary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            passo.chegou ? Icons.flag : Icons.turn_slight_right,
            color: esquema.onPrimary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              passo.instrucao,
              style: TextStyle(
                color: esquema.onPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Painel inferior com progresso, distância restante e ações da navegação.
class _PainelInferior extends StatelessWidget {
  const _PainelInferior({
    required this.rota,
    required this.indiceAtual,
    required this.distanciaRestante,
    required this.progresso,
    required this.aoAvancar,
    required this.aoCentralizar,
  });

  final Rota rota;
  final int indiceAtual;
  final double distanciaRestante;
  final double progresso;
  final VoidCallback aoAvancar;
  final VoidCallback aoCentralizar;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final pontoAtual = rota.pontos[indiceAtual];

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: progresso,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Próxima parada ${indiceAtual + 1} de '
                          '${rota.pontos.length}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Text(
                          pontoAtual.nome,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Restante',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        GeoUtils.formatarDistancia(distanciaRestante),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: esquema.primary),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: aoCentralizar,
                      icon: const Icon(Icons.my_location, size: 18),
                      label: const Text('Centralizar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: aoAvancar,
                      icon: const Icon(Icons.skip_next, size: 18),
                      label: const Text('Próximo ponto'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
