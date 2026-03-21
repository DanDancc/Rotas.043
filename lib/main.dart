import 'package:flutter/material.dart';
import 'screens/home_page.dart'; 

void main() {
  runApp(const MeuAplicativo());
}

class MeuAplicativo extends StatelessWidget {
  const MeuAplicativo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rotas App',
      debugShowCheckedModeBanner: false, // Tira faixa de Debug
      theme: ThemeData(
        primarySwatch: Colors.blue, 
      ),
      home: const HomePage(), // Define qual tela vai abrir primeiro
    );//camel
  }
}