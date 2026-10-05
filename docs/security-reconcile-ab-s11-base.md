# Wave 2 A+B+S11 — base e plano anterior à implementação

Task task_f1405057b7ca; Dispatch ctx_9492646dce73; Run run_78943810cec2.
Worktree exclusiva C:/Users/Usuário/orca/workspaces/project/codex-security-reconcile-ab-s11.
HEAD autorizado 18231c88e844167db94fb50feef6cfaca0e06853; árvore inicial limpa e índice vazio.
Branch automática nova gabrielcarvalho1-cpu/codex-security-reconcile-ab-s11 renomeada para codex/security-reconcile-ab-s11 após verificar destino inexistente. Mesma Task/processo/Dispatch, sem nova criação.
Modelo/effort solicitado GPT-6.1-Sol HIGH por autenticação, concorrência e fair play; configuração efetiva não consultada por este worker.

## Fontes verificadas

A: C:/Users/Usuário/orca/workspaces/project/codex-fix-ranked-race-s05, branch codex/fix-ranked-race-s05, HEAD dddf4f86e985cc98388fb55ea38380d28e67fe18, mudanças locais verificadas.
B: C:/Users/Usuário/orca/workspaces/project/codex-session-hardening-s02-s04, branch codex/session-hardening-s02-s04, HEAD 2e8837b845febfcead613a3d55de52b75b05bceb, mudanças locais verificadas.
Coordenador: C:/Users/Usuário/Documents/Codex/orca-worktrees/codex-setup-rules. Os três relatórios completos e a spec foram lidos; AGENTS, fraiha-xadrez, fraiha-coordinator, orchestration e guia oficial do executável solicitado foram carregados.
S11: git show a126c107edb1d761486a4ce5959a328c7fa6767e confirma backend.js e tests/server/analysis_fair_play_test.cjs; teste extraído do objeto Git, hunks backend reconciliados manualmente.

SHA256 dos arquivos originais (somente leitura):

| Origem | Arquivo | SHA256 |
| --- | --- | --- |
| A | online_v021/ranked/service.js | 1752E62905C7F30E2ED088673461EE8CC0CC5B32CC08D811CB56D357DF17EF92 |
| A | tests/server/ranked_race_s05_test.cjs | 3D59CBD276472B94C745015F1E53C042804DB3651A5682D3BD58859FB85D350E |
| A | docs/correcao-ranked-race-s05-2026-10-05.md | 202E5D1B6BA6035B775020E17ED11F5A0A6701C64DE526A4C9797914583ED157 |
| B | online_v021/backend.js | 713778D76C244BFEC4B0B1C1B23E60462F50301E4351004B2490E81A495CADC9 |
| B | online_v021/accounts/auth.js | 7EC29FE05A6E852B876B25959FF65A00774709D8A9BF8A037BC1ED77FC240858 |
| B | tests/server/session_hardening_test.cjs | 0A9A4C47EEF143463C59707D277E9B59070E93B41083BEBCEBEB7A3C94B46C0A |
| B | tests/web/session_socket_e2e.cjs | FC4C533D81589B783F6FE5C0F6EFF351F076795263A6E683DC9BE84E843C004C |
| B | docs/session-hardening-s02-s04-2026-10-05.md | 8F322160C9CBB2F1D59627AD6F19CE7BEE7AF27D1C5D094E5A533050FE9562E3 |
| Coordinator | docs/security-hardening-wave-1-final-2026-10-05.md | 5A3695F2BBB687DE1BDF2A63DF67C99D4F27AED3A743A74B0650EBBAB4A8E745 |
| Coordinator | docs/security-integration-review-checkpoint-2026-10-05.md | 9C3DB49C8F0D6E2CCE0AB6FE335BB6DA3FFCB8B25B8C00316A700A703C6542A9 |
| Coordinator | docs/security-integration-review-final-2026-10-05.md | 16247A1E672DD6D9EDA2BC73249710B54B3DD5D849EA946523F641DCCCEEA474 |
| Coordinator | docs/security-wave-2-task-1-spec.md | DAA9040921CCCF5880F3C9DDA1752C54D3AB342CB0BC5F74DA5EA22CEBF5A979 |

## Plano exato

Conteúdos S11 conferidos no objeto Git: tests/server/analysis_fair_play_test.cjs SHA256 a71b229e632f15a17ad0c698c9c433992b809ffac800bb5edb2f74cd49bd0b76; online_v021/backend.js SHA256 617211eeced65647949060dad752da5e86c5de9b1c068f95a913298d16b838aa. Estes hashes foram calculados também no fechamento; nenhum commit S11 foi aplicado.

1. Compor A service/test e B backend/auth/testes por conteúdo original, preservando integralmente os 26/32 casos/assertions; extrair teste S11. Nenhum merge/cherry-pick/commit. Reproduzir deterministicamente enqueue com Auth pendente e continuações de bots/DM/convites/social antes da correção.
2. Separar revisão vigente de prontidão autorizada no Backend. Ranked aguarda validade após stats e valida intenção, socket, revisão, prontidão e exclusividade sincronicamente antes de enqueue. Pairing ignora participantes suspensos sem removê-los, startMatch exige prontidão final.
3. Introduzir guarda central reutilizável com UID/perfil/identidade capturados e autorização imediatamente antes de novas escritas; após awaits, cancelar operações antigas inclusive broadcasts para terceiros. Instrumentar bots, convites, DM e social; validar participantes reais no aceite e liberar reservas canceladas. Escritas já iniciadas não são revertidas.
4. Renovação avança revisão imediatamente e suspende autorização durante Auth; preserva ligação de fila/partida/Party enquanto resolve identidade, com timeout fail-closed. Confirmação da mesma conta preserva continuidade durante store; UID distinto, rejeição, expiração, logout/close desconectam. Operações antigas nunca são retomadas, Auth não é consultado por lance.
5. Compor S11 com checagens de PvP e revisão antes/depois de todos awaits, inclusive Auth. Atualizar fixture para sockets abertos autenticados/registrados e desconectar somente após start legítimo; preservar assertions.
6. Revisar grants anteriores e buscas em voo na porta local existente de engine; interromper/suprimir resultados quando fair play passa a bloquear. Sem engines binárias novas nem regras/produto; documentar limites de cliente modificado, Worker e quota consumida em voo.
7. Rodar testes combinados reais Backend/Ranked, cancel/logout/close/ABA, revalidação válida/rejeitada/timeout/exp e oponente preservado; delegados observando store/mapas/todos destinatários; análise/refresh/Party. Rodar regressões próximas e WS Chrome local se dependências disponíveis. Comparar falhas à base em memória ou ambiente local idêntico; syntax/whitespace incluindo novos arquivos e verificação de áreas protegidas.
8. Entregar docs/security-reconcile-ab-s11-implementation.md com evidência base/final, fontes preservadas, arquivos/comandos/resultados, limites Godot/Auth/engines/múltiplos processos e independência S06/S07. Consultar inbox e emitir worker_done próprio exatamente uma vez.

Sem acesso à principal, secrets ou serviços externos. Escrita apenas nesta worktree; nenhum manifesto/lockfile, área protegida, regra de xadrez, migration, artefato Godot, commit, push ou deploy. Dependências B e demais fontes ficam preservadas.
