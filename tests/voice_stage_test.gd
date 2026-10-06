extends SceneTree
## R45 · FRAIHA Voice no jogo real (stage completo) contra o servidor real e o PeerParty (que entra na voz).
## Provedor MOCK no lugar da Agora (headless não tem microfone/WebRTC). Confere:
## - voz só aparece em PvP humano online (Casual por convite, MARCHA online, XEQUE online); bot/local nunca;
## - servidor dá token do canal certo; aviso "fulano está na voz";
## - falha de voz NÃO mexe na partida; fim/saída da partida sempre limpa a voz.
## Uso: tests/run_voice_stage.sh [--shots prefixo]
var failures := 0
var shots := ""
var stage
var mock
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func wait_until(cond: Callable, seconds: float) -> bool:
    var end = Time.get_ticks_msec() + int(seconds * 1000)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await process_frame
    return cond.call()
func shot(name: String):
    if shots.is_empty(): return
    for i in range(8): await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(shots + "_" + name + ".png")
func texts(ui) -> Array:
    return ui.box.find_children("*", "Label", true, false).map(func(l): return l.text)
func press(ui, text: String) -> bool:
    for b in ui.box.find_children("*", "Button", true, false):
        if b.text == text and b.is_visible_in_tree() and not b.disabled:
            b.pressed.emit()
            return true
    return false
func joins() -> Array:
    return mock.calls.filter(func(c): return c[0] == "join")
func invite(social, peer_id: String, friend: Dictionary, button: String) -> void:
    stage.hub.friends_requested.emit()
    await wait_until(func(): return social.is_open(), 3.0)
    social.open_invite(peer_id, friend)
    await process_frame
    var b = social.box.find_child(button, true, false)
    if b != null: b.pressed.emit()

func run():
    var args := OS.get_cmdline_user_args()
    var i := args.find("--shots")
    if i >= 0 and i + 1 < args.size(): shots = args[i + 1]
    DirAccess.remove_absolute(ProjectSettings.globalize_path("user://voice.cfg"))   # preferência limpa (entra falando)
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for k in range(3): await process_frame
    stage.account_ui.hide_ui()
    var v = stage.voice
    check(v != null and v.provider != null, "FraihaVoice criado uma vez no jogo (módulo único)")
    check(not v.available(), "fora do navegador: provedor Agora informa sem suporte (botão some)")
    mock = load("res://voice/mock_voice_provider.gd").new()
    v.use_provider(mock)
    var acc = stage.account
    var social = stage.social_ui
    acc.access_token = "dev:GodotVoice"
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conectado com conta")
    if acc.needs_nickname: acc.create_profile("GodotVoice")
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    stage.hub.friends_requested.emit()
    check(await wait_until(func(): return texts(social).any(func(t): return t.begins_with("PEDIDOS RECEBIDOS")), 20.0), "pedido de amizade do PeerParty chegou")
    press(social, "ACEITAR")
    check(await wait_until(func(): return social.data["friends"].size() == 1, 8.0), "PeerParty é amigo")
    var peer_id := String(social.data["friends"][0]["user_id"])
    var friend: Dictionary = social.data["friends"][0]
    social.close()
    # -------- bot e local: nunca voz
    stage._start_bot("madeira", "w")
    await wait_until(func(): return false, 0.6)
    check(stage.mode == "bot" and not v.in_match() and not stage.desk_voice.visible, "contra BOT: sem voz e sem botão")
    stage.open_home()
    stage._start_local()
    await wait_until(func(): return false, 0.6)
    check(not v.in_match(), "jogo LOCAL: sem voz")
    stage.open_home()
    # -------- XADREZ Casual por convite de amigo
    await invite(social, peer_id, friend, "Invite_casual_10min")
    check(await wait_until(func(): return stage.mode == "casual" and stage.casual.in_match(), 15.0), "amigo aceitou: partida Casual começou")
    var mid := String(stage.casual.match_id)
    check(await wait_until(func(): return v.in_match() and String(v.ctx.match_id) == mid and String(v.ctx.kind) == "casual", 2.0), "voz segue a partida (casual, match_id do servidor)")
    check(v.state == "DISCONNECTED" and mock.calls.is_empty(), "voz começa DESLIGADA (só entra com toque do jogador)")
    check(await wait_until(func(): return "PeerParty está na voz" in v.status_text(), 6.0), "aviso do servidor: '%s'" % v.status_text())
    await wait_until(func(): return stage.desk_voice.visible, 2.0)
    check(stage.desk_voice.visible and stage.desk_voice.mic.is_visible_in_tree(), "botão do microfone no HUD da partida")
    await shot("1_casual_voz_aviso")
    # falha de voz no meio da partida: a partida segue
    mock.fail_join = "CAN_NOT_GET_GATEWAY_SERVER"
    var status_before := String(stage.casual.status)
    stage.desk_voice.mic.pressed.emit()
    check(await wait_until(func(): return v.state == "ERROR", 6.0), "falha do RTC: ERRO na voz (%s)" % v.message)
    check(stage.casual.in_match() and String(stage.casual.status) == status_before and stage.mode == "casual", "falha de voz NÃO altera a partida (status %s)" % stage.casual.status)
    await shot("2_casual_voz_erro")
    mock.fail_join = ""
    stage.desk_voice.mic.pressed.emit()
    check(await wait_until(func(): return v.state == "CONNECTED", 6.0), "tentar de novo: CONNECTED")
    var j: Array = joins()[-1]
    check(String(j[2].channel) == "fx_casual_" + mid and String(j[2].token).begins_with("007") and int(j[2].uid) in [1, 2], "token do servidor para o canal da partida (uid = assento)")
    mock.fire({"ev": "remote", "seq": v._seq, "uids": [3 - int(j[2].uid)]})
    check("PeerParty" in v.status_text() and "PeerParty" in stage.desk_voice.label.text, "quem está na sala: %s" % stage.desk_voice.label.text)
    await shot("3_casual_voz_conectada")
    stage.desk_voice.mic.pressed.emit()
    check(v.state == "MUTED", "microfone: mudo")
    stage.desk_voice.mic.pressed.emit()
    check(v.state == "CONNECTED", "microfone: fala")
    # fim da partida (desistência) → resultado oficial → voz sai sozinha
    stage.casual.resign()
    check(await wait_until(func(): return not stage.casual.in_match(), 10.0), "partida terminou pelo fluxo normal")
    check(await wait_until(func(): return v.state == "DISCONNECTED" and not v.in_match(), 2.0), "fim da partida: voz desligada e limpa")
    check(mock.calls[-1][0] == "leave", "provedor recebeu leave (microfone liberado)")
    check(not stage.desk_voice.visible, "botão some depois da partida")
    if stage.result_overlay != null: stage.result_overlay.hide_result()
    stage.open_home()
    await wait_until(func(): return false, 1.0)
    # -------- MARCHA REAL online
    await invite(social, peer_id, friend, "Invite_marcha")
    check(await wait_until(func(): return stage.hub.marcha != null and stage.hub.marcha.online and stage.hub.marcha.mode == "game", 12.0), "MARCHA online abriu")
    var mu = stage.hub.marcha
    check(await wait_until(func(): return v.in_match() and String(v.ctx.kind) == "marcha" and String(v.ctx.match_id) == String(mu.room_id), 2.0), "voz segue a mesa da MARCHA (2 humanos + 2 bots)")
    mu._on_hit("voice")
    check(await wait_until(func(): return v.state in ["CONNECTED", "MUTED"], 6.0), "MARCHA: toque no microfone → na voz")
    j = joins()[-1]
    check(String(j[2].channel) == "fx_marcha_" + String(mu.room_id), "MARCHA: canal da mesa")
    mu._redraw()
    await process_frame
    check(mu.hits.any(func(h): return String(h.id) == "voice") and mu.hits.any(func(h): return String(h.id) == "voice_off"), "MARCHA: botão de voz e de sair da voz desenhados")
    await shot("4_marcha_voz")
    mu._on_hit("voice_off")
    check(v.state == "DISCONNECTED" and v.in_match(), "MARCHA: × sai da voz, a mesa continua")
    mu._on_hit("voice")
    await wait_until(func(): return v.state in ["CONNECTED", "MUTED"], 6.0)
    mu._on_hit("menu")
    mu._on_hit("menu_quit")
    check(await wait_until(func(): return not v.in_match() and v.state == "DISCONNECTED", 2.0), "MARCHA: sair da partida tira da voz")
    mu.close()
    await wait_until(func(): return false, 1.5)
    # -------- XEQUE online
    await invite(social, peer_id, friend, "Invite_xeque")
    check(await wait_until(func(): return stage.hub.xeque != null and stage.hub.xeque.online and stage.hub.xeque.mode == "game", 12.0), "XEQUE online abriu")
    var xu = stage.hub.xeque
    check(await wait_until(func(): return v.in_match() and String(v.ctx.kind) == "xeque", 2.0), "voz segue a mesa do XEQUE")
    xu._on_hit("voice")
    check(await wait_until(func(): return v.state in ["CONNECTED", "MUTED"], 6.0), "XEQUE: na voz")
    check(String(joins()[-1][2].channel) == "fx_xeque_" + String(xu.room_id), "XEQUE: canal da mesa")
    xu._redraw()
    await shot("5_xeque_voz")
    xu._on_hit("menu")
    xu._on_hit("menu_quit")
    xu._on_hit("quit_yes")
    check(await wait_until(func(): return not v.in_match() and v.state == "DISCONNECTED", 2.0), "XEQUE: sair da partida tira da voz")
    # -------- logout com voz ativa (sem partida não há voz; aqui só confere que não sobra nada)
    check(not v.active() and v.remote.is_empty() and v.my_uid == 0, "estado final limpo (sem participantes, sem assento)")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
