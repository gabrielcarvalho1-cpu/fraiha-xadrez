# Distribution — readiness e propostas NÃO APLICADAS

Consulta oficial em 2026-10-06 UTC / 2026-10-05 São Paulo. Não são exports, autorização de publicação ou promessa de aprovação das lojas. Revalidar fontes na data da release e contra Godot real 4.7.2; documentação `stable` pode avançar. Não operar contas, comprar certificados, criar keystore ou instalar SDK nesta tarefa.

## P1 Windows installer

Inno Setup escolhido: roteiro pequeno já fornece shortcuts/uninstall e modo por usuário com `PrivilegesRequired=lowest`, sem elevação. [Inno privileges](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm), [modo não administrativo](https://jrsoftware.org/ishelp/topic_admininstallmode.htm). NSIS também é scriptável, mas exige maior construção explícita de fluxo/remoção; WiX modela Windows Installer com toolchain adicional, desnecessário ao DEV atual. [NSIS oficial](https://nsis.sourceforge.io/Docs/Chapter4.html), [WiX oficial](https://docs.firegiant.com/wix/).

`distribution/installer/FRAIHA-DEV.iss` é template não compilado: Inno/NSIS ausentes no inventário local, nenhuma instalação de toolchain realizada. Nome FRAIHA DEV, publisher legal e ICO oficial são parâmetros humanos obrigatórios; há somente splash PNG, portanto não foi fingido ícone oficial. Per-user `{localappdata}\Programs\FRAIHA-DEV`, shortcut menu e desktop opcional, uninstall do binário/shortcuts preparado. Payloads baixados não são removidos recursivamente pelo template: implementar remoção confinada com handles Windows e teste contra junction antes de considerar uninstall completo.

QA futuro: instalar em usuário nãoadmin/VM isolada, iniciar feed DEV, abrir launcher, check/update/stub PLAY, fechar processos, uninstall, conferir atalhos/binários/payloads e preservação userdata. **Não executado** por compiler ausente. Assinaturas Authenticode do installer/launcher/jogo, timestamp e reputação SmartScreen são gates de release humana; nada comprado/assinado. Self-update é Phase2 do documento de arquitetura, não parte deste installer.

## P2 Android .aab

Godot recomenda OpenJDK 17 e SDK configurado; AAB requer Gradle, assinatura de release externa e ícones próprios. SDK/JDK/adb não encontrados no PATH; templates 4.7.2 presentes não comprovam toolchain Android funcional. [Godot Android](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html). Em 2026-10-06, novas versões Play precisam target Android 16/API 36 desde 31/08/2026, enquanto receita `stable` consultada ainda lista platform/build-tools 35: **não copiar SDK35 como compliance**. Resolver combinação Godot4.7.2/Gradle/SDK36 validada antes da AAB. [Play target atual](https://developer.android.com/google/play/requirements/target-sdk). Apps nativos precisam validar suporte 16 KiB de páginas e suas bibliotecas para Android15+; não inferir pela presença do template. [Android 16 KiB](https://developer.android.com/guide/practices/page-sizes).

Proposta de identidade **não registrada** `com.fraiha.xadrez.dev`; produção `com.fraiha.xadrez` depende de titularidade/colisão e decisão humana. `version/code=build_number` monotônico (limite central 2100000000), `version/name=game_version`; protocol/rules não são versões da loja. DEV0.0.0 não é release aprovada. Play signing/upload key e conta são externos; nenhuma keystore criada.

Proposta exata de novo bloco `export_presets.cfg`, para revisão futura, **NÃO APLICAR agora**. IDs de preset devem ser recalculados no mainline; nomes de opções conferidos na [classe export Android](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformandroid.html); enum AAB e defaults de min SDK precisam confirmar no editor 4.7.2 antes da export real.

```ini
[preset.2]
name="Android DEV AAB"
platform="Android"
runnable=true
custom_features="DEV,android"
export_filter="all_resources"
include_filter="online.cfg"
exclude_filter="tests/*,docs/*,tools/*,web/*,distribution/*"
export_path=""
[preset.2.options]
gradle_build/use_gradle_build=true
gradle_build/export_format=1
gradle_build/target_sdk="36"
architectures/arm64-v8a=true
package/unique_name="com.fraiha.xadrez.dev"
package/name="FRAIHA DEV"
version/code=1
version/name="0.0.0"
permissions/internet=true
permissions/record_audio=false
permissions/read_external_storage=false
permissions/write_external_storage=false
```

Ícones: paths só após arte oficial adequada existir; não apontar splash como ícone. Orientation: preservar landscape e homologar retrato/tablets antes de autorizar mudança `display/window/handheld/orientation`; touch, teclado, scroll, escala e safe areas precisam QA real. WSS/TLS para backend; sem broad cleartext exception. Dados/cache privados do app, sem storage amplo; áudio output atual, futura mic apenas com requisito de produto/consentimento/permissão runtime e Privacy/Data Safety revisados. Não tocar Voice agora. Pause/resume, screenlock, rede trocada/offline, morte do processo/relogin/reconnect e audio focus precisam testes reais; nenhum fluxo foi alterado. Play gerencia binários; Windows updater jamais entra na AAB.

## P3 iOS/iPadOS

**BLOQUEADO POR REQUISITO EXTERNO**: export requer macOS/Xcode e templates; App Store Team ID e bundle ID devem ser reais e provisionados. Windows não assina a entrega final. [Godot iOS](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html). Desde 28/04/2026, envio App Store Connect exige Xcode26+ e SDK iOS/iPadOS26+, além de questionário de classificação atualizado; não confundir versão mínima do SDK de build com deployment target suportado. [Apple requisitos atuais](https://developer.apple.com/news/upcoming-requirements/).

Proposta futura `com.fraiha.xadrez.dev` e production `com.fraiha.xadrez`, sujeita a titularidade. `application/short_version=game_version`, `application/version` derivada do build monotônico em formato aceito pelo exporter/CFBundleVersion (proposta `1.0.0` para DEV build1; futura fórmula `<build>.0.0` validar limites Apple). Não duplicar versão manual em pipeline. [Godot iOS opções](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformios.html).

Bloco proposto NÃO APLICADO, ainda incompleto por identidade/arte/signing externos:

```ini
[preset.3]
name="iOS DEV"
platform="iOS"
runnable=true
custom_features="DEV,ios"
export_filter="all_resources"
include_filter="online.cfg"
exclude_filter="tests/*,docs/*,tools/*,web/*,distribution/*"
export_path=""
[preset.3.options]
application/bundle_identifier="com.fraiha.xadrez.dev"
application/short_version="0.0.0"
application/version="1.0.0"
architectures/arm64=true
entitlements/game_center=false
privacy/tracking_enabled=false
```

Team ID/provisioning/certs/ícones/capabilities não preenchidos. TLS/WSS sem relaxar ATS globalmente. Future mic exigirá purpose string `privacy/microphone_usage_description`, autorização runtime e revisão de coleta, não adicionada agora. Sem background audio, Game Center ou capacidades extras sem necessidade. iPhone/iPad: safe areas, notch, landscape/retrato/tablet, keyboard, gesture bars, pause/resume, scene/session lifecycle, reconnect e audio interruption são planos não executados. AppleDeveloper/certs/perfis, Mac/Xcode, dispositivo, TestFlight e review AppStore são ações humanas futuras; nenhuma conta/custo/envio. Não existe binary updater iOS.

## Web e config Godot protegida

Preservar pipeline Web Alpha staging existente e seu cache/headers/WASM/PCK/engine assets. Não substituir scripts/export/deploy. Futuro release metadata usa central game/build/protocol/rules/canal e platform=web; versionar URLs do conjunto exportado, publicar manifesto/cache policy coerentes e evitar index novo com PCK velho. QA service worker/cache offline se futuramente habilitado; atualmente PWA disabled no preset. Nada publicado.

Proposta futura `project.godot [application] config/version="0.0.0"` **somente DEV**; `config/custom_user_dir_name` está hoje como teste V026 e só pode mudar após plano de migração local para preservar userdata. Proposta Windows Desktop `custom_features="DEV,windows_site"`, exclusion de `distribution/*` somada às exclusões atuais; `application/product_name`, `application/company_name`, `application/product_version` e `application/icon` após publisher/arte aprovados. Preset Steam separado com platform feature `windows_steam`. Nenhum desses arquivos alterado. Não gerar uid/import.

## Paths e propriedade

| Plataforma | App/binários | userdata/config | cache/download/log/temp | Dono das atualizações |
|---|---|---|---|---|
| Windows site DEV implementado | launcher `.local/bin`; game `dev-install/versions` | userdata Godot atual preservado; config UI não persistida | temp privado do updater; fixtures `.local/qa-*`; logs persistentes não implementados | launcher DEV, produção bloqueada |
| Windows site produção proposto | LocalAppData/Programs/FRAIHA | LocalAppData/FRAIHA userdata/config, adaptar Godot sem perder dados | LocalAppData/FRAIHA/cache/downloads/logs/temp separados do binário | launcher assinado |
| Steam proposto | Steam library app/depot | userdata Godot fora do depot; sem Steam Cloud | app-local cache/log/temp fora do conteúdo gerido Steam | Steam |
| Android proposto | instalação Play | armazenamento app-private/Godot user:// | diretórios privados cache/files/temp | Play |
| iOS proposto | bundle read-only | sandbox Application Support/config; política backup | Library/Caches/tmp; logs sem tokens | App Store/TestFlight |
| Web preservado | export hospedado | storage do navegador por origem, servidor autoritativo | caches do navegador; logs sem secrets | deploy/cache Web existente |

Conta FRAIHA permanece primária; plataforma é somente distribuição, nunca prova de auth, partição de matchmaking ou entitlement. Progress/server e monetization/payments intocados. Futuro pagamento digital deve reconciliar recibos verificados no servidor com entitlement FRAIHA idempotente, conforme regras/território da loja, sem confiar flags do launcher. [Play pagamentos](https://support.google.com/googleplay/android-developer/answer/9858738), [Apple review §3.1](https://developer.apple.com/app-store/review/guidelines/), [Steam microtransactions](https://partner.steamgames.com/doc/features/microtransactions). Sem implementação/edição de pagamentos, compra ou ligação SteamID nesta tarefa.
