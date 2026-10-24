import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Assinatura de quem fornece uma conexão aberta com o banco.
///
/// Os DAOs recebem um provedor em vez de acessarem o singleton diretamente,
/// o que permite injetar um banco em memória nos testes automatizados.
/// Em produção usa-se `DatabaseHelper.instance.database` (um tear-off).
typedef ProvedorBanco = Future<Database> Function();

/// Responsável por abrir o banco SQLite local e por aplicar as migrações.
///
/// O esquema evoluiu em quatro versões, sempre de forma incremental e sem
/// perder dados já cadastrados:
///
/// * **v1** — tabela `pontos` (caso de uso UC01, Gerenciar Locais).
/// * **v2** — tabelas `rotas` e `rota_pontos` (UC02 e UC03, Gerar Rotas e
///   Gerenciar Rotas Salvas).
/// * **v3** — tabelas `usuarios`, `sessao` e `geocache`, além da coluna
///   `pontos.id_usuario` (UC04, Gerenciar Usuário, e cache de geocodificação).
/// * **v4** — tabela `preferencias`, que guarda a opção ``manter conectado``
///   e a conta lembrada, para reduzir a digitação no acesso.
class DatabaseHelper {
  static const String _nomeBanco = 'RotasApp.db';
  static const int _versaoBanco = 4;

  static const String tabelaPontos = 'pontos';
  static const String tabelaRotas = 'rotas';
  static const String tabelaRotaPontos = 'rota_pontos';
  static const String tabelaUsuarios = 'usuarios';
  static const String tabelaSessao = 'sessao';
  static const String tabelaGeocache = 'geocache';
  static const String tabelaPreferencias = 'preferencias';

  DatabaseHelper._privateConstructor();

  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  /// Versão atual do esquema, exposta para os testes de migração.
  static int get versaoAtual => _versaoBanco;

  /// Retorna a conexão existente ou abre uma nova.
  Future<Database> get database async {
    final aberto = _database;
    if (aberto != null) return aberto;
    final novo = await _iniciarBanco();
    _database = novo;
    return novo;
  }

  Future<Database> _iniciarBanco() async {
    final caminho = join(await getDatabasesPath(), _nomeBanco);
    return openDatabase(
      caminho,
      version: _versaoBanco,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onConfigure(Database db) async {
    // Necessário para que as chaves estrangeiras e o ON DELETE CASCADE
    // definidos no esquema sejam realmente aplicados pelo SQLite.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Criação do esquema completo, usada em instalações novas.
  static Future<void> _onCreate(Database db, int version) async {
    final lote = db.batch();
    // `usuarios` é criada primeiro porque as demais tabelas a referenciam.
    _esquemaUsuarios(lote);
    _esquemaPontos(lote);
    _esquemaRotas(lote);
    _esquemaRotaPontos(lote);
    _esquemaSessao(lote);
    _esquemaGeocache(lote);
    _esquemaPreferencias(lote);
    await lote.commit(noResult: true);
  }

  /// Migração incremental, aplicada apenas quando o banco já existia.
  static Future<void> _onUpgrade(
      Database db, int versaoAntiga, int versaoNova) async {
    if (versaoAntiga < 2) {
      final lote = db.batch();
      _esquemaRotas(lote);
      _esquemaRotaPontos(lote);
      await lote.commit(noResult: true);
    }
    if (versaoAntiga < 3) {
      final lote = db.batch();
      _esquemaUsuarios(lote);
      _esquemaSessao(lote);
      _esquemaGeocache(lote);
      await lote.commit(noResult: true);
      // ADD COLUMN preserva os pontos já cadastrados; eles ficam com
      // id_usuario nulo (dados legados) até serem vinculados a uma conta.
      await db.execute(
          'ALTER TABLE $tabelaPontos ADD COLUMN id_usuario INTEGER '
          'REFERENCES $tabelaUsuarios(id) ON DELETE CASCADE');
    }
    if (versaoAntiga < 4) {
      // Apenas acrescenta uma tabela nova, sem tocar nos dados existentes.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tabelaPreferencias (
          chave TEXT PRIMARY KEY,
          valor TEXT NOT NULL
        )
      ''');
    }
  }

  // --- Definições de esquema --------------------------------------------

  static void _esquemaPontos(Batch lote) {
    lote.execute('''
      CREATE TABLE $tabelaPontos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        endereco TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        id_usuario INTEGER REFERENCES $tabelaUsuarios(id) ON DELETE CASCADE
      )
    ''');
  }

  static void _esquemaRotas(Batch lote) {
    lote.execute('''
      CREATE TABLE $tabelaRotas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        tipo TEXT NOT NULL DEFAULT 'ponto_a_ponto',
        distancia_total REAL NOT NULL DEFAULT 0,
        duracao_total REAL NOT NULL DEFAULT 0,
        geometria TEXT,
        data_criacao TEXT NOT NULL,
        id_usuario INTEGER REFERENCES $tabelaUsuarios(id) ON DELETE CASCADE,
        fonte_calculo TEXT NOT NULL DEFAULT 'local'
      )
    ''');
  }

  static void _esquemaRotaPontos(Batch lote) {
    lote.execute('''
      CREATE TABLE $tabelaRotaPontos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_rota INTEGER NOT NULL REFERENCES $tabelaRotas(id) ON DELETE CASCADE,
        id_ponto INTEGER NOT NULL REFERENCES $tabelaPontos(id) ON DELETE CASCADE,
        ordem_de_visita INTEGER NOT NULL
      )
    ''');
    lote.execute(
        'CREATE INDEX idx_rota_pontos_rota ON $tabelaRotaPontos (id_rota)');
  }

  static void _esquemaUsuarios(Batch lote) {
    lote.execute('''
      CREATE TABLE $tabelaUsuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        senha_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        data_cadastro TEXT NOT NULL
      )
    ''');
  }

  static void _esquemaSessao(Batch lote) {
    // Tabela de linha única (id fixo em 1) que guarda o usuário conectado,
    // permitindo restaurar a sessão quando o aplicativo é reaberto.
    lote.execute('''
      CREATE TABLE $tabelaSessao (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        id_usuario INTEGER REFERENCES $tabelaUsuarios(id) ON DELETE CASCADE,
        data_login TEXT
      )
    ''');
  }

  static void _esquemaGeocache(Batch lote) {
    lote.execute('''
      CREATE TABLE $tabelaGeocache (
        endereco TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        data_consulta TEXT NOT NULL
      )
    ''');
  }

  static void _esquemaPreferencias(Batch lote) {
    // Armazena pares chave/valor simples. Hoje guarda a opção
    // "manter conectado" e a conta lembrada, usada para pré-preencher o
    // formulário de acesso e reduzir a digitação.
    lote.execute('''
      CREATE TABLE $tabelaPreferencias (
        chave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');
  }

  /// Fecha a conexão e limpa a referência estática.
  ///
  /// Usado ao encerrar o aplicativo e entre testes automatizados.
  Future<void> fechar() async {
    final aberto = _database;
    if (aberto != null) {
      await aberto.close();
      _database = null;
    }
  }

  // --- Apoio aos testes automatizados ------------------------------------
  // Os três métodos abaixo existem para que os testes montem um banco em
  // memória com exatamente o mesmo esquema e as mesmas migrações usados em
  // produção, sem depender do arquivo real do aparelho.

  /// Habilita as chaves estrangeiras em uma conexão de teste.
  static Future<void> configurarConexao(Database db) => _onConfigure(db);

  /// Cria o esquema completo em um banco já aberto.
  static Future<void> criarEsquemaCompleto(Database db) =>
      _onCreate(db, _versaoBanco);

  /// Aplica as migrações incrementais em um banco já aberto.
  static Future<void> aplicarMigracoes(
    Database db,
    int versaoAntiga,
    int versaoNova,
  ) =>
      _onUpgrade(db, versaoAntiga, versaoNova);
}
