extends Node
## Tela cheia do FRAIHA (R29.2) — comportamento natural do navegador.
##   • Web: Fullscreen API na página inteira (documentElement: os campos HTML do login no celular ficam
##     no <body> e sumiriam atrás do canvas). O canvas ocupa 100% da viewport dentro E fora da tela cheia
##     (export: canvas_resize_policy=2), então sair nunca deixa o jogo pequeno.
##   • Botão de tela cheia ao lado do som (entra / sai).
##   • R35.1 · Esc NÃO tira da tela cheia: com a tela cheia ativa o jogo pede o Keyboard Lock do Esc
##     (Chrome/Edge/Opera). O Esc vira só do jogo (voltar, menu, sair da partida); para sair da tela
##     cheia: botão do jogo ou SEGURAR o Esc (o navegador avisa). Navegador sem Keyboard Lock
##     (Firefox/Safari): o Esc continua saindo da tela cheia e, nesse caso, não navega.
##   • R42.2: o jogo NUNCA entra em tela cheia sozinho — só pelo botão de expandir (o pedido automático
##     no 1º clique, do R29.2, foi desligado a pedido do dono; auto_on_first_gesture não é mais chamado).
##   • iPhone/Safari (sem a API para páginas): supported() = false e o botão some.
##   • Desktop (não Web): o botão alterna janela <-> tela cheia exclusiva (stage.toggle_fullscreen).
signal changed(on: bool)

const ESC_GRACE_MS := 600   # Esc que acabou de tirar da tela cheia não vira "voltar página"

## Estado no navegador (instalado uma vez): on/off, quando saiu, se o jogador já saiu ou alternou.
const JS_SETUP := """(() => { const w = window, d = document;
    if (w.__fraihaFs) return 1;
    w.__fraihaFs = { lastExit: 0, userLeft: false, autoDone: false, wasOn: false, escLocked: false };
    const on = () => { const fs = !!(d.fullscreenElement || d.webkitFullscreenElement);
        if (!fs && w.__fraihaFs.wasOn) { w.__fraihaFs.lastExit = Date.now(); w.__fraihaFs.userLeft = true; }
        w.__fraihaFs.wasOn = fs;
        const kb = navigator.keyboard;
        if (fs && kb && kb.lock) { kb.lock(['Escape']).then(() => { w.__fraihaFs.escLocked = true; }).catch(() => { w.__fraihaFs.escLocked = false; }); }
        if (!fs) { w.__fraihaFs.escLocked = false; if (kb && kb.unlock) { try { kb.unlock(); } catch (e) {} } } };
    d.addEventListener('fullscreenchange', on); d.addEventListener('webkitfullscreenchange', on);
    return 1; })()"""
const JS_SUPPORTED := "(() => { const e = document.documentElement; return !!((e.requestFullscreen || e.webkitRequestFullscreen) && (document.fullscreenEnabled !== false || document.webkitFullscreenEnabled)); })()"
const JS_IS_ON := "!!(document.fullscreenElement || document.webkitFullscreenElement)"
const JS_ENTER := """(() => { try { const d = document, e = d.documentElement;
    if (d.fullscreenElement || d.webkitFullscreenElement) return 'on';
    const f = e.requestFullscreen || e.webkitRequestFullscreen; if (!f) return 'unsupported';
    const r = f.call(e, { navigationUI: 'hide' }); if (r && r.catch) r.catch(() => {}); return 'requested';
    } catch (err) { return 'error'; } })()"""
const JS_EXIT := """(() => { try { const d = document;
    if (!(d.fullscreenElement || d.webkitFullscreenElement)) return 'off';
    const f = d.exitFullscreen || d.webkitExitFullscreen; if (!f) return 'unsupported';
    const r = f.call(d); if (r && r.catch) r.catch(() => {}); return 'exiting'; } catch (err) { return 'error'; } })()"""
## Auto-entrada única: só se o jogador ainda não saiu nem usou o botão nesta sessão.
const JS_AUTO := """(() => { const s = window.__fraihaFs; if (!s || s.autoDone || s.userLeft) return 'skip';
    s.autoDone = true; return 'go'; })()"""

var stage            # presentation_v019/stage.gd (só para o desktop)
var _web := false
var _supported := false
var _last_on := false
var _poll := 0.0

func _ready():
    _web = OS.has_feature("web")
    if _web:
        JavaScriptBridge.eval(JS_SETUP)
        _supported = bool(JavaScriptBridge.eval(JS_SUPPORTED))
    else:
        _supported = true   # desktop: janela <-> tela cheia exclusiva
    _last_on = is_on()
    set_process(true)

func supported() -> bool:
    return _supported

## Estado sem custo (atualizado a cada 0,2 s): para desenhar o ícone a cada frame.
func on_cached() -> bool:
    return _last_on

## R43 · ícone de tela cheia para botões desenhados à mão (MARCHA REAL / XEQUE): 4 cantos para fora
## (entrar) ou para dentro (sair) — o mesmo desenho do botão da Home (ui_v022/hud_button.gd).
static func draw_glyph(ci: CanvasItem, rect: Rect2, on: bool, col: Color, w := 3.0):
    var center := rect.get_center()
    var r := minf(rect.size.x, rect.size.y) * 0.30
    for dx in [-1, 1]:
        for dy in [-1, 1]:
            var corner: Vector2 = center + Vector2(dx, dy) * r
            var tip: Vector2 = corner if not on else center + Vector2(dx, dy) * r * 0.35
            var arm := r * 0.6
            var sx: float = -dx if not on else dx
            var sy: float = -dy if not on else dy
            ci.draw_line(tip, tip + Vector2(sx * arm, 0), col, w)
            ci.draw_line(tip, tip + Vector2(0, sy * arm), col, w)

func is_on() -> bool:
    if _web: return bool(JavaScriptBridge.eval(JS_IS_ON))
    var w := get_window()
    return w != null and w.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]

## Botão de tela cheia (gesto do usuário).
func toggle():
    if is_on(): exit()
    else: enter()

func enter():
    if _web:
        JavaScriptBridge.eval("window.__fraihaFs && (window.__fraihaFs.autoDone = true)")
        JavaScriptBridge.eval(JS_ENTER)
    elif stage != null and not is_on():
        stage.toggle_fullscreen()
    _poll = 0.0

func exit():
    if _web:
        JavaScriptBridge.eval(JS_EXIT)
    elif stage != null and is_on():
        stage.toggle_fullscreen()
    _poll = 0.0

## Esc deve ser só "sair da tela cheia"? (tela cheia ativa agora, ou acabou de sair por causa dele)
func esc_belongs_to_fullscreen() -> bool:
    if not _web: return false
    if esc_locked(): return false        # Keyboard Lock ativo: o Esc é do jogo
    if is_on(): return true
    var last := float(JavaScriptBridge.eval("(window.__fraihaFs && window.__fraihaFs.lastExit) || 0"))
    var now := float(JavaScriptBridge.eval("Date.now()"))
    return last > 0.0 and now - last < ESC_GRACE_MS

## R35.1 · Keyboard Lock do Esc ativo (tela cheia não sai com um toque no Esc).
func esc_locked() -> bool:
    return _web and bool(JavaScriptBridge.eval("!!(window.__fraihaFs && window.__fraihaFs.escLocked)"))

## 1º clique/toque da sessão: um único pedido. Depois que o jogador sai, nunca mais sozinho.
func auto_on_first_gesture(event: InputEvent):
    if not _web or not _supported: return
    var gesture: bool = (event is InputEventMouseButton and not event.pressed) or (event is InputEventScreenTouch and not event.pressed)
    if not gesture: return
    if str(JavaScriptBridge.eval(JS_AUTO)) == "go": JavaScriptBridge.eval(JS_ENTER)

## SAIR na Web: sai da tela cheia e volta para o site (a aba não foi aberta pelo jogo: nada de window.close()).
const SITE_URL := "https://fraihaxadrez.com/"
func leave_to_site():
    if not _web: return
    JavaScriptBridge.eval(JS_EXIT)
    JavaScriptBridge.eval("setTimeout(() => { window.location.assign(" + JSON.stringify(SITE_URL) + "); }, 120)")

func _process(delta):
    _poll -= delta
    if _poll > 0.0: return
    _poll = 0.2
    var on := is_on()
    if on != _last_on:
        _last_on = on
        changed.emit(on)
