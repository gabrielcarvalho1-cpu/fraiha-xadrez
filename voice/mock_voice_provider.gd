extends "res://voice/voice_provider.gd"
## FRAIHA Voice · provedor de TESTE (headless): registra chamadas e deixa o teste disparar eventos.
var calls: Array = []
var reason := ""
var auto := true          # responde sozinho como um provedor que dá certo
var fail_prepare := ""    # código de erro para simular (ex.: "PERMISSION_DENIED")
var fail_join := ""
var remote: Array = []

func unsupported_reason() -> String: return reason
func prepare(seq: int) -> void:
    calls.append(["prepare", seq])
    if not auto: return
    event.emit({"ev": "permission", "seq": seq})
    if fail_prepare != "": event.emit({"ev": "error", "seq": seq, "stage": "mic", "code": fail_prepare})
    else: event.emit({"ev": "mic_ready", "seq": seq})
func join(seq: int, cfg: Dictionary) -> void:
    calls.append(["join", seq, cfg.duplicate()])
    if not auto: return
    if fail_join != "": event.emit({"ev": "error", "seq": seq, "stage": "join", "code": fail_join})
    else: event.emit({"ev": "joined", "seq": seq, "muted": bool(cfg.get("muted", false)), "uids": remote})
func leave(seq: int, why := "") -> void:
    calls.append(["leave", seq, why])
    if auto: event.emit({"ev": "left", "seq": seq, "reason": why})
func set_muted(on: bool) -> void:
    calls.append(["mute", on])
    if auto: event.emit({"ev": "muted", "muted": on})
func renew(token: String) -> void:
    calls.append(["renew", token.length()])
func fire(d: Dictionary) -> void:
    event.emit(d)
func names() -> Array:
    return calls.map(func(c): return c[0])
