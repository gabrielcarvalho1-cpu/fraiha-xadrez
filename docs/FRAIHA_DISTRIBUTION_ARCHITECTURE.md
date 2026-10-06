# FRAIHA Distribution v1 — arquitetura

Data de auditoria: 2026-10-06 UTC (2026-10-05 São Paulo). Base exclusiva `a5fc1cf479138a23905ba1ff84d298b1be92b3de`, branch `codex/distribution-v1`, checkout inicialmente limpo. AGENTS.md, fraiha-xadrez e fraiha-coordinator lidos em `C:/Users/Usuário/Documents/Codex/orca-worktrees/codex-setup-rules`; lifecycle via Orca orchestration, sem subworkers.

## Phase0: evidência somente leitura

- Godot real: `4.7.2.stable.official.ed1daf0bf`; projeto referencia `4.5`, GL Compatibility. Templates locais `4.7.2.stable`. Não importar/exportar este projeto: isso poderia gerar arquivos protegidos.
- `export_presets.cfg` contém Windows Desktop x86_64 e Web Alpha sem threads/extensions, staging, include online.cfg. `web/INICIAR.*`, `web/server.cjs` e documentação existentes são preservados; não duplicar publicação Web.
- `project.godot` ainda usa nome V0.30 e userdata de teste V026; `package.json` 0.31.0 descreve backend, não versão de distribuição. Nenhuma fonte central de release, launcher, instalador ou scripts mobile encontrada nas áreas de tooling consultadas.
- Branding existente: splash PNG, sem ícone oficial ICO/mobile declarado no projeto. Reutilização futura exige aprovação do ícone adequado; não fabricar oficialidade a partir do splash.
- .NET Framework 4 compiler `C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe` disponível; runtime .NET 8.0.13, sem SDK. Inno Setup/NSIS não encontrados nos caminhos padrão nem PATH; Android SDK/JDK/adb não no PATH. Windows sem Mac/Xcode.
- Não abrir secrets; nenhuma operação em Supabase/Render/Cloudflare, principal somente Git. Quota percentual não exposta pela API/CLI consultada; planejamento conservador e solicitação de status ao coordenador.

## Design e arquivos novos

`distribution/` é tooling isolado, não integrado a jogo/backend. `version.json` contém versão DEV experimental `0.0.0`, build monotônico 1, protocol/rules 0 como valores **não atribuídos para produção**. Canal DEV/BETA/STABLE e plataforma web/windows_site/windows_steam/android/ios. `schemas/` documenta contratos; validação runtime rejeita campos extras/duplicados e tipos inválidos. `src/Contracts.cs` é fonte de validação/versionamento/compatibilidade; `src/Updater.cs` instala Windows site; `src/Launcher.cs` UI WinForms; `src/Tool.cs` empacota e gera manifestos; `tests/` testa no Windows real. `build.ps1` usa somente compiler já instalado. Nenhuma dependência NuGet ou mudança de configuração Godot.

Contrato de compatibilidade isolado: MAINTENANCE primeiro, depois protocolo/regras incompatíveis, depois build mínimo, depois COMPATIBLE. Plataforma/canal não particionam matchmaking: a conta FRAIHA é primária, backend/progresso/entitlements autoritativos permanecem intactos; identificador de distribuição não comprova login. Compatibilidade crossplay depende do mesmo backend e protocolo/regras; sem integração de auth nesta fase.

Launcher DEV permite check/update/PLAY, progresso, erro/retry, notas textuais, path e canal fixado DEV. Feed mock HTTP somente `127.0.0.1`/`[::1]`; fora disso HTTPS e redirects sempre recusados. Mesmo HTTPS+SHA256 não autenticam manifesto hostil: instalação remota não DEV é bloqueada até trust anchor/signature. Nenhum comando/script/argumento/entrypoint remoto é permitido: somente `FRAIHA.exe` fixo, PCK `FRAIHA.pck`.

Pacote limitado: ZIP flat com exatamente dois arquivos, sem diretórios/extras/aliases/link/reparse, teto por arquivo/total/download e hash por pacote/arquivo. Validação integral precede criação do staging. Instalação usa diretórios imutáveis `versions/<version>-<build>`, staging privado e pointer substituído atomicamente; anterior preservado, falhas antes do commit conservam pointer. Reexecução após falha recupera sem reaproveitar diretório parcial. Rollback explícito só para versão previamente instalada; high-water mark impede downgrade via feed mesmo após rollback. Exclusão por lock entre launcher/update/PLAY e inspeção de processos; nenhum overwrite do jogo em execução. Reparse em cada componente local recusado. Defesa contra atacante concorrente do mesmo usuário não equivale a sandbox: race de junctions após checagem continua gate para produção, deve ser eliminada com handles Windows e ACLs antes de release.

## Riscos/gates e expansão

P0 primeiro: build/test Windows real e servidor TCP loopback; stub claramente separado de export Godot. Testar faults/hash/URLs/timeout/partial/traversal/locks/reparse/pointer/rollback e manifesto estrito. QA real do jogo/crossplay requer export aprovado fora desta tarefa. P1 apenas preparar documentação se compiler instalador ausente, não instalar toolchain. Android/iOS/Steam são readiness com fontes oficiais atuais e patch proposto, nunca aplicado aos arquivos protegidos. Web preserva pipeline/cache; não publicar.

Produção exige assinatura do manifesto com chave pública embutida, identidade/chave de release separada, expiração/replay protection, política de rotação/revogação, hashes assinados e testes de chave inválida; assinatura Authenticode de launcher/jogo/installer e reputação SmartScreen são ações humanas futuras. Self-update Phase2 usa helper assinado separado, lock/PID/wait, staged binary validado, rename/rollback e restart fixo; nunca sobrescrever launcher vivo. Não implementado nesta fase.

Release operacional: SOURCE → TESTS → VERSION → BUILD → PACKAGE → HASH → MANIFEST → QA → PUBLISH. PUBLISH não autorizado. Changelog inclui versão/build/data, breaking e mandatory. Este documento é design inicial; evidência final e diferenças ficam no handoff.

Implementação final acrescenta `src/LauncherFlow.cs` e opt-in `--auto-play` coordenando consulta→update quando necessário→PLAY, sem fallback após erro. Schemas/documentação/`dev-mock.ps1` novos; runtime do script separado bloqueado pela policy, AST validado. Suite final inclui UI manual/automática e 28 grupos Windows. Orphan após move é reaproveitado apenas após identidade integral do manifesto e hashes instalados coincidirem, sem overwrite. Installer template/preparação ficam separados; nenhuma configuração protegida aplicada.
