extends "res://voice/voice_provider.gd"
## FRAIHA Voice · provedor Agora (só Web). Carrega voice/fraiha-voice-bridge-v1.js (que carrega o SDK
## voice/AgoraRTC_N-4.24.8.js só quando o jogador toca no microfone) e conversa por JavaScriptBridge.
## Eventos chegam como UMA string JSON por chamada (o JavaScriptBridge só passa tipos simples).
## Nunca escreve token em log.
const BRIDGE_URL := "voice/fraiha-voice-bridge-v1.js"
const LOAD_TIMEOUT := 15.0

var _cb = null
var _ready := false
var _loading := false
var _wait := 0.0
var _queue: Array = []   # chamadas feitas antes da ponte carregar

func unsupported_reason() -> String:
    if not OS.has_feature("web"): return "not_web"
    var raw = JavaScriptBridge.eval("""(() => { try {
        if (!window.isSecureContext) return 'insecure';
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return 'no_media';
        if (!window.RTCPeerConnection) return 'no_webrtc';
        return '';
    } catch (e) { return 'no_media'; } })()""")
    return String(raw) if raw != null else "no_media"

func _ensure_bridge() -> void:
    if _ready or _loading: return
    _loading = true
    _wait = 0.0
    if _cb == null:
        _cb = JavaScriptBridge.create_callback(_on_js)
        JavaScriptBridge.get_interface("window").set("FraihaVoiceCb", _cb)
    JavaScriptBridge.eval("""(() => {
        if (window.FraihaVoiceBridge || document.getElementById('fraiha-voice-bridge')) return 1;
        const s = document.createElement('script');
        s.id = 'fraiha-voice-bridge'; s.src = %s; s.async = true;
        s.onerror = () => { window.__fraihaVoiceBridgeFailed = 1; };
        document.head.appendChild(s); return 1; })()""" % JSON.stringify(BRIDGE_URL))
    set_process(true)

func _process(delta):
    if not _loading: return
    _wait += delta
    var ok = JavaScriptBridge.eval("window.FraihaVoiceBridge ? window.FraihaVoiceBridge.bind() : (window.__fraihaVoiceBridgeFailed ? -1 : 0)")
    var n := int(ok) if (ok is int or ok is float) else 0
    if n == 1:
        _loading = false
        _ready = true
        set_process(false)
        var q := _queue.duplicate()
        _queue.clear()
        for js in q: JavaScriptBridge.eval(js)
    elif n == -1 or _wait > LOAD_TIMEOUT:
        _loading = false
        set_process(false)
        _queue.clear()
        JavaScriptBridge.eval("window.__fraihaVoiceBridgeFailed = 0; var e = document.getElementById('fraiha-voice-bridge'); if (e) e.remove();")
        event.emit({"ev": "error", "seq": -1, "stage": "sdk", "code": "BRIDGE_LOAD"})

func _call(js: String) -> void:
    if _ready:
        JavaScriptBridge.eval(js)
        return
    _queue.append(js)
    _ensure_bridge()

func _enter_tree():
    set_process(false)

func prepare(seq: int) -> void:
    _call("window.FraihaVoiceBridge.prepare(%d)" % seq)

func join(seq: int, cfg: Dictionary) -> void:
    _call("window.FraihaVoiceBridge.join(%d, %s)" % [seq, JSON.stringify(JSON.stringify(cfg))])

func leave(seq: int, reason := "") -> void:
    if not _ready and not _loading: return   # nunca carregou: não há nada para desfazer
    if not _ready: _queue.clear()
    _call("window.FraihaVoiceBridge.leave(%d, %s)" % [seq, JSON.stringify(reason)])

func set_muted(on: bool) -> void:
    if _ready: JavaScriptBridge.eval("window.FraihaVoiceBridge.setMuted(%s)" % ("true" if on else "false"))

func renew(token: String) -> void:
    if _ready: JavaScriptBridge.eval("window.FraihaVoiceBridge.renew(%s)" % JSON.stringify(token))

func _on_js(args: Array):
    if args.is_empty(): return
    var d = JSON.parse_string(str(args[0]))
    if d is Dictionary:
        if d.has("seq"): d["seq"] = int(d["seq"])
        event.emit(d)
