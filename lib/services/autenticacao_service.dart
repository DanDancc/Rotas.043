import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/excecoes.dart';
import '../data/dao/ponto_dao.dart';
import '../data/dao/preferencias_dao.dart';
import '../data/dao/usuario_dao.dart';
import '../models/usuario.dart';

/// Dados da conta lembrada entre execuções, usados para pré-preencher a tela
/// de acesso e reduzir a digitação ao mínimo.
class ContaLembrada {
  const ContaLembrada({required this.email, required this.nome});

  final String email;
  final String nome;

  String get primeiroNome {
    final partes = nome.trim().split(RegExp(r'\s+'));
    return partes.isEmpty || partes.first.isEmpty ? nome : partes.first;
  }
}

/// Cadastro, login e sessão do usuário (caso de uso UC04 — Gerenciar Usuário).
///
/// A Especificação Complementar exige que o usuário esteja previamente
/// cadastrado para acessar o sistema, de modo que este serviço é a porta de
/// entrada do aplicativo. Para que essa exigência não se transforme em atrito
/// diário, duas medidas reduzem a digitação ao mínimo:
///
/// 1. **Conta lembrada** — o e-mail e o nome do último acesso são guardados na
///    tabela `preferencias`, de modo que o formulário abre preenchido e o
///    usuário digita apenas a senha.
/// 2. **Manter conectado** — quando a opção está marcada, que é o padrão, a
///    sessão é gravada e o aplicativo abre direto no conteúdo nas execuções
///    seguintes. Quando não está, a sessão vale só para a execução atual e a
///    senha volta a ser pedida na próxima abertura, ainda com o e-mail
///    preenchido.
///
/// **Sobre o armazenamento da senha.** A senha nunca é gravada em texto claro.
/// Para cada conta é sorteado um sal aleatório de 16 bytes; o valor guardado é
/// o resultado de aplicar SHA-256 repetidamente (ver [iteracoesDerivacao])
/// sobre `sal:senha`. Essa repetição — chamada de alongamento de chave — torna
/// a tentativa de adivinhação por força bruta muito mais cara do que um único
/// cálculo de hash. É um esquema didático e simplificado: um sistema em
/// produção deveria usar PBKDF2, bcrypt ou Argon2, que são algoritmos
/// projetados especificamente para senhas e resistentes a hardware dedicado.
class AutenticacaoService {
  AutenticacaoService({
    required UsuarioDao usuarioDao,
    required PontoDao pontoDao,
    required PreferenciasDao preferencias,
  })  : _usuarioDao = usuarioDao,
        _pontoDao = pontoDao,
        _preferencias = preferencias;

  final UsuarioDao _usuarioDao;
  final PontoDao _pontoDao;
  final PreferenciasDao _preferencias;

  /// Número de repetições do resumo criptográfico ao derivar a senha.
  static const int iteracoesDerivacao = 10000;

  static const int _tamanhoMinimoSenha = 6;
  static const int _tamanhoMinimoNome = 3;

  static final RegExp _formatoEmail =
      RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  /// Cria a conta, vincula os dados legados e já abre a sessão.
  Future<Usuario> cadastrar({
    required String nome,
    required String email,
    required String senha,
    required String confirmacaoSenha,
    bool manterConectado = true,
  }) async {
    final nomeLimpo = nome.trim();
    final emailLimpo = Usuario.normalizarEmail(email);

    final erroNome = validarNome(nomeLimpo);
    if (erroNome != null) throw FalhaAutenticacao(erroNome);
    final erroEmail = validarEmail(emailLimpo);
    if (erroEmail != null) throw FalhaAutenticacao(erroEmail);
    final erroSenha = validarSenha(senha);
    if (erroSenha != null) throw FalhaAutenticacao(erroSenha);
    if (senha != confirmacaoSenha) {
      throw const FalhaAutenticacao('As duas senhas informadas não coincidem.');
    }

    final existente = await _usuarioDao.buscarPorEmail(emailLimpo);
    if (existente != null) {
      throw const FalhaAutenticacao(
          'Já existe uma conta cadastrada com este e-mail.');
    }

    final salt = gerarSalt();
    final novo = Usuario(
      nome: nomeLimpo,
      email: emailLimpo,
      senhaHash: derivarSenha(senha, salt),
      salt: salt,
    );

    final id = await _usuarioDao.inserir(novo);
    final salvo = novo.copyWith(id: id);

    // Pontos cadastrados antes da existência de contas passam a pertencer a
    // quem criou a primeira conta no dispositivo, em vez de ficarem órfãos.
    await _pontoDao.vincularPontosLegados(id);
    await _aplicarPoliticaDeSessao(salvo, manterConectado: manterConectado);

    return salvo;
  }

  /// Autentica o usuário e abre a sessão.
  ///
  /// A mensagem de erro é a mesma para e-mail inexistente e senha incorreta,
  /// para não revelar quais e-mails estão cadastrados no dispositivo.
  Future<Usuario> entrar({
    required String email,
    required String senha,
    bool manterConectado = true,
  }) async {
    final emailLimpo = Usuario.normalizarEmail(email);
    if (emailLimpo.isEmpty || senha.isEmpty) {
      throw const FalhaAutenticacao('Informe o e-mail e a senha.');
    }

    final usuario = await _usuarioDao.buscarPorEmail(emailLimpo);
    if (usuario == null) {
      throw const FalhaAutenticacao('E-mail ou senha incorretos.');
    }

    final calculado = derivarSenha(senha, usuario.salt);
    if (!compararSeguro(calculado, usuario.senhaHash)) {
      throw const FalhaAutenticacao('E-mail ou senha incorretos.');
    }

    await _aplicarPoliticaDeSessao(usuario, manterConectado: manterConectado);
    return usuario;
  }

  /// Encerra a sessão, mantendo a conta e a preferência de acesso.
  ///
  /// A conta lembrada é preservada de propósito: no próximo acesso o usuário
  /// encontra o e-mail preenchido e digita apenas a senha.
  Future<void> sair() => _usuarioDao.encerrarSessao();

  /// Usuário conectado em uma sessão gravada, ou nulo quando não há sessão.
  ///
  /// Só existe sessão gravada quando a opção ``manter conectado`` estava
  /// marcada no momento do acesso. Caso contrário, este método devolve nulo e
  /// a tela de acesso é apresentada com o e-mail já preenchido.
  Future<Usuario?> usuarioAtual() => _usuarioDao.usuarioDaSessao();

  /// Conta lembrada do último acesso, ou nulo quando ainda não houve acesso.
  Future<ContaLembrada?> contaLembrada() async {
    final email = await _preferencias.ler(PreferenciasDao.chaveUltimoEmail);
    if (email == null || email.isEmpty) return null;
    final nome =
        await _preferencias.ler(PreferenciasDao.chaveUltimoNome) ?? '';
    return ContaLembrada(email: email, nome: nome);
  }

  /// Valor inicial da opção ``manter conectado`` na tela de acesso.
  ///
  /// O padrão é verdadeiro porque é o comportamento que combina com o uso
  /// diário: a senha é pedida uma vez, não a cada abertura do aplicativo.
  Future<bool> manterConectadoPadrao() async {
    final valor =
        await _preferencias.ler(PreferenciasDao.chaveManterConectado);
    return valor == null ? true : valor == '1';
  }

  /// Altera os dados cadastrais do usuário conectado.
  Future<Usuario> atualizarPerfil({
    required Usuario usuario,
    required String nome,
    required String email,
  }) async {
    final nomeLimpo = nome.trim();
    final emailLimpo = Usuario.normalizarEmail(email);
    final erroNome = validarNome(nomeLimpo);
    if (erroNome != null) throw FalhaAutenticacao(erroNome);
    final erroEmail = validarEmail(emailLimpo);
    if (erroEmail != null) throw FalhaAutenticacao(erroEmail);

    if (emailLimpo != usuario.email) {
      final existente = await _usuarioDao.buscarPorEmail(emailLimpo);
      if (existente != null) {
        throw const FalhaAutenticacao(
            'Já existe uma conta cadastrada com este e-mail.');
      }
    }

    final atualizado = usuario.copyWith(nome: nomeLimpo, email: emailLimpo);
    await _usuarioDao.atualizar(atualizado);

    // Mantém a conta lembrada coerente com os dados atualizados, para que a
    // tela de acesso não pré-preencha um e-mail que não existe mais.
    await _preferencias.gravar(
        PreferenciasDao.chaveUltimoEmail, atualizado.email);
    await _preferencias.gravar(
        PreferenciasDao.chaveUltimoNome, atualizado.nome);

    return atualizado;
  }

  /// Troca a senha do usuário conectado após conferir a senha atual.
  Future<Usuario> alterarSenha({
    required Usuario usuario,
    required String senhaAtual,
    required String novaSenha,
    required String confirmacaoNovaSenha,
  }) async {
    final calculado = derivarSenha(senhaAtual, usuario.salt);
    if (!compararSeguro(calculado, usuario.senhaHash)) {
      throw const FalhaAutenticacao('A senha atual está incorreta.');
    }
    final erro = validarSenha(novaSenha);
    if (erro != null) throw FalhaAutenticacao(erro);
    if (novaSenha != confirmacaoNovaSenha) {
      throw const FalhaAutenticacao('As duas senhas informadas não coincidem.');
    }

    final novoSal = gerarSalt();
    final atualizado = usuario.copyWith(
      salt: novoSal,
      senhaHash: derivarSenha(novaSenha, novoSal),
    );
    await _usuarioDao.atualizar(atualizado);
    return atualizado;
  }

  /// Remove a conta e, por cascata no banco, os seus pontos e rotas.
  Future<void> excluirConta(Usuario usuario) async {
    if (usuario.id == null) {
      throw const FalhaAutenticacao('Usuário inválido.');
    }
    await _usuarioDao.excluir(usuario.id!);
    // A conta lembrada deixa de fazer sentido sem a conta.
    await _preferencias.remover(PreferenciasDao.chaveUltimoEmail);
    await _preferencias.remover(PreferenciasDao.chaveUltimoNome);
  }

  /// Aplica a política de sessão escolhida e registra a conta lembrada.
  Future<void> _aplicarPoliticaDeSessao(
    Usuario usuario, {
    required bool manterConectado,
  }) async {
    if (manterConectado) {
      await _usuarioDao.abrirSessao(usuario.id!);
    } else {
      // Sem sessão gravada, a próxima execução volta a pedir a senha. A
      // limpeza é necessária para não retomar uma sessão anterior.
      await _usuarioDao.encerrarSessao();
    }
    await _preferencias.gravar(
        PreferenciasDao.chaveUltimoEmail, usuario.email);
    await _preferencias.gravar(
        PreferenciasDao.chaveUltimoNome, usuario.nome);
    await _preferencias.gravar(
        PreferenciasDao.chaveManterConectado, manterConectado ? '1' : '0');
  }

  // --- Validações e criptografia -----------------------------------------

  static String? validarNome(String nome) {
    if (nome.trim().length < _tamanhoMinimoNome) {
      return 'Informe o seu nome completo.';
    }
    return null;
  }

  static String? validarEmail(String email) {
    final limpo = email.trim();
    if (limpo.isEmpty) return 'Informe o e-mail.';
    if (!_formatoEmail.hasMatch(limpo)) {
      return 'Informe um e-mail válido, como nome@exemplo.com.';
    }
    return null;
  }

  static String? validarSenha(String senha) {
    if (senha.length < _tamanhoMinimoSenha) {
      return 'A senha deve ter ao menos $_tamanhoMinimoSenha caracteres.';
    }
    return null;
  }

  /// Sorteia um sal aleatório de 16 bytes, em texto Base64.
  static String gerarSalt() {
    final aleatorio = Random.secure();
    final bytes = List<int>.generate(16, (_) => aleatorio.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Deriva o valor de senha a ser gravado a partir do sal e da senha.
  static String derivarSenha(String senha, String salt) {
    var resumo = sha256.convert(utf8.encode('$salt:$senha')).bytes;
    for (var i = 1; i < iteracoesDerivacao; i++) {
      resumo = sha256.convert(resumo).bytes;
    }
    return base64Url.encode(resumo);
  }

  /// Compara dois valores sem interromper na primeira diferença.
  ///
  /// A comparação usual para no primeiro caractere diferente, e o tempo que
  /// ela leva revela quantos caracteres iniciais estavam corretos. Aqui todas
  /// as posições são sempre percorridas.
  static bool compararSeguro(String a, String b) {
    if (a.length != b.length) return false;
    var diferenca = 0;
    for (var i = 0; i < a.length; i++) {
      diferenca |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diferenca == 0;
  }
}
