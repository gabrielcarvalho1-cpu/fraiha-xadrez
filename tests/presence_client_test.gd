extends SceneTree
## Presença em tempo real no cliente Godot (Etapa 7) contra servidor real e PeerAna (tests/server/social_peer.cjs):
## DM "presenca partida" -> Ana joga 5 s; "presenca some" -> Ana cai e volta em 3 s.
## Uso: PRES_GRACE=1000 TEST=tests/presence_client_test.gd /tmp/run_friends_client.sh [--mobile-test] [--size WxH] [--shots prefixo]
var failures = 0
var args: PackedStringArray
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
func arg(name: String) -> String:
    var i = args.find(name)
    return args[i + 1] if i >= 0 and i + 1 < args.size() else ""
func shot(ui, name: String):
    if shots.is_empty(): return
    for i in range(8): await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(shots + "_" + name + ".png")

func buttons(ui, text: String, nick := "") -> Array:
    var out := []
    for b in ui.box.find_children("*", "Button", true, false):
        if b.text != text or not b.is_visible_in_tree(): continue
        if not nick.is_empty():
            var row = b.get_parent()
            while row != null and not row.has_meta("user_id"): row = row.get_parent()
            if row == null: continue
            var names = row.find_children("*", "Button", true, false).map(func(x): return x.text)
            if not nick in names: continue
        out.append(b)
    return out
func press(ui, text: String, nick := "") -> bool:
    var b = buttons(ui, text, nick)
    if b.is_empty() or b[0].disabled: return false
    b[0].pressed.emit()
    return true
func texts(ui) -> Array:
    return ui.box.find_children("*", "Label", true, false).map(func(l): return l.text)
func section_count(ui, title: String) -> int:
    for t in texts(ui):
        if t.begins_with(title + " ("): return int(t.get_slice("(", 1).get_slice(")", 0))
    return -1
func inside_view(ui) -> bool:
    var view = ui.get_viewport().get_visible_rect()
    if view.size.x < 200.0: return true  # headless sem --size (janela 64x64): só vale com tamanho definido
    var real = ui.panel.get_global_rect()  # já inclui a escala do painel
    if not view.grow(1.0).encloses(real): print("DBG view ", view, " panel ", real)
    return view.grow(1.0).encloses(real)

func friend_section(ui) -> String:
    for key in ["ONLINE", "EM PARTIDA", "OFFLINE"]:
        if section_count(ui, key) == 1: return key
    return ""
func say(stage, ana_id: String, text: String):
    stage.account.send_server({"type": "dm_send", "user_id": ana_id, "text": text})

func run():
    args = OS.get_cmdline_user_args()
    shots = arg("--shots")
    var size = arg("--size")
    if size.contains("x"):
        root.mode = Window.MODE_WINDOWED
        root.size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
        root.content_scale_size = root.size
        await process_frame
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(3): await process_frame
    stage.account_ui.hide_ui()
    var ui = stage.social_ui
    var acc = stage.account
    acc.access_token = "dev:GodotAmigo"
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conectado com conta")
    if acc.needs_nickname: acc.create_profile("GodotAmigo")
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    stage.hub.friends_requested.emit()
    check(await wait_until(func(): return section_count(ui, "PEDIDOS RECEBIDOS") == 2, 25.0), "pedidos chegaram")
    press(ui, "ACEITAR", "PeerAna")
    press(ui, "RECUSAR", "PeerBia")
    check(await wait_until(func(): return friend_section(ui) == "ONLINE", 6.0), "PeerAna aparece em ONLINE")
    var ana_id = String(ui.data["friends"][0]["user_id"])
    # DM: presença ao lado do nickname, atualizada sem perder o texto digitado
    ui.open_dm(ana_id, ui.data["friends"][0], "list")
    check(await wait_until(func(): return not ui.dm_loading, 5.0) and ui.box.find_child("DmPresence", true, false).text == "Conversa privada · Online", "DM mostra Online")
    ui.dm_input.text = "rascunho"
    say(stage, ana_id, "presenca partida")
    check(await wait_until(func(): return ui.box.find_child("DmPresence", true, false).text == "Conversa privada · Em partida", 6.0), "DM: amiga entrou em partida -> Em partida (tempo real)")
    check(ui.dm_input.text == "rascunho" and ui.screen == "dm", "mudança de presença não apaga o texto nem fecha a conversa")
    await shot(ui, "11_dm_em_partida")
    check(not ui.dm_messages.any(func(m): return "presen" in String(m.get("body", "")) and String(m.get("sender_id", "")) == ana_id), "presença não vira mensagem na DM")
    check(await wait_until(func(): return ui.box.find_child("DmPresence", true, false).text == "Conversa privada · Online", 10.0), "DM: fim da partida -> Online")
    # Lista reorganiza sozinha
    ui.close_dm()
    check(ui.screen == "list" and friend_section(ui) == "ONLINE", "lista: Online")
    say(stage, ana_id, "presenca partida")
    check(await wait_until(func(): return friend_section(ui) == "EM PARTIDA", 6.0), "lista: amiga move para EM PARTIDA sem reabrir a tela")
    await shot(ui, "12_lista_em_partida")
    ui.open_profile(ana_id)
    check(await wait_until(func(): return ui.screen == "profile" and ui.profile.has("nickname"), 5.0), "perfil da amiga")
    check(buttons(ui, "CONVIDAR PARA JOGAR").size() == 1 and buttons(ui, "CONVIDAR PARA JOGAR")[0].disabled and ui.box.find_child("InviteUnavailable", true, false) != null, "Em partida: CONVIDAR indisponível (com motivo)")
    check(await wait_until(func(): return ui.profile.get("presence") == "online" and not buttons(ui, "CONVIDAR PARA JOGAR")[0].disabled, 10.0), "voltou a Online: CONVIDAR liberado no perfil (tempo real)")
    press(ui, "VOLTAR")
    check(await wait_until(func(): return friend_section(ui) == "ONLINE", 3.0), "lista: de volta a ONLINE")
    # Amiga cai e volta (tolerância de teste: 1 s)
    say(stage, ana_id, "presenca some")
    check(await wait_until(func(): return friend_section(ui) == "OFFLINE", 6.0), "amiga desconectou: OFFLINE depois da tolerância")
    await shot(ui, "13_lista_offline")
    check(await wait_until(func(): return friend_section(ui) == "ONLINE", 8.0), "amiga reconectou: ONLINE")
    # Minha conexão cai: mantém a lista e mostra Reconectando…
    acc.socket.close()
    check(await wait_until(func(): return ui.notice.visible and ui.notice.text == "Reconectando…", 5.0), "minha conexão caiu: 'Reconectando…'")
    check(friend_section(ui) == "ONLINE", "amigos não viram Offline por causa da MINHA queda")
    check(await wait_until(func(): return acc.has_profile() and not ui.reconnecting, 12.0), "reconectou: snapshot recebido")
    check(await wait_until(func(): return not ui.notice.visible or ui.notice.text != "Reconectando…", 3.0) and friend_section(ui) == "ONLINE", "aviso some e a presença continua correta")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
