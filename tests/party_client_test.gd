extends SceneTree
## R35 · MARCHA REAL e XEQUE online com amigo no cliente Godot, contra o servidor real e PeerParty
## (tests/server/party_peer.cjs: pede amizade, aceita convites e joga a vez dele).
## Uso: tests/run_party_client.sh [--shots prefixo]
const MAI := preload("res://marcha/ai.gd")
var failures := 0
var shots := ""
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
    for i in range(6): await process_frame
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

func run():
    var args := OS.get_cmdline_user_args()
    var i := args.find("--shots")
    if i >= 0 and i + 1 < args.size(): shots = args[i + 1]
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for k in range(3): await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    var social = stage.social_ui
    acc.access_token = "dev:GodotParty"
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conectado com conta")
    if acc.needs_nickname: acc.create_profile("GodotParty")
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    stage.hub.friends_requested.emit()
    check(await wait_until(func(): return texts(social).any(func(t): return t.begins_with("PEDIDOS RECEBIDOS")), 20.0), "pedido de amizade do PeerParty chegou")
    press(social, "ACEITAR")
    check(await wait_until(func(): return social.data["friends"].size() == 1, 8.0), "PeerParty é amigo")
    var peer_id := String(social.data["friends"][0]["user_id"])
    # -------- MARCHA REAL
    social.open_invite(peer_id, social.data["friends"][0])
    check(social.box.find_child("Invite_marcha", true, false) != null and social.box.find_child("Invite_xeque", true, false) != null, "tela de convite tem MARCHA REAL e XEQUE")
    await shot("1_convite_modos")
    # perfil do amigo: nickname numa linha só (antes ficava letra por letra na vertical)
    social.open_profile(peer_id)
    await wait_until(func(): return social.screen == "profile" and social.profile.has("nickname"), 5.0)
    for k in 4: await process_frame
    var nk = social.box.find_child("ProfileNickname", true, false)
    check(nk != null and nk.size.y < 60.0 and nk.size.x > 100.0, "perfil do amigo: nome numa linha (%s)" % (str(nk.size) if nk != null else "?"))
    social.close()
    # R35.1 · CONVIDAR AMIGO de dentro da MARCHA REAL (lobby do modo)
    stage.hub.open_marcha()
    await wait_until(func(): return stage.hub.marcha != null and stage.hub.marcha.is_open(), 3.0)
    stage.hub.marcha.tut_page = -1
    stage.hub.marcha._on_hit("lobby_invite")
    check(await wait_until(func(): return social.is_open() and social.screen == "invite_friends", 5.0), "MARCHA REAL → CONVIDAR AMIGO abre a lista de amigos por cima do modo")
    check(social.layer > stage.hub.marcha.layer and stage.invite_ui.layer > stage.hub.marcha.layer, "lista e cartão do convite ficam por cima da tela do modo")
    await wait_until(func(): return social.box.find_child("PickFriend_PeerParty", true, false) != null, 6.0)
    await shot("1b_convidar_no_modo")
    var pick_row = social.box.find_child("PickFriend_PeerParty", true, false)
    var inv_btn: Button = null
    if pick_row != null:
        for b in pick_row.find_children("*", "Button", true, false):
            if b.text == "CONVIDAR": inv_btn = b
    check(inv_btn != null, "amigo online com botão CONVIDAR")
    if inv_btn != null: inv_btn.pressed.emit()
    check(await wait_until(func(): return stage.hub.marcha != null and stage.hub.marcha.online and stage.hub.marcha.mode == "game", 10.0), "amigo aceitou: MARCHA REAL abre online sozinha")
    var mu = stage.hub.marcha
    check(not social.is_open(), "a tela de Amigos fecha quando a mesa abre")
    check(mu.names[2] == "PeerParty" and mu.names[1] != "PeerParty", "o amigo aparece como ALIADO (em cima)")
    check(mu.g.hands[0].size() == 4 and mu.g.hands[2].all(func(c): return c == "2"), "minha mão real; a do amigo só como quantidade")
    await shot("2_marcha_online")
    # R37.3 · chat da mesa: botão CHAT, escolha PARA TODOS / SÓ ALIADO
    var pc = stage.party_chat
    check(pc.active() and pc.toggle.visible and pc.to_row.visible, "MARCHA online: botão CHAT com PARA TODOS / SÓ ALIADO")
    pc.set_open(true)
    pc.set_to("ally")
    pc.input.text = "oi aliado"
    pc.send_current()
    check(await wait_until(func(): return pc.messages.any(func(m): return String(m.text) == "oi aliado" and String(m.to) == "ally"), 5.0), "MARCHA online: mensagem para o aliado enviada e mostrada")
    await shot("2b_marcha_chat")
    pc.set_open(false)
    var my_moves := 0
    var server_ok := true
    var t0 := Time.get_ticks_msec()
    while my_moves < 6 and Time.get_ticks_msec() - t0 < 120000:
        await process_frame
        if mu.mode != "game": break
        if mu._my_turn() and not mu.busy and not mu.waiting_server and mu.ev_queue.is_empty() and not mu.ev_running:
            var mv: Dictionary = MAI.choose(mu.g, 0, null)
            var before = mu.plays
            if String(mv.kind) == "discard": mu.pick_card(int(mv.card))
            else: mu.pending = mv
            mu.sel_card = int(mv.card)
            mu.confirm()
            if not await wait_until(func(): return mu.plays > before or mu.mode != "game", 15.0): server_ok = false
            my_moves += 1
    check(my_moves >= 6 and server_ok, "6 jogadas minhas aceitas pelo servidor e animadas (%d)" % my_moves)
    check(mu.cues_played.has("your_turn") and mu.cues_played.has("card"), "sons de vez e de carta no online")
    # jogada inválida: o servidor recusa e a mesa continua
    await wait_until(func(): return mu._my_turn() and not mu.busy and mu.ev_queue.is_empty() and not mu.ev_running, 30.0)
    mu._online_send({"kind": "move", "card": 0, "pawn": [0, 0], "steps": 99})
    check(await wait_until(func(): return mu.flash.contains("inválida"), 6.0), "jogada inválida recusada pelo servidor (aviso na tela)")
    check(await wait_until(func(): return not mu.busy, 4.0), "depois da recusa a vez continua comigo")
    await shot("3_marcha_jogando")
    # sair da partida: o amigo segue com um bot no meu lugar
    var rid: String = mu.room_id
    mu._on_hit("menu")
    mu._on_hit("menu_quit")
    check(not mu.online and mu.mode == "lobby", "SAIR DA PARTIDA deixa a mesa online")
    check(not pc.active(), "saiu da mesa: o CHAT some")
    var hist: Array = stage.match_history.entries.filter(func(e): return String(e.get("mode_id", "")) == "marcha_real" and bool(e.get("online", false)) and String(e.get("room_id", "")) == rid)
    check(hist.size() == 1 and String(hist[0].result) == "abandon" and String(hist[0].ruleset_version) == "marcha-real-7", "histórico: partida online da Marcha (abandono, marcha-real-7)")
    mu.close()
    await wait_until(func(): return false, 1.5)
    # -------- XEQUE
    stage.hub.friends_requested.emit()
    await wait_until(func(): return social.is_open(), 3.0)
    social.open_invite(peer_id, social.data["friends"][0])
    social.box.find_child("Invite_xeque", true, false).pressed.emit()
    check(await wait_until(func(): return stage.hub.xeque != null and stage.hub.xeque.online and stage.hub.xeque.mode == "game", 10.0), "XEQUE abre online sozinho quando o amigo aceita")
    var xu = stage.hub.xeque
    check(xu.g.names[2] == "PeerParty" and xu.g.hands[0].size() == 5 and xu.g.hands[1].all(func(c): return c == "?"), "XEQUE: amigo na mesa; só a minha mão é conhecida")
    check(pc.active() and not pc.to_row.visible and pc.to == "all", "XEQUE online: CHAT para todos")
    var acts := 0
    var challenged := false
    var t1 := Time.get_ticks_msec()
    while acts < 8 and xu.mode == "game" and Time.get_ticks_msec() - t1 < 150000:
        await process_frame
        if xu.phase == "" and xu.g != null and xu.g.state == "TURN_WAITING" and xu.g.turn == 0 and not xu.input_locked and xu.mesa_anim < 0.0:
            if xu.g.can_challenge(0) and not challenged:
                challenged = true
                xu.human_challenge()
            else:
                xu.selected = [0]
                xu.human_play()
            acts += 1
            await wait_until(func(): return xu.input_locked == false and xu.g != null and xu.g.turn == 0 and xu.phase == "" or xu.g == null or xu.g.turn != 0 or xu.mode != "game", 20.0)
    check(acts >= 4, "XEQUE: minhas jogadas aceitas pelo servidor (%d)" % acts)
    check(xu.cues_played.has("xeque") or challenged == false or xu.g.reveals.size() > 0, "XEQUE: desafio resolvido no servidor e apresentado (revelar → relógio)")
    await shot("4_xeque_online")
    xu._on_hit("menu")
    xu._on_hit("menu_quit")
    xu._on_hit("quit_yes")
    check(not xu.online, "sair do XEQUE online")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
