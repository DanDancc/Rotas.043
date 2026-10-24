# S.R.I. — Sistema de Rotas Inteligentes

Aplicativo móvel (Flutter) para planejamento, execução e reutilização de rotas de
coleta e entrega, com foco em motoristas autônomos, entregadores e pequenas
empresas de logística. Projeto desenvolvido como etapa prática do estágio
obrigatório do Curso de Bacharelado em Ciência da Computação do Centro
Universitário Filadélfia (Unifil), na empresa concedente NPI — Núcleo de Práticas
em Informática.

## Funcionalidades

Os casos de uso estão descritos na pasta `documentos/` (documentos do processo
RUP). Todos estão implementados na versão atual:

| Caso de uso | Descrição | Situação |
|---|---|---|
| **UC01 — Gerenciar Locais** | Cadastro, consulta, edição e exclusão de pontos de interesse, com conversão automática do endereço em coordenadas | Implementado |
| **UC02 — Gerar Rotas** | Montagem de rotas ponto a ponto e em circuito, com ordenação automática das paradas, traçado no mapa, distância total e duração estimada | Implementado |
| **UC03 — Gerenciar Rotas Salvas** | Gravação, reabertura, edição e exclusão das rotas calculadas | Implementado |
| **UC04 — Gerenciar Usuário** | Criação de conta, acesso, manutenção dos dados cadastrais, troca de senha e exclusão da conta | Implementado |
| **Navegação assistida** | Acompanhamento da posição por GPS, indicação do próximo ponto, distância e sentido até ele e avanço automático entre paradas | Implementado |

## Organização do código

O código está separado em camadas, de modo que as telas não acessem o banco nem
os serviços externos diretamente:

```
lib/
  main.dart, app.dart        Ponto de entrada e portão de sessão
  core/                      Tema, exceções de domínio, utilitários geográficos
                             e montagem das dependências (Dependencias)
  models/                    Ponto, Rota (com TipoRota e FonteCalculo) e Usuario
  data/
    database/                DatabaseHelper: conexão, esquema e migrações
    dao/                     Objetos de acesso a dados, um por conjunto de tabelas
    repositories/            Regras de negócio (PontoRepository, RotaRepository)
  services/                  Geocodificação, roteamento, otimização, autenticação,
                             localização e cálculos de navegação
  screens/                   Telas
  widgets/                   Componentes visuais reutilizáveis
```

A classe `Dependencias` (`lib/core/dependencias.dart`) é o ponto único de
montagem: em produção ela usa o banco real e o cliente HTTP real; nos testes,
basta atribuir uma instância com banco em memória e cliente HTTP simulado a
`Dependencias.instance`.

## Tecnologias

| Componente | Versão |
|---|---|
| Flutter | 3.41.5 |
| Dart | 3.11.3 |
| sqflite | 2.4.2 |
| flutter_map | 8.2.2 |
| latlong2 | 0.9.1 |
| http | 1.6.0 |
| geolocator | 14.1.1 |
| crypto | 3.0.7 |
| path | 1.9.1 |
| flutter_lints (dev) | 5.0.0 |
| sqflite_common_ffi (dev) | 2.4.0+3 |

Todas as bibliotecas são de código aberto e nenhuma exige chave de API paga.

## Serviços externos

| Serviço | Uso | Observação |
|---|---|---|
| **Nominatim** (OpenStreetMap) | Conversão de endereço em coordenadas | A política de uso recomenda no máximo 1 requisição por segundo. O serviço implementado impõe um intervalo mínimo de 1,1 s entre consultas externas e mantém cache local na tabela `geocache` |
| **OSRM** (`router.project-osrm.org`) | Trajeto sobre as vias, com distância e duração | Limite de 20 s por requisição; quando falha, o sistema recua para estimativa local em linha reta e informa o usuário |
| **Tile Server** (OpenStreetMap) | Imagens do mapa | Atribuição exibida no mapa, conforme a licença |

## Banco de dados local

O esquema evoluiu em quatro versões, sempre de forma incremental e sem perda de
dados (migrações aplicadas por `DatabaseHelper`):

- **v1** — `pontos`: os locais cadastrados.
- **v2** — `rotas` e `rota_pontos`: as rotas e a sua ordem de visita.
- **v3** — `usuarios`, `sessao` e `geocache`, além da coluna `pontos.id_usuario`.
- **v4** — `preferencias`: a opção "manter conectado" e a conta lembrada.

As chaves estrangeiras são aplicadas de fato (`PRAGMA foreign_keys = ON`), de
modo que excluir um ponto o remove das rotas que o utilizavam e excluir uma
conta remove os pontos e as rotas dela. A gravação de uma rota ocorre dentro de
uma transação, porque envolve duas tabelas.

## Acesso ao aplicativo

A autenticação é obrigatória, conforme a Especificação Complementar, mas a tela
de acesso foi construída para exigir o **mínimo de digitação**:

- **Conta lembrada** — o e-mail e o nome do último acesso ficam gravados em
  `preferencias`. Na abertura seguinte, a tela mostra um cartão com a conta
  identificada no lugar do campo de e-mail, e o foco já começa na senha. O
  usuário digita apenas a senha e confirma no próprio botão do teclado.
  O botão **Trocar** permite informar outra conta.
- **Manter conectado** — marcado por padrão. Marcado, a sessão é gravada e o
  aplicativo abre direto no conteúdo nas próximas execuções; desmarcado, a
  senha volta a ser pedida na próxima abertura, mas o e-mail continua lembrado.

Para que isso funcione, o usuário autenticado é mantido em memória na tela que
decide entre acesso e conteúdo (`PortaoSessao` em `lib/app.dart`), e a gravação
da sessão é uma decisão à parte.

## Ordenação das paradas

A ordem de visita é definida por `OtimizadorRotaService`, em duas etapas:

1. **Construção** — heurística do vizinho mais próximo, a partir da origem.
2. **Refinamento** — método 2-opt, que inverte trechos do percurso enquanto
   houver ganho de distância.

Nas rotas em circuito o percurso é tratado como um ciclo com partida fixa; nas
rotas ponto a ponto, a origem e o destino escolhidos pelo usuário são
preservados. O ganho obtido e o número de ajustes são registrados e exibidos na
interface. O resultado é comparado com o ótimo obtido por força bruta em um
teste automatizado.

## Como executar

```bash
flutter pub get
flutter run
```

As permissões necessárias já estão declaradas nos projetos nativos:

- `android/app/src/main/AndroidManifest.xml`: `INTERNET`,
  `ACCESS_FINE_LOCATION` e `ACCESS_COARSE_LOCATION`;
- `ios/Runner/Info.plist`: `NSLocationWhenInUseUsageDescription`.

O GPS precisa estar ligado para a tela de navegação assistida. As demais
funcionalidades operam sem localização.

## Verificação

```bash
flutter analyze              # análise estática: nenhum aviso ou erro
flutter test                 # 108 testes automatizados
flutter build apk --debug    # pacote de instalação Android
flutter build web --release  # compilação para a web
```

A suíte está distribuída assim:

| Arquivo | Testes | Cobertura |
|---|---|---|
| `test/geo_utils_test.dart` | 20 | Distâncias por Haversine, formatação, geometria e tolerância a dados corrompidos |
| `test/otimizador_rota_test.dart` | 9 | 2-opt, preservação de origem e destino, comparação com o ótimo por força bruta |
| `test/navegacao_test.dart` | 16 | Avanço entre paradas, instruções, distância restante e progresso |
| `test/autenticacao_test.dart` | 25 | Derivação e comparação de senha, validações, conta lembrada, política de sessão e exclusão de conta |
| `test/persistencia_test.dart` | 30 | Esquema, migração da v1, objetos de acesso, preferências, integridade referencial, transação, cache e recuo de roteamento |
| `test/widget_test.dart` | 8 | Formulário de acesso, cadastro e acesso com conta lembrada |

Os testes de persistência usam um banco SQLite em memória criado com o **mesmo
esquema e as mesmas migrações** de produção, e as chamadas externas são
substituídas por respostas simuladas, de modo que a suíte não depende de rede.

## Documentação

- `Docs/relatorio-final/` — relatório final de estágio em LaTeX. Os diagramas
  são gerados a partir das fontes PlantUML em `Docs/relatorio-final/diagramas/`:

  | Fonte PlantUML | Figura no relatório | Onde aparece |
  |---|---|---|
  | `diagrama-de-classes.puml` | `diagrama-de-classes.png` | Modelo de classes |
  | `der.puml` | `der.png` | Modelo de dados |
  | `diagrama-de-camadas.puml` | `diagrama-de-camadas.png` | Organização em camadas |
  | `atividades-otimizacao.puml` | `atividades-otimizacao.png` | Ordenação das paradas |
  | `sequencia-gerenciar-locais.puml` | `sequencia-gerenciar-locais.png` | UC01, gerenciamento de locais |
  | `sequencia-gerar-rota.puml` | `sequencia-gerar-rota.png` | UC02, geração de rotas |
  | `sequencia-autenticacao.puml` | `sequencia-autenticacao.png` | UC04, autenticação |

  Para regerar: `java -jar plantuml.jar -charset UTF-8 -tpng -o ../imagens diagramas/*.puml`

  O diagrama antigo do UC01 (anterior à refatoração em camadas) está preservado
  em `diagramas/backup/sequencia-gerenciar-locais-v1.png`.

  Os diagramas herdados do plano (`caso-de-uso`, `estado-gerenciar-locais`,
  `implantacao`, `workflow-as-is`) são imagens finais, sem fonte no repositório.

  Os diagramas de sequência são densos: em uma página A4 eles ocupam a largura
  inteira do texto e são inseridos em página própria, de modo que a leitura
  confortável é feita na versão digital, com zoom.

  Os diagramas também foram atualizados dentro dos artefatos do RUP em
  `documentos/` (`DER.docx`, `Diagrama de Classe.docx` e
  `Diagrama de sequência.docx`), com a moldura recalculada para a proporção
  nova. Os originais estão em `documentos/_originais/`.

- `Docs/plano-de-estagio/` — plano de estágio em LaTeX (atenção: os capítulos de
  texto dessa pasta foram reaproveitados de outro projeto e **não** correspondem
  ao S.R.I.; o plano efetivamente entregue é `documentos/Entrega da banca/`).
- `documentos/` — documentos do processo RUP: Visão, Pedido do Investidor,
  Especificação de Caso de Uso, Especificação Complementar, Glossário, diagramas
  e registros de orientação.

## Verificação funcional

O aplicativo foi instalado e operado em emulador Android (API 36), percorrendo os
fluxos dos quatro casos de uso e da navegação assistida. Foram verificados:

- criação de conta, abertura de sessão e restauração da sessão ao reabrir;
- conta lembrada: na segunda abertura a tela de acesso já vem com a conta
  identificada e apenas o campo de senha;
- **manter conectado marcado** — o app foi encerrado e reaberto e apresentou
  direto a lista de pontos, sem passar pela tela de acesso;
- **manter conectado desmarcado** — o app foi encerrado e reaberto e voltou a
  pedir a senha, porém com o e-mail já preenchido;
- cadastro de pontos e conversão de endereços em coordenadas pelo Nominatim;
- renderização do mapa com blocos do OpenStreetMap e marcador do ponto;
- migração de um banco da versão 1, com os pontos antigos vinculados à primeira
  conta criada, sem perda de dados;
- cálculo de rota em circuito com quatro paradas, resolvido pelo **OSRM** e não
  pelo recuo local (23,9 km, 40 min, traçado sobre as vias de Londrina);
- gravação e reabertura da rota salva;
- permissão de localização, instrução do próximo ponto e avanço automático entre
  paradas na navegação assistida.

## Limitações conhecidas

- A navegação é **assistida**, não curva a curva: não recalcula o trajeto a cada
  desvio da malha viária nem emite comandos de voz.
- A distância restante mostrada durante a navegação usa distância em linha reta
  até o próximo ponto, e não a geometria do trajeto sobre as vias.
- As métricas de tempo de resposta (abaixo de 30 s) e de assertividade (pelo
  menos 70%) declaradas nos requisitos ainda dependem de medição em campo.
- A verificação foi feita em emulador, que não reproduz a variação real da
  precisão do GPS, a instabilidade da rede móvel nem o consumo de energia em uso
  prolongado; a validação em aparelho físico permanece pendente.
