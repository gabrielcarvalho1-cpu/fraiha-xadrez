# Distribution v1 — QA executada

## Atualização v1.1: código final de 2026-10-06

`./distribution/build.ps1 -Test -RealTest` passou no código do commit `000b836904c82cf98fa5ea694ae81125e5e4187a`: **29 grupos mock/segurança, 0 falhas**, mais aceitação real independente com duas builds históricas FRAIHA V029/V030. Mock suite: `distribution/.local/qa-20261006-033720-6f59f496b5644adfb95e7f71c9c0f370/results.txt`; real: `distribution/.local/rqa-033737641/results.txt`. O feed TCP é simulado somente como transporte HTTP loopback; o payload real não é stub.

Novo grupo v2 comprova quatro nomes/hashes fixos, sidecar/readme adulterados, hashes individuais inválidos, campos ausentes/limites, nomes traversal/absolute/ADS/aliases, source com DLL extra rejeitado, real opt-in recusando stub/export desconhecido, profile com junction/sessão rejeitado e enumeração segura de cache >260 caracteres. Os casos originais traversal/symlink/reparse/partial/timeout/channel/downgrade/schema/race-lock/fault continuam passando; race atacante mesmo usuário continua gate de produção.

Aceitação real: install A=V029, launcher WinForms consulta manifesto B=V030, baixa pacote inteiro/hash, instala e muda pointer; startup GUI/viewport Home real A/B; update bloqueado com jogo aberto; rollback; pacote/hash inválido preserva A; download parcial/retry; A abre após rollback/falha; manifesto inválido/redirect/endpoint loopback offline recusado sem auto-PLAY de estado antigo; sidecar tamper bloqueia PLAY; staging limpo; userdata isolada sem arquivos de sessão/reparse. A→B→A reutiliza cache populado e passou com suporte a long paths. Build DEV3 usa novamente o mesmo PCK V030, não é terceira build real.

`game-A.png`, `game-B.png`, `game-A-after-failure-rollback.png`, `launcher-real.png` finais foram inspecionados: Home/menu completo e UI legível. Captura de 12 frames do viewport usa flags fixas locais do harness, confirmadas no `--help` do export. Adicionalmente, o binário `Launcher.exe` normal copiado para `.local/g033850/` fez `--dev-real-offline --auto-play` e abriu V030 sem movie/fixed-fps: HWND/title, PID/path, pointer e log `normal-game.log` comprovados. Fechamento por janela/Enter funcionou; não houve fallback de kill nesse run final.

Falhas preservadas: consulta ExitCode por Process enumerado; captura prematura inválida de desktop (não usar/publicar); foreground lock; assert excessivo de qualquer CFG quando o core cria `visual_theme.cfg`; shader cache em paths longos; PowerShell Tee com stderr do Godot convertido em NativeCommandError; switches .NET sem prefixo nativo insuficientes. Correções mantiveram verificações de sessão/junction e o teste >260. Runs históricos falhos não são o resultado final.

Limitações reais: TCP IPv4/IPv6 amostrado somente no startup, sem cobertura UDP/intervalos; offline vale apenas para hashes e resolver de endpoint revisados. Fontes declarados no README foram lidos via Git, mas não reconstruímos PCK determinístico para provar correspondência byte a byte. Warn ObjectDB/resource ainda em uso aparece ao sair no modo movie, com exit0; isso requer Claude/core, não foi suprimido nem corrigido aqui. Shader initialize errors vistos no root longo desapareceram no root curto final; não certificar long paths arbitrários do Godot. Nenhum gameplay/auth/serviço/crossplay foi testado. Installer/uninstall continuam sem runtime; ver review02. Produção continua bloqueada por trust/signature/TOCTOU e gates do handoff02.

## Checkpoint v1 histórico

As seções abaixo preservam o resultado anterior; suas listas de não execução são históricas, atualizadas acima para Windows real.

2026-10-06 UTC, Windows real, .NET Framework compiler instalado, nenhum NuGet/SDK novo. Comando `./distribution/build.ps1 -Test`: **28 grupos passaram, 0 falharam** no run final `distribution/.local/qa-20261006-014346-2fe4f59412d140f09ed52981e0814c52/results.txt`. Suite cria TCP loopback na porta efêmera, processos C# stub e junctions Windows reais; **não** é QA do jogo Godot nem teste de crossplay. PNG de UI em cada run de sucesso, render WinForms inspecionado; controles legíveis, check/update/PLAY/error/retry reais e janelas fechadas.

| Grupo | Evidência/resultado |
|---|---|
| Fonte versão/schema | DEV0.0.0-1 explícita lida do arquivo central; tipos/limites validados |
| Ordem versão | same build/lower build/lower game version/canal/plataforma rejeitados; higher validado |
| Compatibilidade | quatro outcomes e precedência; cinco plataformas sem partição; contrato isolado |
| JSON estrito | duplicate literal/alias unicode, missing/extra, command, não inteiro, overflow/null/nested/trailing inválidos |
| URL | HTTPS reconhecido; HTTP só literal loopback opt-in; localhost/127.1/credenciais/fragment/query/dotdot/backslash/%/scheme inválidos |
| Clean install/upgrades | progresso byte-a-byte; checks/hash/novo/same/lower/rollback/high-water |
| Production trust | HTTPS/BETA/STABLE instalação falha fechado sem signature/trust anchor |
| Manifest | schema/platform/hash/size/date/entrypoint inválidos recusados; retry hash válido |
| Download partial | truncamento socket preserva anterior, remove staging; retry sucesso |
| Download corrupt | SHA pacote recusa bytes corrompidos; cleanup/retry |
| Redirect | 302 recusado, sem seguir destino; cleanup/retry |
| Size | HTTP tamanho excedido rejeitado; cleanup/retry |
| Timeout | read/response timeout mock com deadline curto, cleanup/retry; limites default 5s I/O e 60s total |
| Fault before-download | IOException simulada, pointer anterior intacto, retry |
| Fault after-download | idem e cleanup |
| Fault after-extract | idem e cleanup |
| Fault before-move | idem e cleanup |
| Fault after-move | órfão íntegro verificado no retry, commit pointer; rollback |
| Fault before-pointer | state.next recuperável, anterior preservado, retry/rollback |
| Archive | caminhos abs/dotdot/backslash/%/case/ADS/extras/duplicates, Unix symlink/Windows reparse/directory recusados, hash arquivo validado; fixtures mantêm outros tamanhos válidos |
| Locks/process | lock exclusivo real, PLAY exe fixo cria marker stub, bloqueio durante jogo e processo externo |
| Junction | root/versions/payload/pointer reais rejeitados; sem writes através do alvo |
| Tamper installed | hash/tamanho adulterado impede PLAY/rollback |
| IPv6 roundtrip | URL literal preservada pelo serializer, loopback mantido |
| Auto pipeline | check→install/new/same skip→PLAY; lower rejeitado, sem fallback |
| Auto falhas | UTF-8 inválido/hash incorreto/conflicting same release não iniciam jogo |
| Auto UI startup | WinForms inicia check/update e stub após sucesso |
| UI manual | clicks check/update/PLAY/error/retry e render bitmap |

Falhas iniciais não foram ocultadas: compiler flags/catch order corrigidos; .NET Framework expande host IPv6, então política valida autoridade literal antes da normalização e serializa OriginalString; decoder UTF-8 inválido virou InvalidDataException; harness UI agora bombeia Shown antes de avaliar conclusão, sem aumentar deadline/remover assert. Último run acima valida código final, inclusive fixtures ZIP com tamanhos válidos para alcançar o gate correto. Nenhum teste foi ignorado.

Adicional: CLI `validate-version` passou; ambos schemas parseados; `dev-mock.ps1` AST PowerShell passou. **Runtime do script standalone não executado**: automatic approval policy rejeitou comando de smoke com Start-Process hidden PowerShell, download/hash e stop do helper, razão somente `blocked by policy`. Não houve bypass/retry equivalente. Isso não invalida mocks TCP da suite executada nem permite afirmar que o script standalone funciona.

Não executados: power loss físico, disk-full físico (faults foram simulados), NTFS durability sob perda de energia, race de junction concorrente mesmo-usuário, archive fuzzing completo, Authenticode/manifest signature, installer install/update/uninstall, export/launch do jogo Godot, Android AAB/device, iOS/Mac/TestFlight, Steam client install, navegador/export Web/crossplay, backend/session/entitlement. Produção bloqueada por esses gates pertinentes; DEV local não deve ser distribuído como release segura.

## Crossplay futuro — plano, não evidência

Todos abaixo **NÃO EXECUTADOS**; teste de CompatibilityContract com platform enums não demonstra crossplay. Cada par precisa build homologada, mesmo backend aprovado, protocol/rules compatíveis, conta FRAIHA; testar entrada/sala/movimentos/reconnect/pause/resultados/progresso autoritativos em tarefa autorizada, sem engine durante PvP humano. Nenhuma mudança nessas áreas agora.

| Par | Estado |
|---|---|
| Web–Web | NÃO EXECUTADO |
| Web–Windows | NÃO EXECUTADO |
| Site–Steam | NÃO EXECUTADO |
| Steam–Android | NÃO EXECUTADO |
| Steam–iOS | NÃO EXECUTADO |
| Android–iOS | NÃO EXECUTADO |
| Windows–Android | NÃO EXECUTADO |
| Windows–iOS | NÃO EXECUTADO |

## Release ledger modelo

`SOURCE SHA → TESTS evidência → VERSION game/build/protocol/rules/channel/platform → BUILD toolchain/templates/export settings aprovados → PACKAGE completo → HASH → MANIFEST assinado → QA artefato exato → PUBLISH humano`. BuildID Steam/versionCode Android/CFBundleVersion iOS são mapeamentos da mesma fonte, não substitutos de protocol/rules. `mandatory` no manifesto é metadata nesta fase, não enforcement do backend. Changelog a preencher antes de release: game_version, build_number, data UTC, breaking changes, atualização obrigatória sim/não, platform/channel, source SHA, hashes, QA e responsáveis; não inventar release de produção.
