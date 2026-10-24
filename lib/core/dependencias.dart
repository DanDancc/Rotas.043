import 'package:http/http.dart' as http;

import '../data/dao/geocache_dao.dart';
import '../data/dao/ponto_dao.dart';
import '../data/dao/preferencias_dao.dart';
import '../data/dao/rota_dao.dart';
import '../data/dao/usuario_dao.dart';
import '../data/database/database_helper.dart';
import '../data/repositories/ponto_repository.dart';
import '../data/repositories/rota_repository.dart';
import '../services/autenticacao_service.dart';
import '../services/geocodificacao_service.dart';
import '../services/localizacao_service.dart';
import '../services/navegacao_service.dart';
import '../services/otimizador_rota_service.dart';
import '../services/roteamento_service.dart';

/// Ponto único de montagem das dependências do aplicativo.
///
/// Em vez de cada tela criar os seus próprios serviços — o que espalharia a
/// criação de conexões e clientes HTTP pelo código — tudo é montado aqui e
/// entregue pronto. Dependências sem estado são compartilhadas; as que abrem
/// recursos, como os clientes HTTP, também são únicas, o que aproveita a
/// conexão e facilita o descarte.
///
/// Nos testes automatizados, atribui-se uma instância com banco em memória e
/// cliente HTTP simulado a [instance], o que permite exercitar telas e
/// repositórios sem rede e sem tocar no banco real do aparelho.
class Dependencias {
  Dependencias({
    ProvedorBanco? provedor,
    http.Client? clienteHttp,
    LocalizacaoService? localizacao,
  }) {
    _provedor = provedor ?? () => DatabaseHelper.instance.database;
    _clienteHttp = clienteHttp;
    this.localizacao = localizacao ?? const LocalizacaoService();
  }

  /// Instância usada pelo aplicativo; substituível nos testes.
  static Dependencias instance = Dependencias();

  late final ProvedorBanco _provedor;
  late final http.Client? _clienteHttp;

  late final LocalizacaoService localizacao;

  // --- Acesso a dados -----------------------------------------------------

  late final PontoDao pontoDao = PontoDao(_provedor);
  late final RotaDao rotaDao = RotaDao(_provedor);
  late final UsuarioDao usuarioDao = UsuarioDao(_provedor);
  late final GeocacheDao geocacheDao = GeocacheDao(_provedor);
  late final PreferenciasDao preferenciasDao = PreferenciasDao(_provedor);

  // --- Serviços -----------------------------------------------------------

  late final GeocodificacaoService geocodificacao =
      GeocodificacaoService(cache: geocacheDao, cliente: _clienteHttp);

  late final RoteamentoService roteamento =
      RoteamentoService(cliente: _clienteHttp);

  late final OtimizadorRotaService otimizador = const OtimizadorRotaService();

  late final NavegacaoService navegacao = const NavegacaoService();

  late final AutenticacaoService autenticacao = AutenticacaoService(
    usuarioDao: usuarioDao,
    pontoDao: pontoDao,
    preferencias: preferenciasDao,
  );

  // --- Repositórios -------------------------------------------------------

  late final PontoRepository pontos = PontoRepository(
    dao: pontoDao,
    geocodificacao: geocodificacao,
  );

  late final RotaRepository rotas = RotaRepository(
    dao: rotaDao,
    otimizador: otimizador,
    roteamento: roteamento,
  );

  /// Fecha os recursos abertos, como os clientes HTTP.
  void dispose() {
    geocodificacao.dispose();
    roteamento.dispose();
  }
}
