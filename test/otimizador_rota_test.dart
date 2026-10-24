import 'package:flutter_test/flutter_test.dart';
import 'package:rotas_app/core/excecoes.dart';
import 'package:rotas_app/core/geo_utils.dart';
import 'package:rotas_app/models/ponto.dart';
import 'package:rotas_app/models/rota.dart';
import 'package:rotas_app/services/otimizador_rota_service.dart';

import 'apoio/banco_teste.dart';

void main() {
  const otimizador = OtimizadorRotaService();

  /// Quatro pontos formando um quadrado, usados para verificar o 2-opt.
  ///
  /// A ordem A → C → B → D cruza as diagonais; a ordem ótima percorre o
  /// perímetro A → B → C → D.
  final a = pontoComCoordenada('A', 0, 0);
  final b = pontoComCoordenada('B', 0, 1);
  final c = pontoComCoordenada('C', 1, 1);
  final d = pontoComCoordenada('D', 1, 0);

  group('OtimizadorRotaService.refinar (2-opt)', () {
    test('desfaz o cruzamento em um circuito', () {
      final resultado = otimizador.refinar([a, c, b, d], circuito: true);

      expect(resultado.movimentos2Opt, greaterThan(0));
      expect(resultado.distanciaKm, lessThan(resultado.distanciaAntesKm));
      // Perímetro do quadrado: três lados de 1 grau e um de 1 grau de
      // longitude na latitude 1, aproximadamente 444,8 km.
      expect(resultado.distanciaKm, closeTo(444.76, 1.0));
      expect(
        resultado.pontos.map((ponto) => ponto.nome).toSet(),
        {'A', 'B', 'C', 'D'},
      );
    });

    test('desfaz o cruzamento em uma rota ponto a ponto mantendo os extremos', () {
      final resultado = otimizador.refinar([a, c, b, d], circuito: false);

      expect(resultado.distanciaKm, lessThan(resultado.distanciaAntesKm));
      // Os extremos A (partida) e D (destino) não podem mudar de posição.
      expect(resultado.pontos.first.nome, 'A');
      expect(resultado.pontos.last.nome, 'D');
      expect(resultado.distanciaKm, closeTo(333.57, 1.0));
    });

    test('não altera uma ordem que já é ótima', () {
      final resultado = otimizador.refinar([a, b, c, d], circuito: true);
      expect(resultado.movimentos2Opt, 0);
      expect(resultado.distanciaKm, closeTo(resultado.distanciaAntesKm, 1e-9));
    });

    test('exige ao menos dois pontos com coordenadas', () {
      expect(
        () => otimizador.refinar([pontoSemCoordenada('X')], circuito: true),
        throwsA(isA<DadosInvalidos>()),
      );
    });
  });

  group('OtimizadorRotaService.otimizar', () {
    test('posiciona a origem no início e o destino no fim', () {
      final pontos = [
        pontoComCoordenada('P1', 0, 0),
        pontoComCoordenada('P2', 0, 1),
        pontoComCoordenada('P3', 0, 2),
        pontoComCoordenada('P4', 0, 3),
      ];

      final resultado = otimizador.otimizar(
        pontos: pontos,
        tipo: TipoRota.pontoAPonto,
        origem: pontos[3],
        destino: pontos[0],
      );

      expect(resultado.pontos.first.nome, 'P4');
      expect(resultado.pontos.last.nome, 'P1');
      expect(resultado.pontos, hasLength(4));
    });

    test('descarta pontos sem coordenadas', () {
      final pontos = [
        pontoComCoordenada('P1', 0, 0),
        pontoSemCoordenada('Sem mapa'),
        pontoComCoordenada('P2', 0, 1),
      ];

      final resultado =
          otimizador.otimizar(pontos: pontos, tipo: TipoRota.circuito);

      expect(resultado.pontos, hasLength(2));
      expect(
        resultado.pontos.map((ponto) => ponto.nome),
        isNot(contains('Sem mapa')),
      );
    });

    test('nunca piora em relação à ordem da heurística construtiva', () {
      final pontos = [
        pontoComCoordenada('P1', 0, 0),
        pontoComCoordenada('P2', 0.5, 2.0),
        pontoComCoordenada('P3', 1.0, 0.4),
        pontoComCoordenada('P4', 1.6, 2.4),
        pontoComCoordenada('P5', 2.2, 0.9),
        pontoComCoordenada('P6', 2.8, 2.1),
      ];

      final resultado =
          otimizador.otimizar(pontos: pontos, tipo: TipoRota.circuito);

      expect(resultado.distanciaKm,
          lessThanOrEqualTo(resultado.distanciaAntesKm + 1e-9));
    });

    test('fica próximo do ótimo obtido por força bruta em um circuito', () {
      final pontos = [
        pontoComCoordenada('P1', 0, 0),
        pontoComCoordenada('P2', 0.5, 2.0),
        pontoComCoordenada('P3', 1.0, 0.4),
        pontoComCoordenada('P4', 1.6, 2.4),
        pontoComCoordenada('P5', 2.2, 0.9),
      ];

      final resultado =
          otimizador.otimizar(pontos: pontos, tipo: TipoRota.circuito);
      final otimo = _melhorCircuitoPorForcaBruta(pontos);

      // O ótimo é um limite inferior: a heurística não pode ficar melhor que
      // ele, e o teste exige que fique no máximo 15% acima.
      expect(resultado.distanciaKm, greaterThanOrEqualTo(otimo - 1e-6));
      expect(resultado.distanciaKm, lessThanOrEqualTo(otimo * 1.15));
    });

    test('exige ao menos dois pontos com coordenadas', () {
      expect(
        () => otimizador.otimizar(
          pontos: [pontoSemCoordenada('X'), pontoSemCoordenada('Y')],
          tipo: TipoRota.circuito,
        ),
        throwsA(isA<DadosInvalidos>()),
      );
    });
  });
}

/// Calcula o menor circuito possível testando todas as ordens de visita.
///
/// Só é viável para poucos pontos — é exatamente essa explosão combinatória
/// que justifica o uso de heurísticas no aplicativo —, mas serve como
/// referência de qualidade para o algoritmo implementado.
double _melhorCircuitoPorForcaBruta(List<Ponto> pontos) {
  final coordenadas = pontos.map((ponto) => ponto.coordenada!).toList();
  final restantes = List<int>.generate(pontos.length - 1, (i) => i + 1);
  var melhor = double.infinity;

  void avaliar(List<int> ordemParcial) {
    if (ordemParcial.length == restantes.length) {
      final percurso = [0, ...ordemParcial];
      var total = 0.0;
      for (var i = 0; i < percurso.length; i++) {
        total += GeoUtils.distanciaEntre(
          coordenadas[percurso[i]],
          coordenadas[percurso[(i + 1) % percurso.length]],
        );
      }
      if (total < melhor) melhor = total;
      return;
    }
    for (final indice in restantes) {
      if (ordemParcial.contains(indice)) continue;
      avaliar([...ordemParcial, indice]);
    }
  }

  avaliar(const []);
  return melhor;
}
