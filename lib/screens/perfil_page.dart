import 'package:flutter/material.dart';

import '../core/dependencias.dart';
import '../core/excecoes.dart';
import '../models/usuario.dart';
import '../services/autenticacao_service.dart';
import '../widgets/avisos.dart';

/// Resultado devolvido pela tela de perfil para a tela inicial.
class ResultadoPerfil {
  const ResultadoPerfil({this.alterou = false, this.contaExcluida = false});

  /// Houve alteração de nome ou de e-mail.
  final bool alterou;

  /// A conta foi removida e a sessão deve ser encerrada.
  final bool contaExcluida;
}

/// Gerenciamento da conta do usuário (caso de uso UC04 — Gerenciar Usuário).
///
/// Reúne as três operações de manutenção da conta previstas no caso de uso:
/// alterar os dados cadastrais, trocar a senha e excluir a conta.
class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key, required this.usuario});

  final Usuario usuario;

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  final _formularioDados = GlobalKey<FormState>();
  final _formularioSenha = GlobalKey<FormState>();

  late final TextEditingController _nomeController;
  late final TextEditingController _emailController;

  final _senhaAtualController = TextEditingController();
  final _novaSenhaController = TextEditingController();
  final _confirmacaoController = TextEditingController();

  late Usuario _usuario;
  bool _salvandoDados = false;
  bool _salvandoSenha = false;
  bool _alterouAlgo = false;

  @override
  void initState() {
    super.initState();
    _usuario = widget.usuario;
    _nomeController = TextEditingController(text: _usuario.nome);
    _emailController = TextEditingController(text: _usuario.email);
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaAtualController.dispose();
    _novaSenhaController.dispose();
    _confirmacaoController.dispose();
    super.dispose();
  }

  Future<void> _salvarDados() async {
    if (!_formularioDados.currentState!.validate()) return;
    setState(() => _salvandoDados = true);
    try {
      final atualizado = await Dependencias.instance.autenticacao.atualizarPerfil(
        usuario: _usuario,
        nome: _nomeController.text,
        email: _emailController.text,
      );
      if (!mounted) return;
      setState(() {
        _usuario = atualizado;
        _salvandoDados = false;
        _alterouAlgo = true;
      });
      Avisos.sucesso(context, 'Dados atualizados com sucesso.');
    } on FalhaApp catch (falha) {
      if (!mounted) return;
      setState(() => _salvandoDados = false);
      Avisos.erro(context, falha.mensagem);
    }
  }

  Future<void> _alterarSenha() async {
    if (!_formularioSenha.currentState!.validate()) return;
    setState(() => _salvandoSenha = true);
    try {
      final atualizado = await Dependencias.instance.autenticacao.alterarSenha(
        usuario: _usuario,
        senhaAtual: _senhaAtualController.text,
        novaSenha: _novaSenhaController.text,
        confirmacaoNovaSenha: _confirmacaoController.text,
      );
      if (!mounted) return;
      setState(() {
        _usuario = atualizado;
        _salvandoSenha = false;
        _alterouAlgo = true;
      });
      _senhaAtualController.clear();
      _novaSenhaController.clear();
      _confirmacaoController.clear();
      Avisos.sucesso(context, 'Senha alterada com sucesso.');
    } on FalhaApp catch (falha) {
      if (!mounted) return;
      setState(() => _salvandoSenha = false);
      Avisos.erro(context, falha.mensagem);
    }
  }

  Future<void> _excluirConta() async {
    final confirmou = await Avisos.confirmar(
      context,
      titulo: 'Excluir conta',
      mensagem: 'Esta ação remove a sua conta e também todos os pontos e '
          'rotas cadastrados por ela neste aparelho. Não é possível desfazer.',
      rotuloConfirmar: 'Excluir definitivamente',
      destrutivo: true,
    );
    if (!confirmou) return;

    try {
      await Dependencias.instance.autenticacao.excluirConta(_usuario);
      if (!mounted) return;
      Avisos.informacao(context, 'Conta excluída.');
      Navigator.pop(context, const ResultadoPerfil(contaExcluida: true));
    } on FalhaApp catch (falha) {
      if (!mounted) return;
      Avisos.erro(context, falha.mensagem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, ResultadoPerfil(alterou: _alterouAlgo));
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Gerenciar conta')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: esquema.primaryContainer,
              child: Text(
                _inicialDoNome(_usuario.primeiroNome),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: esquema.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Conta criada em '
                '${_formatarData(_usuario.dataCadastro)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 24),
            _TituloSecao('Dados cadastrais'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formularioDados,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nomeController,
                        textCapitalization: TextCapitalization.words,
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
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: (valor) =>
                            AutenticacaoService.validarEmail(valor ?? ''),
                      ),
                      const SizedBox(height: 20),
                      _salvandoDados
                          ? const CircularProgressIndicator()
                          : FilledButton.icon(
                              onPressed: _salvarDados,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Salvar dados'),
                            ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _TituloSecao('Alterar senha'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formularioSenha,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _senhaAtualController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Senha atual',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (valor) => (valor == null || valor.isEmpty)
                            ? 'Informe a senha atual.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _novaSenhaController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Nova senha',
                          helperText: 'Mínimo de 6 caracteres',
                          prefixIcon: Icon(Icons.lock_reset),
                        ),
                        validator: (valor) =>
                            AutenticacaoService.validarSenha(valor ?? ''),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmacaoController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Repita a nova senha',
                          prefixIcon: Icon(Icons.lock_reset),
                        ),
                        validator: (valor) =>
                            (valor != _novaSenhaController.text)
                                ? 'As duas senhas informadas não coincidem.'
                                : null,
                      ),
                      const SizedBox(height: 20),
                      _salvandoSenha
                          ? const CircularProgressIndicator()
                          : FilledButton.icon(
                              onPressed: _alterarSenha,
                              icon: const Icon(Icons.password),
                              label: const Text('Alterar senha'),
                            ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _TituloSecao('Excluir conta'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'A exclusão remove permanentemente a conta e todos os '
                      'pontos e rotas cadastrados por ela neste aparelho.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _excluirConta,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: esquema.error,
                        side: BorderSide(color: esquema.error),
                        minimumSize: const Size.fromHeight(50),
                      ),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Excluir a minha conta'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  static String _inicialDoNome(String nome) {
    return nome.trim().isEmpty ? '?' : nome.trim().substring(0, 1).toUpperCase();
  }

  static String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }
}

class _TituloSecao extends StatelessWidget {
  const _TituloSecao(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        texto.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}
