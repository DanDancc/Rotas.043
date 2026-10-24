import 'package:flutter/material.dart';

import 'core/dependencias.dart';
import 'core/tema.dart';
import 'models/usuario.dart';
import 'screens/home_page.dart';
import 'screens/login_page.dart';
import 'widgets/estados.dart';

/// Aplicativo S.R.I. — Sistema de Rotas Inteligentes.
class RotasApp extends StatelessWidget {
  const RotasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S.R.I. — Sistema de Rotas Inteligentes',
      debugShowCheckedModeBanner: false,
      theme: Tema.construir(),
      home: const PortaoSessao(),
    );
  }
}

/// Decide qual tela abrir conforme exista ou não uma sessão gravada.
///
/// A autenticação é exigida pela Especificação Complementar, e centralizar
/// essa decisão aqui — em vez de repetir a verificação em cada tela — garante
/// que nenhuma funcionalidade fique acessível sem login.
///
/// O usuário autenticado é mantido **em memória** nesta tela, e não apenas no
/// banco. Isso é o que permite oferecer a opção ``manter conectado``: quando
/// ela está desmarcada, nenhuma sessão é gravada, mas o usuário continua
/// navegando normalmente até fechar o aplicativo.
class PortaoSessao extends StatefulWidget {
  const PortaoSessao({super.key});

  @override
  State<PortaoSessao> createState() => _PortaoSessaoState();
}

class _PortaoSessaoState extends State<PortaoSessao> {
  Usuario? _usuario;
  bool _carregando = true;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregarSessaoGravada();
  }

  /// Lê do banco a eventual sessão gravada por um acesso anterior.
  Future<void> _carregarSessaoGravada() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final usuario = await Dependencias.instance.autenticacao.usuarioAtual();
      if (!mounted) return;
      setState(() {
        _usuario = usuario;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        _erro = erro;
        _carregando = false;
      });
    }
  }

  /// Chamado pela tela de acesso após autenticar ou criar a conta.
  void _aoAutenticar(Usuario usuario) {
    setState(() {
      _usuario = usuario;
      _erro = null;
    });
  }

  /// Chamado após o encerramento da sessão ou a exclusão da conta.
  void _aoEncerrarSessao() {
    setState(() => _usuario = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: TelaCarregando(mensagem: 'Carregando o S.R.I...'),
      );
    }

    if (_erro != null) {
      return Scaffold(
        body: EstadoVazio(
          icone: Icons.error_outline,
          titulo: 'Não foi possível abrir o aplicativo',
          descricao: 'Houve uma falha ao acessar os dados locais.\n$_erro',
          rotuloAcao: 'Tentar novamente',
          aoAcionar: _carregarSessaoGravada,
        ),
      );
    }

    final usuario = _usuario;
    if (usuario == null) {
      return LoginPage(aoAutenticar: _aoAutenticar);
    }
    return HomePage(
      usuario: usuario,
      aoEncerrarSessao: _aoEncerrarSessao,
    );
  }
}
