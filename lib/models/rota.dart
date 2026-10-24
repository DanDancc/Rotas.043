import 'package:latlong2/latlong.dart';

import '../core/geo_utils.dart';
import 'ponto.dart';

/// Modo de operação da rota, conforme o caso de uso UC02 (Gerar Rotas).
enum TipoRota {
  /// O trajeto termina no último ponto; a rota é uma linha, não um ciclo.
  pontoAPonto('ponto_a_ponto', 'Ponto a ponto'),

  /// O trajeto retorna ao ponto de partida, fechando um circuito.
  circuito('circuito', 'Circuito (retorna ao início)');

  const TipoRota(this.valor, this.rotulo);

  /// Valor gravado na coluna `tipo` da tabela `rotas`.
  final String valor;

  /// Texto apresentado na interface.
  final String rotulo;

  static TipoRota deValor(String? valor) {
    return TipoRota.values.firstWhere(
      (tipo) => tipo.valor == valor,
      orElse: () => TipoRota.pontoAPonto,
    );
  }
}

/// Origem do cálculo de distância e duração de uma rota.
///
/// Registrar essa informação permite demonstrar, no relatório, quando o
/// sistema usou a API de roteamento e quando precisou do cálculo local.
enum FonteCalculo {
  /// Trajeto calculado pela API OSRM, seguindo as vias reais.
  osrm('osrm', 'OSRM (vias reais)'),

  /// Trajeto estimado localmente por Haversine, em linha reta.
  local('local', 'Estimativa local (linha reta)');

  const FonteCalculo(this.valor, this.rotulo);

  final String valor;
  final String rotulo;

  static FonteCalculo deValor(String? valor) {
    return FonteCalculo.values.firstWhere(
      (fonte) => fonte.valor == valor,
      orElse: () => FonteCalculo.local,
    );
  }
}

/// Uma rota salva pelo usuário, ligando vários [Ponto] em uma ordem de visita.
///
/// Corresponde às entidades `rotas` e `rota_pontos` do Diagrama Entidade
/// Relacionamento: a lista [pontos] já chega ordenada pela coluna
/// `ordem_de_visita`, de modo que o índice da lista é a ordem de visita.
class Rota {
  int? id;
  String nome;
  TipoRota tipo;

  /// Distância total do percurso, em quilômetros.
  double distanciaTotal;

  /// Duração estimada do percurso, em segundos.
  double duracaoTotal;

  /// Traçado do percurso no mapa, em coordenadas.
  List<LatLng> geometria;

  DateTime dataCriacao;
  int? idUsuario;
  FonteCalculo fonteCalculo;

  /// Pontos que compõem a rota, já na ordem de visita.
  List<Ponto> pontos;

  Rota({
    this.id,
    required this.nome,
    this.tipo = TipoRota.pontoAPonto,
    this.distanciaTotal = 0.0,
    this.duracaoTotal = 0.0,
    List<LatLng>? geometria,
    DateTime? dataCriacao,
    this.idUsuario,
    this.fonteCalculo = FonteCalculo.local,
    List<Ponto>? pontos,
  })  : geometria = geometria ?? <LatLng>[],
        pontos = pontos ?? <Ponto>[],
        dataCriacao = dataCriacao ?? DateTime.now();

  /// Quantidade de paradas da rota.
  int get quantidadePontos => pontos.length;

  /// Indica se há pontos suficientes para calcular um trajeto.
  bool get podeCalcular => pontos.length >= 2;

  /// Distância formatada para exibição (ex.: "12,4 km").
  String get distanciaFormatada => GeoUtils.formatarDistancia(distanciaTotal);

  /// Duração formatada para exibição (ex.: "35 min").
  String get duracaoFormatada => GeoUtils.formatarDuracao(duracaoTotal);

  /// Coordenadas dos pontos que possuem geocodificação concluída.
  List<LatLng> get coordenadasDosPontos => pontos
      .map((ponto) => ponto.coordenada)
      .whereType<LatLng>()
      .toList(growable: false);

  /// Ponto usado para centralizar o mapa: o centro da geometria quando ela
  /// existe, ou o centro dos pontos cadastrados.
  LatLng? get centroMapa {
    if (geometria.isNotEmpty) return GeoUtils.centro(geometria);
    return GeoUtils.centro(coordenadasDosPontos);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'tipo': tipo.valor,
      'distancia_total': distanciaTotal,
      'duracao_total': duracaoTotal,
      'geometria': GeoUtils.geometriaParaTexto(geometria),
      'data_criacao': dataCriacao.toIso8601String(),
      'id_usuario': idUsuario,
      'fonte_calculo': fonteCalculo.valor,
    };
  }

  /// Monta a rota a partir de uma linha da tabela `rotas`.
  ///
  /// A lista de pontos não vem desta linha: ela é carregada à parte, pela
  /// tabela `rota_pontos`, e atribuída por quem consulta.
  factory Rota.fromMap(Map<String, dynamic> map) {
    return Rota(
      id: map['id'] as int?,
      nome: (map['nome'] ?? '') as String,
      tipo: TipoRota.deValor(map['tipo'] as String?),
      distanciaTotal:
          map['distancia_total'] != null
              ? (map['distancia_total'] as num).toDouble()
              : 0.0,
      duracaoTotal: map['duracao_total'] != null
          ? (map['duracao_total'] as num).toDouble()
          : 0.0,
      geometria: GeoUtils.geometriaDeTexto(map['geometria'] as String?),
      dataCriacao: _lerData(map['data_criacao']),
      idUsuario: map['id_usuario'] as int?,
      fonteCalculo: FonteCalculo.deValor(map['fonte_calculo'] as String?),
    );
  }

  static DateTime _lerData(dynamic valor) {
    if (valor is String) {
      return DateTime.tryParse(valor) ?? DateTime.now();
    }
    return DateTime.now();
  }

  Rota copyWith({
    int? id,
    String? nome,
    TipoRota? tipo,
    double? distanciaTotal,
    double? duracaoTotal,
    List<LatLng>? geometria,
    DateTime? dataCriacao,
    int? idUsuario,
    FonteCalculo? fonteCalculo,
    List<Ponto>? pontos,
  }) {
    return Rota(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      distanciaTotal: distanciaTotal ?? this.distanciaTotal,
      duracaoTotal: duracaoTotal ?? this.duracaoTotal,
      geometria: geometria ?? this.geometria,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      idUsuario: idUsuario ?? this.idUsuario,
      fonteCalculo: fonteCalculo ?? this.fonteCalculo,
      pontos: pontos ?? this.pontos,
    );
  }

  @override
  String toString() =>
      'Rota(id: $id, nome: $nome, tipo: ${tipo.valor}, pontos: ${pontos.length})';
}
