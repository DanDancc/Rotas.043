import 'package:sqflite/sqflite.dart';

import '../../models/usuario.dart';
import '../database/database_helper.dart';

/// Acesso às tabelas `usuarios` e `sessao` (caso de uso UC04 — Gerenciar Usuário).
class UsuarioDao {
  UsuarioDao(this._provedor);

  final ProvedorBanco _provedor;

  static const String _tabela = DatabaseHelper.tabelaUsuarios;
  static const String _tabelaSessao = DatabaseHelper.tabelaSessao;

  Future<int> inserir(Usuario usuario) async {
    final db = await _provedor();
    final dados = usuario.toMap()..remove('id');
    return db.insert(_tabela, dados);
  }

  Future<Usuario?> buscarPorEmail(String email) async {
    final db = await _provedor();
    final resultado = await db.query(
      _tabela,
      where: 'email = ?',
      whereArgs: [Usuario.normalizarEmail(email)],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return Usuario.fromMap(resultado.first);
  }

  Future<Usuario?> buscarPorId(int id) async {
    final db = await _provedor();
    final resultado =
        await db.query(_tabela, where: 'id = ?', whereArgs: [id], limit: 1);
    if (resultado.isEmpty) return null;
    return Usuario.fromMap(resultado.first);
  }

  Future<List<Usuario>> listar() async {
    final db = await _provedor();
    final resultado = await db.query(_tabela, orderBy: 'nome COLLATE NOCASE ASC');
    return resultado.map(Usuario.fromMap).toList(growable: false);
  }

  /// Atualiza os dados cadastrais e, quando informado, também as credenciais.
  Future<int> atualizar(Usuario usuario) async {
    final db = await _provedor();
    final dados = usuario.toMap()..remove('id');
    return db.update(_tabela, dados,
        where: 'id = ?', whereArgs: [usuario.id]);
  }

  /// Remove a conta. Pontos e rotas do usuário saem por ON DELETE CASCADE.
  Future<int> excluir(int id) async {
    final db = await _provedor();
    return db.transaction((txn) async {
      await txn.delete(_tabelaSessao, where: 'id_usuario = ?', whereArgs: [id]);
      return txn.delete(_tabela, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> contar() async {
    final db = await _provedor();
    final resultado = await db.rawQuery('SELECT COUNT(*) AS total FROM $_tabela');
    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  // --- Sessão -------------------------------------------------------------

  /// Registra quem está conectado, mantendo uma única linha (id = 1).
  Future<void> abrirSessao(int idUsuario) async {
    final db = await _provedor();
    await db.insert(
      _tabelaSessao,
      {
        'id': 1,
        'id_usuario': idUsuario,
        'data_login': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Devolve o usuário da sessão atual, ou nulo se ninguém está conectado.
  Future<Usuario?> usuarioDaSessao() async {
    final db = await _provedor();
    final resultado = await db.rawQuery('''
      SELECT u.* FROM $_tabelaSessao s
        JOIN $_tabela u ON u.id = s.id_usuario
       WHERE s.id = 1
       LIMIT 1
    ''');
    if (resultado.isEmpty) return null;
    return Usuario.fromMap(resultado.first);
  }

  Future<void> encerrarSessao() async {
    final db = await _provedor();
    await db.delete(_tabelaSessao, where: 'id = ?', whereArgs: [1]);
  }
}
