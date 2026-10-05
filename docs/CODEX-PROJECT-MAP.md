# FRAIHA Xadrez — mapa em leitura

Verificado em 05/10/2026 no checkout isolado, sem executar o jogo, testes, builds ou serviços.

## Base e isolamento

- Worktree: `C:\Users\Usuário\Documents\Codex\orca-worktrees\codex-setup-rules`.
- Branch: `codex/setup-rules`, criada após `git fetch origin` a partir de `origin/dev/web-alpha`.
- SHA base e remoto observado: `1f3dd8f5ba7b8bf087ebc5ca3debe7a6290c9060` (R39).
- Checkout inicial limpo; 777 arquivos rastreados na base. Alterações locais da pasta principal não foram copiadas.
- A pasta principal tem alterações e pacotes locais; nenhum deles foi editado. Worktrees compartilham metadados Git, mas não a árvore de arquivos.

## Pontos de entrada e módulos

| Área | Arquivos / diretórios observados | Papel observado |
| --- | --- | --- |
| Cliente | `presentation_v019/stage.tscn`, `presentation_v019/stage.gd` | Cena principal configurada em `project.godot`; coordena conta, bots, Ranked, social, análise e resultado |
| Home e UI | `ui_v022/main_hub.gd`, `mobile_layout.gd`, `fullscreen_control.gd`, `web_text_field.gd` | Home, layouts mobile, fullscreen e ponte de inputs Web |
| Xadrez | `chess/rules.gd`, `online_v021/chess_rules.js` | Motores de regras cliente/servidor |
| Conta / social | `account/`, `profile/`, `social/`, `online_v021/accounts/`, `online_v021/social/` | Conta, perfil, presença, convites, mensagens e cosméticos |
| Ranked / Casual | `ranked/`, `online_v021/ranked/` | Controladores, relógios, matchmaking e progressão |
| Bots | `bot/`, `online_v021/bots/service.js` | Ladder, busca, progresso e recompensa |
| Análise | `analysis/engine.gd`, `fair_play.gd`, `match_recorder.gd`, `match_history.gd` | Engine, fair play, registros, revisão e treino |
| Marcha Real | `marcha/`, `online_v021/modes/marcha_rules.js` | UI, IA e regras; ambos os motores de regras são protegidos |
| XEQUE | `xeque/`, `online_v021/modes/xeque_rules.js` | Modo próprio com UI, IA e regras |
| Backend Node | `online_v021/server.js`, `backend.js`, `package.json` | Entrada HTTP/WebSocket e serviços; Node >=20, dependência `ws`, script `npm start` |
| Backend anterior / cliente online | `online_v020/server.gd`, `client.gd`, `endpoint.gd` | Servidor Godot e código cliente; o nome v020 não torna todo o diretório obsoleto |
| Pagamentos | `monetization/`, `online_v021/payments/` | Áreas protegidas; não alteradas nem auditadas internamente nesta tarefa |
| Banco | `supabase/migrations/` | Dez arquivos SQL, de 0001 a 0010; existência local não prova aplicação |
| Export Web | `web/engines/`, `analysis/ENGINE.md`, `analysis/LICENSES.md` | Documentação de Stockfish WASM/Worker e distribuição |
| Documentação | `docs/R32-MARCHA-REAL.md`, `R33-XEQUE.md`, `R35-ONLINE-MODOS.md`, `PAGAMENTOS.md` | Contexto de releases; não prova estado atual dos serviços |

## Divergências e limites da evidência

`package.json` aponta para `online_v021/server.js`. Em 05/10/2026, o usuário confirmou que os logs de deploy de hoje mostram `> node online_v021/server.js` e que o serviço Render é do tipo Node. Portanto, o servidor ativo informado é `online_v021/server.js` com Node. Essa confirmação veio do usuário; o Codex não consultou o painel nem verificou SHA LIVE.

`Dockerfile` usa Godot 4.5.1 e inicia `online_v020/server.gd`; `render.yaml` declara esse Dockerfile. O usuário confirmou que ambos estão desatualizados e não são usados pelo serviço atual. `README.md` também descreve o servidor anterior. Registrar a divergência não autoriza corrigir esses arquivos: foram preservados nesta tarefa.

`online_v020/endpoint.gd` centraliza o destino de conta/Casual/Ranked/amigos: configuração padrão → staging se a build tiver essa feature → override ignorado pelo Git no editor → configuração ao lado do executável desktop → `FRAIHA_SERVER_URL`. Portanto, URL no repositório sozinha não prova destino efetivo da build.

`project.godot`, `export_presets.cfg`, `.uid` e `.import` já estão rastreados na base. Conforme esclarecimento do usuário, a regra exclui mudanças desses arquivos dos commits do Codex; não exige removê-los do histórico ou do índice. `.gitignore` não foi alterado.

Não verificados: SHA LIVE de Render, migrations aplicadas no Supabase, compartilhamento real do banco entre ambientes, build pública/Cloudflare, engine ativa, credenciais configuradas, comandos disponíveis de Godot e resultados atuais de testes. Supabase, Render e Cloudflare não foram acessados ou alterados.

## Testes encontrados, sem execução

- Godot: `tests/*_test.gd`, incluindo regras, análise, conta, UI, bots, Marcha e XEQUE. `tests/marcha_rules_test.gd` documenta `godot --headless --path . -s tests/marcha_rules_test.gd`; confirmar binário e efeitos antes de uso futuro.
- Node: `tests/server/*_test.cjs`. `helpers.cjs` pode iniciar o servidor Node local; não executar durante mapeamento.
- Paridade: `tests/server/modes_parity_test.cjs` compara motores com `tests/fixtures/marcha_parity.json.gz` e `xeque_parity.json.gz`, incluindo ações, IA, estado e eventos. Geradores: `tools/marcha_parity_fixture.gd` e `xeque_parity_fixture.gd`. Fixture existente não prova paridade atual sem execução.
- Web: `tests/web/fullscreen_flow_e2e.py` documenta teste Playwright contra build Web servida, com caminho de Chromium configurável. Sua existência não comprova outros fluxos Web.
- Scripts de integração de pagamentos/party iniciam processos auxiliares. Nenhum foi executado.
- `package.json` tem script `start`, sem script `test`; descobrir comandos de cada suíte em vez de presumir `npm test`.

## Configuração produzida

`AGENTS.md` concentra as regras permanentes e o isolamento. A skill de projeto está em `.agents/skills/fraiha-xadrez/`, com referências carregadas conforme o assunto. Nenhum checkpoint histórico do anexo foi promovido a estado atual.

Esta tarefa permite somente documentação/regras/skill. Nenhum código, asset, SQL, dependência ou configuração de runtime foi modificado. A validação da skill e o commit de configuração são relatados no encerramento; não são testes do jogo.
