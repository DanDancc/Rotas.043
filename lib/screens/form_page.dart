import 'package:flutter/material.dart';

import '../core/dependencias.dart';
import '../models/ponto.dart';
import '../widgets/avisos.dart';
import '../widgets/estados.dart';

/// Cadastro e edição de um ponto de interesse (caso de uso UC01).
///
/// O endereço digitado é enviado ao serviço de geocodificação e as
/// coordenadas resultantes são gravadas junto com o ponto. Quando a consulta
/// falha, o ponto é salvo mesmo assim e um aviso explica como completar as
/// coordenadas depois.
class FormPage extends StatefulWidget {
  const FormPage({super.key, this.pontoParaEditar, this.idUsuario});

  /// Ponto a editar; nulo quando se está criando um novo.
  final Ponto? pontoParaEditar;

  final int? idUsuario;

  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  final _formulario = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _enderecoController = TextEditingController();

  bool _carregando = false;

  bool get _editando => widget.pontoParaEditar != null;

  @override
  void initState() {
    super.initState();
    final ponto = widget.pontoParaEditar;
    if (ponto != null) {
      _nomeController.text = ponto.nome;
      _enderecoController.text = ponto.endereco;
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _enderecoController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formulario.currentState!.validate()) return;

    setState(() => _carregando = true);
    try {
      final resultado = await Dependencias.instance.pontos.salvar(
        nome: _nomeController.text,
        endereco: _enderecoController.text,
        existente: widget.pontoParaEditar,
        idUsuario: widget.idUsuario,
      );

      if (!mounted) return;
      if (resultado.aviso != null) {
        Avisos.atencao(context, resultado.aviso!);
      } else {
        Avisos.sucesso(
          context,
          _editando
              ? 'Ponto atualizado com sucesso!'
              : 'Ponto salvo e localizado no mapa!',
        );
      }
      Navigator.pop(context, true);
    } on Exception catch (erro) {
      if (!mounted) return;
      setState(() => _carregando = false);
      Avisos.erro(context, 'Não foi possível salvar o ponto. $erro');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar ponto' : 'Novo ponto'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formulario,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_editando && widget.pontoParaEditar!.temCoordenadas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: CaixaAviso(
                      icone: Icons.info_outline,
                      cor: Theme.of(context).colorScheme.primary,
                      mensagem: 'As coordenadas atuais serão mantidas se o '
                          'endereço não for alterado.',
                    ),
                  ),
                TextFormField(
                  controller: _nomeController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nome do local',
                    hintText: 'Ex.: Mercado Central',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (valor) => (valor == null || valor.trim().isEmpty)
                      ? 'Digite um nome para o local.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _enderecoController,
                  textCapitalization: TextCapitalization.words,
                  maxLines: 2,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Endereço completo',
                    hintText: 'Ex.: Av. Maringá, 134, Centro, Londrina - PR',
                    helperText: 'Quanto mais completo o endereço, mais precisa '
                        'a localização no mapa.',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  validator: (valor) => (valor == null || valor.trim().isEmpty)
                      ? 'Digite o endereço do local.'
                      : null,
                ),
                const SizedBox(height: 32),
                if (_carregando) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text('Buscando as coordenadas no mapa...'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _salvar,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Salvar e buscar no mapa'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
