# Wave 2 — implementação local A+B+S11

## Resultado e autoridade

Task `task_f1405057b7ca`, Dispatch `ctx_9492646dce73`, Run `run_78943810cec2`. Único implementador; nenhum subworker, novo Run/Task/Dispatch ou reinício. Preamble original mantido após correção do modelo nesta sessão. Solicitado GPT-6.1-Sol HIGH por autenticação, concorrência e fair play; configuração efetiva do launcher não consultada pelo worker.

Worktree exclusiva `C:/Users/Usuário/orca/workspaces/project/codex-security-reconcile-ab-s11`, branch `codex/security-reconcile-ab-s11`. HEAD inicial/final `18231c88e844167db94fb50feef6cfaca0e06853`. Branch automática nova limpa renomeada somente após confirmar destino inexistente; sem criação adicional. Índice vazio. Fetch prévio realizado pelo coordenador, conforme spec; nenhum fetch necessário pelo worker. Divergência remota/LIVE não consultados, pois não houve push/deploy.

**TECHNICAL OUTCOME:** implementação local dos impeditivos e validação server-side/WS concluída; GDScript e cliente Godot/export não executados. **Classificação: APROVAR COM AJUSTES**, condicionada ao gate de QA Godot descrito abaixo e revisão do candidato; não é autorização de commit/publicação. **ORCHESTRATION OUTCOME:** sucesso técnico reportável pelo próprio Dispatch; o settlement depende do `worker_done` válido emitido após este documento, não deste texto.

Estado entregue: implementado localmente e testado localmente no alcance especificado; nada commitado, enviado, integrado, exportado ou publicado. Sem acesso à principal, secrets, Supabase, Render ou Cloudflare. Sem migrations, pagamentos, infraestrutura, regras de xadrez/Marcha ou artefatos protegidos. Nenhuma limpeza/sobrescrita das fontes e worktrees antigas.

## Proveniência e composição

Plano anterior à implementação e SHA256 das fontes em `docs/security-reconcile-ab-s11-base.md`. A branch/HEAD/status reais de A e B foram conferidos. Os três relatórios integrais do coordenador, relatórios A/B, spec, AGENTS e skills obrigatórias foram lidos. O executável Orca usado em todos os comandos foi `C:/Users/Usuário/AppData/Local/Programs/orca/resources/bin/orca.exe`.

Composição por conteúdo em arquivos locais não commitados:

- A: `online_v021/ranked/service.js` e `tests/server/ranked_race_s05_test.cjs` das mudanças locais de `codex/fix-ranked-race-s05`, HEAD `dddf4f86e985cc98388fb55ea38380d28e67fe18`.
- B: `online_v021/backend.js`, `online_v021/accounts/auth.js`, `tests/server/session_hardening_test.cjs`, `tests/web/session_socket_e2e.cjs` das mudanças locais de `codex/session-hardening-s02-s04`, HEAD `2e8837b845febfcead613a3d55de52b75b05bceb`.
- S11: `git show a126c107edb1d761486a4ce5959a328c7fa6767e` conferido; teste extraído do objeto Git e hunks de análise reconciliados manualmente com B. Sem escolher uma versão inteira de backend e sem merge/cherry-pick/rebase.

Os 26 testes A, 32 B e harness Chrome B preservam integralmente casos/assertions: comparação normalizada de CRLF/LF e fim do arquivo passou. Nenhuma assertion enfraquecida. O teste S11 mantém todas as assertions, inclusive ambos os jogadores desconectados e estado `starting`; a fixture autentica sockets abertos realmente registrados, usa conexão independente de análise e somente desconecta os jogadores depois do start legítimo. Nenhuma guarda de `startMatch` foi removida. Os 12 SHA256 das fontes originais foram reconferidos e permaneceram iguais, incluindo relatórios do coordenador. Dependências/pastas B não foram copiadas, alteradas ou removidas.

## Causas e soluções

### Prontidão, fila e início de partida

`current` continua significando revisão vigente/conexão/prazo; `ready` acrescenta ausência de autenticação/revalidação pendente e prazo de revalidação não vencido. Isso permite aceitar a resposta Auth da própria revisão sem liberar novas ações durante a espera.

Ranked captura UID, socket, revisão da sessão e intenção mais recente. Depois de stats, aguarda `ensureSession`; o último check de prontidão/revisão/intenção/socket/exclusividade e o enqueue continuam síncronos, sem await entre guarda e mutação. Cancelamento do socket responsável cancela imediatamente a intenção/fila mesmo durante Auth, sem esperar uma autorização nova. Logout/close/troca/ABA não restauram conclusões antigas.

Pairing usa predicado de elegibilidade no Matchmaker. Fila com ligação vigente e autorização temporariamente suspensa fica preservada; o participante não é pareado e o oponente saudável não é consumido. Sessão inválida/fechada/expirada é removida. `startMatch` exige prontidão imediatamente antes de registrar partida/byUser. Uma segunda varredura descarta entradas que perderam validade durante a seleção, preservando o adversário. O contrato síncrono de convite e exclusividade entre Ranked/Casual/Party continua vigente.

### Continuações e delegados

`Backend.operation` captura revisão, UID, perfil e identidade; `wait` recebe thunk e autoriza **antes de chamar** cada nova operação, revalida depois do await e disponibiliza `assert` síncrono para mapas/broadcasts. `accounts/operation.js` mantém compatibilidade dos harnesses sem Backend; o backend de produção fornece sempre a guarda real. BotService recebe o Backend existente, sem serviço paralelo.

Bots, DM, convites e Social usam UID/metadados capturados e guardas em leituras/escritas. Não releem usuário B depois de consultar A. Social protege cada etapa de aceitar/bloquear/remover relações e seus ganchos. DM protege persistência, todos destinatários e unread; listas/unread recomputam os sockets do UID ao emitir para evitar destinatário que mudou de identidade enquanto o store esperava.

ALS agora suprime mensagens de uma operação antiga para **todos** destinatários, durante o handler ativo. O contexto é marcado inativo ao concluir, para timers autoritativos posteriores não herdarem uma proibição permanente. Cleanup de sessão e liberação de reserva usam contexto de sistema, permitindo eventos legítimos de desconexão/falha aos outros participantes. Essas ações de limpeza não são concessões antigas.

Aceite de convite captura sockets e revisões dos dois participantes antes do await. Aguarda prontidão de ambos e revalida ator, reservas, status e participantes no trecho final síncrono. Outra aba da mesma conta não conclui aceite revogado do ator original. Invalidação libera as reservas e marca falha em vez de deixar `starting` preso.

Handlers de conta também usam autorização anterior ao dispatch de novas escritas. Um caso controla explicitamente a invalidação no microtask entre a conclusão de `checked` e a próxima escrita; nenhum write é iniciado. State confere prontidão e revisão final antes de instalar perfil/identidade.

**Limite transacional:** um write iniciado com autorização de A antes da invalidação pode persistir em A; não é magicamente cancelado, revertido nem transferido a B. Testes de bots/DM/Social comprovam persistência da etapa iniciada e ausência de nova escrita/broadcast depois da troca. Operações Social de várias etapas não ganham atomicidade de banco com esta guarda: cancelamento pode deixar etapa anterior aplicada e exigir retry/refresh do estado. Payments permanece protegido e não foi auditado/instrumentado; não se declara fechamento de suas continuações.

### Política de autenticação e renovação

Cada `acct_auth` avança revisão e revoga imediatamente a autorização de operações antigas. Auth explícita usa `force` para ignorar cache, inclusive token repetido, evitando adiar a verificação por sucessivos refreshes. Mensagens/lances de sessão pronta não consultam Auth. Revalidação continua single-flight a cada 60 s, expiração no menor prazo entre exp e 1 h, Auth com timeout de 10 s; revalidação não prorroga exp/teto. Falha/rejeição/UID divergente/timeout/expiração são fail-closed; respostas tardias não restauram a revisão anterior. A janela de revogação entre revalidações continua sendo até 60 s mais espera Auth de até 10 s.

Enquanto o token novo é verificado, user/profile ficam indisponíveis e `ready` é falso. A ligação anterior de presença/fila/partida/Party é retida apenas como continuidade de conexão, sem autorizar ações. Confirmação do mesmo UID instala o token novo, reaproveita o perfil confirmado anterior e mantém a ligação enquanto as leituras de store terminam; não dispara close/reconnect nem novo timer de ausente. Intenções pendentes anteriores são invalidadas, mas fila já confirmada permanece. Perfil novo é publicado somente pelo state da nova revisão.

UID diferente desliga a ligação antiga antes de instalar o novo usuário. Rejeição, exceção Auth, timeout, logout e close limpam a ligação; store lento depois de Auth válida não transforma a conexão em ausente. Testes usam Ranked/Casual/Party reais e verificam `connected`, `leftAt`/`away_since`, fila, mapas e presença. Retenção durante Auth não é rollback de autorização. Sem QA da renovação real em `account_service.gd` ou export Godot; o comportamento do cliente antes/depois de `acct_state` continua gate.

### S11, grants e jobs em voo

O handler composto captura accountId/revisão e nega análise em PvP registrado em Ranked/Casual/Party, inclusive convites, `starting`, jogadores desconectados, Club e Fundador. Checa antes de entitlements, depois de store/Auth adicional, antes de disparar consume e depois de consume/revalidação. Um PvP iniciado por outro socket do UID durante Auth extra também impede grant. Pós-partida e bots locais seguem permitidos. Quota cujo write começou antes do PvP pode ter sido consumida; nenhum grant é emitido depois do início observado. Não há transação quota+match nem refund novo nesta tarefa.

Grant anterior não revoga Worker/processo local. O cliente oficial agora reconsulta o guard da engine depois de startup/espera busy, monitora jobs ativos a cada frame, envia UCI stop/aborta fallback e suprime resultado cancelado/bloqueado. Analyzer cancela em vez de transformar bloqueio em avaliação neutra. O controlador existente dos bots invalida trabalho pendente, aborta fallback e confere o guard antes de apresentar/aplicar e depois dos awaits Stockfish. Perfis/níveis/regras e binários/licenças permanecem iguais.

Essa proteção depende do cliente oficial e da atualização de estado PvP recebida por ele. O gate do servidor sozinho não revoga um Worker de cliente modificado, jobs iniciados por acesso direto fora dessas portas ou informação já entregue antes do início. Stop/abort é cooperativo e não elimina retroativamente computação/resultado já visto. Não foi executado Stockfish real, fallback Godot ou navegador com export do jogo nesta Task; portanto não há declaração de engine ativa nem de bloqueio local completamente validado.

## Reprodução e validação

Windows/PowerShell e Node `v24.19.0`; comunicação local `127.0.0.1`. Sem sleeps na matriz determinística: promises controladas e relógio/timers injetados; Backend, serviços, Matchmaker, MemoryStore, registries e Party são reais. Em suites de fluxo as temporizações existentes não foram alteradas.

Antes das correções adicionais, A+B passou 58/58 e os seis primeiros probes novos falharam 6/6: enqueue durante Auth, pairing durante Auth, bot gravando em B após ler A, DM write/broadcast antigo, convite/mapas/metadados misturados e Social write após troca. Os mesmos probes passam na versão corrigida. Falhas posteriores de desenvolvimento foram diagnosticadas: fixture Social precisou desfazer amizade existente antes de testar aceite; nenhuma assertion foi relaxada. A fixture S11 foi adaptada para o contrato real de A. A revisão do diff GDScript corrigiu uma guarda inicialmente colocada no cleanup, mantendo o stop obrigatório; GDScript não foi executado.

| Comando | Resultado observado |
| --- | --- |
| `node --test --test-reporter=tap tests/server/session_hardening_test.cjs tests/server/ranked_race_s05_test.cjs tests/server/security_reconcile_test.cjs tests/server/analysis_fair_play_test.cjs` | Final 170/170, exit 0: B32 + A26 + novos89 + S11 23 |
| `node tests/server/ranked_unit_test.cjs` | 37 checks, 0 falhas, exit 0 |
| `node tests/server/ranked_flow_test.cjs` | 36 checks, 0 falhas, exit 0 |
| `node tests/server/casual_flow_test.cjs` | 20 checks, 0 falhas, exit 0 |
| `node tests/server/accounts_test.cjs` | 25 checks, 0 falhas, exit 0 |
| `node tests/server/presence_test.cjs` | 30 checks, 0 falhas, exit 0 |
| `node tests/server/bot_progress_test.cjs` | 20 checks, 0 falhas, exit 0 |
| `node tests/server/social_test.cjs` | 38 checks, 0 falhas, exit 0 |
| `node tests/server/invite_test.cjs` | 51 checks, 0 falhas, exit 0 |
| `node tests/server/dm_test.cjs` | 31 checks, 0 falhas, exit 0 |
| `node tests/server/nickname_avatar_test.cjs` | 41 checks, 0 falhas, exit 0 |
| `node tests/server/analysis_payments_test.cjs` | 15 checks, 0 falhas, exit 0; execução local, sem mudanças/auditoria de pagamentos |
| `node tests/server/party_test.cjs` | 24 checks, 0 falhas, exit 0 |
| `node tests/server/party_chat_test.cjs` | 7 checks, 0 falhas, exit 0 |
| `node --test --test-reporter=tap tests/web/session_socket_e2e.cjs` | Chrome headless real 121.0.6167.187; 1 teste/6 cenários, exit 0 |
| `node --check` nos nove módulos JS e cinco testes CJS da entrega | Exit 0 |
| `git diff --check` e validação Node de trailing whitespace em novos arquivos | Exit 0; somente avisos LF/CRLF |
| Diff das áreas protegidas e índice | Vazios |

Os 89 novos casos cobrem stats+swap/ABA/refresh/cancel/logout/close/auth inválida/exp/revalidação válida/rejeitada/timeout; cancel durante Auth; pairing e adversário preservado; guarda final de startMatch; quatro delegados com todas as saídas relevantes, writes em voo, mapas e todos destinatários; refresh mesma conta em fila/Ranked/Casual/Party e invalidação sem rollback; aceite com outra aba; análise em entitlements/consume/Auth e PvP iniciado por outro socket; o microtask anterior a nova escrita; Auth force e ausência de Auth por ação válida. Não há caso vazio/skip para Club+consume, caminho inaplicável porque Club não consome quota.

Chrome usou o harness B original intacto, Backend real e Auth/store locais: login lento A→B, login→logout, token inválido, novo login/refresh/logout e close físico. **Isso não substitui cliente Godot/Auth real nem export Web.** Não houve export/build, QA visual/mobile, serviço Auth remoto, banco aplicado ou SHA LIVE verificado.

Configuração de execução local, sem ler valores anteriores de secrets:

```powershell
$env:NODE_PATH='C:/Users/Usuário/orca/workspaces/project/codex-session-hardening-s02-s04/.session-test-deps/node_modules'
$env:SUPABASE_URL=''
$env:SUPABASE_SERVICE_ROLE_KEY=''
$env:SUPABASE_SECRET_KEY=''
$env:SUPABASE_ANON_KEY=''
$env:FRAIHA_BROWSER_PROFILE='C:/Users/Usuário/orca/workspaces/project/codex-security-reconcile-ab-s11/.security-qa/browser-profile'
```

Nenhuma dependência instalada nesta Task e nenhum manifesto/lockfile alterado. NODE_PATH utiliza as dependências B existentes somente em leitura. O perfil Chrome local gerado nesta worktree permanece em `.security-qa/browser-profile/` (52 arquivos na verificação), sem credenciais reais; é artefato de QA excluído da entrega de código/stage. A pasta `.session-test-deps/` B anteriormente bloqueada por policy permanece intacta; nenhum cleanup foi tentado nela ou contornado.

## S01, S05, S11 e independência

S01 não foi integrado e `online_v021/server.js` não foi editado. O teste `ws_input_test.cjs` de `af54aea` foi compilado em memória com Module e filename/paths da worktree: contra o dispatcher atual falhou no payload null (processo TypeError e timeout, exit 1). Comparação no mesmo ambiente carregando todos os módulos modificados e server originais de HEAD em memória reproduziu o mesmo erro/exit 1: **PRE-EXISTING**, não regressão deste candidato. `git diff --exit-code HEAD -- online_v021/server.js` confirmou dispatcher inalterado.

Em seguida, apenas o `server.js` de S01 foi compilado em memória em subprocesso local, mantendo os módulos deste candidato; o teste S01 passou **48 checks, 0 falhas, exit 0**. Evidência de coexistência, não integração/commit. Os wrappers interceptaram `child_process.spawn` do helper para substituir a entrada server por `node -e`/Module `_compile(git show ...)`; nenhum arquivo de server/teste S01 foi gravado. Isso não resolve S01 na árvore entregue: ainda exige integração separada autorizada.

S05 ganha o contrato real de prontidão de B, sem apagar casos A ou diagnóstico original. S11 e B agora coexistem no mesmo handler/fixture e na matriz multi-socket/Auth. S06 permanece independente e aberto: replay não prova autoria dos lances do bot, e esta Task não implementa chooser/ledger/CAS/recibo durável. S07 permanece independente e aberto: nenhuma regra/RNG/projeção foi alterada. Não houve migration, crédito/reward v2 ou mudança em Marcha/XEQUE.

## Lista exata de arquivos da entrega

| Arquivo | Conteúdo |
| --- | --- |
| `online_v021/backend.js` | B composto com prontidão, contexto/guarda, política de renovação, novas escritas autorizadas e S11 |
| `online_v021/accounts/auth.js` | B, cache limitado por exp/force e informação de expiração |
| `online_v021/accounts/operation.js` | Adaptador de guarda reutilizável para serviços/harnesses |
| `online_v021/ranked/service.js` | A com prontidão/espera, pairing suspenso e preservação do oponente |
| `online_v021/ranked/matchmaker.js` | Predicado opcional de elegibilidade; algoritmo/ritmos mantidos |
| `online_v021/bots/service.js` | UID capturado e autorização anterior a persistência/continuação |
| `online_v021/social/invites.js` | Guardas de envio/aceite, sockets/revisões e liberação de reserva |
| `online_v021/social/dm.js` | Guardas, remetente coerente e destinatários atuais |
| `online_v021/social/service.js` | Guardas em cada etapa de escrita/leitura e broadcasts |
| `analysis/engine.gd` | Guard após espera, monitor de jobs, cancel/stop e supressão de resultado |
| `analysis/analyzer.gd` | Cancelamento propagado ao pipeline em vez de resultado neutro |
| `bot/controller.gd` | Fallback cancelado e guard antes de aplicação/depois de awaits |
| `tests/server/ranked_race_s05_test.cjs` | A26 intactos |
| `tests/server/session_hardening_test.cjs` | B32 intactos |
| `tests/server/analysis_fair_play_test.cjs` | S11 23 com fixture autenticada/registrada e assertions intactas |
| `tests/server/security_reconcile_test.cjs` | 89 testes combinados determinísticos |
| `tests/web/session_socket_e2e.cjs` | Harness Chrome B intacto |
| `tests/analysis_engine_race_test.gd` | Harness de startup/busy/fallback/UCI em voo e controlador; **não executado** |
| `docs/security-reconcile-ab-s11-base.md` | Base, plano anterior e hashes das fontes |
| `docs/security-reconcile-ab-s11-implementation.md` | Este relatório |

Além desses 20 arquivos, o diretório de perfil Chrome acima é gerado/preservado e não deve ser integrado. Nenhum arquivo protegido rastreado/não rastreado foi criado ou modificado pela Task; índice permanece vazio. Não houve teste/script/escrita na principal. Não há baseline da principal nesta Task e não se afirma igualdade byte a byte de trabalho paralelo fora das fontes verificadas.

## Riscos residuais e próximo gate

1. **QA Godot antes de integrar:** o coordenador confirmou indisponibilidade do executável em reply `msg_7ebab92ff3da` e proibiu ampliar inventário/baixar toolchain. Executar `godot --headless --path . -s tests/analysis_engine_race_test.gd` quando houver ferramenta autorizada, mais regressões `tests/analysis_test.gd` e bots; verificar parse, startup/busy, stop UCI, abort fallback, retorno tardio, grant recebido antes de PvP futuro e múltiplas instâncias. O harness simula transportes e não comprova Stockfish/Worker real.
2. Verificar no export Godot/Web real o refresh durante fila/Ranked/Casual/Party, incluindo store lento, logout, expiração, reconexão e troca UID. Validar ausência de engine/resultados no PvP com Worker/WASM/processo/fallback efetivamente executados. Não gerar artefatos protegidos nesta Task.
3. Exclusividade/filas/grants são de um processo. Não há lock distribuído, transação de quota+partida, rollback de escrita iniciada ou reconciliação retroativa de índices corrompidos. Pagamentos protegidos não foram examinados; S06/S07 não estão mitigados por esta entrega.
4. Fail-closed em Auth indisponível pode desconectar usuários após timeout/revalidação. Janela de revogação, custo por socket e compatibilidade no rollout real precisam observação autorizada posterior; nenhum serviço foi operado para isso.

Próximo consumidor: coordenador/reviewer, para revisar o diff e gate residual; nenhuma integração automática. Toda publicação, migration, infraestrutura, commit/push/merge permanece fora desta autorização.
