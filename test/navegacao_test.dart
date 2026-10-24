import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rotas_app/models/rota.dart';
import 'package:rotas_app/services/navegacao_service.dart';

import 'apoio/banco_teste.dart';

void main() {
  const navegacao = NavegacaoService();

  // Três pontos sobre um meridiano, com cerca de 1 km entre cada par.
  final p1 = pontoComCoordenada('P1', 0, 0);
  final p2 = pontoComCoordenada('P2', 0.009, 0);
  final p3 = pontoComCoordenada('P3', 0.018, 0);

  Rota rota(TipoRota tipo) =>
      Rota(nome: 'Rota de teste', tipo: tipo, pontos: [p1, p2, p3]);

  group('NavegacaoService.proximoIndice', () {
    test('mantém o primeiro ponto quando o veículo está longe dele', () {
      expect(
        navegacao.proximoIndice([p1, p2, p3], const LatLng(0.5, 0.5)),
        0,
      );
    });

    test('avança quando o veículo entra no raio de chegada', () {
      expect(navegacao.proximoIndice([p1, p2, p3], const LatLng(0, 0)), 1);
    });

    test('considera chegada a 40 metros e não a 66 metros', () {
      // O raio de chegada é de 50 metros.
      expect(
        navegacao.proximoIndice([p1, p2, p3], const LatLng(0.0004, 0)),
        1,
      );
      expect(
        navegacao.proximoIndice([p1, p2, p3], const LatLng(0.0006, 0)),
        0,
      );
    });

    test('parte do índice informado, sem revisitar pontos já cumpridos', () {
      // Estando sobre o segundo ponto, a navegação deve seguir para o terceiro
      // mesmo que o primeiro esteja longe do veículo.
      expect(
        navegacao.proximoIndice([p1, p2, p3], const LatLng(0.009, 0),
            aPartirDe: 1),
        2,
      );
    });

    test('não ultrapassa o último ponto da lista', () {
      expect(
        navegacao.proximoIndice([p1, p2, p3], const LatLng(0.018, 0),
            aPartirDe: 2),
        2,
      );
    });
  });

  group('NavegacaoService.passoAtual', () {
    test('descreve a distância e o sentido até o próximo ponto', () {
      final passo = navegacao.passoAtual(rota(TipoRota.pontoAPonto),
          const LatLng(0.0, 0.0));

      expect(passo, isNotNull);
      expect(passo!.indice, 1);
      expect(passo.ponto.nome, 'P2');
      expect(passo.chegou, isFalse);
      expect(passo.distanciaKm, closeTo(1.0, 0.02));
      expect(passo.direcao, 'N');
      expect(passo.instrucao, contains('Siga'));
      expect(passo.instrucao, contains('P2'));
    });

    test('avança o alvo quando o veículo alcança um ponto intermediário', () {
      // Sobre o primeiro ponto, o alvo passa a ser o segundo.
      final noPrimeiro = navegacao.passoAtual(
          rota(TipoRota.pontoAPonto), const LatLng(0.0, 0.0));
      expect(noPrimeiro!.chegou, isFalse);
      expect(noPrimeiro.indice, 1);

      // Estando sobre o segundo ponto, o índice avança para o terceiro; a
      // chegada é comunicada pela mudança de índice na tela de navegação, e
      // não pelo passo devolvido, que sempre aponta para o próximo alvo.
      final noSegundo = navegacao.passoAtual(
        rota(TipoRota.pontoAPonto),
        const LatLng(0.009, 0),
        indiceAtual: 1,
      );
      expect(noSegundo!.indice, 2);
      expect(noSegundo.ponto.nome, 'P3');
      expect(noSegundo.chegou, isFalse);
    });

    test('reconhece o último ponto do percurso', () {
      final passo = navegacao.passoAtual(rota(TipoRota.pontoAPonto),
          const LatLng(0.018, 0), indiceAtual: 2);
      expect(passo!.indice, 2);
      expect(passo.ultimoPonto, isTrue);
      expect(passo.chegou, isTrue);
      expect(passo.instrucao, contains('destino final'));
    });

    test('devolve nulo quando a rota não tem pontos', () {
      final vazia = Rota(nome: 'Vazia', tipo: TipoRota.pontoAPonto);
      expect(navegacao.passoAtual(vazia, const LatLng(0, 0)), isNull);
    });
  });

  group('NavegacaoService.distanciaRestanteKm', () {
    test('soma os trechos que ainda faltam em uma rota ponto a ponto', () {
      // Sobre o primeiro ponto: faltam 1 km até P2 e 1 km de P2 a P3.
      expect(
        navegacao.distanciaRestanteKm(
            rota(TipoRota.pontoAPonto), const LatLng(0, 0)),
        closeTo(2.0, 0.05),
      );
    });

    test('acrescenta o retorno à partida em um circuito', () {
      // Sobre o primeiro ponto: 1 km + 1 km + 2 km de volta ao início.
      expect(
        navegacao.distanciaRestanteKm(
            rota(TipoRota.circuito), const LatLng(0, 0)),
        closeTo(4.0, 0.05),
      );
    });

    test('diminui conforme o veículo avança', () {
      // Com a partida já cumprida, o restante é medido do veículo até o
      // próximo alvo, e não de volta ao ponto inicial.
      final inicial = navegacao.distanciaRestanteKm(
        rota(TipoRota.pontoAPonto),
        const LatLng(0, 0),
        indiceAtual: 1,
      );
      final adiantado = navegacao.distanciaRestanteKm(
        rota(TipoRota.pontoAPonto),
        const LatLng(0.008, 0),
        indiceAtual: 1,
      );
      expect(adiantado, lessThan(inicial));
      expect(adiantado, closeTo(1.11, 0.05));
    });
  });

  group('NavegacaoService.progresso', () {
    test('é zero no início e um no último ponto', () {
      expect(
        navegacao.progresso(rota(TipoRota.pontoAPonto), const LatLng(0.5, 0.5)),
        0.0,
      );
      expect(
        navegacao.progresso(
          rota(TipoRota.pontoAPonto),
          const LatLng(0.018, 0),
          indiceAtual: 2,
        ),
        1.0,
      );
    });

    test('fica entre zero e um nas posições intermediárias', () {
      // A meio caminho entre o segundo e o terceiro ponto, com a partida já
      // cumprida, o progresso é de metade da rota.
      final valor = navegacao.progresso(
        rota(TipoRota.pontoAPonto),
        const LatLng(0.005, 0),
        indiceAtual: 1,
      );
      expect(valor, closeTo(0.5, 1e-9));
      expect(valor, greaterThan(0.0));
      expect(valor, lessThan(1.0));
    });
  });

  group('NavegacaoService.navegacaoConcluida', () {
    test('é falso no início e verdadeiro no último ponto', () {
      expect(
        navegacao.navegacaoConcluida(rota(TipoRota.pontoAPonto),
            const LatLng(0.0, 0.0)),
        isFalse,
      );
      expect(
        navegacao.navegacaoConcluida(rota(TipoRota.pontoAPonto),
            const LatLng(0.018, 0.0)),
        isTrue,
      );
    });

    test('é verdadeiro para uma rota sem pontos', () {
      final vazia = Rota(nome: 'Vazia', tipo: TipoRota.pontoAPonto);
      expect(navegacao.navegacaoConcluida(vazia, const LatLng(0, 0)), isTrue);
    });
  });
}
