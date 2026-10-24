import 'package:flutter/material.dart';

import '../core/dependencias.dart';
import '../core/excecoes.dart';
import '../models/usuario.dart';
import '../services/autenticacao_service.dart';
import '../widgets/avisos.dart';
import 'cadastro_page.dart';

/// Tela de acesso ao sistema (caso de uso UC04 — Gerenciar Usuário).
///
/// O acesso é obrigatório: a Especificação Complementar estabelece que o
/// usuário precisa estar previamente cadastrado para utilizar o aplicativo.
/// Para que essa exigência não se transforme em atrito diário, a tela foi
/// construída para exigir o mínimo de digitação:
///
/// * o e-mail do último acesso já vem preenchido, então basta digitar a senha;
/// * o foco começa no campo de senha quando há conta lembrada, e o teclado
///   envia o formulário diretamente;
/// * a opção ``manter conectado``, marcada por padrão, faz o aplicativo abrir
///   direto no conteúdo nas próximas execuções.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.aoAutenticar});

  /// Chamada quando a autenticação termina com sucesso, entregando o usuário
  /// conectado ao portão de sessão.
  final ValueChanged<Usuario> aoAutenticar;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formulario = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _focoSenha = FocusNode();
  final _focoEmail = FocusNode();

  bool _carregando = false;
  bool _senhaVisivel = false;
  bool _manterConectado = true;
  ContaLembrada? _contaLembrada;

  @override
  void initState() {
    super.initState();
    _carregarPreferenciasDeAcesso();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    _focoSenha.dispose();
    _focoEmail.dispose();
    super.dispose();
  }

  /// Preenche o formulário com a conta lembrada e a preferência de sessão.
  Future<void> _carregarPreferenciasDeAcesso() async {
    final servico = Dependencias.instance.autenticacao;
    final lembrada = await servico.contaLembrada();
    final manter = await servico.manterConectadoPadrao();
    if (!mounted) return;

    setState(() {
      _contaLembrada = lembrada;
      _manterConectado = manter;
      if (lembrada != null) _emailController.text = lembrada.email;
    });

    // Com o e-mail preenchido, o foco já começa na senha: o usuário digita
    // apenas ela e confirma no próprio teclado.
    if (lembrada != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focoSenha.requestFocus();
      });
    }
  }

  Future<void> _entrar() async {
    if (!_formulario.currentState!.validate()) return;

    setState(() => _carregando = true);
    try {
      final usuario = await Dependencias.instance.autenticacao.entrar(
        email: _emailController.text,
        senha: _senhaController.text,
        manterConectado: _manterConectado,
      );
      if (!mounted) return;
      widget.aoAutenticar(usuario);
    } on FalhaApp catch (falha) {
      if (!mounted) return;
      setState(() => _carregando = false);
      Avisos.erro(context, falha.mensagem);
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      Avisos.erro(context, 'Não foi possível entrar. Tente novamente.');
    }
  }

  Future<void> _abrirCadastro() async {
    final criado = await Navigator.push<Usuario>(
      context,
      MaterialPageRoute(builder: (_) => const CadastroPage()),
    );
    if (!mounted) return;
    if (criado != null) {
      widget.aoAutenticar(criado);
    }
  }

  /// Permite informar outra conta no lugar da conta lembrada.
  void _trocarDeConta() {
    setState(() {
      _contaLembrada = null;
      _emailController.clear();
    });
    _focoEmail.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final lembrada = _contaLembrada;
    final campoEmail = lembrada == null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formulario,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.alt_route, size: 72, color: esquema.primary),
                    const SizedBox(height: 12),
                    Text(
                      'S.R.I.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Sistema de Rotas Inteligentes',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: esquema.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    if (lembrada != null) ...[
                      _CartaoContaLembrada(
                        conta: lembrada,
                        aoTrocarDeConta: _trocarDeConta,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (campoEmail) ...[
                      TextFormField(
                        controller: _emailController,
                        focusNode: _focoEmail,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: (valor) =>
                            AutenticacaoService.validarEmail(valor ?? ''),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _senhaController,
                      focusNode: _focoSenha,
                      obscureText: !_senhaVisivel,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _entrar(),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip:
                              _senhaVisivel ? 'Ocultar senha' : 'Mostrar senha',
                          icon: Icon(_senhaVisivel
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _senhaVisivel = !_senhaVisivel),
                        ),
                      ),
                      validator: (valor) => (valor == null || valor.isEmpty)
                          ? 'Informe a senha.'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _manterConectado,
                      onChanged: (valor) =>
                          setState(() => _manterConectado = valor ?? true),
                      title: const Text('Manter conectado'),
                      subtitle: const Text(
                        'Entrar direto nas próximas vezes, sem digitar a senha.',
                        style: TextStyle(fontSize: 12),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    const SizedBox(height: 16),
                    _carregando
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(
                            onPressed: _entrar,
                            icon: const Icon(Icons.login),
                            label: const Text('Entrar'),
                          ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _carregando ? null : _abrirCadastro,
                      child: const Text('Não tenho conta — cadastrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartão que apresenta a conta lembrada no lugar do campo de e-mail.
class _CartaoContaLembrada extends StatelessWidget {
  const _CartaoContaLembrada({
    required this.conta,
    required this.aoTrocarDeConta,
  });

  final ContaLembrada conta;
  final VoidCallback aoTrocarDeConta;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final nomeExibido =
        conta.nome.trim().isEmpty ? conta.email : conta.primeiroNome;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: esquema.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: esquema.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: esquema.primary,
            child: Icon(Icons.person, color: esquema.onPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá de novo, $nomeExibido',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  conta.email,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: esquema.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: aoTrocarDeConta,
            child: const Text('Trocar'),
          ),
        ],
      ),
    );
  }
}
