import 'package:flutter/material.dart';

import '../core/dependencias.dart';
import '../models/usuario.dart';
import '../widgets/avisos.dart';
import 'form_page.dart';
import 'perfil_page.dart';
import 'pontos_tab.dart';
import 'rota_form_page.dart';
import 'rotas_tab.dart';

/// Tela inicial do aplicativo, com as abas de pontos e de rotas.
///
/// As abas recebem um `ValueNotifier` que funciona como gatilho de recarga:
/// quando esta tela cria um ponto ou uma rota, incrementa o contador
/// correspondente e a aba interessada recarrega os seus dados. Assim a aba não
/// precisa conhecer quem a modificou, e a lista nunca fica desatualizada.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.usuario,
    required this.aoEncerrarSessao,
  });

  final Usuario usuario;

  /// Chamada após o logout, para que o portão de sessão volte ao login.
  final VoidCallback aoEncerrarSessao;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _abaAtual = 0;

  final ValueNotifier<int> _gatilhoPontos = ValueNotifier<int>(0);
  final ValueNotifier<int> _gatilhoRotas = ValueNotifier<int>(0);

  int? get _idUsuario => widget.usuario.id;

  @override
  void dispose() {
    _gatilhoPontos.dispose();
    _gatilhoRotas.dispose();
    super.dispose();
  }

  Future<void> _novoPonto() async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FormPage(idUsuario: _idUsuario)),
    );
    if (!mounted) return;
    if (salvou ?? false) _gatilhoPontos.value++;
  }

  Future<void> _novaRota() async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RotaFormPage(idUsuario: _idUsuario)),
    );
    if (!mounted) return;
    if (salvou ?? false) _gatilhoRotas.value++;
  }

  Future<void> _abrirPerfil() async {
    final resultado = await Navigator.push<ResultadoPerfil>(
      context,
      MaterialPageRoute(builder: (_) => PerfilPage(usuario: widget.usuario)),
    );
    if (!mounted) return;

    // A conta excluída derruba a sessão, e o portão de sessão volta ao login.
    if (resultado?.contaExcluida ?? false) {
      widget.aoEncerrarSessao();
      return;
    }
    if (resultado?.alterou ?? false) {
      // Alterações de nome ou de e-mail refletem nas listas; recarregar as
      // duas abas mantém os títulos coerentes com os dados gravados.
      _gatilhoPontos.value++;
      _gatilhoRotas.value++;
    }
  }

  Future<void> _sair() async {
    final confirmou = await Avisos.confirmar(
      context,
      titulo: 'Encerrar sessão',
      mensagem: 'Deseja sair da sua conta? Os seus pontos e rotas continuam '
          'salvos neste aparelho.',
      rotuloConfirmar: 'Sair',
    );
    if (!confirmou) return;

    await Dependencias.instance.autenticacao.sair();
    if (!mounted) return;
    widget.aoEncerrarSessao();
  }

  @override
  Widget build(BuildContext context) {
    final naAbaDePontos = _abaAtual == 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(naAbaDePontos ? 'Meus pontos' : 'Minhas rotas'),
            Text(
              'Olá, ${widget.usuario.primeiroNome}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Meu perfil',
            onPressed: _abrirPerfil,
            icon: const Icon(Icons.account_circle_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (opcao) {
              if (opcao == 'perfil') _abrirPerfil();
              if (opcao == 'sair') _sair();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'perfil',
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_outlined),
                  title: Text('Gerenciar conta'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'sair',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Sair'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _abaAtual,
        children: [
          PontosTab(
            idUsuario: _idUsuario,
            gatilhoAtualizacao: _gatilhoPontos,
          ),
          RotasTab(
            idUsuario: _idUsuario,
            gatilhoAtualizacao: _gatilhoRotas,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: naAbaDePontos ? _novoPonto : _novaRota,
        icon: Icon(naAbaDePontos ? Icons.add_location_alt_outlined : Icons.add_road),
        label: Text(naAbaDePontos ? 'Novo ponto' : 'Nova rota'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _abaAtual,
        onDestinationSelected: (indice) => setState(() => _abaAtual = indice),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place),
            label: 'Pontos',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Rotas',
          ),
        ],
      ),
    );
  }
}
