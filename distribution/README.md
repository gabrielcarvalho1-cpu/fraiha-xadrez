# FRAIHA Distribution v1 — LOCAL DEV

Tooling novo isolado. Requer Windows, PowerShell e compiler .NET Framework já instalado; nenhum SDK/NuGet/download de toolchain. Não integra Godot/backend/login. Versão central `version.json` é DEV não atribuída para produção: game 0.0.0/build 1/protocol 0/rules 0. A versão 0.31.0 do backend não foi alterada.

```powershell
# Da raiz deste worktree isolado:
./distribution/build.ps1 -Test
./distribution/.local/bin/FRAIHA.Package.exe validate-version ./distribution/version.json
# Terminal 1, servidor somente loopback; Ctrl+C encerra:
./distribution/dev-mock.ps1 -Build 1 -Port 8765
# Terminal 2, UI manual:
./distribution/.local/bin/FRAIHA.Launcher.exe --dev-mock
# Ou check -> update se necessário -> PLAY automático ao abrir:
./distribution/.local/bin/FRAIHA.Launcher.exe --dev-mock --auto-play
```

Para demonstrar atualização: fechar o stub/launcher, parar feed com Ctrl+C, reiniciar `dev-mock.ps1 -Build 2`; reabrir launcher. Same build pula download no fluxo automático somente se hashes/identidade coincidirem; lower/channel/platform conflitantes falham e nunca lançam por fallback. UI manual oferece Check/Retry, Update, PLAY e rollback. Retry é ação explícita, não loop sem limite.

O feed serve um **stub C#**, PCK artificial, nunca o jogo Godot. Compilar com `-Test` executa testes de núcleo/UI/junctions/processos e salva `.local/qa-*/results.txt` e PNG. DEV servidor só serve dois nomes gerados; não expõe diretórios do projeto. Scripts/binaries/fixtures ficam em `distribution/.local/`; não adicionar ao Git. Não alteramos `.gitignore`; stage sempre por nome.

Validação entregue: suite TCP mock/WinForms executada; AST de `dev-mock.ps1` válido, mas runtime desse script standalone **pendente** porque a policy automática rejeitou o smoke com helper oculto (`blocked by policy`). Comandos acima são reproduções propostas desse caminho, não prova de execução do script.

Empacotar uma exportação aprovada futuramente:

```powershell
./distribution/.local/bin/FRAIHA.Package.exe package ./distribution/version.json ./distribution/.local/approved-two-file-export ./distribution/.local/new-package http://127.0.0.1:8765/fraiha-0.0.0-1.zip 'DEV approved export notes' --dev-only
```

Diretório source precisa conter **somente** `FRAIHA.exe` e `FRAIHA.pck`. O Tool não exporta Godot nem busca dependências. Export real com online.cfg/DLLs/engine/runtime/licenças externas exige futura homologação e novo formato explicitamente allowlisted, não excluir dependências para conseguir verde. Manifesto gerado incorpora SHA256/size de pacote e ambos os arquivos, data/notas/mandatory=false. Nenhum entrypoint/argumento remoto. Schema documental + validador C# estrito, sem dependência de biblioteca JSON Schema. SHA não autentica editor do manifesto.

Instalação em `.local/bin/dev-install/` (adjacente ao launcher): `versions/<game_version>-<build_number>/`, `state.json`, `state.backup`, `operation.lock`, `temp/<uuid>/`. GAME/PLAY abre exe fixo com working directory da versão, sem args. Pointer é commit atomicamente; versão anterior preservada; falhas após move permitem retry do órfão somente com manifesto idêntico/hashes válidos. High-water impede feed downgrade após rollback manual. Pointer corrompido falha fechado: não restaurar backup automaticamente perdendo high-water; recuperar manualmente após auditoria. `.next` parcial é substituído no próximo commit. Não há cleanup automático de versões conhecidas.

Limites: manifest 32 KiB, pacote 512 MiB, payload total 1 GiB, notes 4096 chars, 5s I/O/60s total, zero redirects, zero credenciais/proxy por download. HTTP só DEV literal loopback; HTTPS reconhecido pelo contrato, instalação bloqueada sem assinatura/trust anchor. ZIP flat recusa path/encoded traversal/case aliases/duplicatas/link/reparse/extras. Componentes locais reparse recusados; races de atacante concorrente mesmo usuário permanecem bloqueio de produção. Lock cobre update e PLAY; processos externos FRAIHA também bloqueiam conservadoramente.

Uninstall DEV manual: fechar launcher/jogo/feed; remover somente o diretório `.local/bin/dev-install` já resolvido/conferido dentro deste worktree, sem seguir junctions e sem apagar userdata Godot. Não há uninstall automatizado nesta fase. Preservamos fixtures com junctions para evidência; **não usar remoção recursiva indiscriminada de `.local`**, especialmente em PowerShell antigo. Installer não compilado/testado. Plano, requisitos externos e handoff em `docs/FRAIHA_*DISTRIBUTION*` e `docs/FRAIHA_STEAM_RELEASE_PLAN.md`.

## v1.1: exports reais históricos, DEV offline

O formato v2 preserva os quatro arquivos necessários dos exports V029/V030 já existentes: `FRAIHA.exe`, `FRAIHA.pck`, `online.cfg`, `LEIA-ME.txt`, cada um com tamanho/hash. EXE/PCK são cópias integrais renomeadas; o sidecar DEV tem endpoint vazio, enquanto a configuração original permanece preservada na origem/inventário. Não apagar dependências para caber em ZIP2: outros exports com DLLs/engines/licenças externas continuam exigindo inventário e outro formato revisado.

```powershell
./distribution/prepare-real-exports.ps1 -SourceRoot 'C:/Users/Usuário/Documents/Codex/2026-09-20/referenced-chatgpt-conversation-this-is-an/work'
./distribution/build.ps1 -Test -RealTest
# UI normal, com feed DEV real loopback já servido na porta 8765:
./distribution/.local/bin/FRAIHA.Launcher.exe --dev-real-offline
```

`-RealTest` serve pacotes reais por loopback, testa controles WinForms e também inicia o EXE Launcher normal com `--dev-real-offline --auto-play`. São builds **históricas reais diferentes**, não exports do mainline atual. Os números DEV 0.0.0/build1–3 são metadata da distribuição; build3 reutiliza V030 para retry, não uma terceira build real. Frames do viewport comprovam Home; flags movie/fixed-fps são locais do harness e não existem no manifesto/UI normal.

PLAY real requer opt-in local e hashes EXE/PCK/sidecar revisados. Isola APPDATA/LOCALAPPDATA/TEMP dentro da instalação, desativa endpoints por ambiente e recusa profile com reparse/junction ou arquivos de sessão. ROOT real máximo 110 caracteres evita falhas observadas do shader cache desses exports. Isso é perfil DEV delimitado: não homologação de offline para qualquer export. A observação de TCP IPv4/IPv6 no startup não cobre UDP nem intervalos entre amostras.

Instalação real normal: `.local/bin/dev-real-install/`; evidências em `.local/rqa-*`, `.local/g*`, inventário e logs. Não remover recursivamente esses caminhos nem fixtures. Installer continua apenas preparado, sem compilação/instalação/uninstall validado. Produção, self-update, backend/crossplay e plataformas adicionais continuam pendentes; consultar `docs/FRAIHA_DISTRIBUTION_HANDOFF_02.md`.
