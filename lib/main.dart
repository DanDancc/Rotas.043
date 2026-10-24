import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  // Necessário porque a inicialização do banco usa plugins de plataforma.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RotasApp());
}
