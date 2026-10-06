# FRAIHA Distribution — integração na mainline (R46)

Revisão humana (Claude) da entrega do Orca (`codex/distribution-v1`) e adaptação ao FRAIHA atual.
**Estado: HOMOLOGADO EM DEV/LOCAL (Windows real, exports atuais). NÃO é homologação de produção.**

## Proveniência

Branch local do Orca (não estava no GitHub), base `a5fc1cf` (R42.2), escopo só `distribution/` + docs:

| Commit Orca | Conteúdo | Situação |
| --- | --- | --- |
| `1b8eec722105c43ed8485af4d0196abcd2dd0895` | launcher/updater Windows DEV, contrato de versão, schemas, testes | integrado (cópia fiel) |
| `049a61482a7130b61181db6cedca582c0aa4cc60` | readiness Android/iOS, plano Steam, template de installer, handoff 01 | integrado (cópia fiel) |
| `000b836904c82cf98fa5ea694ae81125e5e4187a` | formato v2 (4 arquivos), modo `--dev-real-offline`, QA com exports históricos V029/V030 | integrado + **adaptado** |
| `bb45eaedf377174008b5a1b56c8ac2a4ae60d552` | QA real v1.1, inventário, review do installer, handoff 02 | integrado (cópia fiel) |

Na mainline: `f6ac7f6` (import byte a byte, referência) → `eec86bf` (adaptação). Nenhum outro caminho do
repositório é tocado; `distribution/` fica fora do Godot (`.gdignore`); `distribution/.local` (EXE/PCK/fixtures) nunca entra.

## O que foi adaptado (e por quê)

1. **Pins de export real fora do código.** O Orca deixou fixos no `Updater.cs` os SHA-256 dos exports
   históricos V029/V030 → o FRAIHA atual nunca passaria. Agora os pins vêm de `dev-reviewed-exports.txt`
   **ao lado do launcher** (arquivo local do operador, gerado por `prepare-real-exports.ps1` a partir de exports
   aprovados). O manifesto/feed nunca escolhe nem escreve pins. Export sem pin → PLAY real recusado (testado).
2. **`prepare-real-exports.ps1`** agora recebe 2 exports Windows reais do FRAIHA atual (A/B), recusa arquivos
   extras (DLL/engine que o formato v2 não cobre), cria o `online.cfg` DEV com endpoint vazio.
3. **Smoke de jogo no binário real** (não só a Home): o próprio `FRAIHA.exe` instalado roda
   `rules_test`, `home_navigation_test` e `bot_search_test` que vêm no `.pck` (args fixos do harness).
4. **Steam**: o updater do site recusa instalação dentro de `steamapps` (Steam atualiza a cópia Steam) + teste.
5. Compatível com o FRAIHA atual sem tocar no core: o jogo já resolve servidor por `online.cfg` ao lado do exe
   e `FRAIHA_SERVER_URL` (`online_v020/endpoint.gd`), e Supabase por `FRAIHA_SUPABASE_URL/KEY`
   (`account_service.gd`) — vazios = offline. Userdata isolado via `APPDATA/LOCALAPPDATA`.

## Export Windows atual

- Godot 4.5.1 oficial; templates oficiais `Godot_v4.5.1-stable_export_templates.tpz` (SHA-512 conferido com
  `SHA512-SUMS.txt` do release oficial). Preset `Windows Desktop`, `FRAIHA.exe` + `FRAIHA.pck`, sem DLLs.
- A = R45 `b389849` → PCK `ac4d60c5…6d92`; B = R46 (voz recebida) → PCK `fc91e8eb…8c7e`; EXE `3bba9f68…4465`
  (template oficial sem rcedit: ícone/metadados padrão do Godot — ver pendências).
- Stockfish nativo não vai no export Windows (fica em `user://engines/` ou `FRAIHA_STOCKFISH`), então no
  Windows a engine do bot/análise é o **fallback FRAIHA** se o binário não existir — não mascarar.

## QA executado (Windows real do dono, 2026-10-06)

`distribution/qa/RUN-QA.ps1` → **QA CONCLUÍDO SEM FALHAS**; evidência `distribution/.local/rqa-064358820`.
- Suíte mock: **30/30** (os 29 grupos do Orca + Steam).
- Aceitação real com os exports ATUAIS: instalação limpa A → abriu até a **Home** (frames do viewport real) →
  update bloqueado com o jogo aberto → launcher detectou B, baixou, validou hash, instalou, trocou o pointer →
  B abriu → rollback restaurou A → update inválido preservou A → pacote parcial rejeitado → retry ok →
  manifesto inválido/indisponível recusado (nunca joga estado antigo no automático) → `online.cfg` adulterado
  bloqueou PLAY → `FRAIHA.Launcher.exe` normal (`--dev-real-offline --auto-play`) fez check/install/PLAY →
  smoke real `rules`/`home_navigation` (28/28)/`bot_search` em A e B → export sem pin recusado.
- TCP observado no startup: só loopback (amostragem; não é prova de pacote/UDP).

## Revisão de segurança (resumo)

| Item | Situação |
| --- | --- |
| path/archive traversal, absoluto, `..\`, `%`, ADS, aliases, duplicados | bloqueado + testado (mock e real) |
| junction/symlink/reparse (raiz, versões, payload, pointer) | bloqueado + testado com junctions reais |
| manifesto malicioso / execução arbitrária | formato flat fixo; nenhum comando/entrypoint/argumento vem do manifesto |
| URL arbitrária | HTTPS obrigatório; HTTP só loopback literal em DEV; sem redirect/proxy/credenciais |
| hash bypass / pacote adulterado / download parcial / timeout | SHA-256 + tamanho antes de extrair; 5 s I/O / 60 s total |
| downgrade / canal / plataforma | high-water mark; DEV/windows_site obrigatórios |
| jogo aberto / corrida local | lock exclusivo + recusa com `FRAIHA.exe` rodando; PLAY segura os handles |
| rollback / cleanup | versões imutáveis, pointer atômico, staging removido, sem delete recursivo |
| **TOCTOU (atacante concorrente mesmo usuário)** | **pendente** — gate de produção (handles/ACLs) |
| **assinatura do manifesto / trust anchor** | **pendente** — produção bloqueada por código (`RequireDevTrust`) |
| uninstall | template Inno revisado; **não executado** (sem compilador/ICO/publisher) |

## Auditoria Orca R46 — 2 MEDIUM novos corrigidos (2026-10-06)

Snapshot auditado: `6cc1c6d` (1 BLOCKER de trust root/assinatura **fora do escopo**, continua aberto).

| Finding | Causa raiz | Correção | Prova |
| --- | --- | --- | --- |
| Gates de packaging saíam 0 mesmo falhando | `MONTAR-UPLOAD` capturava o erro (`catch { Write-Host }`) e terminava sem `exit`; `CONFERIR-SITE` só imprimia; os `.cmd` gerados terminavam em `pause` (código do `pause` = 0); `RUN-QA` imprimia "QA FALHOU" e saía 0 | `exit 0` só no sucesso real, `exit 1` em qualquer falha; MONTAR apaga a pasta `UPLOAD` parcial; `.cmd` devolvem o código do PowerShell depois do `pause` (`FRAIHA_NO_PAUSE` para automação) | `tools/web_release/test_gates_exit_codes.py` (PowerShell real): manifesto ausente/incompleto, arquivo/parte faltando, SHA/tamanho errado, site faltando arquivo → ≠0; pacote válido → 0. Antes: manifesto ausente = ERRO + exit 0 |
| Preparação DEV aceitava `online.cfg` com endpoint | `prepare-real-exports.ps1` só escrevia o `online.cfg` se ele NÃO existisse e fixava o hash do que estivesse lá | **Contrato:** o `online.cfg` DEV é exatamente `[online]\nserver_url=""\n` (UTF-8 sem BOM, SHA256 `ffaee906…606e`). Outro conteúdo → PARA (≠0), não sobrescreve, não gera pins. `ReviewedPins` recusa pin `cfg` diferente desse hash | `distribution/tests/test_prepare_offline.py` (PowerShell real; 3 falhas no script antigo, 0 no novo) + caso C# em `Tests.cs` |

Testes que dependem de Windows (.NET Framework `csc`, WinForms, junctions): a suíte mock (`build.ps1 -Test`)
e a aceitação real (`RUN-QA`) precisam rodar no PC Windows; aqui o C# foi compilado com `mcs -langversion:5`
e a regra nova de pins foi executada em mono.

## Pendências reais (não bloqueiam DEV; bloqueiam produção)

- Assinatura do manifesto + trust anchor + anti-replay/rotação; TOCTOU com handles/ACLs.
- Code signing do launcher/jogo (custo — decisão humana), ícone/metadados no EXE (rcedit/ICO oficial), publisher.
- Installer/uninstaller: compilar e testar em VM (precisa Inno Setup instalado no PC — instalar software é decisão sua).
- Fonte central de versão (`game_version/build/protocol/rules`) adotada pelo jogo/servidor (hoje só `distribution/version.json` DEV 0.0.0).
- Self-update do próprio launcher (helper separado), feed real HTTPS.
- Stockfish nativo no pacote Windows (origem/hash/licença GPLv3) — hoje fallback no Windows.
- **Dívida técnica (não é regressão, não falhou o QA):** ao fechar os exports Godot aparece
  `WARNING: ObjectDB instances leaked at exit` / `ERROR: 2–3 resources still in use at exit`, também nos exports
  históricos. Investigar separadamente (provável recurso/autoload sem liberar no `quit()`).
- Android/iOS/Steam: só readiness/planos (Orca), nenhuma operação; cross-play continua um backend só.
