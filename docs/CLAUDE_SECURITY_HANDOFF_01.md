# PRONTO PARA HANDOFF AO CLAUDE

Pronto para revisão humana do pacote local; **integração do cliente e publicação continuam condicionadas à QA manual Godot/export real**. O critério final segue a orientação de encerramento transmitida pelo coordenador em `msg_5169363d81e9`: indisponibilidade rápida de QA real vira gate manual explícito, sem ampliar investigação. Não significa aprovação de release, fechamento global de vulnerabilidades ou autorização de integração automática.

## Autoridade e estados

- Wave 2 Run `run_78943810cec2`, Task `task_b39b65c63ac7`, Dispatch `ctx_488217b765d9`, terminal `term_98fbfba4-d9a3-4bb8-8775-8da8ed6d80e1`. Um worker, zero subworkers/novas Waves.
- GPT-6.1-Sol MEDIUM solicitado e efetivo; `worker-show` confirmou `launch.effective.model=gpt-6.1-sol`, `effort=medium`.
- Worktree desta entrega: `C:/Users/Usuário/orca/workspaces/project/codex-final-compat-qa-gate`, branch `codex/final-compat-qa-gate`, HEAD inicial/final `63ed9405cd028d1db8d2d20e8397b88931848482`. Branch automática nova/pristine renomeada após confirmar destino ausente, mesmo HEAD, antes de escrita.
- Base atual: `dev/web-alpha` e `origin/dev/web-alpha` em `63ed9405cd028d1db8d2d20e8397b88931848482`; fetch anterior do coordenador, nenhuma rede externa nesta Task.
- Fonte preservada: `C:/Users/Usuário/orca/workspaces/project/codex-security-reconcile-ab-s11`, branch `codex/security-reconcile-ab-s11`, HEAD `18231c88e844167db94fb50feef6cfaca0e06853`, candidato de **20 arquivos locais sem commit**. Os 20 hashes da fonte foram reconferidos após validação e coincidem com a cópia.
- **Technical outcome:** compatibilidade local delimitada concluída, sem conflito identificado nas áreas selecionadas; handoff pronto com QA manual pendente. **Formal outcome:** este relatório não liquida o Dispatch; `worker_done succeeded` próprio conclui a tarefa documental/gate, sem certificar a QA não executada. Wave 2 implementação/review já succeeded/released; Wave 1 D failed/abandoned/user_owned retained permanece intocado.

## Compatibilidade e composição exata

Comparei o delta Git entre a base do candidato `18231c88` e `63ed940`: 19 caminhos, majoritariamente pagamentos/testes/documentação e retirada de instruções locais da árvore corrente. AGENTS e fraiha-xadrez foram lidos na worktree de setup indicada pelo usuário. Nenhum dos 20 caminhos entregues tem delta de base; por isso a composição mínima foi **COPY de conteúdo dos 20 arquivos selecionados**, sem patch adicional de código. Não copiei diretórios, dependências, perfis de browser nem arquivos sujos da principal. Nenhum merge/cherry-pick/rebase/pull/reset/clean/restore.

O único delta compartilhado relevante é `online_v021/accounts/store.js:getPayment`: seleção PostgREST acrescenta `method`; assinatura `(provider, ref)`, retorno primeira linha/null e demais campos permanecem iguais. Mantive o store atual inteiro; os serviços compostos não dependem de remover esse campo. A validação de contas com backend/auth do candidato e store atual passou. O probe do método real confirma seleção/escaping/retorno, com `req` substituído e rede proibida; não valida pagamentos reais nem schema remoto. Áreas de payments/monetization não foram editadas nem auditadas.

Conflitos textuais nas 20 entregas: nenhum. Adaptações de código novas: nenhuma. `online_v021/server.js` e `accounts/store.js` permanecem byte a byte da base desta worktree (`git diff --exit-code HEAD -- ...`, exit 0).

**S01 independente:** `af54aeaed1766c4d30953a5ce92275bd92d1741c` não é ancestral da base atual (exit 1), e o dispatcher atual ainda não contém a guarda `m===null || typeof m!=='object' || Array.isArray(m) || typeof m.type!=='string'` antes de `handle`. A ausência foi confirmada por conteúdo, não só ancestralidade. Portanto S01 continua dependência separada para fechar o hardening de entrada WS; o pacote A+B+S11 não a resolve. Nenhuma reescrita de server.js ou integração S01 nesta Task. Evidência herdada: payload null falha igualmente na base/candidato antigos e S01 em memória coexistiu com o candidato em 48 checks; isso não prova execução S01 no HEAD atual. S06 design e S07 hipótese/documentação ficam excluídos de fixes e não foram reinvestigados.

## Evidência executada agora versus herdada

Windows/PowerShell, Node `v24.19.0`, somente ambiente isolado/local. Dependência `ws` existente em B utilizada por `NODE_PATH=C:/Users/Usuário/orca/workspaces/project/codex-session-hardening-s02-s04/.session-test-deps/node_modules`, leitura apenas; nenhuma instalação/upgrade. SUPABASE_URL/SERVICE_ROLE_KEY/ANON_KEY vazios no processo de teste, auth dev local; doubles HTTP/Auth do teste não acessam serviços externos.

| Verificação nova | Resultado e bytes alcançados |
| --- | --- |
| `node tests/server/accounts_test.cjs` | **25 checks, 0 falhas, exit 0**; server/backend/auth/serviços carregados desta cópia sobre store atual; log `.final-qa/accounts.log`. Primeira tentativa sem NODE_PATH abortou por `MODULE_NOT_FOUND: ws`, ambiental; corrigida usando dependência existente, sem alterar teste. |
| `node .final-qa/store-contract.cjs` | **3 assertions PASS, exit 0**; método SupabaseStore atual, seleção incluindo method, escaping e retorno null. Probe inicial inline não executou por quoting PowerShell; script persistido corrigiu o comando, sem ajuste no código candidato. |
| `git diff --check` | Exit 0; apenas avisos LF/CRLF. Não certifica parser GDScript. |
| Sobreposição de bases/hashes/diff | Zero delta nos 20 caminhos selecionados; COPY exato e SHA256 confirmado antes/depois. Digest do candidato idêntico ao reviewer/coordenador. |
| Principal Git somente leitura | Início/fim HEAD63ed940, branch dev/web-alpha, status final 362 entradas, delta vazio contra baseline fresco; índice do worker vazio. |

Bytes adicionais efetivamente testados: store atual SHA256 `f7d34d869b83f4fdeaa40dc47eda21571b0bf882d6530bb5da075df74f012631`; dispatcher atual `c19b7ded6a34d7c2e2356681e7823d17635b6d806e597f27ec04d891367c9f8b`. A suite de contas exercita apenas seus fluxos, não toda a lógica desses arquivos. Os hashes das 20 entregas abaixo identificam a cópia completa; **GDScript, race harness e export desta cópia não foram executados**.

Herdado, sem repetição ampla nesta Task: 170 targeted verdes (implementador e reviewer), 375 checks próximos verdes (implementador), seis cenários Chrome/WS verdes (implementador), review independente zero findings no alcance delimitado e S01 48 checks somente em memória. As entregas copiadas têm exatamente os bytes revisados; esses números não são QA do Godot atual nem resultados novos deste worker. Relatórios lidos: coordenador `docs/security-hardening-wave-2-final-2026-10-05.md`, `docs/security-hardening-wave-1-final-2026-10-05.md`; candidato `docs/security-reconcile-ab-s11-implementation.md`; reviewer `docs/security-reconcile-ab-s11-review.md`, nos respectivos worktrees preservados.

## Gate manual obrigatório para integração completa

Inventário curto: `godot`/`godot4` ausentes do PATH (`where godot` não encontrou); nenhum executável foi localizado nas consultas limitadas de Downloads/Program Files/Tools/Godot. Há cache Godot e nome de template `4.7.2.stable` em AppData, que **não provam executável disponível**. Chrome existe em `C:/Program Files/Google/Chrome/Application/chrome.exe`; arquivos Stockfish JS/WASM existem no repo. Não há export Godot atual identificado nesta worktree, nem engine real executada nesta Task. Não houve download/upgrade, browser iniciado, acesso a perfil/secrets ou import/export. ENGINE.md e LICENSES.md lidos. A indisponibilidade é limitada ao inventário curto, não afirma ausência global na máquina.

Claude deve executar em ambiente local isolado autorizado, preservando todos os artefatos/proteções:

1. `godot --headless --path . -s tests/analysis_engine_race_test.gd`, depois `tests/analysis_test.gd` e testes bots pertinentes: parser, PvP surgindo durante startup/busy, cancelamento de fallback, stop UCI e supressão de callback tardio. O harness simula transportes; verde nele ainda exige teste real.
2. Export/cliente oficial real: refresh e store lento enquanto em fila, Ranked, Casual e Party; expiração/revalidação, rejeição/timeout, logout, troca UID, reconnect/F5 e outra aba. Confirmar estado do cliente, `connected`/ausência e mapas server-side, sem depender só de mock WS.
3. Engines reais Stockfish/Worker/WASM e fallback: sequência UCI `uciok → readyok → busca → bestmove` fora de PvP, identificando ANALYSIS ENGINE/BOT ENGINE. Iniciar PvP durante startup/busy/job já em voo e com grant anterior; exigir stop/abort e nenhum resultado/aplicação posterior. Repetir nas portas análise e bot, múltiplas instâncias e modos PvP pertinentes. Registrar hashes de build servida; export bem-sucedido sozinho não fecha o gate.

Riscos residuais herdados: write autorizado já iniciado pode persistir em A; Social não transacional; quota pode consumir sem grant após início PvP; grant/Worker modificado não revogado retroativamente; bloqueio cliente depende de estado PvP recebido; exclusividade por processo; revogação Auth até 60s mais espera de 10s, fail-closed em indisponibilidade. Esses limites não foram ampliados/mitigados nesta Task. Não há prova LIVE, schema, engine distribuída ou QA externa.

## Caminho e ordem exata para Claude

1. Abrir este relatório em `C:/Users/Usuário/orca/workspaces/project/codex-final-compat-qa-gate/docs/CLAUDE_SECURITY_HANDOFF_01.md`, conferir hashes abaixo e preservar as fontes antigas. Revisar primeiro `online_v021/backend.js`, `accounts/auth.js`, `accounts/operation.js`; depois `ranked/service.js`, `ranked/matchmaker.js`; depois `bots/service.js`, `social/invites.js`, `social/dm.js`, `social/service.js`; depois `analysis/engine.gd`, `analysis/analyzer.gd`, `bot/controller.gd`; por fim os seis testes e os dois relatórios de proveniência.
2. Reconfirmar Git da principal/base antes de qualquer futura integração. Se a base divergir de 63ed940, reavaliar o delta; não substituir store atual, pagamentos ou mudanças locais por versões antigas. Este worker não autoriza escrita na principal.
3. Revisar S01 separadamente no objeto Git `af54aea...` e seu teste `tests/server/ws_input_test.cjs`; se autorizada sua integração, compor somente sua guarda mínima e teste no dispatcher atual, mantendo demais mudanças, e executar o teste no candidato final. Não usar merge/cherry-pick amplo nem chamar S01 já integrado.
4. Validar os gates manuais acima antes de integrar o pacote completo. Após autorização humana, aplicar explicitamente os 18 arquivos de código/testes desta lista e arquivar os dois relatórios como proveniência. Conteúdo fonte exato está nesta worktree; os 20 arquivos também permanecem intactos na worktree candidato original. Não copiar `.security-qa/`, `.session-test-deps/`, `.final-qa/` para entrega de produto; esta última é somente evidência local.
5. Commits locais **recomendados, não executados**: S01 separado (`fix(security): validate websocket input before dispatch`); A+B+S11 combinado após QA (`fix(security): reconcile session readiness and PvP engine guards`), preservando o contrato atual do store; documentação/handoff em commit próprio se desejado. Não dividir o backend composto em commits parciais que reinstalem conflito B/S11. Nenhum commit/stage/push/deploy/migration/infra autorizado por este relatório.

Principal preservada por Git observado, não por snapshot completo de conteúdo: `C:/Users/Usuário/Documents/Codex/2026-09-20/referenced-chatgpt-conversation-this-is-an/work/v024/project`, dirty pré-existente preservado. Evidência final em `docs/final-compat-principal-verification-2026-10-05.json`; nenhuma execução/teste/escrita ali. Não houve artefato Godot gerado deliberadamente ou alteração de arquivos protegidos. Encerrar para revisão humana, sem Wave 3.

## Manifesto exato de conteúdo

SHA256 do conjunto dos 20 arquivos, linhas ordenadas `caminho SHA256` unidas por LF: `80abeefc6044c4d3c8051366d9b3791b27c500412f0c79232f8b2f67bf3b8720`. Manifesto também em `docs/final-compat-delivery-hashes-2026-10-05.json`; documentos auxiliares deste gate e `.final-qa/` não entram nesse digest herdado.

| Caminho relativo na worktree desta entrega | SHA256 dos bytes |
| --- | --- |
| analysis/analyzer.gd | 8b24bdf98beb3cef0fbb2f5cd6d514f7612f4ac49a3c7fc709c6b80615d5f0d1 |
| analysis/engine.gd | 24c865a4dd738f662980c47e8224f745216aec3ee9e8cdd892507ac2e073120a |
| bot/controller.gd | 0c252d1320d413d0694d7d7ce5dd5f3e6edd603f5b417ed2caf1fa4749d67ae7 |
| docs/security-reconcile-ab-s11-base.md | e78c425627b17f13dab6550c9d305e45a6741d75a92471524eec9b02fcfad414 |
| docs/security-reconcile-ab-s11-implementation.md | ef445a9f84a0aa8a0ff789a1ce3babde088f68e5531a36cd7dda6364bc2dd3e1 |
| online_v021/accounts/auth.js | bef113086cedf7039d2214dd2d9940277a31d879e0011b4a33492b5dc6149c82 |
| online_v021/accounts/operation.js | d2ea1a6e15f337a41b104eca90eb1eb5063a72c3fec2369d7289a47b61b1a459 |
| online_v021/backend.js | a74e1632afc2e741752c8609dde7dd3459fa9e1d0e411f14e56d6cc50201b853 |
| online_v021/bots/service.js | 78bde83a4fd88ce26cce4314ca4be38947d352db69602e589def2cec72a89121 |
| online_v021/ranked/matchmaker.js | 30895699479bdad5a860c3968be0ead56713618c0c9136a4cdc5d41cf61f4275 |
| online_v021/ranked/service.js | 3d930498a57d18e3c7fb9f639d5e7ef7bbb372134a50b3c44ccc48a395986a47 |
| online_v021/social/dm.js | 5d5a89363aeec5c0fbf307d29eeeb993baaa7337c24f8c3096a54692c06192cd |
| online_v021/social/invites.js | dab184ada0405d45dbb14933c7fa02eb1109b03f9974224fd57520a28df56ab3 |
| online_v021/social/service.js | 350a82cd8386caa4022f0301c00656fe779ba8d0b4e8475fff26f540b6359c93 |
| tests/analysis_engine_race_test.gd | 93f8f66fa9879983762119b1b83f296067c592504ae82036a576efe5dbc48b35 |
| tests/server/analysis_fair_play_test.cjs | 3502ed57de79fe0da9312ac91d27f2a1ae3bfea83d2fbd2887d060a6c545613d |
| tests/server/ranked_race_s05_test.cjs | ca74915e9bc8dad96c1fe0404eae56ea6a55c2d4bd85c2626bf9f82a93b95a11 |
| tests/server/security_reconcile_test.cjs | 2dc0f5bab288370e9c870727824d46bc7b2d30f0f2c46611aa751bcc6f0fe19f |
| tests/server/session_hardening_test.cjs | 0a9a4c47eef143463c59707d277e9b59070e93b41083bebcebeb7a3c94b46c0a |
| tests/web/session_socket_e2e.cjs | fc4c533d81589b783f6fe5c0f6eff351f076795263a6e683dc9be84e843c004c |

## Empacotamento local autorizado — commits para revisão

Missão posterior de empacotamento: somente commits locais, nenhum worker/Task/Wave adicional, nenhuma alteração técnica ou teste amplo novo.

- Base esperada para futura composição: `dev/web-alpha` em `63ed9405cd028d1db8d2d20e8397b88931848482`.
- S01 existente, preservado: branch `codex/fix-ws-input-s01`, SHA `af54aeaed1766c4d30953a5ce92275bd92d1741c`; arquivos `online_v021/server.js` e `tests/server/ws_input_test.cjs`; objetivo validar entrada WebSocket antes do dispatcher. Evidência de testes anterior descrita acima, não reexecutada neste empacotamento.
- A+B+S11: branch `codex/security-reconcile-ab-s11`, SHA `2d8f4b81b9f7d8da830626da8b958ecd1cfbf00f`, mensagem `fix(security): reconcile session ranked and pvp guards`; somente os 18 arquivos de código/testes do manifesto. Os dois relatórios do manifesto ficam no commit de documentação. Os 20 hashes do working tree foram conferidos antes do commit, sem divergências.
- Documentação: mesma branch; commit `docs(security): prepare Claude integration handoff`, identificável por `git log -1 --format=%H codex/security-reconcile-ab-s11 -- docs/CLAUDE_SECURITY_HANDOFF_01.md`. O SHA exato será entregue no fechamento; um documento não pode incluir o SHA do próprio commit como valor literal autorreferente.
- Seis documentos úteis: este handoff/compatibilidade; manifesto; relatório final Wave 2; relatório de implementação; relatório de base/proveniência; revisão independente. Sem checkpoints redundantes, logs, perfis Chrome ou dependências temporárias no commit.

**Atenção à ancestralidade:** o commit A+B+S11 foi criado na branch candidata original, cujo pai é `18231c88e844167db94fb50feef6cfaca0e06853`. A composição validada sobre `63ed940` permanece na worktree `codex/final-compat-qa-gate`. Não mesclar a história inteira da candidata nem usar seu HEAD como substituto da principal: revisar o diff dos 18 arquivos do commit e compor explicitamente sobre a base atual, preservando `accounts/store.js`, pagamentos e trabalho paralelo. Conversão Git LF/CRLF é normalização de armazenamento; implementação não editada.

Ordem recomendada, sem autorização automática: ler documentação e revisar S01; revisar A+B+S11 como unidade; reconfirmar base; compor em ambiente isolado autorizado; validar S01 no candidato final e executar os gates manuais Godot/Web/engines já descritos; somente após aprovação humana integrar/publicar por procedimento autorizado. S06 é design e S07 é relatório/hipótese: **não integrar como fix**. Nenhum push, merge, deploy, migration ou mudança de área protegida neste empacotamento.
