extends SceneTree
## R45 · FRAIHA Voice — máquina de estados do cliente (headless, provedor MOCK, conta falsa).
## Rodar: godot --headless --path . -s tests/voice_client_test.gd
var failures := 0
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")

class FakeAccount extends Node:
    signal server_message(msg: Dictionary)
    signal changed
    var sent: Array = []
    var profile_ok := true
    var socket_ok := true
    func has_profile() -> bool: return profile_ok
    func account_pending() -> bool: return false
    func send_server(m: Dictionary) -> bool:
        if not socket_ok: return false
        sent.append(m.duplicate())
        return true
    func types() -> Array: return sent.map(func(m): return String(m.type))

const MID := "11111111-2222-4333-8444-555555555555"
var acc: FakeAccount
var mock
var v

func fresh(reason := "") -> void:
    if v != null: v.free()
    if acc != null: acc.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path("user://voice.cfg"))
    acc = FakeAccount.new()
    root.add_child(acc)
    mock = load("res://voice/mock_voice_provider.gd").new()
    mock.reason = reason
    v = load("res://voice/fraiha_voice.gd").new()
    v.provider = mock
    root.add_child(v)
    v.setup(acc)

func grant(renew := false, uid := 1, mid := MID):
    acc.server_message.emit({"type": "voice_granted", "renew": renew, "match_id": mid, "kind": "ranked", "app_id": "a".repeat(32),
        "channel": "fx_ranked_" + mid, "uid": uid, "token": "007tok", "ttl": 600,
        "participants": [{"uid": 1, "name": "Ana"}, {"uid": 2, "name": "Beto"}]})

func run():
    # 1) fora de partida: nada acontece no provedor
    fresh()
    v.press()
    check(v.state == "ERROR" and mock.calls.is_empty(), "fora de PvP: microfone não liga (sem chamar o provedor)")
    # 2) navegador/aparelho sem suporte
    fresh("not_web")
    v.enter_match("ranked", MID)
    check(not v.available(), "desktop nativo: voz indisponível (botão some)")
    v.press()
    check(v.state == "ERROR" and mock.calls.is_empty(), "sem suporte: erro claro, nada de RTC")
    # 3) fluxo feliz: permissão -> token -> join -> publish
    fresh()
    v.enter_match("ranked", MID)
    check(v.state == "DISCONNECTED" and v.in_match(), "entrou na partida: voz DESLIGADA até o jogador tocar (sem gastar minutos)")
    v.press()
    check(mock.names() == ["prepare"], "1º passo: microfone/permissão ANTES do token")
    check(v.state == "CONNECTING" and acc.types() == ["voice_join"], "depois da permissão: pede token ao servidor")
    check(String(acc.sent[0].match_id) == MID and String(acc.sent[0].kind) == "ranked", "pedido com match_id e modo")
    v.press(); v.join()
    check(mock.names() == ["prepare"] and acc.sent.size() == 1, "toques repetidos enquanto conecta: sem join duplicado")
    grant(false, 2, "99999999-0000-4000-8000-000000000000")
    check(mock.names() == ["prepare"], "token de OUTRA partida: ignorado")
    grant(false, 2)
    check(mock.names() == ["prepare", "join"], "token certo: entra no canal")
    var cfg: Dictionary = mock.calls[1][2]
    check(int(cfg.uid) == 2 and String(cfg.token) == "007tok" and String(cfg.channel) == "fx_ranked_" + MID and not bool(cfg.muted), "join com canal/uid/token do servidor")
    check(v.state == "CONNECTED", "CONNECTED")
    grant(false, 2)
    check(mock.names().count("join") == 1, "token repetido: não entra duas vezes")
    # participantes
    mock.fire({"ev": "remote", "seq": v._seq, "uids": [1]})
    check(v.remote == [1] and "Ana" in v.status_text(), "quem está na sala: " + v.status_text())
    mock.fire({"ev": "speaking", "seq": v._seq, "uids": [0, 1]})
    check(v.is_speaking(2) and v.is_speaking(1), "indicador de fala (local uid 0 -> meu assento)")
    # mudo
    v.press()
    check(v.state == "MUTED" and mock.calls[-1] == ["mute", true] and v.muted_pref, "toque = mudo (preferência local salva)")
    mock.fire({"ev": "speaking", "seq": v._seq, "uids": [0]})
    check(not v.is_speaking(2), "mudo nunca aparece falando")
    v.press()
    check(v.state == "CONNECTED" and mock.calls[-1] == ["mute", false], "toque de novo = fala")
    # renovação do token
    acc.sent.clear()
    mock.fire({"ev": "will_expire", "seq": v._seq})
    check(acc.types() == ["voice_renew"], "token perto de expirar: pede renovação ao servidor")
    grant(true, 2)
    check(mock.calls[-1][0] == "renew" and v.state == "CONNECTED", "renovação aplicada sem cair da sala")
    # reconexão da Agora
    mock.fire({"ev": "state", "seq": v._seq, "now": "RECONNECTING", "reason": "NETWORK_ERROR"})
    check(v.state == "RECONNECTING", "rede caiu: RECONNECTING")
    mock.fire({"ev": "state", "seq": v._seq, "now": "CONNECTED"})
    check(v.state == "CONNECTED", "voltou: CONNECTED")
    # microfone perdido (permissão revogada / plugue): continua ouvindo, fica mudo
    mock.fire({"ev": "mic_lost", "seq": v._seq, "code": "TRACK_ENDED"})
    check(v.state == "MUTED" and v.message != "", "microfone perdido: MUDO com aviso, ainda ouvindo")
    # autoplay
    mock.fire({"ev": "autoplay_blocked"})
    check(v.status_text() == "Toque na tela para ouvir", "autoplay bloqueado: pede um toque")
    mock.fire({"ev": "autoplay_ok"})
    # renovação recusada (partida acabou)
    acc.server_message.emit({"type": "voice_denied", "renew": true, "match_id": MID, "code": "match_over", "message": "A partida terminou."})
    check(v.state == "DISCONNECTED" and mock.calls[-1][0] == "leave", "renovação recusada: sai da voz e limpa")
    # 4) fim da partida: exit_match limpa tudo e avisa o servidor
    fresh()
    v.enter_match("casual", MID)
    v.press(); grant()
    acc.sent.clear()
    v.exit_match("match_end")
    check(v.state == "DISCONNECTED" and not v.in_match() and mock.calls[-1] == ["leave", v._seq, "match_end"], "fim da partida: leave + estado limpo")
    check(acc.types() == ["voice_leave"], "fim da partida: avisa o servidor (log/mesa)")
    mock.fire({"ev": "joined", "seq": v._seq - 1, "uids": []})
    check(v.state == "DISCONNECTED", "evento atrasado de tentativa antiga: ignorado")
    # 5) permissão negada
    fresh()
    mock.fail_prepare = "PERMISSION_DENIED"
    v.enter_match("ranked", MID)
    v.press()
    check(v.state == "ERROR" and "bloqueado" in v.message and mock.names()[-1] == "leave" and acc.sent.is_empty(), "permissão negada: erro claro, limpa, nenhum token pedido")
    mock.fail_prepare = ""
    v.press()
    check(v.state == "CONNECTING", "tentar de novo depois do erro funciona")
    # 6) servidor recusa
    acc.server_message.emit({"type": "voice_denied", "match_id": MID, "code": "not_configured", "message": "Voz ainda não configurada no servidor."})
    check(v.state == "ERROR" and v.message == "Voz ainda não configurada no servidor." and mock.names()[-1] == "leave", "servidor recusa: ERRO com a mensagem do servidor")
    # 7) falha ao entrar no canal
    fresh()
    mock.fail_join = "CAN_NOT_GET_GATEWAY_SERVER"
    v.enter_match("xeque", MID)
    v.press(); grant()
    check(v.state == "ERROR" and mock.names()[-1] == "leave", "falha no join: ERRO + limpeza")
    # 8) timeouts: nunca fica preso em CONECTANDO
    fresh()
    mock.auto = false
    v.enter_match("marcha", MID)
    v.press()
    check(v.state == "REQUESTING_PERMISSION", "aguardando permissão")
    v._deadline = Time.get_ticks_msec() / 1000.0 - 1.0
    v._process(0.1)
    check(v.state == "ERROR" and mock.names()[-1] == "leave", "permissão sem resposta: timeout -> ERRO + limpeza")
    v.press()
    mock.fire({"ev": "mic_ready", "seq": v._seq})
    check(v.state == "CONNECTING", "conectando")
    v._deadline = Time.get_ticks_msec() / 1000.0 - 1.0
    v._process(0.1)
    check(v.state == "ERROR", "servidor sem resposta: timeout -> ERRO (nunca preso em CONECTANDO)")
    # 9) WebSocket do jogo fora
    fresh()
    acc.socket_ok = false
    v.enter_match("ranked", MID)
    v.press()
    check(v.state == "ERROR" and mock.names()[-1] == "leave", "sem conexão com o servidor do jogo: ERRO + limpeza")
    # 10) RTC caiu de vez
    fresh()
    v.enter_match("ranked", MID)
    v.press(); grant()
    mock.fire({"ev": "state", "seq": v._seq, "now": "DISCONNECTED", "reason": "NETWORK_ERROR"})
    check(v.state == "ERROR" and mock.names()[-1] == "leave", "RTC caiu: ERRO + limpeza (partida segue)")
    # 11) token expirou
    fresh()
    v.enter_match("ranked", MID)
    v.press(); grant()
    mock.fire({"ev": "expired", "seq": v._seq})
    check(v.state == "ERROR" and mock.names()[-1] == "leave", "token expirou: sai e mostra erro")
    # 12) logout no meio
    fresh()
    v.enter_match("ranked", MID)
    v.press(); grant()
    acc.profile_ok = false
    acc.changed.emit()
    check(v.state == "DISCONNECTED" and not v.in_match() and mock.names()[-1] == "leave", "logout: sai da voz e esquece a partida")
    # 13) troca de partida com voz ligada
    fresh()
    v.enter_match("ranked", MID)
    v.press(); grant()
    v.enter_match("casual", "22222222-2222-4222-8222-222222222222")
    check(v.state == "DISCONNECTED" and mock.names()[-1] == "leave" and String(v.ctx.match_id).begins_with("2222"), "partida nova: sai da sala antiga")
    # 14) aviso de quem entrou na voz (antes de eu entrar)
    acc.server_message.emit({"type": "voice_peer", "match_id": "22222222-2222-4222-8222-222222222222", "uid": 1, "name": "Ana", "joined": true})
    check("Ana está na voz" in v.status_text(), "aviso: " + v.status_text())
    # 15) preferência de mudo vale na próxima entrada (só ela é salva)
    fresh()
    v.set_muted(true)
    var v2 = load("res://voice/fraiha_voice.gd").new()
    v2.provider = load("res://voice/mock_voice_provider.gd").new()
    root.add_child(v2)
    check(v2.muted_pref, "preferência 'entrar mudo' lembrada")
    v2.setup(acc)
    v2.enter_match("ranked", MID)
    v2.press();
    acc.server_message.emit({"type": "voice_granted", "match_id": MID, "uid": 1, "token": "007x", "channel": "c", "app_id": "a", "participants": []})
    check(v2.state == "MUTED" and bool(v2.provider.calls[1][2].muted), "entra MUDO quando a preferência é mudo")
    var f := FileAccess.open("user://voice.cfg", FileAccess.READ)
    var txt := f.get_as_text() if f != null else ""
    check(not ("007" in txt) and not ("match" in txt) and not ("channel" in txt), "disco: só a preferência (nada de token/partida)")
    v2.free()
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
