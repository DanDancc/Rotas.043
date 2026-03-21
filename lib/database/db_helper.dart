import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/local_map.dart'; //importa o modelo de dados

class DatabaseHelper {
  static const _databaseName = "RotasApp.db"; //Nome definido
  static const _databaseVersion = 1;
  static const table = 'pontos'; //Nome da tabela

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  //Se o banco existe retorna, senão inicia.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async{ 
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(path, version: _databaseVersion, 
    onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {  
    await db.execute('''
      CREATE TABLE $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        endereco TEXT NOT NULL,
        latitude REAL,
        longitude REAL
      )
      ''');
  }

  // Funções do Crud

  Future<int> insert(LocalMap ponto) async {
    Database db = await instance.database;
    // Pega o item, transforma em map e salva no banco
    return await db.insert(table, ponto.toMap());
  }

  Future<List<LocalMap>> getTodosPontos() async {
    Database db = await instance.database;
    var res = await db.query(table); //Busca todos os pontos

    //Se achar algo, transforma de volta em lista no LocalMap
    List<LocalMap> list = res.isNotEmpty ? res.map((c) => LocalMap.fromMap(c)).toList() : [];
    return list;
  }

  Future<int> update(LocalMap ponto) async {
    Database db = await instance.database;
    return await db.delete(
      table,
      where: 'id = ?',
      whereArgs: [ponto.id], //Atualiza onde o ID for igual
    );
  }

  Future<int> delete(int id) async {
    Database db = await instance.database; 
    return await db.delete(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}