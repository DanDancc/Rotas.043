import 'package:latlong2/latlong.dart';

import '../core/geo_utils.dart';
import '../models/ponto.dart';
import '../models/rota.dart';

/// Situação do deslocamento em relação ao próximo ponto da rota.
class PassoNavegacao {
  const PassoNavegacao({
    required this.indice,
    required this.ponto,
    required this.distanciaKm,
    required this.rumoGraus,
    required this.chegou,
    required this.ultimoPonto,
  });

  /// Posição do ponto na ordem de visita.
  final int indice;

  /// Ponto que o motorista deve alcançar agora.
  final Ponto ponto;

  /// Distância atual até esse ponto, em quilômetros.
  final double distanciaKm;

  /// Rumo até esse ponto, em graus (0 = norte).
  final double rumoGraus;

  /// Indica que o veículo já está dentro do raio de chegada do ponto.
  ///
  /// Como [NavegacaoService.passoAtual] sempre devolve o próximo ponto ainda
  /// não alcançado, este sinal só fica verdadeiro quando o alvo é o último
  /// ponto da rota: nos pontos intermediários o índice avança assim que o
  /// veículo chega, e quem informa a chegada é a tela, comparando o índice
  /// anterior com o novo.
  final bool chegou;

  /// Indica que este é o último ponto da rota.
  final bool ultimoPonto;

  /// Ponto cardeal do rumo (N, NE, L, SE, S, SO, O, NO).
  String get direcao => GeoUtils.pontoCardeal(rumoGraus);

  /// Distância pronta para exibição (ex.: "850 m").
  String get distanciaFormatada => GeoUtils.formatarDistancia(distanciaKm);

  /// Instrução textual mostrada em destaque na tela de navegação.
  String get instrucao {
    if (chegou) {
      return 'Você chegou ao destino final: ${ponto.nome}.';
    }
    return 'Siga $distanciaFormatada no sentido $direcao até ${ponto.nome}.';
  }
}

/// Cálculos da navegação assistida a partir da posição do veículo.
///
/// Toda a lógica é pura — recebe uma posição e devolve o próximo passo — o que
/// a torna independente do GPS e verificável por testes automatizados
/// (ver `test/navegacao_test.dart`).
class NavegacaoService {
  const NavegacaoService();

  /// Distância a partir da qual se considera que o veículo chegou ao ponto.
  ///
  /// Cinquenta metros é um valor compatível com a precisão do GPS em área
  /// urbana e com a largura de um quarteirão, evitando que o sistema exija do
  /// motorista parar exatamente sobre a coordenada.
  static const double raioChegadaKm = 0.05;

  /// Índice do próximo ponto ainda não alcançado, partindo de [aPartirDe].
  ///
  /// Avança enquanto o veículo já estiver dentro do raio de chegada do ponto
  /// atual, o que faz a navegação seguir sozinha para a próxima parada.
  int proximoIndice(
    List<Ponto> pontos,
    LatLng posicao, {
    int aPartirDe = 0,
  }) {
    if (pontos.isEmpty) return 0;
    var indice = aPartirDe.clamp(0, pontos.length - 1);

    while (indice < pontos.length - 1) {
      final coordenada = pontos[indice].coordenada;
      if (coordenada == null) {
        indice++;
        continue;
      }
      if (GeoUtils.distanciaEntre(posicao, coordenada) <= raioChegadaKm) {
        indice++;
      } else {
        break;
      }
    }
    return indice;
  }

  /// Monta o passo atual da navegação, ou nulo se a rota não tem coordenadas.
  PassoNavegacao? passoAtual(
    Rota rota,
    LatLng posicao, {
    int indiceAtual = 0,
  }) {
    final pontos = rota.pontos;
    if (pontos.isEmpty) return null;

    final indice = proximoIndice(pontos, posicao, aPartirDe: indiceAtual);
    final ponto = pontos[indice];
    final coordenada = ponto.coordenada;
    if (coordenada == null) return null;

    final distancia = GeoUtils.distanciaEntre(posicao, coordenada);
    return PassoNavegacao(
      indice: indice,
      ponto: ponto,
      distanciaKm: distancia,
      rumoGraus: GeoUtils.rumoGraus(posicao, coordenada),
      chegou: distancia <= raioChegadaKm,
      ultimoPonto: indice == pontos.length - 1,
    );
  }

  /// Distância que ainda falta percorrer, em quilômetros.
  ///
  /// Considera o trecho da posição atual até o próximo ponto, os trechos
  /// seguintes e, nos circuitos, o retorno do último ponto ao ponto de partida
  /// da rota.
  double distanciaRestanteKm(
    Rota rota,
    LatLng posicao, {
    int indiceAtual = 0,
  }) {
    final pontos = rota.pontos;
    if (pontos.isEmpty) return 0;

    final indice = proximoIndice(pontos, posicao, aPartirDe: indiceAtual);
    var total = 0.0;

    final proximo = pontos[indice].coordenada;
    if (proximo != null) {
      total += GeoUtils.distanciaEntre(posicao, proximo);
    }

    final seguintes = pontos
        .sublist(indice)
        .map((ponto) => ponto.coordenada)
        .whereType<LatLng>()
        .toList(growable: false);
    total += GeoUtils.distanciaTotalKm(seguintes);

    // No circuito o percurso só termina quando o veículo volta à partida,
    // que é o primeiro ponto da rota.
    if (rota.tipo == TipoRota.circuito && seguintes.isNotEmpty) {
      final partida = pontos.first.coordenada;
      if (partida != null) {
        total += GeoUtils.distanciaEntre(seguintes.last, partida);
      }
    }
    return total;
  }

  /// Fração da rota já concluída, de 0 a 1, usada na barra de progresso.
  double progresso(Rota rota, LatLng posicao, {int indiceAtual = 0}) {
    final total = rota.pontos.length;
    if (total <= 1) return 0;
    final indice = proximoIndice(rota.pontos, posicao, aPartirDe: indiceAtual);
    return (indice / (total - 1)).clamp(0.0, 1.0);
  }

  /// Indica que o veículo alcançou o último ponto da rota.
  bool navegacaoConcluida(Rota rota, LatLng posicao) {
    final pontos = rota.pontos;
    if (pontos.isEmpty) return true;
    final ultimo = pontos.last.coordenada;
    if (ultimo == null) return false;
    return GeoUtils.distanciaEntre(posicao, ultimo) <= raioChegadaKm;
  }
}
