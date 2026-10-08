# Android 01 — Auditoria de porte (base R52f `12ec72a`)

Auditoria estática do cliente Godot para o **export nativo Android** (sem WebView/PWA).
Feita sobre R52e `a4586f4` e confirmada sobre R52f `12ec72a`: o R52f não toca nenhum arquivo citado abaixo
(diff `a4586f4..12ec72a` = club_home_entry, mobile_hub, home_fx, water_spirit, reload_diag, testes).

## Projeto

| Item | Valor real |
|---|---|
| Godot | 4.5.1.stable.official (`f62fdbde1`) — logs do PC e `Dockerfile` |
| Renderer | `gl_compatibility` (também `.mobile`) — mantido; Android usa OpenGL ES 3 |
| Cena inicial | `res://presentation_v019/stage.tscn` |
| Autoloads | nenhum |
| Stretch | `canvas_items` / `expand`, base 1920×1080 |
| Janela | `mode=4` (fullscreen exclusivo), `mode.web=0` |
| Orientação | **não definida** (padrão Godot = paisagem) → corrigido para `sensor` (6) |
| Voltar Android | padrão `quit_on_go_back=true` (fecha o app) → corrigido |
| Plugins / GDExtension / `.so` / `.dll` | nenhum |
| WASM / JS | só `web/engines/stockfish-19-lite-single.*` e `voice/AgoraRTC_*.js` (fora do APK) |
| Texturas VRAM | 50 `.import` com `compress/mode=2` → exigem `import_etc2_astc=true` |
| Ícone do projeto | **não definido** (APK usa ícone padrão do Godot) — decisão de branding |

## Dependências Web/plataforma

Classificações: COMPARTILHADA · WEB-ONLY COM GUARD CORRETO · WEB-ONLY SEM GUARD · PRECISA EQUIVALENTE ANDROID · NÃO NECESSÁRIA NO ANDROID · DECISÃO FUTURA

| Área / arquivo | Uso | Classificação | Ação Android 01 |
|---|---|---|---|
| `account/account_service.gd` | `window.location`, `sessionStorage`, redirect OAuth Google | WEB-ONLY COM GUARD CORRETO | nenhuma. Google no Android = DECISÃO FUTURA (Android 03) |
| `account/account_service.gd` `_notification` | FOCUS_IN/RESUMED → ping + reconecta se `socket == null` | COMPARTILHADA | ok. Revalidação/ressync em partida = Android 04 |
| `analysis/engine.gd` | Worker WASM (web) / `OS.execute_with_pipe` (desktop) | WEB-ONLY COM GUARD + DECISÃO FUTURA | guard: Android nunca procura nem executa binário → FALLBACK interno explícito |
| `analysis/export.gd` | `download_buffer` (web) / `user://` + `shell_show_in_file_manager` | COMPARTILHADA | ok (abrir pasta é no-op no Android) |
| `audio_v025/game_audio.gd` | música via `<audio>` HTML, `visibilitychange` | WEB-ONLY COM GUARD CORRETO | nenhuma (Android toca pelo AudioServer) |
| `bot/controller.gd` | threads só checadas na Web | COMPARTILHADA | ok (Android tem threads) |
| `cosmetics/theme_manager.gd` | `window.location.search` | WEB-ONLY COM GUARD CORRETO | nenhuma |
| `marcha/marcha_access.gd` | `localStorage` (cota diária, espelho local) | WEB-ONLY COM GUARD CORRETO | nenhuma (servidor é a autoridade) |
| `monetization/card_form_web.gd` | Mercado Pago cartão (DOM) | WEB-ONLY COM GUARD CORRETO | indisponível no Android |
| `monetization/payment_real_ui.gd` | clipboard JS / `DisplayServer.clipboard_set`; `OS.shell_open` | COMPARTILHADA (área protegida) | não tocado |
| `monetization/premium_hub.gd` `open_payment` | entrada única do checkout real (PIX/cartão) | **PRECISA BLOQUEIO NO ANDROID** | guard: aviso "INDISPONÍVEL NO ANDROID", sem criar pagamento |
| `online_v020/endpoint.gd` | `online.cfg` + `staging` feature | COMPARTILHADA | preset Android DEV usa `staging` (nunca produção por padrão) |
| `presentation_v019/stage.gd` | WM_CLOSE → quit; SAIR → site (web) | COMPARTILHADA | **Voltar Android** tratado (ver abaixo) |
| `profile/image_picker.gd` | `<input type=file>` (web) / `FileDialog` nativo | COMPARTILHADA | testar em aparelho (seletor nativo Android/SAF) |
| `ui_v022/fullscreen_control.gd` | Fullscreen API do navegador / `Window.mode` | WEB-ONLY COM GUARD CORRETO | nenhuma (Android já é fullscreen imersivo) |
| `ui_v022/mobile_layout.gd` `active()` | `has_feature("mobile")` → layout mobile | COMPARTILHADA | ok: Android entra no layout mobile |
| `ui_v022/mobile_layout.gd` `_css_size` | pixels CSS na Web; `window.size` (px físicos) no resto | **PRECISA EQUIVALENTE ANDROID** | converte px físicos → dp (dpi/160). Sem isso a UI fica ~2,6× menor num celular 420 dpi |
| `ui_v022/mobile_layout.gd` `safe_rect` | `env(safe-area-inset-*)` só na Web | **PRECISA EQUIVALENTE ANDROID** | usa `DisplayServer.get_display_safe_area()` (notch/cutout) |
| `ui_v022/web_text_field.gd` | `<input>` HTML sobreposto | WEB-ONLY COM GUARD CORRETO (`wanted()` exige web) | Android usa LineEdit + teclado virtual nativo |
| `ui_v022/main_hub.gd`, `mobile_hub.gd` | textos "Voltar para o site" | WEB-ONLY COM GUARD CORRETO | nenhuma |
| `voice/agora_voice_provider.gd` | Agora Web SDK | WEB-ONLY COM GUARD CORRETO (`not_web`) | Voice indisponível no Android (FRAIHA Voice Android = missão futura) |
| `tools/diag/reload_diag.js` | diagnóstico de reload (navegador) | NÃO NECESSÁRIA NO ANDROID | não vai para o APK |
| WebSocket (`WebSocketPeer`) | conta, Casual/Ranked, online legado | COMPARTILHADA | `wss://` (TLS). Android bloqueia cleartext; nenhum `ws://` em release |
| OAuth / Google | só redirect Web | DECISÃO FUTURA | Android 03 (deep link ou SDK; exige config Supabase/Google = efeito externo) |
| `navigator`, `clipboard`, `pagehide`, `Engine.has_singleton`, `has_feature("android")` | — | — | `pagehide`/singletons: não usados; `has_feature("android")` só nos guards novos |

Nenhum uso de `JavaScriptBridge` sem guard foi encontrado: no Android esses caminhos não executam.

## Lifecycle (auditoria)

- `account_service._notification`: FOCUS_IN/RESUMED → heartbeat imediato; reconecta se o socket caiu. **Não** revalida sessão
  nem ressincroniza partida explicitamente. Pontos futuros (Android 04): `account_service._notification`
  (revalidar token), Ranked/Casual (`ranked.in_match()`, `casual.in_match()` → pedir estado ao servidor), relógio vem do servidor.
- `mobile_layout._notification` FOCUS_IN → recalcula viewport/safe area (vale também para o Android).
- Sem tratamento de `NOTIFICATION_APPLICATION_PAUSED`: o Godot pausa o loop no background; o WebSocket pode morrer
  e a reconexão existente cobre o caso. Precisa de teste em aparelho (background durante partida, Wi-Fi ↔ dados).

## Decisões em aberto (não tomadas nesta missão)

- Stockfish Android: arquitetura (binário nativo / biblioteca / JNI / plugin). Hoje: FALLBACK interno, explícito.
- Package ID final da Play Store (DEV temporário: `com.fraiha.xadrez.dev`).
- Ícone/nome do app.
- Pagamentos Android (política Google Play × PIX/Mercado Pago).
- Google login Android (Android 03).
- "Toque Voltar de novo para sair" na Home: hoje o Voltar na Home não fecha o app (comportamento seguro); sair continua pelo botão SAIR.
