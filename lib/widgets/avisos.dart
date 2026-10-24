import 'package:flutter/material.dart';

/// Mensagens padronizadas do aplicativo.
///
/// Centralizar a exibição evita que cada tela invente o seu próprio formato de
/// aviso e garante que toda falha chegue ao usuário com a mesma aparência.
class Avisos {
  const Avisos._();

  static void sucesso(BuildContext context, String mensagem) {
    _mostrar(context, mensagem, Icons.check_circle_outline,
        Theme.of(context).colorScheme.primary);
  }

  static void erro(BuildContext context, String mensagem) {
    _mostrar(context, mensagem, Icons.error_outline,
        Theme.of(context).colorScheme.error);
  }

  static void atencao(BuildContext context, String mensagem) {
    _mostrar(context, mensagem, Icons.warning_amber_outlined,
        const Color(0xFFEF6C00));
  }

  static void informacao(BuildContext context, String mensagem) {
    _mostrar(context, mensagem, Icons.info_outline,
        Theme.of(context).colorScheme.secondary);
  }

  static void _mostrar(
    BuildContext context,
    String mensagem,
    IconData icone,
    Color cor,
  ) {
    final mensageiro = ScaffoldMessenger.maybeOf(context);
    if (mensageiro == null) return;
    mensageiro
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icone, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(mensagem)),
            ],
          ),
          backgroundColor: cor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  /// Pede confirmação antes de uma ação destrutiva.
  ///
  /// Devolve verdadeiro apenas quando o usuário confirma explicitamente.
  static Future<bool> confirmar(
    BuildContext context, {
    required String titulo,
    required String mensagem,
    String rotuloConfirmar = 'Confirmar',
    String rotuloCancelar = 'Cancelar',
    bool destrutivo = false,
  }) async {
    final esquema = Theme.of(context).colorScheme;
    final resposta = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogo, false),
            child: Text(rotuloCancelar),
          ),
          FilledButton(
            style: destrutivo
                ? FilledButton.styleFrom(
                    backgroundColor: esquema.error,
                    foregroundColor: esquema.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(dialogo, true),
            child: Text(rotuloConfirmar),
          ),
        ],
      ),
    );
    return resposta ?? false;
  }
}
