import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

/// Cache local dos endereços já geocodificados.
///
/// Evita repetir a mesma consulta ao Nominatim, o que reduz o tempo de
/// resposta do formulário e respeita a política de uso do serviço, que
/// recomenda no máximo uma requisição por segundo por aplicação.
class GeocacheDao {
  GeocacheDao(this._provedor);

  final ProvedorBanco _provedor;

  static const String _tabela = DatabaseHelper.tabelaGeocache;

  /// Normaliza a chave de busca, para que variações de caixa e espaços não
  /// gerem entradas duplicadas no cache.
  static String chave(String endereco) =>
      endereco.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Devolve a coordenada gravada para o endereço, ou nulo se não houver.
  Future<({double latitude, double longitude})?> buscar(String endereco) async {
    final db = await _provedor();
    final resultado = await db.query(
      _tabela,
      where: 'endereco = ?',
      whereArgs: [chave(endereco)],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    final linha = resultado.first;
    return (
      latitude: (linha['latitude'] as num).toDouble(),
      longitude: (linha['longitude'] as num).toDouble(),
    );
  }

  Future<void> salvar(String endereco, double latitude, double longitude) async {
    final db = await _provedor();
    await db.insert(
      _tabela,
      {
        'endereco': chave(endereco),
        'latitude': latitude,
        'longitude': longitude,
        'data_consulta': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> limpar() async {
    final db = await _provedor();
    return db.delete(_tabela);
  }

  Future<int> contar() async {
    final db = await _provedor();
    final resultado = await db.rawQuery('SELECT COUNT(*) AS total FROM $_tabela');
    return Sqflite.firstIntValue(resultado) ?? 0;
  }
}
