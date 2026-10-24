import 'package:latlong2/latlong.dart';

/// Um ponto de interesse cadastrado pelo usuário.
///
/// Corresponde à entidade `pontos` do Diagrama Entidade Relacionamento.
/// O nome anterior desta classe era `LocalMap`; ela foi renomeada durante a
/// refatoração para refletir melhor o domínio (um local, não um mapa).
class Ponto {
  int? id;
  String nome;
  String endereco;
  double? latitude;
  double? longitude;

  /// Usuário proprietário do registro. Nulo em registros criados antes da
  /// introdução da autenticação (dados legados).
  int? idUsuario;

  Ponto({
    this.id,
    required this.nome,
    required this.endereco,
    this.latitude,
    this.longitude,
    this.idUsuario,
  });

  /// Indica se a geocodificação do endereço já produziu coordenadas.
  bool get temCoordenadas => latitude != null && longitude != null;

  /// Coordenada do ponto, ou nulo quando o endereço ainda não foi geocodificado.
  LatLng? get coordenada =>
      temCoordenadas ? LatLng(latitude!, longitude!) : null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'endereco': endereco,
      'latitude': latitude,
      'longitude': longitude,
      'id_usuario': idUsuario,
    };
  }

  factory Ponto.fromMap(Map<String, dynamic> map) {
    return Ponto(
      id: map['id'] as int?,
      nome: (map['nome'] ?? '') as String,
      endereco: (map['endereco'] ?? '') as String,
      latitude: map['latitude'] != null
          ? (map['latitude'] as num).toDouble()
          : null,
      longitude: map['longitude'] != null
          ? (map['longitude'] as num).toDouble()
          : null,
      idUsuario: map['id_usuario'] as int?,
    );
  }

  Ponto copyWith({
    int? id,
    String? nome,
    String? endereco,
    double? latitude,
    double? longitude,
    int? idUsuario,
    bool limparCoordenadas = false,
  }) {
    return Ponto(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      endereco: endereco ?? this.endereco,
      latitude: limparCoordenadas ? null : (latitude ?? this.latitude),
      longitude: limparCoordenadas ? null : (longitude ?? this.longitude),
      idUsuario: idUsuario ?? this.idUsuario,
    );
  }

  @override
  String toString() => 'Ponto(id: $id, nome: $nome, endereco: $endereco)';
}
