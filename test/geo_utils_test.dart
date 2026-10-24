import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rotas_app/core/geo_utils.dart';

void main() {
  group('GeoUtils.distanciaKm', () {
    test('retorna zero para o mesmo ponto', () {
      expect(GeoUtils.distanciaKm(-23.31, -51.16, -23.31, -51.16), 0.0);
    });

    test('um grau de latitude equivale a aproximadamente 111 km', () {
      expect(GeoUtils.distanciaKm(0, 0, 1, 0), closeTo(111.19, 0.05));
    });

    test('um grau de longitude no equador equivale à mesma distância', () {
      expect(GeoUtils.distanciaKm(0, 0, 0, 1), closeTo(111.19, 0.05));
    });

    test('a distância entre Heathrow e JFK fica próxima de 5555 km', () {
      final distancia = GeoUtils.distanciaKm(51.4700, -0.4543, 40.6413, -73.7781);
      expect(distancia, closeTo(5555, 25));
    });

    test('é simétrica', () {
      final ida = GeoUtils.distanciaKm(-23.31, -51.16, -23.42, -51.93);
      final volta = GeoUtils.distanciaKm(-23.42, -51.93, -23.31, -51.16);
      expect(ida, closeTo(volta, 1e-9));
    });
  });

  group('GeoUtils.distanciaTotalKm', () {
    final reta = [
      const LatLng(0, 0),
      const LatLng(0.009, 0),
      const LatLng(0.018, 0),
    ];

    test('soma os trechos consecutivos', () {
      // Dois trechos de 0,009 grau, cada um com cerca de 1 km.
      expect(GeoUtils.distanciaTotalKm(reta), closeTo(2.0, 0.02));
    });

    test('fecha o circuito somando o retorno ao primeiro ponto', () {
      expect(
        GeoUtils.distanciaTotalKm(reta, fecharCircuito: true),
        closeTo(4.0, 0.02),
      );
    });

    test('devolve zero com menos de dois pontos', () {
      expect(GeoUtils.distanciaTotalKm([const LatLng(0, 0)]), 0.0);
      expect(GeoUtils.distanciaTotalKm(const []), 0.0);
    });
  });

  group('GeoUtils.formatarDistancia', () {
    test('usa metros abaixo de um quilômetro', () {
      expect(GeoUtils.formatarDistancia(0.85), '850 m');
      expect(GeoUtils.formatarDistancia(0.0), '0 m');
    });

    test('usa quilômetros com vírgula decimal a partir de um quilômetro', () {
      expect(GeoUtils.formatarDistancia(1.0), '1,0 km');
      expect(GeoUtils.formatarDistancia(12.44), '12,4 km');
    });

    test('trata valores inválidos', () {
      expect(GeoUtils.formatarDistancia(double.nan), '—');
      expect(GeoUtils.formatarDistancia(-1), '—');
    });
  });

  group('GeoUtils.formatarDuracao', () {
    test('formata minutos e horas', () {
      expect(GeoUtils.formatarDuracao(30), 'menos de 1 min');
      expect(GeoUtils.formatarDuracao(2700), '45 min');
      expect(GeoUtils.formatarDuracao(3600), '1h');
      expect(GeoUtils.formatarDuracao(4800), '1h 20min');
    });

    test('trata valores inválidos', () {
      expect(GeoUtils.formatarDuracao(double.infinity), '—');
      expect(GeoUtils.formatarDuracao(-5), '—');
    });
  });

  group('GeoUtils - serialização da geometria', () {
    test('preserva as coordenadas na ida e volta', () {
      final original = [
        const LatLng(-23.3103, -51.1628),
        const LatLng(-23.3200, -51.1700),
      ];
      final texto = GeoUtils.geometriaParaTexto(original);
      final lido = GeoUtils.geometriaDeTexto(texto);

      expect(lido, hasLength(2));
      expect(lido.first.latitude, closeTo(original.first.latitude, 1e-9));
      expect(lido.first.longitude, closeTo(original.first.longitude, 1e-9));
      expect(lido.last.latitude, closeTo(original.last.latitude, 1e-9));
    });

    test('devolve lista vazia para conteúdo ausente ou corrompido', () {
      expect(GeoUtils.geometriaDeTexto(null), isEmpty);
      expect(GeoUtils.geometriaDeTexto(''), isEmpty);
      expect(GeoUtils.geometriaDeTexto('isto não é json'), isEmpty);
      expect(GeoUtils.geometriaDeTexto('{"a":1}'), isEmpty);
      expect(GeoUtils.geometriaDeTexto('[[1]]'), isEmpty);
    });

    test('ignora itens malformados e mantém os válidos', () {
      final lido = GeoUtils.geometriaDeTexto('[[-23.31,-51.16],[1],["a","b"]]');
      expect(lido, hasLength(1));
    });
  });

  group('GeoUtils.centro', () {
    test('devolve o ponto médio', () {
      final medio = GeoUtils.centro([
        const LatLng(0, 0),
        const LatLng(2, 2),
      ]);
      expect(medio!.latitude, closeTo(1, 1e-9));
      expect(medio.longitude, closeTo(1, 1e-9));
    });

    test('devolve nulo para lista vazia', () {
      expect(GeoUtils.centro(const []), isNull);
    });
  });

  group('GeoUtils - rumo e ponto cardeal', () {
    test('norte é zero grau e leste é noventa graus', () {
      expect(
        GeoUtils.rumoGraus(const LatLng(0, 0), const LatLng(1, 0)),
        closeTo(0, 0.01),
      );
      expect(
        GeoUtils.rumoGraus(const LatLng(0, 0), const LatLng(0, 1)),
        closeTo(90, 0.5),
      );
    });

    test('converte graus em direções', () {
      expect(GeoUtils.pontoCardeal(0), 'N');
      expect(GeoUtils.pontoCardeal(45), 'NE');
      expect(GeoUtils.pontoCardeal(90), 'L');
      expect(GeoUtils.pontoCardeal(180), 'S');
      expect(GeoUtils.pontoCardeal(270), 'O');
      expect(GeoUtils.pontoCardeal(359), 'N');
    });
  });
}
