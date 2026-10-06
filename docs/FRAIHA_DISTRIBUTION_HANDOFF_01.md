# FRAIHA DISTRIBUTION HANDOFF 01

Checkpoint imutável, 2026-10-06 UTC / 2026-10-05 São Paulo. Destinatário: outro agente/Claude após revisão própria. Task `task_70ba367586b0`, Dispatch `ctx_29c6df68418d`, worker `term_9ddb73d1-7326-4a76-8a7f-e0e1b4be8983`, coordinator `term_25731eaf-3553-49b8-b210-aa3ac7b548e4`. Nenhum subworker ou outra Wave.

## Estado Git e identidade do documento

- Worktree **exclusivo de escrita**: `C:/Users/Usuário/orca/workspaces/project/codex-distribution-v1`.
- Branch: `codex/distribution-v1`; auto-branch nova inicialmente `gabrielcarvalho1-cpu/codex-distribution-v1` foi renomeada somente após cwd/HEAD/status limpo e destino ausente.
- Base fetch fornecida pelo coordenador e confirmada no tracking: `a5fc1cf479138a23905ba1ff84d298b1be92b3de` R42.2; principal/remote snapshot `dev/web-alpha` na mesma base. Não criar nova base a partir de dirty files.
- Commit implementação: **`1b8eec722105c43ed8485af4d0196abcd2dd0895`**. HEAD antes deste documento é esse commit.
- **HEAD de entrega / selfSHA**: o commit que introduz este documento; resolver full SHA com `git log -1 --format=%H -- docs/FRAIHA_DISTRIBUTION_HANDOFF_01.md`. O full SHA final é informado ao coordenador em status/worker_done e na resposta final. Não editar o documento para embutir seu próprio hash (isso mudaria o hash). Para obter conteúdo imutável, usar `git show <selfSHA>:docs/FRAIHA_DISTRIBUTION_HANDOFF_01.md`; confira `git rev-parse HEAD` contra selfSHA no checkpoint.
- AGENTS/fraiha-xadrez/fraiha-coordinator lidos no setup `C:/Users/Usuário/Documents/Codex/orca-worktrees/codex-setup-rules`, além das skills oficiais Orca CLI/orchestration. Usuário pediu worker MEDIUM, sem subworkers; modelo/effort efetivamente configurados não expostos por ferramenta confiável nesta sessão. Quota atual percentual também não verificável; não reutilizamos ~11% histórico. Checkpoints/heartbeats enviados e priorizado P0 sem fase nova.

## Outcome e aprovação

**TECHNICAL OUTCOME:** P0 LOCAL DEV implementado e testado em Windows, 28 grupos/0 falhas; produção bloqueada, requisitos externos/readiness registrados. **ORCHESTRATION OUTCOME pretendido:** `succeeded` ao enviar worker_done válido uma vez para concluir o escopo DEV/readiness, não prova de release/store/crossplay. Estado formal aceito deve ser conferido pelo coordenador no Orca, não fabricado neste documento antes do envio.

**APROVAR COM AJUSTES**: novos arquivos isolados podem ser revisados/commitados localmente (commits autorizados pelo despacho); produção e integração no mainline dependem dos gates abaixo. Não houve push, merge, rebase, publish, deploy, migration, compra, conta, custo, signing ou operação Supabase/Render/Cloudflare, nem staging. Backend/auth/session/rules/gameplay/UI Home/lobby/Voice/assets/online_v021/payments/monetization/supabase intactos. Configs `project.godot`, `export_presets.cfg`, `*.uid`, `*.import` não editados nem staged.

## Arquitetura e entregáveis reais

`distribution/version.json` é a fonte central do **tooling novo**, não adotada pelo core: schema1, game0.0.0/build1, protocol0/rules0 **não atribuídos à produção**, DEV/windows_site/development_only=true. Não fingir que backend package0.31.0 representa release ou que 0 protocol/rules são contratos reais. Channels DEV/BETA/STABLE (INTERNAL não implementado), platforms web/windows_site/windows_steam/android/ios. Schema e C# validam tipos/campos extras/duplicados unicode/limites; versão canônica numérica, build monotônico; canal/plataforma incompatíveis e downgrade recusados.

`Contracts.cs`: parser JSON flat estrito, version/manifest validator, SHA256, URL policy, `CompatibilityContract`. Outcomes isolados MAINTENANCE → INCOMPATIBLE_PROTOCOL (inclui rules mismatch) → UPDATE_REQUIRED (build mínimo) → COMPATIBLE. Não integrado a backend/auth/matchmaking. Conta FRAIHA primária; platform/canal são distribuição e não prova confiável de auth/entitlement nem partição matchmaking. Crossplay futuramente precisa backend compartilhado + protocol/rules homologados; servidor continua autoridade de progresso/entitlements.

`Tool.cs`: valida versão, gera ZIP/manifest metadata/SHA256 pacote e arquivos/data/notas/mandatory=false a partir de pasta export pré-aprovada com **exatamente** FRAIHA.exe e FRAIHA.pck. Nunca exporta Godot. ZIP v1 **não homologado para export FRAIHA real**: online.cfg/DLL/engines/assets/licenças extras podem ser necessários. Não remover dependências para caber no formato; futura expansão exige whitelist/formato/revisão de segurança próprios. `mandatory` é metadata, não enforcement do servidor nesta fase.

`Updater.cs`: fixed executable FRAIHA.exe e fixed FRAIHA.pck, sem comandos/scripts/arguments/entrypoint remoto. HTTP apenas literal loopback DEV opt-in; outras URLs exigem HTTPS no contrato, mas **qualquer instalação não mock DEV HTTP está bloqueada** até assinatura/trust. Redirects zero, proxy/credenciais zero, 5s I/O/60s total, manifest32KiB, package512MiB, expanded1GiB, notes4096. Size/hash verificados antes do staging; ZIP flat exatamente2 entradas, sem abs/dotdot/backslash/%/case aliases/ADS/duplicate/extra/Unix symlink/reparse/directories. Root/ancestors/componentes locais rejeitam reparse/junction; testes Windows reais executados.

Versões imutáveis `versions/<game>-<build>`, download/staging privados `temp/<uuid>`, commit `state.json` via File.Replace/Move com state.backup; anterior preservado, high-water não reduz no rollback manual. Fault antes do pointer conserva estado conhecido; retry de órfão pós-move somente com manifesto integral idêntico + hashes válidos, sem overwrite. `.next` parcial é removido na próxima gravação. Pointer corrompido falha fechado; recuperação de backup automática não implementada, pois não pode perder high-water. Lock de operação exclusivo e processos FRAIHA externos bloqueiam update; PLAY mantém handles/lock até exit. Sem game overwrite em execução.

`Launcher.cs` WinForms real: path/canal/version installed/available, Check/Retry, Download/Update/progress/status/error/notes, PLAY/rollback. Manual com `--dev-mock`; automático opt-in `--dev-mock --auto-play` usa `LauncherFlow.cs`: consulta→validar→instalar novo (same release com conteúdo idêntico pula download)→PLAY. Check/download/hash/install/versão conflitante falha sem iniciar jogo. UI e coordenação testadas via clicks/startup reais, não só métodos. Root DEV adjacente ao launcher em `.local/bin/dev-install`; config/log persistente de usuário não implementado. `.gdignore` novo mantém todo tooling externo ao scanner/import de Godot; não houve import/export para comprová-lo nesta tarefa.

`build.ps1` usa csc Framework existente, sem SDK/NuGet; `.local/bin` binaries não versionados. `dev-mock.ps1` prepara stub C#/PCK artificial e serve somente localhost; **AST validado, runtime separado pendente**. Policy automática rejeitou tentativa de smoke com helper oculto/download/hash/stop, informou apenas `blocked by policy`; nenhum bypass/retry equivalente. Mocks TCP da suite são outro caminho e foram executados. Stub nunca é Godot/jogo FRAIHA real.

## Estado por plataforma/fase

| Entrega | Estado | Evidência/dependência |
|---|---|---|
| P0 versão/schema/metadata/hashes/compat contrato | IMPLEMENTADO local | runtime Windows/testes; integração core/backend NÃO INICIADA |
| Windows site launcher/update DEV | IMPLEMENTADO local | builds/UI/locks/junction/fault/auto tests |
| Windows site produção | BLOQUEADO POR REQUISITO EXTERNO + ajustes técnicos | trust anchor/signature/TOCTOU/code signing/feed homologado |
| P1 installer | PREPARADO, QA PARCIAL | Inno template; compiler/ICO oficial/publisher ausentes, sem instalação/uninstall executados |
| P2 Android | PREPARADO, binário BLOQUEADO POR REQUISITO EXTERNO | templates presentes, SDK/JDK não no PATH; .aab/export/signing/device não executados |
| P3 iOS/iPadOS | PREPARADO, BLOQUEADO POR REQUISITO EXTERNO | Mac/Xcode26+/AppleDeveloper/certs/perfis/device |
| P4 Steam | PREPARADO | plano oficial AppID/depot/SteamPipe/launch direto; nenhuma operação Steam |
| Web | PARCIAL: pipeline existente preservado | novos conceitos versionamento documentados; export/cache/browser QA não executados |
| Launcher self-update Phase2 | PREPARADO design, implementação NÃO INICIADA | helper assinado separado, PID/wait/locks/staged validation/atomic swap/rollback; nunca overwrite launcher vivo |
| Crossplay e loja/entitlements | NÃO INICIADO | matriz/plano somente, nenhum backend/payment change |

## QA, limitações e gates

Final `./distribution/build.ps1 -Test`: **28 passed / 0 failed**; `distribution/.local/qa-20261006-014346-2fe4f59412d140f09ed52981e0814c52/results.txt`, PNG local `launcher-ui.png`. Builds CLI/UI/test exe reais Framework Windows. Testes: same/new/lower/canal/platform/schema/JSON/URLs, interrupted/partial/corrupt/timeout/redirect/size/hash, cleanup/retry, seis disk-IO faults simulados, pointer atomic/orphan recovery/rollback/high-water, malicious ZIP nomes/attrs/duplicates/files hash, junctions reais, lock exclusivo/game-running externally + PLAY stub, installed tamper, IPv6 serialization, auto pipeline/noPLAY errors, manual+startup WinForms. Lista completa e distinções em `docs/FRAIHA_DISTRIBUTION_QA.md`. CLI versão e schemas syntax/PowerShell AST passaram. Não enfraquecemos/removemos casos para verde.

**Não executado**: export/jogo Godot real, real crossplay, devices/lojas/installer, físico disk-full/power-loss, race attacker mesmo-usuário. HTTPS/hash **não autenticam manifesto hostil**; produção requer assinatura sobre canonical bytes (inclui versão/canal/platform/hashes/expiry), public trust anchor embutido, replay protection/rotation/revocation e fixtures de assinatura inválida. Read-check-use de reparse ainda tem **TOCTOU com atacante concorrente mesmo-usuário**, gate de produção: usar handles Windows/ACLs/confinamento final antes de release. Zip fuzzing, durability/powerloss e performance/hashing grandes pacotes também pendentes. Manual PLAY não chama backend compatibility nem implementa enforcement mandatory; isso exige tarefa autorizada no owner correto. Não vender DEV como seguro de produção.

Matriz futura **toda NÃO EXECUTADA**: Web–Web, Web–Windows, site–Steam, Steam–Android, Steam–iOS, Android–iOS, Windows–Android, Windows–iOS. Tests com enums de plataforma não comprovam partidas. Steam/Play/AppStore/Web gerenciam seus próprios binários; nunca reaproveitar updater Windows site nessas plataformas.

## Commit ledger e integração

1. **`1b8eec722105c43ed8485af4d0196abcd2dd0895`**, `feat(distribution): add isolated Windows DEV launcher and verified updater`. Dependência base `a5fc1cf479138a23905ba1ff84d298b1be92b3de`; ordem1. Arquivos completos: `distribution/README.md`, `distribution/build.ps1`, `distribution/dev-mock.ps1`, `distribution/schemas/manifest.schema.json`, `distribution/schemas/version.schema.json`, `distribution/src/Contracts.cs`, `distribution/src/Launcher.cs`, `distribution/src/LauncherFlow.cs`, `distribution/src/Tool.cs`, `distribution/src/Updater.cs`, `distribution/tests/GameStub.cs`, `distribution/tests/Tests.cs`, `distribution/version.json`, `docs/FRAIHA_DISTRIBUTION_ARCHITECTURE.md`, `docs/FRAIHA_DISTRIBUTION_QA.md`.
2. **full SHA = selfSHA resolvido pelo comando acima e comunicado no encerramento**, `docs(distribution): prepare platform release readiness and immutable handoff`. Depende exclusivamente do commit1; ordem2. Arquivos completos: `distribution/.gdignore`, `distribution/installer/FRAIHA-DEV.iss`, `docs/FRAIHA_DISTRIBUTION_PLATFORM_READINESS.md`, `docs/FRAIHA_STEAM_RELEASE_PLAN.md`, `docs/FRAIHA_DISTRIBUTION_MAIN_GIT_CHECK.json`, `docs/FRAIHA_DISTRIBUTION_HANDOFF_01.md`. Sem amend/rewrite/push/merge. Não integrar automaticamente só porque não há conflito textual.

**NOVOS arquivos seguros para revisão de integração:** todos os sources/docs/schema/tooling acima, sem core patch. `.gdignore` isola scanner. **Precisam adaptação ao mainline atual antes de uso real:** central metadata não adotado no Godot/server; versão/protocol/rules/publisher/ícone precisam decisão; export completo não cabe necessariamente ZIP2; compiler Windows path é local; future app paths/userdata migration/signing/installer cleanup precisam revisão. **PROPOSTO NÃO APLICADO:** alterações de project.godot/export_presets.cfg para versão/features/mobile/exclusion/ícones/identity/paths. Patches exatos e nomes de campos em `PLATFORM_READINESS`; IDs de preset/enums devem validar contra mainline/Godot4.7.2. Sem UID/import novos ou edições protegidas.

## Principal preservada no nível verificado

Principal readonly Git: `C:/Users/Usuário/Documents/Codex/2026-09-20/referenced-chatgpt-conversation-this-is-an/work/v024/project`. Snapshot final em `docs/FRAIHA_DISTRIBUTION_MAIN_GIT_CHECK.json`, comparação 2026-10-06T01:45:42Z contra baseline setup. HEAD permaneceu `a5fc1cf479138a23905ba1ff84d298b1be92b3de`, branch `dev/web-alpha`; status cresceu 373→374 entradas, novo **`?? _entrega_r43/`** apareceu externamente. Nenhum delta de nomes commitados na leitura; não abrimos nem copiamos arquivos dessa entrega, não revertemos nada. **HEAD/status não provam igualdade de conteúdo**: não houve inventory/hash de conteúdo na principal, como proibido. Main pode avançar enquanto Claude revisa; repetir fresh Git HEAD/status/diff/check colisão dos novos caminhos e revisão semântica, sem presumir o HEAD deste snapshot nem descartar dirty files.

## Próximos passos exatos e ações humanas

1. Resolver selfSHA/checkout, confirmar branch/status e ler arquivos/QA; no mainline somente Git conforme autorização vigente, avaliar novo `_entrega_r43/` pelo owner humano sem copiar dirty state para este worker.
2. Rodar DEV reproduções abaixo em worktree isolado Windows. Runtime `dev-mock.ps1` permanece pendente de teste permitido; não contornar policy. Nunca lançar este stub como jogo real.
3. Homologar export completa do jogo e arte/publisher em tarefa própria com permissão de config protegida. Definir produção game/protocol/rules/build/canais reais; mapear central source sem editar backend/auth indiretamente.
4. Fechar assinatura/trust/TOCTOU/fuzz/durability e installer cleanup/test VM. Installer compiler/ICO/publisher externos; **nenhum custo** feito. Comprar/gerir code signing somente humano autorizado futuro.
5. Android: SDK/JDK17/Gradle compatíveis API36, 16KiB/libs, pacote/ícones/orientation/network/storage/audio/lifecycle/device e upload signing externos. iOS: Mac/Xcode26+/SDK26/AppleDeveloper/certs/profiles/capabilities/safeareas/TestFlight/AppStore. Steam: humanos criam conta/AppID/depot/package/store e aprovam custos/release, jogo direto sem launcher. Fontes oficiais/data no readiness/Steam docs, revalidar na release.
6. Compatibilidade/crossplay no mesmo backend e futura store payments versus FRAIHA entitlements são planos; jamais adicionar platform auth/partition/microtransactions nesta entrega. Não realizar service operations.

Future secret **NAMES ONLY**, nada criado/lido/copied: `FRAIHA_RELEASE_SIGNING_KEY`, `FRAIHA_RELEASE_KEY_ID`, `WINDOWS_SIGNING_CERTIFICATE`, `WINDOWS_SIGNING_CERT_PASSWORD`, `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_SIGNING_CERTIFICATE`, `APPLE_PROVISIONING_PROFILE`, `STEAM_BUILD_ACCOUNT`, `STEAM_GUARD_TOKEN`. Paths/IDs públicos não são motivo para guardar secrets em repo; provisionamento futuro fora do chat/repo. Não solicitei valores, não acessei contas.

## Reprodução e arquivos locais não commitados

```powershell
# Somente neste worktree isolado Windows:
./distribution/build.ps1 -Test
./distribution/.local/bin/FRAIHA.Package.exe validate-version ./distribution/version.json
# Script standalone abaixo tem AST válido; runtime PENDENTE pela policy:
./distribution/dev-mock.ps1 -Build 1 -Port 8765
# Outro terminal:
./distribution/.local/bin/FRAIHA.Launcher.exe --dev-mock
# Alternativa automática opt-in:
./distribution/.local/bin/FRAIHA.Launcher.exe --dev-mock --auto-play
```

Após entrega, tracked diff limpo; **`?? distribution/.local/`** é evidência/binários/testfixtures intencionalmente preservados, não staged. Contém runs de testes anteriores (inclusive falhas honestas), run final, ZIPs/manifests/stubs e **junction fixtures**; não executar recursive delete indiscriminado. Não há alterações parciais de source pendentes; installer/readiness são entregas preparadas, não executadas. Todos novos arquivos de source/docs estão nos dois commits; não copiar `.local` para mainline/release e não adicionar `git add .`. Nenhum servidor/jogo/launcher/testprocess mantido aberto ao fechar testes; helper smoke bloqueado não foi iniciado. Encerrar este despacho após worker_done exatamente uma vez e ficar idle, sem nova Wave.
