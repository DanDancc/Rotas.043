import 'package:latlong2/latlong.dart';

import '../core/excecoes.dart';
import '../core/geo_utils.dart';
import '../models/ponto.dart';
import '../models/rota.dart';

/// Resultado da ordenação otimizada dos pontos de uma rota.
class ResultadoOtimizacao {
  const ResultadoOtimizacao({
    required this.pontos,
    required this.distanciaKm,
    required this.distanciaAntesKm,
    required this.movimentos2Opt,
  });

  /// Pontos já na ordem de visita otimizada.
  final List<Ponto> pontos;

  /// Distância da ordem final, em quilômetros.
  final double distanciaKm;

  /// Distância da ordem produzida apenas pela heurística construtiva, antes
  /// do refinamento. Serve para medir o ganho obtido com o 2-opt.
  final double distanciaAntesKm;

  /// Quantidade de inversões de trecho aceitas pelo 2-opt.
  final int movimentos2Opt;

  /// Quilômetros economizados pelo refinamento.
  double get ganhoKm => distanciaAntesKm - distanciaKm;

  /// Percentual economizado pelo refinamento, em relação à ordem inicial.
  double get ganhoPercentual =>
      distanciaAntesKm <= 0 ? 0 : (ganhoKm / distanciaAntesKm) * 100.0;

  bool get houveRefinamento => movimentos2Opt > 0;
}

/// Ordena os pontos de uma rota para reduzir a distância total percorrida.
///
/// O problema de encontrar a menor rota que visita um conjunto de pontos é o
/// do caixeiro-viajante, que é NP-difícil: o número de ordens possíveis cresce
/// de forma fatorial e não há solução exata viável para muitos pontos em um
/// celular. A estratégia adotada é, portanto, heurística, em duas etapas:
///
/// 1. **Construção — vizinho mais próximo.** Partindo do ponto de origem,
///    escolhe-se sempre o ponto ainda não visitado mais próximo do atual. É
///    rápido (custo quadrático), mas pode deixar um trecho longo para o final.
/// 2. **Refinamento — 2-opt.** Procura-se um par de arestas cuja troca encurte
///    o percurso; quando encontrado, o trecho entre elas é invertido. Repete-se
///    até não haver melhora, o que elimina os cruzamentos de trajeto típicos
///    do resultado do vizinho mais próximo.
///
/// A classe não depende de banco nem de interface, o que permite verificá-la
/// com testes automatizados (ver `test/otimizador_rota_test.dart`).
class OtimizadorRotaService {
  const OtimizadorRotaService();

  /// Número máximo de passagens completas do 2-opt, como salvaguarda contra
  /// laços longos em conjuntos muito grandes de pontos.
  static const int maxPassagens2Opt = 50;

  /// Tolerância para considerar que houve melhora real, evitando que erros de
  /// arredondamento de ponto flutuante disparem inversões inúteis.
  static const double _epsilon = 1e-9;

  /// Distância total de uma sequência de pontos, em quilômetros.
  ///
  /// Quando [circuito] é verdadeiro, soma também o trecho de retorno do
  /// último ponto ao primeiro.
  double distanciaDaOrdem(List<Ponto> ordem, {required bool circuito}) {
    final coordenadas = ordem
        .map((p) => p.coordenada)
        .whereType<LatLng>()
        .toList(growable: false);
    return GeoUtils.distanciaTotalKm(coordenadas, fecharCircuito: circuito);
  }

  /// Ordena [pontos] reduzindo a distância total do percurso.
  ///
  /// [origem] e [destino], quando informados, têm posição fixa: a rota começa
  /// na origem e, em rotas ponto a ponto, termina no destino. Lança
  /// [DadosInvalidos] se houver menos de dois pontos com coordenadas.
  ResultadoOtimizacao otimizar({
    required List<Ponto> pontos,
    required TipoRota tipo,
    Ponto? origem,
    Ponto? destino,
  }) {
    final utilizaveis =
        pontos.where((p) => p.temCoordenadas).toList(growable: false);
    if (utilizaveis.length < 2) {
      throw const DadosInvalidos(
        'São necessários ao menos dois pontos com endereço localizado '
        'no mapa para calcular a rota.',
      );
    }

    final coords = utilizaveis
        .map((p) => p.coordenada!)
        .toList(growable: false);
    final circuito = tipo == TipoRota.circuito;

    final indiceOrigem = _indiceDe(utilizaveis, origem) ?? 0;
    final indiceDestino = circuito ? null : _indiceDe(utilizaveis, destino);
    final destinoFixo = (indiceDestino != null && indiceDestino != indiceOrigem)
        ? indiceDestino
        : null;

    final ordemInicial = _vizinhoMaisProximo(
      coords,
      indiceOrigem,
      destinoFixo: destinoFixo,
    );
    final ordemRefinada = _doisOpt(coords, ordemInicial, circuito: circuito);

    final distanciaInicial =
        _custo(coords, ordemInicial, circuito: circuito);
    final distanciaFinal =
        _custo(coords, ordemRefinada.ordem, circuito: circuito);

    return ResultadoOtimizacao(
      pontos: ordemRefinada.ordem.map((i) => utilizaveis[i]).toList(),
      distanciaKm: distanciaFinal,
      distanciaAntesKm: distanciaInicial,
      movimentos2Opt: ordemRefinada.movimentos,
    );
  }

  /// Aplica apenas o refinamento 2-opt a uma ordem já definida.
  ///
  /// Exposto para permitir que o algoritmo seja verificado isoladamente, com
  /// uma ordem sabidamente cruzada, sem depender da heurística construtiva.
  ResultadoOtimizacao refinar(
    List<Ponto> ordem, {
    required bool circuito,
  }) {
    final utilizaveis =
        ordem.where((ponto) => ponto.temCoordenadas).toList(growable: false);
    if (utilizaveis.length < 2) {
      throw const DadosInvalidos(
        'São necessários ao menos dois pontos com coordenadas para refinar '
        'a ordem de visita.',
      );
    }

    final coords = utilizaveis
        .map((ponto) => ponto.coordenada!)
        .toList(growable: false);
    final inicial = List<int>.generate(coords.length, (i) => i);
    final distanciaAntes = _custo(coords, inicial, circuito: circuito);
    final resultado = _doisOpt(coords, inicial, circuito: circuito);
    final distanciaDepois =
        _custo(coords, resultado.ordem, circuito: circuito);

    return ResultadoOtimizacao(
      pontos: resultado.ordem.map((i) => utilizaveis[i]).toList(),
      distanciaKm: distanciaDepois,
      distanciaAntesKm: distanciaAntes,
      movimentos2Opt: resultado.movimentos,
    );
  }

  static int? _indiceDe(List<Ponto> pontos, Ponto? alvo) {    if (alvo == null) return null;
    if (alvo.id != null) {
      final porId = pontos.indexWhere((p) => p.id == alvo.id);
      if (porId >= 0) return porId;
    }
    final porNome = pontos.indexWhere((p) =>
        p.nome == alvo.nome && p.endereco == alvo.endereco);
    return porNome >= 0 ? porNome : null;
  }

  /// Heurística construtiva do vizinho mais próximo.
  ///
  /// [destinoFixo], quando informado, é reservado para a última posição.
  List<int> _vizinhoMaisProximo(
    List<LatLng> coords,
    int inicio, {
    int? destinoFixo,
  }) {
    final total = coords.length;
    final visitados = List<bool>.filled(total, false);
    final ordem = <int>[inicio];
    visitados[inicio] = true;
    var atual = inicio;

    while (ordem.length < total) {
      final faltam = total - ordem.length;

      // Se o único ponto restante é o destino fixo, não há o que comparar.
      if (destinoFixo != null && !visitados[destinoFixo] && faltam == 1) {
        ordem.add(destinoFixo);
        break;
      }

      int? escolhido;
      var menorDistancia = double.infinity;
      for (var i = 0; i < total; i++) {
        if (visitados[i]) continue;
        if (destinoFixo != null && i == destinoFixo) continue;
        final distancia = GeoUtils.distanciaEntre(coords[atual], coords[i]);
        if (distancia < menorDistancia) {
          menorDistancia = distancia;
          escolhido = i;
        }
      }

      // Sobrou apenas o destino fixo.
      escolhido ??= destinoFixo;
      if (escolhido == null) break;

      visitados[escolhido] = true;
      ordem.add(escolhido);
      atual = escolhido;
    }

    return ordem;
  }

  /// Refinamento 2-opt: inverte trechos enquanto houver ganho de distância.
  ///
  /// Nas rotas em circuito o percurso é um ciclo e o primeiro ponto permanece
  /// fixo como partida. Nas rotas ponto a ponto, o primeiro e o último pontos
  /// são preservados, pois representam a origem e o destino escolhidos.
  ({List<int> ordem, int movimentos}) _doisOpt(
    List<LatLng> coords,
    List<int> inicial, {
    required bool circuito,
    int maxPassagens = maxPassagens2Opt,
  }) {
    final ordem = List<int>.from(inicial);
    final total = ordem.length;
    if (total < 3) return (ordem: ordem, movimentos: 0);

    // Extremos que podem ser invertidos: o primeiro ponto (partida) e, nas
    // rotas ponto a ponto, também o último (destino) ficam de fora.
    final primeiro = 1;
    final ultimo = circuito ? total - 1 : total - 2;

    var movimentos = 0;
    var houveMelhora = true;
    var passagem = 0;

    while (houveMelhora && passagem < maxPassagens) {
      houveMelhora = false;
      passagem++;

      for (var i = primeiro; i <= ultimo; i++) {
        for (var j = i + 1; j <= ultimo; j++) {
          final anterior = ordem[i - 1];
          // No circuito o trecho pode terminar na última posição, e a aresta
          // seguinte dá a volta para o ponto de partida.
          final seguinte =
              circuito ? ordem[(j + 1) % total] : ordem[j + 1];

          final atual =
              GeoUtils.distanciaEntre(coords[anterior], coords[ordem[i]]) +
                  GeoUtils.distanciaEntre(coords[ordem[j]], coords[seguinte]);
          final proposta =
              GeoUtils.distanciaEntre(coords[anterior], coords[ordem[j]]) +
                  GeoUtils.distanciaEntre(coords[ordem[i]], coords[seguinte]);

          if (atual - proposta > _epsilon) {
            _inverter(ordem, i, j);
            movimentos++;
            houveMelhora = true;
          }
        }
      }
    }

    return (ordem: ordem, movimentos: movimentos);
  }

  /// Inverte o trecho entre as posições [de] e [ate], inclusive.
  static void _inverter(List<int> ordem, int de, int ate) {
    while (de < ate) {
      final troca = ordem[de];
      ordem[de] = ordem[ate];
      ordem[ate] = troca;
      de++;
      ate--;
    }
  }

  /// Distância total de uma ordem expressa em índices.
  double _custo(List<LatLng> coords, List<int> ordem, {required bool circuito}) {
    if (ordem.length < 2) return 0;
    var total = 0.0;
    for (var i = 0; i < ordem.length - 1; i++) {
      total += GeoUtils.distanciaEntre(coords[ordem[i]], coords[ordem[i + 1]]);
    }
    if (circuito) {
      total += GeoUtils.distanciaEntre(coords[ordem.last], coords[ordem.first]);
    }
    return total;
  }
}
