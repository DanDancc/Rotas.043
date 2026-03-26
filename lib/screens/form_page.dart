import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // requisição web
import 'dart:convert'; // resposta do OSM
import '../models/local_map.dart';
import '../database/db_helper.dart';

class FormPage extends StatefulWidget {
  // Recebe um ponto se for para Editar. Se for para Criar, será nulo (null).
  final LocalMap? pontoParaEditar;

  const FormPage({super.key, this.pontoParaEditar});

  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  // Controladores para pegar o texto
  final _nomeController = TextEditingController();
  final _enderecoController = TextEditingController();
  
  // Valida o formulário
  final _formKey = GlobalKey<FormState>();
  
  // Variável para mostrar busca no mapa
  bool _carregando = false; 

  @override
  void initState() {
    super.initState();
    // Se recebemos um ponto para editar, preenchemos os campos com os dados dele
    if (widget.pontoParaEditar != null) {
      _nomeController.text = widget.pontoParaEditar!.nome;
      _enderecoController.text = widget.pontoParaEditar!.endereco;
    }
  }

  // busca as coordenadas e salva no banco
  Future<void> _salvarPonto() async {
    // 1. Verifica se os campos não estão vazios
    if (_formKey.currentState!.validate()) {
      setState(() {
        _carregando = true;
      });

      String nome = _nomeController.text;
      String enderecoTexto = _enderecoController.text;
      double? lat;
      double? lon;

      // 2. Busca Lat e Long no OSM
      try {
        // Link de busca para o endereço digitado
        final url = Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=$enderecoTexto&format=json&limit=1');
        
        // Chamada HTTP
        final resposta = await http.get(url, headers: {
          'User-Agent': 'RotasApp_Flutter_Learning', // O Nominatim exige que a gente se identifique
        });

        // Extrair a Lat e Long
        if (resposta.statusCode == 200) {
          final dados = json.decode(resposta.body);
          if (dados.isNotEmpty) {
            lat = double.parse(dados[0]['lat']);
            lon = double.parse(dados[0]['lon']);
          }
        }
      } catch (e) {
        print("Erro ao buscar coordenadas: $e");
      }

      // 3. Monta a ficha
      final ponto = LocalMap(
        id: widget.pontoParaEditar?.id, // Mantém o ID
        nome: nome,
        endereco: enderecoTexto,
        latitude: lat,
        longitude: lon,
      );

      // 4. Salva no Banco
      if (widget.pontoParaEditar != null) {
        await DatabaseHelper.instance.update(ponto);
      } else {
        await DatabaseHelper.instance.insert(ponto);
      }

      // 5. Sai do formulário e volta para a tela inicial
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pontoParaEditar == null ? 'Novo Ponto' : 'Editar Ponto'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Nome
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(labelText: 'Nome do Local'),
                validator: (valor) => valor!.isEmpty ? 'Digite um nome' : null,
              ),
              const SizedBox(height: 16),
              
              // Endereço
              TextFormField(
                controller: _enderecoController,
                decoration: const InputDecoration(
                    labelText: 'Endereço Completo',
                    hintText: 'Ex: Av. Maringá, 134, Centro, Cidade'),
                validator: (valor) => valor!.isEmpty ? 'Digite um endereço' : null,
              ),
              const SizedBox(height: 32),
              
              // Salvar
              _carregando
                  ? const CircularProgressIndicator() // Bolinha girando se estiver carregando
                  : ElevatedButton(
                      onPressed: _salvarPonto,
                      child: const Text('Salvar e Buscar no Mapa'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}