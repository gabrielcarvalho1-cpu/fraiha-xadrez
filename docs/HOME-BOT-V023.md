# FRAIHA Xadrez V0.23 — Home corrigida e Bot Fácil/Médio

## Escopo e preservação

Esta build de desenvolvimento parte da Home salva em `553fc0a6fd8166317cd2d82bfe2a582377f8a226`. O checkpoint do motor permanece em `dev/v022-rules-checkpoint`, commit `401d813042bcaa8ac1ccfacd71d706b09a10a8c5`. `chess/rules.gd` e os três PNGs da Home não foram alterados.

Não há mudança no servidor Node, no protocolo WebSocket, na main ou no Render. O motor novo é usado nas partidas contra o Bot. Local e Online mantêm as implementações anteriores, com os pontos de integração da interface protegidos por `world.bot != null`. Ranked não foi implementado; Difícil e Expert permanecem desabilitados.

## Home

- As páginas internas usam `MarginContainer`, `VBoxContainer` e uma área de rolagem vertical com largura fixa. Labels têm quebra automática e obtêm a largura do container; o conteúdo pode crescer verticalmente sem sair do painel.
- Foi removida a segunda cópia do cenário que causava banners duplicados. Arte e controles compartilham uma única transformação proporcional. Em janelas que não têm proporção 16:9, o enquadramento preserva os controles com margens verde-escuras sólidas, sem repetir, esticar ou mover partes da arte.
- Perfil, Bot, seleção de lado, Ranking, Configurações, Sobre e Online foram incluídos na revisão de limites.

## Bot e integração

Fluxo: Jogar contra o Bot → Escolha a dificuldade → Escolha seu lado → partida no mesmo nó `World`, tabuleiro, peças e cenário já existentes. Brancas, Pretas e Aleatório são aceitos. Ao escolher Pretas, o Bot inicia com Brancas.

`bot/search.gd` não gera regras próprias. Recebe uma cópia de posição e usa os lances e resultados de `chess/rules.gd`:

- **Fácil:** escolha aleatória uniforme entre os lances legais, incluindo as quatro promoções.
- **Médio:** aprofundamento iterativo, Negamax com alpha-beta, material e fatores posicionais simples, ordenação de capturas e extensão limitada para capturas/xeques. Limite normal de 650 ms e profundidade 3; uma iteração incompleta não substitui a última completa. É um adversário básico, sem promessa de elo ou força competitiva.

`bot/controller.gd` faz a ponte entre a posição e a apresentação. O worker roda em `Thread`, em uma posição independente, sem acessar a árvore de cenas. O resultado é recolhido na thread principal e novamente validado pelo motor antes de aparecer no tabuleiro. A promoção humana usa as alternativas fornecidas pelo motor; roque e en passant são refletidos pelo tabuleiro resultante, sem duplicar sua aplicação na UI.

Cada início/reinício/saída invalida os resultados antigos. Voltar à Home não espera a busca terminar. Uma busca em andamento é descartada ao finalizar; o encerramento do processo faz o join seguro do trabalho, cujo tempo é limitado. ESC pausa a aplicação de lances e pede `Deseja abandonar a partida?`, com `Continuar partida` e `Sair para Home`. Diálogos e menus bloqueiam cliques de jogo.

## Política de resultados

O Bot usa a política do checkpoint: mate, afogamento, material insuficiente reconhecido pelo motor, empate automático na terceira repetição e após 100 meios-lances. O controlador impede continuar após um resultado terminal. A política não implementa reivindicação de empate separada, cinco repetições ou 75 lances; esse limite já está documentado em `RULES-CHECKPOINT.md`.

## Testes reproduzíveis

Usar Godot 4.5.1 e, para o teste de protocolo, Node 22+:

```text
godot --headless --path . --script res://tests/rules_test.gd
godot --headless --path . --script res://tests/bot_search_test.gd
godot --headless --path . --script res://tests/bot_integration_test.gd
godot --headless --path . --script res://tests/home_layout_test.gd
godot --headless --path . --script res://tests/home_navigation_test.gd
godot --headless --path . --script res://tests/legacy_client_test.gd
node tests/online_smoke.cjs wss://fraiha-xadrez.onrender.com
```

O teste WSS cria uma sala temporária, joga, reconecta, pede revanche e desiste; não faz deploy. Os tokens ficam apenas em memória. Capturas são feitas da cena renderizada, não do desktop.

## Build e próximo passo

Build Windows x64, Godot 4.5.1 e template de exportação oficial da mesma versão. O ZIP contém EXE, PCK, online.cfg e instruções. Extrair em uma pasta nova e manter os arquivos juntos. O perfil usa `FRAIHA Xadrez Home Bot V023 Teste`, separado das builds anteriores e do jogo de produção.

Próximo passo: o usuário testa a interface e os níveis Fácil/Médio. Aguardar esse retorno antes de novos modos, Ranked, merge ou deploy.
