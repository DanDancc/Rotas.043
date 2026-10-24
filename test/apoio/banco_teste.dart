import 'package:rotas_app/data/database/database_helper.dart';
import 'package:rotas_app/models/ponto.dart';
import 'package:rotas_app/models/usuario.dart';
import 'package:rotas_app/services/autenticacao_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Apoio comum aos testes automatizados.

/// Prepara o SQLite para uso fora de um dispositivo (na máquina de testes).
///
/// [semIsolado] deve ser verdadeiro nos testes de widget: ali o tempo é
/// simulado pelo `flutter_test`, e as chamadas ao banco precisam resolver na
/// mesma linha de execução, sem depender das mensagens de um isolamento.
void prepararSqflite({bool semIsolado = false}) {
  sqfliteFfiInit();
  databaseFactory =
      semIsolado ? databaseFactoryFfiNoIsolate : databaseFactoryFfi;
}

/// Abre um banco SQLite em memória com o esquema real do aplicativo.
///
/// Usar o mesmo `onCreate` e o mesmo `onUpgrade` do aplicativo garante que os
/// testes verifiquem o esquema de verdade, e não uma cópia que poderia
/// divergir com o tempo.
Future<Database> abrirBancoEmMemoria() async {
  return databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: DatabaseHelper.versaoAtual,
      onConfigure: DatabaseHelper.configurarConexao,
      onCreate: (db, _) => DatabaseHelper.criarEsquemaCompleto(db),
    ),
  );
}

/// Cria um ponto com coordenadas, para uso nos testes.
Ponto pontoComCoordenada(
  String nome,
  double latitude,
  double longitude, {
  int? id,
  int? idUsuario,
}) {
  return Ponto(
    id: id,
    nome: nome,
    endereco: 'Endereço de $nome',
    latitude: latitude,
    longitude: longitude,
    idUsuario: idUsuario,
  );
}

/// Cria um ponto sem coordenadas, simulando um endereço não localizado.
Ponto pontoSemCoordenada(String nome, {int? id}) {
  return Ponto(
    id: id,
    nome: nome,
    endereco: 'Endereço de $nome',
  );
}

/// Cria um usuário com credenciais válidas, para uso nos testes.
Usuario usuarioDeTeste(String nome, String email, {String senha = 'segredo1'}) {
  const salt = 'sal-de-teste';
  return Usuario(
    nome: nome,
    email: Usuario.normalizarEmail(email),
    senhaHash: AutenticacaoService.derivarSenha(senha, salt),
    salt: salt,
  );
}
