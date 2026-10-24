/// Conta de acesso ao aplicativo (caso de uso UC04 — Gerenciar Usuário).
///
/// A senha nunca é armazenada em texto claro: [senhaHash] guarda o resumo
/// SHA-256 calculado sobre o sal + senha, e [salt] guarda o sal aleatório
/// usado nesse cálculo.
class Usuario {
  int? id;
  String nome;
  String email;
  String senhaHash;
  String salt;
  DateTime dataCadastro;

  Usuario({
    this.id,
    required this.nome,
    required this.email,
    required this.senhaHash,
    required this.salt,
    DateTime? dataCadastro,
  }) : dataCadastro = dataCadastro ?? DateTime.now();

  /// E-mail normalizado para comparação e armazenamento.
  static String normalizarEmail(String email) => email.trim().toLowerCase();

  /// Primeiro nome, usado nas saudações da interface.
  String get primeiroNome {
    final partes = nome.trim().split(RegExp(r'\s+'));
    return partes.isEmpty || partes.first.isEmpty ? nome : partes.first;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'email': email,
      'senha_hash': senhaHash,
      'salt': salt,
      'data_cadastro': dataCadastro.toIso8601String(),
    };
  }

  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id'] as int?,
      nome: (map['nome'] ?? '') as String,
      email: (map['email'] ?? '') as String,
      senhaHash: (map['senha_hash'] ?? '') as String,
      salt: (map['salt'] ?? '') as String,
      dataCadastro: map['data_cadastro'] is String
          ? (DateTime.tryParse(map['data_cadastro'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Usuario copyWith({
    int? id,
    String? nome,
    String? email,
    String? senhaHash,
    String? salt,
    DateTime? dataCadastro,
  }) {
    return Usuario(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      email: email ?? this.email,
      senhaHash: senhaHash ?? this.senhaHash,
      salt: salt ?? this.salt,
      dataCadastro: dataCadastro ?? this.dataCadastro,
    );
  }

  @override
  String toString() => 'Usuario(id: $id, nome: $nome, email: $email)';
}
