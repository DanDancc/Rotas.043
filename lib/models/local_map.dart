class LocalMap {
  int? id;
  String nome;
  String endereco;
  double? latitude;
  double? longitude;

  // Construtor principal
  LocalMap({
    this.id,
    required this.nome,
    required this.endereco,
    this.latitude,
    this.longitude,
  });

  // Função para converter o Item em um Mapa de dados (Map<String, dynamic>)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'endereco': endereco,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  // Função para fazer o processo inverso: pegar os dados do SQLite (Map) 
  // e transformar de volta em um Item LocalMap 
    factory LocalMap.fromMap(Map<String, dynamic> map) {
    return LocalMap(
      id: map['id'],
      nome: map['nome'],
      endereco: map['endereco'],
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
    );
  }
}