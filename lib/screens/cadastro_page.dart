import 'package:flutter/material.dart';

import '../core/dependencias.dart';
import '../core/excecoes.dart';
import '../services/autenticacao_service.dart';
import '../widgets/avisos.dart';

/// Criação de conta de acesso (caso de uso UC04 — Gerenciar Usuário).
///
/// Ao concluir, a sessão já é aberta pelo serviço de autenticação, e a tela
/// devolve `true` para que o portão de sessão abra a tela inicial.
class CadastroPage extends StatefulWidget {
  const CadastroPage({super.key});

  @override
  State<CadastroPage> createState() => _CadastroPageState();
}

class _CadastroPageState extends State<CadastroPage> {
  final _formulario = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmacaoController = TextEditingController();

  bool _carregando = false;
  bool _senhaVisivel = false;

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmacaoController.dispose();
    super.dispose();
  }

  Future<void> _cadastrar() async {
    if (!_formulario.currentState!.validate()) return;

    setState(() => _carregando = true);
    try {
      final criado = await Dependencias.instance.autenticacao.cadastrar(
        nome: _nomeController.text,
        email: _emailController.text,
        senha: _senhaController.text,
        confirmacaoSenha: _confirmacaoController.text,
      );
      if (!mounted) return;
      Avisos.sucesso(context, 'Conta criada com sucesso. Bem-vindo ao S.R.I.!');
      // Devolve o usuário criado para que o portão de sessão o adote sem
      // depender de uma sessão gravada no banco.
      Navigator.pop(context, criado);
    } on FalhaApp catch (falha) {
      if (!mounted) return;
      setState(() => _carregando = false);
      Avisos.erro(context, falha.mensagem);
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      Avisos.erro(context, 'Não foi possível criar a conta. Tente novamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
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
                    TextFormField(
                      controller: _nomeController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nome completo',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (valor) =>
                          AutenticacaoService.validarNome(valor ?? ''),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (valor) =>
                          AutenticacaoService.validarEmail(valor ?? ''),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _senhaController,
                      obscureText: !_senhaVisivel,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        helperText: 'Mínimo de 6 caracteres',
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
                      validator: (valor) =>
                          AutenticacaoService.validarSenha(valor ?? ''),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmacaoController,
                      obscureText: !_senhaVisivel,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _cadastrar(),
                      decoration: const InputDecoration(
                        labelText: 'Repita a senha',
                        prefixIcon: Icon(Icons.lock_reset),
                      ),
                      validator: (valor) => (valor != _senhaController.text)
                          ? 'As duas senhas informadas não coincidem.'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    _carregando
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(
                            onPressed: _cadastrar,
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text('Criar conta'),
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
