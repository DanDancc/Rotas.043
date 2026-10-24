import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:rotas_app/app.dart';
import 'package:rotas_app/core/dependencias.dart';
import 'package:rotas_app/screens/login_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'apoio/banco_teste.dart';

void main() {
  // Nos testes de widget o banco precisa rodar sem isolamento, para que as
  // consultas resolvam dentro do tempo simulado pelo flutter_test.
  setUpAll(() => prepararSqflite(semIsolado: true));

  late Database db;

  // A tela de acesso consulta a conta lembrada e a preferência de sessão já na
  // abertura, então todos os testes deste arquivo precisam de um banco válido.
  setUp(() async {
    db = await abrirBancoEmMemoria();
    Dependencias.instance = Dependencias(
      provedor: () async => db,
      clienteHttp: MockClient((_) async => throw StateError('sem rede')),
    );
  });

  tearDown(() async {
    await db.close();
    Dependencias.instance = Dependencias();
  });

  group('LoginPage', () {
    testWidgets('cobra o e-mail e a senha antes de tentar entrar',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: LoginPage(aoAutenticar: (_) {})),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pump();

      expect(find.text('Informe o e-mail.'), findsOneWidget);
      expect(find.text('Informe a senha.'), findsOneWidget);
    });

    testWidgets('recusa e-mail em formato inválido', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: LoginPage(aoAutenticar: (_) {})),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        'ana-arroba-exemplo',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'segredo1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pump();

      expect(find.textContaining('e-mail válido'), findsOneWidget);
    });

    testWidgets('a opção manter conectado começa marcada', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: LoginPage(aoAutenticar: (_) {})),
      );
      await tester.pumpAndSettle();

      final caixa = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Manter conectado'),
      );
      expect(caixa.value, isTrue);
    });
  });

  group('fluxo completo de acesso', () {
    testWidgets('cadastro leva o usuário da tela de login à tela inicial',
        (tester) async {
      await tester.pumpWidget(const RotasApp());
      await tester.pumpAndSettle();

      // Sem sessão gravada, o aplicativo abre no login.
      expect(find.text('Sistema de Rotas Inteligentes'), findsOneWidget);

      await tester.tap(find.text('Não tenho conta — cadastrar'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Criar conta'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome completo'),
        'Ana Souza',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        'ana@exemplo.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'segredo1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Repita a senha'),
        'segredo1',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pumpAndSettle();

      // A conta criada é adotada pelo portão de sessão e leva à tela inicial.
      expect(find.text('Meus pontos'), findsWidgets);
      expect(find.textContaining('Olá, Ana'), findsOneWidget);
      expect(find.text('Nenhum ponto salvo ainda'), findsOneWidget);
    });

    testWidgets('a senha confirmada precisa ser igual à informada',
        (tester) async {
      await tester.pumpWidget(const RotasApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Não tenho conta — cadastrar'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome completo'),
        'Ana Souza',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        'ana@exemplo.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'segredo1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Repita a senha'),
        'outrasenha',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Criar conta'));
      await tester.pump();

      expect(find.textContaining('não coincidem'), findsOneWidget);
    });
  });

  group('acesso com conta lembrada', () {
    testWidgets('a tela seguinte abre com o e-mail preenchido e sem o campo',
        (tester) async {
      // Primeiro acesso: cria a conta e, com ela, a conta lembrada.
      final servico = Dependencias.instance.autenticacao;
      await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );
      // Simula "não manter conectado": a sessão não é retomada.
      await servico.sair();
      await servico.entrar(
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        manterConectado: false,
      );
      await servico.sair();

      await tester.pumpWidget(const RotasApp());
      await tester.pumpAndSettle();

      // A conta é lembrada, então o campo de e-mail não é exibido...
      expect(find.textContaining('Olá de novo, Ana'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'E-mail'), findsNothing);
      // ...e o foco já está na senha, restando apenas digitá-la.
      final campoDeSenha = tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Senha'),
          matching: find.byType(EditableText),
        ),
      );
      expect(campoDeSenha.focusNode.hasFocus, isTrue);
    });

    testWidgets('entrar com a conta lembrada leva direto à tela inicial',
        (tester) async {
      final servico = Dependencias.instance.autenticacao;
      await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );
      await servico.sair();

      await tester.pumpWidget(const RotasApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'segredo1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Meus pontos'), findsWidgets);
      expect(find.textContaining('Olá, Ana'), findsOneWidget);
    });

    testWidgets('"Trocar" devolve o campo de e-mail', (tester) async {
      final servico = Dependencias.instance.autenticacao;
      await servico.cadastrar(
        nome: 'Ana Souza',
        email: 'ana@exemplo.com',
        senha: 'segredo1',
        confirmacaoSenha: 'segredo1',
      );
      await servico.sair();

      await tester.pumpWidget(const RotasApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Trocar'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'E-mail'), findsOneWidget);
      expect(find.textContaining('Olá de novo'), findsNothing);
    });
  });
}
