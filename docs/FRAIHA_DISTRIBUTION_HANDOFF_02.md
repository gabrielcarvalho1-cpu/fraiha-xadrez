# FRAIHA DISTRIBUTION HANDOFF 02 — v1.1 LOCAL DEV

2026-10-06 UTC. Task `task_668c43643cc4`, Dispatch `ctx_366cb45bf2c1`, worker `term_791ad95b-bb3e-4f3c-8214-3e4577934df1`, coordinator `term_74e2e1a0-86c9-4c08-acfa-aaba74b1ffbe`. Um worker, nenhum subworker/nova Wave. Lidos integralmente handoff01, AGENTS e fraiha-xadrez/fraiha-coordinator do setup, orchestration e guia oficial versionado Orca. Autorizações desta rodada prevaleceram sobre a etapa histórica somente mapeamento.

## Git, ownership e selfSHA

Escrita exclusiva em `C:/Users/Usuário/orca/workspaces/project/codex-distribution-v1`, branch `codex/distribution-v1`, somente distribution e docs da tarefa. HEAD inicial `049a61482a7130b61181db6cedca582c0aa4cc60`; implementação anterior `1b8eec722105c43ed8485af4d0196abcd2dd0895`; base `a5fc1cf479138a23905ba1ff84d298b1be92b3de`. Merge-base com mainline `bf1ec5db7cbd003cf254c4e2a9d687c70bc5520e` permanece a base indicada. Sem reset/recriação/cópia dirty core.

1. `000b836904c82cf98fa5ea694ae81125e5e4187a`, `feat(distribution): validate complete historical Windows exports offline`, depende de `049a614...`. Arquivos: `distribution/README.md`, `build.ps1`, `prepare-real-exports.ps1`, `schemas/manifest.schema.json`, `src/Contracts.cs`, `src/Launcher.cs`, `src/LauncherFlow.cs`, `src/Tool.cs`, `src/Updater.cs`, `tests/Tests.cs`, `tests/RealTests.cs`.
2. Commit de documentação que introduz este documento, depende do commit1. **HEAD final/selfSHA**: resolver `git log -1 --format=%H -- docs/FRAIHA_DISTRIBUTION_HANDOFF_02.md`; comparar com `git rev-parse HEAD`. SHA final comunicado em worker_done; não embutir circularmente o próprio SHA. Arquivos: handoff02, QA atualizada, export inventory02, installer review02 e main Git check02.

Stage explícito, `.local` não staged, nenhum config/UID/import alterado. Sem push/merge/rebase/deploy, compras, instalação de software ou operações de serviços. Áreas protegidas/core/Voice/backend/auth/session/matchmaking/modos/Home/assets/monetization/payments/Supabase/configs preservadas pelo escopo de escrita. Estado principal verificado **somente no nível Git**, não igualdade de conteúdo.

## Outcomes e rigor

**TECHNICAL OUTCOME:** P0 DEV completo e validado com FRAIHA real histórico V029/V030, incluindo launcher normal, atualização e rollback. P1 preparado com revisão estática; runtime uninstall/installer bloqueado por dependências e guard pendente. Produção/current-mainline release continuam bloqueados, não confundir com êxito DEV.

**ORCHESTRATION OUTCOME:** valor `succeeded` previsto para worker_done ao concluir a entrega autorizada DEV/readiness; confirmação formal pertence ao receipt/settlement Orca do coordenador, não é fabricada antecipadamente neste documento. **APROVAR COM AJUSTES** para revisão/integração futura; commits locais desta rodada já foram autorizados, integração não foi.

MEDIUM solicitado. Coordenador informou observação TUI `GPT-6.1-Sol medium` antes do despacho; `launch.effective` null, sem comprovação independente do runtime/model/effort por este worker. Quota comunicada caiu de ~50% para ~19% ao fechamento; percentual atual não verificável aqui. Não houve elevação de effort ou novo worker; priorizamos P0 e fechamento.

## Busca de exports, composição e proveniência

Busca inicial `rg --files --hidden --no-ignore` na principal, incluindo ignorados, encontrou zero EXE/DLL, três PCK Web e 13 ZIPs; leitura somente de metadados de ZIP revelou apenas um `index.pck` Web. Isso **não** provava ausência global. Coordenador autorizou ampliar busca somente nomes em Documents/Codex, Downloads/Desktop e nomes de Godot/Inno/templates em caminhos usuais. Houve erros de acesso em diretórios não pertinentes, sem bypass; não alegamos inventário global completo.

Exports úteis estavam fora da principal, em `C:/Users/Usuário/Documents/Codex/2026-09-20/referenced-chatgpt-conversation-this-is-an/work/v029/release/windows-test` e equivalente `v030`. ZIPs em `.../outputs/FRAIHA-Xadrez-V029-Ligas-Windows.zip` e `FRAIHA-Xadrez-V030-Windows.zip` possuem exatamente EXE/PCK/online.cfg/LEIA-ME.txt. Diretórios também contêm logs import/export, que são evidência de build e não runtime dependencies. Nenhum DLL/engine externo constava nesses ZIPs; licenças/origem de assets não foram certificadas para produção.

Foram copiados somente quatro arquivos necessários para `.local`: EXE/PCK integrais renomeados FRAIHA.exe/FRAIHA.pck, LEIA-ME preservado e sidecar DEV explicitamente substituído por `[online]` + endpoint vazio. Originais intocados, hashes originais/DEV em `FRAIHA_DISTRIBUTION_EXPORT_INVENTORY_02.json`. Não descartamos dependências para ZIP2 nem chamamos Godot sozinho de FRAIHA. Godot/help identifica runtime export 4.5.1; templates 4.7.2 existem no perfil e outros Godot foram encontrados, mas não houve export novo nem engine executado fora da sandbox.

| Payload | Tamanho | SHA256 |
|---|---:|---|
| EXE A/B idêntico | 96584192 | `3bba9f68131498157e02ec44c296f996dd0a4d64c8fdb582d2794bd59feb4465` |
| PCK A V029 | 82264412 | `351a00c43297bf3feaad8cab7e28ea2974e7238589d050db09b8eb8018c3733c` |
| PCK B V030 | 85100844 | `011137a3d88709cf5f2ab128648ebe5c325783824160939904b1860f74ab5433` |
| CFG DEV | 23 | `ffaee9060a72096d914fc15346a3021d316c2ace6e9f36b780c956c7d325606e` |
| ZIP final A | 115873267 | `ca7d165a7d44dd18fb72cde6dd58f7c6898a9da83a5338715250e83310b3c0be` |
| ZIP final B / DEV3 retry | 118695687 | `2237c9eb711316ffa4b8f867bc7648da305e543e2cdfc184896b0cd2620352c8` |

A/B são **duas builds reais diferentes**, com PCKs diferentes; build DEV3 reutiliza B. Versão DEV distribuição 0.0.0/build1–3/protocol0/rules0 não representa contratos de produção nem versão atual do mainline. README do export declara fontes Git V029 `a62fc3ded168f871bb42aaae55f6ec6624f4f654` e V030 `a04e57cf42a39a65f2b8ce77a11b955b8f10b18d`; os scripts correspondentes foram lidos via Git sob autorização delimitada. Não recompilamos para comprovar correspondência byte a byte PCK/source.

## Implementação e isolamento

Formato `fraiha-flat-zip-v2` preserva quatro nomes fixos, hashes/tamanhos de todos e limites CFG32KiB/README1MiB/total1GiB/pacote512MiB. ZIP1 continua fixtures de dois arquivos. Parser/schema sincronizados, zero entrypoint/script/argumentos/comandos vindos de manifesto. Outros exports com dependências adicionais requerem formato revisado; v2 não é allowlist genérica extensível por feed.

`--dev-real-offline` é opt-in **local**, separado de `--dev-mock`. PLAY real só aceita EXE/PCK/CFG dos hashes revisados; profile sem session files/junction/reparse; APPDATA/LOCALAPPDATA/TEMP/TMP isolados dentro da instalação e overrides FRAIHA_SERVER_URL/SUPABASE_URL/SUPABASE_KEY vazios. Scripts dos exports resolvem endpoint por sidecar e depois variável de ambiente e só conectam com ação online; no startup sem sessão não há reconexão. Godot Windows 4.5.1 usa APPDATA para userdata conforme [fonte oficial](https://github.com/godotengine/godot/blob/4.5.1-stable/platform/windows/os_windows.cpp). Não lemos credenciais nem userdata humana.

Root real máximo110 caracteres evita erros observados de shader cache; scanner de profile mantém recusa de links/sessões inclusive cache >260 via opt-in process-local .NET long paths e prefixo Windows nativo, sem registry/config compartilhada. Requer runtime Framework com suporte 4.6.2+; local registry Release observado `533509`. [Microsoft documenta os switches](https://learn.microsoft.com/en-us/dotnet/framework/configure-apps/file-schema/runtime/appcontextswitchoverrides-element). Não basta limite110 para assegurar todos os caminhos internos <260, por isso mantivemos teste long path e scanner integral.

PLAY mantém lock/handles EXE/PCK até exit e agora reporta exit não zero como erro. `QaAutoQuit` só habilita flags fixas engine confirmadas no help, sem argumento arbitrário: movie PNG/12 frames/fixed-fps1/windowed/resolution. Launcher normal não expõe esse modo. Comparação same-build valida identidade/payload de todos os arquivos, preservando a semântica anterior de notes/date.

## Estados e evidências finais

| Entrega | Classificação | Evidência/limite |
|---|---|---|
| Packaging v2 / launcher / updater / pointer | IMPLEMENTADO + VALIDADO COM FRAIHA REAL | A→B e GUI normal no run final |
| Startup/Home | VALIDADO COM FRAIHA REAL | A/B/rollback viewport completo, HWND/title, exit0 |
| Hash inválido/parcial/retry/rollback/jogo aberto | VALIDADO COM FRAIHA REAL | real `results.txt` |
| Traversal/absolute/dotdot/symlink/junction/timeout/race-lock/version/channel | VALIDADO APENAS COM MOCK-STUB | 29 grupos, incluindo junctions Windows reais; não attack race concorrente |
| Offline profile / cache populado A→B→A | VALIDADO COM FRAIHA REAL | sem sessão/reparse; TCP startup observado |
| Installer/uninstall | PREPARADO / PENDENTE / BLOQUEADO | compiler/ICO/publisher ausentes; guard uninstall pendente |
| Self-update | PREPARADO design anterior; PENDENTE implementação | sem overwrite de launcher em uso; helper confiável futuro |
| Android / Steam / iOS | PREPARADO docs anteriores; PENDENTE binários/QA | nenhuma implementação/operação nova |
| Crossplay | PREPARADO contrato anterior / PENDENTE integração | mesmo ecossistema, nenhum backend/serviço usado |
| Produção/current-mainline export | BLOQUEADO | trust/TOCTOU/export/installer/signing/homologação |

Comando final `./distribution/build.ps1 -Test -RealTest`: **29 grupos/0 falhas** em `.local/qa-20261006-033720-6f59f496b5644adfb95e7f71c9c0f370/results.txt`, aceitação real final **passou** em `.local/rqa-033737641/results.txt`. PNGs A/B/rollback/launcher finais inspecionados mostram Home/menu e controles completos; não apenas splash. Pacotes/manifests/profiles/logs no mesmo run. `normal-game.log` e `.local/g033850/` provam Launcher.exe normal `--dev-real-offline --auto-play`, sem movie/fixed-fps, com V030/PID18336/normal pointer. Fechamento via janela/Enter funcionou; nenhum kill fallback no final. Nenhum processo de jogo/launcher/teste mantido aberto após QA.

Inventário reproduzível: `prepare-real-exports.ps1 -SourceRoot` com caminho autorizado; lê apenas quatro arquivos/hashes dos dois exports, recusa reparse/conflitos, escreve somente `.local`, sem cleanup/import/download. AST/schema/CLI validate-version/diff-check passaram. `.local/real-export-inventory-20261006-033129-237.json` preservado. Repetir QA requer porta8765 livre; falha explícita se ocupada, sem matar serviços alheios.

## Falhas honestas, limitações e produção

Runs falhos anteriores preservados em `.local`: ExitCode por Process enumerado, captura prematura de desktop **inválida (não compartilhar)**, foreground lock, assert amplo de CFG (era `visual_theme.cfg` legítimo, não sessão), shader cache/path longo, PowerShell Tee stderr/NativeCommandError e long path sem prefixo nativo. Nenhuma assertion de segurança foi removida; corrigimos o alvo da prova e mantivemos teste >260/junction/session. Handoff01/mocks anteriores são baseline, não o resultado final.

Godot movie exits0 mas emite ObjectDB/resource ainda em uso no shutdown; **Claude/core precisa investigar**, não corrigido/suprimido neste escopo. Shader initialize errors do root longo desapareceram no root curto final. Não afirmamos zero erros do core nem teste gameplay/regressão/crossplay. TCP IPv4/IPv6 é amostragem startup, sem UDP/intervalos; política offline delimitada aos hashes revisados, não firewall nem prova packet-level.

Hash/HTTPS não autenticam manifesto. Produção precisa assinatura/trust anchor/replay/rotation e substituir read-check-use por confinement/handles/ACLs contra TOCTOU mesmo usuário. Scanner estático/reparse e locks não resolvem atacante concorrente. Pointer corrupto continua fail-closed, backup automático não implementado para não perder high-water. Power-loss/disk-full físicos/fuzzing completo continuam pendentes. Payloads/version rollback preservados; nenhum recursive delete novo.

P1 review em `FRAIHA_DISTRIBUTION_INSTALLER_REVIEW_02.md`: sem compiler em escopo pesquisado, nenhuma install/uninstall; template só launcher/mock shortcut. Ausência de recursive UninstallDelete não garante que raiz substituída por junction não atinja outra instalação. Guard InitializeUninstall fail-closed/ancestors/arquivos registrados, race/segunda instalação e preservação explícita de userdata exigem implementação/QA futura. Comando compilação com parâmetros obrigatórios reais está preparado no review, sem ICO/publisher inventados.

## Principal, Claude e próximos passos

`FRAIHA_DISTRIBUTION_MAIN_GIT_CHECK_02.json` captura HEAD/branch/status somente Git. HEAD observado permanece `bf1ec5db7cbd003cf254c4e2a9d687c70bc5520e`, `dev/web-alpha`; Claude pode legitimamente alterar dirty/imports/exports. Não executamos nem escrevemos ali, não copiamos dirty core, não afirmamos igualdade byte a byte.

Claude/owner deve: (1) produzir export **atual** Windows completo em tarefa autorizada, inventariar todas DLLs/engines/assets/licenças e provar endpoint offline/userdata sem sessão antes de substituir pins; (2) investigar resource leak dos exports históricos no shutdown e validar cache/root atuais; (3) se export atual não suportar isolamento, adicionar contrato DEV offline explícito antes de startup/account restore em `account/account_service.gd:_ready`, resolver endpoint e profile dedicado com configs aprovadas em tarefa core — **propostas não aplicadas aqui**; (4) revisar source central de versões/protocol/rules e compatibilidade/backend em owner apropriado, sem reutilizar zeros DEV; (5) fechar trust/TOCTOU e installer/uninstall antes de release.

Para launcher self-update futuro: helper confiável separado, hashes/assinatura/pins/PID/wait launcher exit, swap/backup/rollback depois do exit; nenhum overwrite em uso implementado. Android/Steam/iOS continuam planos do handoff01, não iniciar múltiplas implementações nem alterar presets/keystore/contas. Crossplay permanece contrato de mesmo backend/ecossistema, sem partição de matchmaking por plataforma e sem mudança backend nesta entrega.

Reconferir Git/mainline e colisões semânticas antes de qualquer integração autorizada. Ao concluir worker_done, parar e ficar idle. Preservar `.local` com fixtures/junctions, runs falhos/finais e exports; não stage/copy para main/release nem usar recursive delete.
