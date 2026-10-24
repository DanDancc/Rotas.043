import 'package:sqflite/sqflite.dart';

import '../../models/ponto.dart';
import '../database/database_helper.dart';

/// Acesso à tabela `pontos` (caso de uso UC01 — Gerenciar Locais).
///
/// Contém apenas operações de banco, sem regra de negócio: quem decide
/// *quando* inserir ou excluir é a camada de repositório.
class PontoDao {
  PontoDao(this._provedor);

  final ProvedorBanco _provedor;

  static const String _tabela = DatabaseHelper.tabelaPontos;

  /// Insere um novo ponto e devolve o identificador gerado.
  Future<int> inserir(Ponto ponto) async {
    final db = await _provedor();
    final dados = ponto.toMap()..remove('id');
    return db.insert(_tabela, dados);
  }

  /// Lista os pontos cadastrados, opcionalmente restritos a um usuário.
  ///
  /// Quando [idUsuario] é informado, a consulta também traz os registros
  /// legados (sem proprietário), que passam a ser visíveis ao usuário
  /// conectado até serem vinculados definitivamente.
  Future<List<Ponto>> listar({int? idUsuario}) async {
    final db = await _provedor();
    final resultado = await db.query(
      _tabela,
      where: idUsuario != null ? 'id_usuario = ? OR id_usuario IS NULL' : null,
      whereArgs: idUsuario != null ? [idUsuario] : null,
      orderBy: 'nome COLLATE NOCASE ASC',
    );
    return resultado.map(Ponto.fromMap).toList(growable: false);
  }

  Future<Ponto?> buscarPorId(int id) async {
    final db = await _provedor();
    final resultado =
        await db.query(_tabela, where: 'id = ?', whereArgs: [id], limit: 1);
    if (resultado.isEmpty) return null;
    return Ponto.fromMap(resultado.first);
  }

  Future<int> atualizar(Ponto ponto) async {
    final db = await _provedor();
    final dados = ponto.toMap()..remove('id');
    return db.update(_tabela, dados,
        where: 'id = ?', whereArgs: [ponto.id]);
  }

  Future<int> excluir(int id) async {
    final db = await _provedor();
    return db.delete(_tabela, where: 'id = ?', whereArgs: [id]);
  }

  /// Vincula ao usuário informado todos os pontos que ainda não têm dono.
  ///
  /// Corresponde à estratégia de migração dos dados cadastrados antes da
  /// introdução da autenticação: na primeira conta criada no dispositivo, os
  /// pontos legados passam a pertencer a ela em vez de ficarem órfãos.
  Future<int> vincularPontosLegados(int idUsuario) async {
    final db = await _provedor();
    return db.update(
      _tabela,
      {'id_usuario': idUsuario},
      where: 'id_usuario IS NULL',
    );
  }

  Future<int> contar({int? idUsuario}) async {
    final db = await _provedor();
    final resultado = await db.rawQuery(
      idUsuario == null
          ? 'SELECT COUNT(*) AS total FROM $_tabela'
          : 'SELECT COUNT(*) AS total FROM $_tabela WHERE id_usuario = ?',
      idUsuario == null ? null : [idUsuario],
    );
    return Sqflite.firstIntValue(resultado) ?? 0;
  }
}
