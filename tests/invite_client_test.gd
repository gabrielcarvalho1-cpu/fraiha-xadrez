extends SceneTree
## Convites para partida Casual no cliente Godot contra servidor real e PeerAna (tests/server/social_peer.cjs:
## aceita 3 min, recusa 5 min, ignora os outros; DM "me convida <modo>" faz ela convidar).
## Uso: INVITE_TTL=8000 TEST=tests/invite_client_test.gd /tmp/run_friends_client.sh [--mobile-test] [--size WxH] [--shots prefixo]
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

func card(stage) -> Array:
    var inv = stage.invite_ui
    return inv.box.find_children("*", "Label", true, false).map(func(l): return l.text) if inv.panel.visible else []
func card_button(stage, name: String) -> Button:
    return stage.invite_ui.box.find_child(name, true, false)
func ask_invite(stage, ana_id: String, mode: String):
    stage.account.send_server({"type": "dm_send", "user_id": ana_id, "text": "me convida " + mode})
func finish_match(stage):
    await wait_until(func(): return stage.casual.status == "playing", 8.0)
    stage.casual.resign()
    await wait_until(func(): return stage.casual.status == "finished", 6.0)
    stage.open_home()
    await wait_until(func(): return stage.mode == "home", 3.0)
    await wait_until(func(): return false, 0.6)

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
    var iv = stage.invite_ui
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
    check(await wait_until(func(): return section_count(ui, "ONLINE") == 1, 6.0), "PeerAna amiga")
    var ana_id = String(ui.data["friends"][0]["user_id"])
    # Perfil -> CONVIDAR PARA JOGAR -> escolher tempo
    ui.open_profile(ana_id)
    check(await wait_until(func(): return ui.screen == "profile" and ui.profile.has("nickname"), 5.0), "perfil da amiga")
    check(press(ui, "CONVIDAR PARA JOGAR"), "CONVIDAR PARA JOGAR ativo para amigo")
    check(ui.screen == "invite_pick" and ["casual_3min", "casual_5min", "casual_10min", "casual_20min"].all(func(m): return ui.box.find_child("Invite_" + m, true, false) != null), "escolha de tempo: 3 / 5 / 10 / 20")
    check(inside_view(ui), "tela de escolha dentro da tela")
    await shot(ui, "8_escolher_tempo")
    # 5 min: PeerAna recusa
    ui.box.find_child("Invite_casual_5min", true, false).pressed.emit()
    check(await wait_until(func(): return ui.screen == "profile" and iv.panel.visible and card(stage).has("CONVITE ENVIADO"), 5.0), "convite enviado: cartão com CANCELAR e contagem")
    check(card_button(stage, "InviteCancel") != null and card(stage).any(func(t): return "Aguardando resposta" in t) and card(stage).any(func(t): return "RÁPIDA · 5 min" in t), "cartão do remetente: tempo e espera")
    await shot(ui, "9_convite_enviado")
    check(await wait_until(func(): return card(stage).any(func(t): return "recusou" in t), 6.0), "amiga recusou: remetente é avisado")
    # 10 min: remetente cancela
    await wait_until(func(): return not iv.panel.visible, 6.0)
    press(ui, "CONVIDAR PARA JOGAR")
    ui.box.find_child("Invite_casual_10min", true, false).pressed.emit()
    check(await wait_until(func(): return card_button(stage, "InviteCancel") != null and iv.panel.visible, 5.0), "convite de 10 min enviado")
    card_button(stage, "InviteCancel").pressed.emit()
    check(await wait_until(func(): return card(stage).any(func(t): return "cancelado" in t), 5.0), "CANCELAR CONVITE funciona")
    # 3 min: amiga aceita -> partida Casual abre sozinha
    await wait_until(func(): return not iv.panel.visible, 6.0)
    press(ui, "CONVIDAR PARA JOGAR")
    ui.box.find_child("Invite_casual_3min", true, false).pressed.emit()
    check(await wait_until(func(): return stage.mode == "casual", 8.0), "amiga aceitou: partida Casual começou automaticamente")
    check(stage.casual.mode == "casual_3min" and not ui.is_open() and not iv.panel.visible, "partida de 3 min; Amigos e cartão fecharam")
    await finish_match(stage)
    # Convite recebido: RECUSAR
    ask_invite(stage, ana_id, "casual_20min")
    check(await wait_until(func(): return iv.panel.visible and card(stage).has("CONVITE PARA PARTIDA"), 6.0), "convite recebido aparece (também fora de Amigos)")
    check(card(stage).has("PeerAna te convidou") and card(stage).any(func(t): return "CONVENCIONAL · 20 min" in t) and card(stage).any(func(t): return t.begins_with("Expira em")), "cartão: nickname, tempo e contagem regressiva")
    check(card_button(stage, "InviteAccept").custom_minimum_size.y >= 50 and card_button(stage, "InviteDecline") != null, "botões grandes ACEITAR / RECUSAR")
    await shot(ui, "10_convite_recebido")
    card_button(stage, "InviteDecline").pressed.emit()
    check(await wait_until(func(): return card(stage).any(func(t): return "recusou" in t), 5.0), "RECUSAR encerra o convite")
    await wait_until(func(): return not iv.panel.visible, 6.0)
    # Convite recebido: ACEITAR duas vezes -> uma partida só, "Iniciando…"
    ask_invite(stage, ana_id, "casual_20min")
    check(await wait_until(func(): return card_button(stage, "InviteAccept") != null and iv.panel.visible, 6.0), "novo convite recebido")
    var found := [0]
    stage.casual.found.connect(func(_m): found[0] += 1)
    card_button(stage, "InviteAccept").pressed.emit()
    check(card_button(stage, "InviteAccept").disabled and card(stage).has("Iniciando partida…"), "ACEITAR mostra 'Iniciando…' e bloqueia clique repetido")
    card_button(stage, "InviteAccept").pressed.emit()
    iv.accept()
    check(await wait_until(func(): return stage.mode == "casual", 6.0), "partida começou ao aceitar")
    await wait_until(func(): return false, 1.0)
    check(found[0] == 1 and stage.casual.mode == "casual_20min", "uma única partida (20 min)")
    ask_invite(stage, ana_id, "casual_10min")
    await wait_until(func(): return false, 2.0)
    check(not iv.panel.visible, "durante a partida nenhum convite aparece por cima")
    await finish_match(stage)
    # Expiração (TTL de teste)
    ask_invite(stage, ana_id, "casual_10min")
    check(await wait_until(func(): return iv.panel.visible and card_button(stage, "InviteAccept") != null, 6.0), "convite para expirar")
    check(await wait_until(func(): return card(stage).any(func(t): return "expirou" in t), 15.0), "convite expira e o cartão avisa")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
