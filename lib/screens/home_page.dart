import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/local_map.dart';
import 'form_page.dart';
import 'map_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // guardar os pontos q vem db
  List<LocalMap> _pontos = [];

  @override
  void initState() {
    super.initState();
    _atualizarLista(); // busca os dados
  }

  // busca a lista atualizada
  void _atualizarLista() async {
    final pontos = await DatabaseHelper.instance.getTodosPontos();
    setState(() {
      _pontos = pontos; // Atualiza a variável
    });
  }

  // deletar um ponto
  void _deletarPonto(int id) async {
    await DatabaseHelper.instance.delete(id);
    _atualizarLista(); // atualiza a lista na tela
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ponto deletado com sucesso!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Pontos no Mapa'),
      ),
      // Se lista vazia, mostra um texto. Se não, constrói a lista.
      body: _pontos.isEmpty
          ? const Center(child: Text('Nenhum ponto salvo ainda. Crie um!'))
          : ListView.builder(
              itemCount: _pontos.length,
              itemBuilder: (context, index) {
                final ponto = _pontos[index];
                
                
                return ListTile(
                  title: Text(ponto.nome),
                  subtitle: Text(ponto.endereco),
                  
                  // Botões que ficam à direita
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                       icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          Navigator.push(
                          context,
                          // Aqui nós passamos o 'ponto' atual para a tela de edição preencher os campos
                          MaterialPageRoute(builder: (context) => FormPage(pontoParaEditar: ponto)),
                          ).then((_) => _atualizarLista());
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deletarPonto(ponto.id!),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(context, 
                    MaterialPageRoute(builder:(context) => MapPage(ponto: ponto),
                    )
                   );
                    // tela do mapa
                  },
                );
              },
            ),
            
      // Botão flutuante para adicionar novos pontos
     floatingActionButton: FloatingActionButton(
  child: const Icon(Icons.add),
  onPressed: () {
    // Vai para o Form ao sair att
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FormPage()),
    ).then((_) => _atualizarLista()); 
  },
),
    );
  }
}