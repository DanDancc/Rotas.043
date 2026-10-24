import 'package:sqflite/sqflite.dart';

import '../../models/ponto.dart';
import '../../models/rota.dart';
import '../database/database_helper.dart';

/// Acesso às tabelas `rotas` e `rota_pontos`.
///
/// A gravação de uma rota envolve duas tabelas e precisa ser atômica: se a
/// inserção dos pontos falhar no meio do caminho, a rota ficaria cadastrada
/// sem percurso. Por isso as escritas acontecem sempre dentro de uma
/// transação do SQLite.
class RotaDao {
  RotaDao(this._provedor);

  final ProvedorBanco _provedor;

  static const String _tabela = DatabaseHelper.tabelaRotas;
  static const String _tabelaJuncao = DatabaseHelper.tabelaRotaPontos;

  /// Grava a rota e a sua ordem de visita, devolvendo o id gerado.
  Future<int> inserir(Rota rota) async {
    final db = await _provedor();
    return db.transaction((txn) async {
      final dados = rota.toMap()..remove('id');
      final idRota = await txn.insert(_tabela, dados);
      await _gravarPontos(txn, idRota, rota);
      return idRota;
    });
  }

  /// Atualiza a rota e substitui integralmente a sua lista de pontos.
  ///
  /// Recriar os vínculos é mais simples e seguro do que tentar descobrir
  /// quais linhas de `rota_pontos` mudaram de posição.
  Future<int> atualizar(Rota rota) async {
    final db = await _provedor();
    final idRota = rota.id;
    if (idRota == null) {
      throw ArgumentError('Não é possível atualizar uma rota sem id.');
    }
    return db.transaction((txn) async {
      final dados = rota.toMap()..remove('id');
      final linhas = await txn.update(_tabela, dados,
          where: 'id = ?', whereArgs: [idRota]);
      await txn.delete(_tabelaJuncao,
          where: 'id_rota = ?', whereArgs: [idRota]);
      await _gravarPontos(txn, idRota, rota);
      return linhas;
    });
  }

  Future<int> excluir(int idRota) async {
    final db = await _provedor();
    // As linhas de `rota_pontos` saem junto por ON DELETE CASCADE.
    return db.delete(_tabela, where: 'id = ?', whereArgs: [idRota]);
  }

  /// Lista as rotas com os seus pontos já na ordem de visita.
  ///
  /// Usa uma única consulta com junção e agrupa o resultado em memória, em
  /// vez de disparar uma consulta por rota.
  Future<List<Rota>> listar({int? idUsuario}) async {
    final db = await _provedor();
    final linhas = await db.query(
      _tabela,
      where: idUsuario != null ? 'id_usuario = ? OR id_usuario IS NULL' : null,
      whereArgs: idUsuario != null ? [idUsuario] : null,
      orderBy: 'data_criacao DESC',
    );
    if (linhas.isEmpty) return const [];

    final rotas = linhas.map(Rota.fromMap).toList();
    final pontosPorRota = await _carregarPontosDeVariasRotas(
      db,
      rotas.map((r) => r.id!).toList(growable: false),
    );
    for (final rota in rotas) {
      rota.pontos = pontosPorRota[rota.id] ?? const [];
    }
    return rotas;
  }

  Future<Rota?> buscarPorId(int idRota) async {
    final db = await _provedor();
    final linhas = await db
        .query(_tabela, where: 'id = ?', whereArgs: [idRota], limit: 1);
    if (linhas.isEmpty) return null;
    final rota = Rota.fromMap(linhas.first);
    final pontos = await _carregarPontosDeVariasRotas(db, [idRota]);
    rota.pontos = pontos[idRota] ?? const [];
    return rota;
  }

  /// Quantidade de rotas gravadas, usada nos indicadores da tela inicial.
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

  // --- Auxiliares ---------------------------------------------------------

  static Future<void> _gravarPontos(
      DatabaseExecutor txn, int idRota, Rota rota) async {
    for (var ordem = 0; ordem < rota.pontos.length; ordem++) {
      final idPonto = rota.pontos[ordem].id;
      if (idPonto == null) {
        throw ArgumentError(
            'Todos os pontos da rota precisam estar salvos antes da rota.');
      }
      await txn.insert(_tabelaJuncao, {
        'id_rota': idRota,
        'id_ponto': idPonto,
        'ordem_de_visita': ordem,
      });
    }
  }

  /// Carrega os pontos de várias rotas em uma só consulta e os agrupa por rota.
  static Future<Map<int, List<Ponto>>> _carregarPontosDeVariasRotas(
    Database db,
    List<int> idsRotas,
  ) async {
    if (idsRotas.isEmpty) return {};
    final marcadores = List.filled(idsRotas.length, '?').join(',');
    final linhas = await db.rawQuery('''
      SELECT rp.id_rota AS id_rota,
             rp.ordem_de_visita AS ordem_de_visita,
             p.id AS ponto_id,
             p.nome AS ponto_nome,
             p.endereco AS ponto_endereco,
             p.latitude AS ponto_latitude,
             p.longitude AS ponto_longitude,
             p.id_usuario AS ponto_id_usuario
        FROM ${DatabaseHelper.tabelaRotaPontos} rp
        JOIN ${DatabaseHelper.tabelaPontos} p ON p.id = rp.id_ponto
       WHERE rp.id_rota IN ($marcadores)
       ORDER BY rp.id_rota ASC, rp.ordem_de_visita ASC
    ''', idsRotas);

    final agrupado = <int, List<Ponto>>{};
    for (final linha in linhas) {
      final idRota = linha['id_rota'] as int;
      agrupado.putIfAbsent(idRota, () => <Ponto>[]).add(_pontoDaLinha(linha));
    }
    return agrupado;
  }

  static Ponto _pontoDaLinha(Map<String, dynamic> linha) {
    return Ponto(
      id: linha['ponto_id'] as int?,
      nome: (linha['ponto_nome'] ?? '') as String,
      endereco: (linha['ponto_endereco'] ?? '') as String,
      latitude: linha['ponto_latitude'] != null
          ? (linha['ponto_latitude'] as num).toDouble()
          : null,
      longitude: linha['ponto_longitude'] != null
          ? (linha['ponto_longitude'] as num).toDouble()
          : null,
      idUsuario: linha['ponto_id_usuario'] as int?,
    );
  }
}
