import 'package:flutter/material.dart';

/// Aparência e identidade visual do aplicativo.
class Tema {
  const Tema._();

  /// Azul usado como cor-base da identidade do S.R.I.
  static const Color primaria = Color(0xFF1565C0);

  /// Verde usado para indicar rota calculada e sucesso.
  static const Color sucesso = Color(0xFF2E7D32);

  /// Laranja usado para avisos, como o recuo para a estimativa local.
  static const Color atencao = Color(0xFFEF6C00);

  static ThemeData construir() {
    final esquema = ColorScheme.fromSeed(
      seedColor: primaria,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      appBarTheme: AppBarTheme(
        backgroundColor: esquema.primary,
        foregroundColor: esquema.onPrimary,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: esquema.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
