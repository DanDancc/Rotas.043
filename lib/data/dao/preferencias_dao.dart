import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

/// Preferências simples do aplicativo, em pares chave/valor.
///
/// Guardar essas informações no próprio banco, e não em um armazenamento
/// separado, mantém tudo em um único lugar e permite que a limpeza de dados do
/// aplicativo apague também as preferências, sem deixar resíduo.
class PreferenciasDao {
  PreferenciasDao(this._provedor);

  final ProvedorBanco _provedor;

  static const String _tabela = DatabaseHelper.tabelaPreferencias;

  // --- Chaves conhecidas ---------------------------------------------------

  /// E-mail da última conta que acessou o aplicativo.
  static const String chaveUltimoEmail = 'ultimo_email';

  /// Nome da última conta que acessou o aplicativo.
  static const String chaveUltimoNome = 'ultimo_nome';

  /// Indica se a sessão deve ser retomada nas próximas execuções.
  static const String chaveManterConectado = 'manter_conectado';

  Future<String?> ler(String chave) async {
    final db = await _provedor();
    final resultado = await db.query(
      _tabela,
      columns: ['valor'],
      where: 'chave = ?',
      whereArgs: [chave],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return resultado.first['valor'] as String?;
  }

  Future<void> gravar(String chave, String valor) async {
    final db = await _provedor();
    await db.insert(
      _tabela,
      {'chave': chave, 'valor': valor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remover(String chave) async {
    final db = await _provedor();
    await db.delete(_tabela, where: 'chave = ?', whereArgs: [chave]);
  }
}
