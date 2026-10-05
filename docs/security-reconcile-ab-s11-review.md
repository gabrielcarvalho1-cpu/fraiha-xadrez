# Wave 2 — revisão independente A+B+S11

Data: 2026-10-05. Run `run_78943810cec2`, Task `task_cc28b5e625f7`, Dispatch `ctx_7addc74b86f8`.

**Veredicto: APROVAR COM AJUSTES.** Não identifiquei finding de código BLOCKER, HIGH, MEDIUM ou LOW no alcance delimitado abaixo. O ajuste pendente é o gate de validação Godot/cliente real; não representa um defeito reproduzido nem autoriza integração/publicação. A revisão server-side é favorável, mas não comprova execução das mudanças GDScript ou bloqueio de todas as engines locais.

## Estado e independência

- Reviewer em `C:/Users/Usuário/orca/workspaces/project/codex-review-security-reconcile-ab-s11`, branch `codex/review-security-reconcile-ab-s11`, HEAD inicial/final `18231c88e844167db94fb50feef6cfaca0e06853`. Árvore inicialmente limpa. Branch automática limpa renomeada após verificar destino inexistente, conforme autorização da Task.
- Implementação somente em leitura em `C:/Users/Usuário/orca/workspaces/project/codex-security-reconcile-ab-s11`, branch `codex/security-reconcile-ab-s11`, mesmo HEAD. O candidato consiste em mudanças locais, incluindo arquivos não rastreados; o HEAD sozinho não contém a implementação.
- Modelo/effort solicitado: GPT-6.1-Sol MEDIUM. Configuração efetiva do launcher não consultada; nenhum aumento de effort nem subworker. Revisão independente do implementador HIGH.
- AGENTS, fraiha-xadrez, fraiha-coordinator, orchestration e guia oficial foram carregados. Usado exclusivamente o executável Orca especificado. Spec Wave 2 e os três relatórios Wave 1 do coordenador foram lidos, assim como mapa, referências architecture/validation, ENGINE/LICENSES e relatórios de base/implementação e A/B.
- Única escrita de conteúdo do reviewer: este relatório. Nenhuma edição na implementação, fonte A/B, dependência B, área protegida, principal, migration, configuração ou artefato Godot. Nenhum commit/push/merge/cherry-pick/rebase/deploy, instalação, secret ou serviço externo.

## Candidato revisado

Diff de todos os 11 arquivos rastreados contra a base autorizada, mais leitura dos nove arquivos novos de entrega: 20 arquivos. Inclui backend/auth, adaptador operation, Ranked/Matchmaker, bots, Social/DM/convites, engine/analyzer/controller, seis arquivos de testes e dois relatórios. `.security-qa/browser-profile/` foi identificado como artefato Chrome e excluído do candidato; seu conteúdo não foi aberto.

Identificação do conteúdo revisado: SHA256 `80abeefc6044c4d3c8051366d9b3791b27c500412f0c79232f8b2f67bf3b8720`, calculado sobre linhas ordenadas `caminho SHA256(bytes do arquivo)` unidas por LF, para os 20 arquivos de entrega. Esse digest inclui documentação e finais de linha; não é SHA de commit.

Comparei também os arquivos locais originais A/B, sem presumir que estavam nos HEADs:

| Fonte | Estado verificado | Evidência de preservação/composição |
| --- | --- | --- |
| A | `codex/fix-ranked-race-s05`, HEAD `dddf4f86e985cc98388fb55ea38380d28e67fe18`, service/test modificados localmente | service original SHA256 `1752E62905C7F30E2ED088673461EE8CC0CC5B32CC08D811CB56D357DF17EF92`; diff adicional de prontidão/espera/pairing revisado; teste A26 idêntico após normalizar CRLF/LF e EOF |
| B | `codex/session-hardening-s02-s04`, HEAD `2e8837b845febfcead613a3d55de52b75b05bceb`, backend/auth modificados e testes novos | backend original SHA256 `713778D76C244BFEC4B0B1C1B23E60462F50301E4351004B2490E81A495CADC9`; auth original `7EC29FE05A6E852B876B25959FF65A00774709D8A9BF8A037BC1ED77FC240858`; B32 e harness Web idênticos sob a mesma normalização |
| S11 | Objeto Git `a126c107edb1d761486a4ce5959a328c7fa6767e` | Hunk backend e teste original conferidos; sequência de todas as linhas `assert.*` do teste idêntica à original; fixture adapta sockets legítimos sem remover assertions |

Os hashes originais acima coincidem com o registro anterior do implementador. Isso sustenta preservação dos arquivos comparados, não igualdade byte a byte de todas as worktrees ou dependências temporárias. Nenhuma principal foi acessada nesta revisão.

## Invariantes avaliadas

| Tema | Evidência e conclusão delimitada |
| --- | --- |
| Sessão antiga/ABA | `backend.js:81,86,105,115,128,168,301`: revisão, UID e metadados capturados; autorização antes do thunk e checagem após await; revisão de state antes de aplicar perfil. Logout/close/auth nova invalidam operações anteriores. ALS suprime respostas/broadcasts de operação ativa revogada para qualquer destinatário, não só socket original. |
| Novas escritas | BotService, DM, Social e handlers de conta usam `op.wait(() => write(...))`; isso evita iniciar escrita depois da invalidação, ao contrário de passar uma Promise já iniciada. Testes observam chamadas de store, mapas e mensagens de todos os destinatários. Writes já iniciados em A podem persistir em A; não são revertidos nem atribuídos a B. |
| Ranked | `ranked/service.js:31,38,67,97,158,179`: current/live separados de ready; stats aguardam validade; última checagem de revisão/intenção/socket/exclusividade e enqueue são síncronos. Pairing suspende participantes pendentes sem consumir adversário saudável, e startMatch verifica prontidão antes de maps/byUser. Cancelamento durante Auth invalida intenção imediatamente. |
| Convite/segunda aba | `social/invites.js:153`: ator e sockets dos dois participantes são capturados antes do await; guards verificam revisão e prontidão novamente; última seção de reservas/ocupação/start é síncrona. Outro socket do mesmo UID não conclui aceite do ator invalidado. Reservas canceladas são liberadas em contexto de sistema. |
| S11 composto | `backend.js:434`: gate antes de entitlements, depois de entitlements e eventual Auth, dentro do thunk antes de consumir quota, depois de consumo/possível Auth e antes de grant. Casual/Ranked/Party, starting/desconectado, free/Club/Fundador e segunda aba são cobertos. Pós-partida/bot local mantêm o contrato testado. Consumo já iniciado antes do PvP pode ocorrer sem grant posterior. |
| Refresh | `backend.js:128,394`: auth nova avança revisão imediatamente e suspende autorização; mesma conta mantém vínculo confirmado de fila/partida/Party, sem close/reconnect desnecessário, inclusive store lento depois de Auth. Troca UID/rejeição/timeout/logout/close limpam vínculo. Operação anterior não volta a ser autorizada. |
| Política Auth | Revalidação single-flight a cada 60 s; exp limitado por token e teto de 1 h; timeout Auth 10 s; force em auth explícita/revalidação. Exp só limita, identidade vem de Auth. Sessão pronta não faz Auth por lance; testes confirmam. Falha do provedor é fail-closed, com janela de revogação declarada. |
| Portas públicas | Backend real encaminha aos serviços instrumentados; matrix usa Backend/Ranked/MemoryStore/registries/Party reais. Chat/ações Party atuais são síncronos; persistência Ranked posterior é resultado autoritativo da partida, não nova autorização do usuário antigo. Payments permanece protegido e fora da revisão de continuações internas. |
| Complexidade/fallback | Guarda central pequena reaproveita Backend e ALS existentes; adapter sem backend.operation mantém harnesses independentes. Produção fornece Backend.operation aos serviços instrumentados. Contexto sem socket/inativo serve efeitos de sistema; timers autoritativos não ficam permanentemente proibidos por uma sessão revogada. Nenhuma nova infraestrutura/dependência/regra. |

## Validação executada pelo reviewer

Windows/PowerShell, Node `v24.19.0`. Somente testes locais de memória; nenhum browser/export/build executado pelo reviewer.

- `node --test --test-reporter=dot tests/server/session_hardening_test.cjs tests/server/ranked_race_s05_test.cjs tests/server/security_reconcile_test.cjs tests/server/analysis_fair_play_test.cjs`: 170 testes sem falha na saída. Confirmei com reporter TAP e captura explícita de exit: **170 PASS, 0 FAIL, 0 cancelados, 0 skipped, exit 0** (B32+A26+novos89+S11 23).
- Comparação Node das fontes locais: A26, B32 e Web B idênticos; assertions S11 idênticas. O primeiro comando de comparação falhou antes de ler arquivos por conversão de `Usuário` em `Usu?rio` no pipe PowerShell; repetição com caminhos relativos resolveu, sem mutação. Não foi falha do candidato.
- `git diff --check`: exit 0, somente avisos LF/CRLF. Verificação própria de trailing whitespace nos nove arquivos novos: lista vazia.
- `node --check` em backend, operation, Ranked e invites: sem erro. Demais módulos foram examinados e exercitados pelo conjunto acima; syntax/lint adicional do implementador é atribuído abaixo.
- Git branch/HEAD/status/diff/numstat e comparações `--no-index` locais A/B; `git show` S11; hashes de fontes e digest do candidato. `git diff --no-index` retorna 1 por diferenças esperadas, não por falha de teste.

Não houve falha de teste nova nesta revisão que exigisse classificação base versus regressão. Testes não foram alterados para produzir verde. Os awaits são controlados por Promises/relógio; flushes de microtasks não foram aumentados pelo reviewer e não são sleeps adicionados para esconder race.

**Resultados atribuídos ao implementador, não executados pelo reviewer:** seis probes iniciais 6/6 falhando antes dos ajustes e verdes depois; regressões Ranked unit37/flow36, Casual20, contas25, presença30, bots20, Social38, convites51, DM31, nickname41, analysis15, Party24/chat7; Chrome WS real 1 teste/seis cenários; syntax geral. A revisão não chama esses resultados de QA Godot nem Auth real.

## Gate pendente e riscos residuais

Não há finding de código reproduzido a encaminhar como BLOCKER/HIGH. As limitações seguintes são gates de evidência, não afirmações de exploração:

1. **QA Godot/engines obrigatório antes da integração do candidato completo.** `analysis/engine.gd:49,218,265,314,357`, `analysis/analyzer.gd:125,137`, `bot/controller.gd:188,273` foram revisados estaticamente: checks depois de startup/busy/await, monitor por frame, stop/abort e supressão de resultado parecem coerentes. Executável Godot não disponível segundo o coordenador/implementador; não busquei toolchain nem gerei imports. Executar o harness novo `tests/analysis_engine_race_test.gd`, regressões analysis/bots e fluxo real Web/desktop quando autorizados. O harness simula transportes e não prova Worker/WASM/Stockfish/fallback real.
2. **Refresh no cliente oficial:** testar fila, Ranked, Casual e Party durante Auth/store lento, expiração, logout, troca UID e reconexão no Godot/export. Os testes server-side demonstram continuidade dos mapas/connected, mas não o tratamento visual/de estado de `acct_state` pelo cliente.
3. **Grant anterior/job em voo:** servidor não revoga grant já entregue nem Worker modificado. Cliente oficial depende de receber estado PvP e consultar o guard; stop é cooperativo e informação já entregue não desaparece. Nenhuma engine ativa foi afirmada. Quota iniciada pode ser consumida; não há transação quota+match/refund.
4. **Persistência:** guards não tornam Social multi-etapas atômico. Cancelamento pode deixar etapa já autorizada aplicada; recuperação exige retry/refresh. Exclusividade e filas são de um processo; sem lock distribuído, rollback ou reparação retroativa de índices.
5. **Escopo protegido/serviços:** payments interno não auditado; nenhuma prova de schema aplicado, Supabase compartilhado, LIVE, staging, produção ou engine/binário publicado. Perfil `.security-qa/` e temporários B ficam preservados e fora de stage/commit.

Menor próximo passo: manter o diff local preservado, realizar o QA autorizado acima e retornar somente com falhas/evidência desses fluxos. Não recomendo refatoração adicional sem defeito observado; não há correção MEDIUM a implementar por inferência nesta revisão.

## Impactos e conclusão

S05 conserva os 26 casos/assertions e recebe o contrato de prontidão real que faltava na integração A+B. S11 conserva as assertions e o bloqueio server-side em composição com revisão/UID, incluindo await extra de Auth. Não restou conflito textual/semântico identificado entre A+B+S11 no candidato examinado; cobertura delimitada não garante ausência global de bugs.

S01 `af54aeaed1766c4d30953a5ce92275bd92d1741c` permanece independente e não integrado: `server.js` inalterado. O implementador atribui falha preexistente de payload null tanto à base quanto ao candidato e 48 checks verdes com S01 compilado só em memória; não repeti nem trato isso como S01 mitigado na árvore entregue.

S06 continua design, sem chooser/ledger/CAS/recibo durável de produção. S07 `0dc2e581a4fe526ad914895dc97057dceeed4d8d` continua documental, sem mitigação RNG/projeção; nenhuma regra protegida foi alterada. Esta aprovação não fecha S06/S07.

**TECHNICAL OUTCOME:** revisão independente concluída, evidência server-side favorável, **APROVAR COM AJUSTES** por QA Godot/cliente real pendente. Aprovação técnica não autoriza commit/integrar/publicar. **ORCHESTRATION OUTCOME:** reportável como `succeeded` pela conclusão da revisão; settlement ocorre somente pelo worker_done próprio após checagem final da inbox, e não pela existência deste documento. Nenhum checkpoint de outro worker foi convertido em sucesso formal.
