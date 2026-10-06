extends Node
## R45 · GATE Web real (Chromium): FRAIHA Voice com o provedor AGORA de verdade (ponte JS + SDK 4.24.8
## servido da pasta voice/). Microfone FALSO do Chromium. O servidor do jogo é simulado aqui (conta
## falsa); credenciais Agora são fictícias, então o join TEM que falhar de forma limpa (sem rede/token
## inválido) e nada pode ficar preso. RTC real entre 2 pessoas: só com credenciais (ver docs/voice).
## Roda como cena principal numa CÓPIA de QA da build (nunca no produto).
var checks := 0
var failures := 0

class FakeAccount extends Node:
    signal server_message(msg: Dictionary)
    signal changed
    var sent: Array = []
    func has_profile() -> bool: return true
    func account_pending() -> bool: return false
    func send_server(m: Dictionary) -> bool:
        sent.append(m.duplicate())
        return true

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("GATE PASS " if ok else "GATE FAIL ") + label)

func secs(s: float):
    await get_tree().create_timer(s).timeout

func wait_until(cond: Callable, s: float) -> bool:
    var end := Time.get_ticks_msec() + int(s * 1000)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await get_tree().process_frame
    return cond.call()

func dbg() -> Dictionary:
    var raw = JavaScriptBridge.eval("window.FraihaVoiceBridge ? window.FraihaVoiceBridge.debug() : '{}'")
    var d = JSON.parse_string(String(raw)) if raw != null else {}
    return d if d is Dictionary else {}

func _ready():
    call_deferred("run")

func run():
    var mode := String(JavaScriptBridge.eval("new URLSearchParams(location.search).get('mode') || 'grant'"))
    var acc := FakeAccount.new()
    add_child(acc)
    var v = load("res://voice/fraiha_voice.gd").new()
    add_child(v)
    v.setup(acc)
    check(v.available(), "navegador com suporte (localhost = contexto seguro, getUserMedia, WebRTC)")
    v.enter_match("ranked", "11111111-2222-4333-8444-555555555555")
    v.press()
    check(v.state == "REQUESTING_PERMISSION", "toque: pedindo microfone (%s)" % v.state)
    v.press()
    if mode == "deny":
        check(await wait_until(func(): return v.state == "ERROR", 30.0), "permissão negada: ERRO (%s)" % v.message)
        check("bloqueado" in v.message or "microfone" in v.message.to_lower(), "mensagem clara: " + v.message)
        check(acc.sent.is_empty(), "sem permissão: nenhum token pedido")
        await secs(0.5)
        var d0 := dbg()
        check(not bool(d0.get("mic", true)) and not bool(d0.get("joined", true)), "nada preso no navegador: %s" % str(d0))
        print("GATE RESULT %d/%d %s" % [checks - failures, checks, "OK" if failures == 0 else "FALHAS=%d" % failures])
        return
    check(await wait_until(func(): return v.state == "CONNECTING", 30.0), "SDK carregado + permissão + microfone: CONNECTING (%s %s)" % [v.state, v.message])
    check(acc.sent.size() == 1 and String(acc.sent[0].type) == "voice_join", "pedido de token ao servidor DEPOIS do microfone (1 só, mesmo com 2 toques)")
    var d1 := dbg()
    check(bool(d1.get("sdk", false)) and bool(d1.get("mic", false)), "SDK Agora presente e trilha do microfone criada: %s" % str(d1))
    var ver = JavaScriptBridge.eval("window.AgoraRTC ? AgoraRTC.VERSION : ''")
    check(String(ver) == "4.24.8", "versão do SDK carregada: %s" % str(ver))
    # servidor (simulado) concede um token — credencial fictícia: a Agora tem que recusar/não alcançar
    acc.server_message.emit({"type": "voice_granted", "renew": false, "match_id": "11111111-2222-4333-8444-555555555555", "kind": "ranked",
        "app_id": "0123456789abcdef0123456789abcdef", "channel": "fx_ranked_11111111-2222-4333-8444-555555555555", "uid": 1,
        "token": "007eJxTYLhWtSNm+d+HX2esVynODip5kOPpLM3Pm7B4reatxtP", "ttl": 600, "participants": [{"uid": 1, "name": "Gate"}, {"uid": 2, "name": "Outro"}]})
    check(await wait_until(func(): return v.state != "CONNECTING", 40.0), "join terminou (sem ficar preso em CONECTANDO): %s" % v.state)
    check(v.state == "ERROR" and v.message != "", "credencial fictícia: ERRO limpo na voz (%s)" % v.message)
    await secs(1.0)
    var d2 := dbg()
    check(not bool(d2.get("joined", true)) and not bool(d2.get("mic", true)) and not bool(d2.get("published", true)), "cleanup: fora do canal, microfone fechado: %s" % str(d2))
    # nova tentativa e saída no meio (idempotência / sem trilha órfã)
    v.press()
    await wait_until(func(): return v.state == "CONNECTING", 20.0)
    v.exit_match("match_end")
    await secs(1.0)
    var d3 := dbg()
    check(v.state == "DISCONNECTED" and not bool(d3.get("mic", true)) and not bool(d3.get("joined", true)), "fim da partida no meio da conexão: tudo limpo %s" % str(d3))
    check(String(acc.sent[-1].type) == "voice_leave", "servidor avisado da saída")
    print("GATE RESULT %d/%d %s" % [checks - failures, checks, "OK" if failures == 0 else "FALHAS=%d" % failures])
