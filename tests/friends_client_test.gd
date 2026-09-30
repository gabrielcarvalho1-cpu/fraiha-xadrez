extends SceneTree
## Cliente Godot na área AMIGOS contra servidor real (FRAIHA_DEV_AUTH) e jogadores automáticos
## (tests/server/social_peer.cjs). Uso: /tmp/run_friends_client.sh [--mobile-test] [--size WxH] [--shots prefixo]
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
    # Convidado: AMIGOS pede para entrar/criar conta
    stage.hub.friends_requested.emit()
    check(stage.account_ui.is_open() and not ui.is_open(), "sem conta: AMIGOS abre entrar/criar conta")
    stage.account_ui.hide_ui()
    # Entra com conta de teste (DevAuth) e cria o nickname
    acc.access_token = "dev:GodotAmigo"
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conectado ao servidor com conta")
    if acc.needs_nickname: acc.create_profile("GodotAmigo")
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil GodotAmigo pronto")
    stage.hub.friends_requested.emit()
    check(ui.is_open() and ui.screen == "list" and not stage.account_ui.is_open(), "AMIGOS abre a área de amigos para contas")
    check(await wait_until(func(): return section_count(ui, "PEDIDOS RECEBIDOS") == 2, 25.0), "dois pedidos recebidos aparecem em tempo real")
    check(ui.toast.visible and "pedido de amizade" in ui.toast_label.text, "aviso (toast) de pedido recebido")
    check(section_count(ui, "ONLINE") == 0 and section_count(ui, "OFFLINE") == 0 and section_count(ui, "EM PARTIDA") == 0, "seções ONLINE / EM PARTIDA / OFFLINE presentes")
    check(inside_view(ui), "painel dentro da tela")
    await shot(ui, "1_pedidos")
    check(press(ui, "ACEITAR", "PeerAna"), "ACEITAR pedido de PeerAna")
    check(await wait_until(func(): return section_count(ui, "ONLINE") == 1 and section_count(ui, "PEDIDOS RECEBIDOS") == 1, 5.0), "PeerAna vira amiga ONLINE")
    check(press(ui, "RECUSAR", "PeerBia"), "RECUSAR pedido de PeerBia")
    check(await wait_until(func(): return section_count(ui, "PEDIDOS RECEBIDOS") == -1, 5.0), "pedido recusado sai da lista")
    # Busca
    ui.search_input.text = "Peer"
    ui.search_input.text_submitted.emit("Peer")
    check(await wait_until(func(): return ui.screen == "search" and ui.results.size() == 3, 5.0), "busca por nickname mostra 3 jogadores")
    check(buttons(ui, "ADICIONAR", "PeerCadu").size() == 1 and buttons(ui, "ADICIONAR", "PeerAna").is_empty(), "ADICIONAR só para quem não é amigo")
    check(not texts(ui).any(func(t): return "@" in t), "nenhum e-mail na tela")
    await shot(ui, "2_busca")
    check(press(ui, "ADICIONAR", "PeerCadu"), "envia pedido para PeerCadu")
    check(await wait_until(func(): return ui.toast.visible and "aceitou" in ui.toast_label.text, 6.0), "PeerCadu aceita: aviso em tempo real")
    ui.search_input.text = "x"
    ui.search_input.text_submitted.emit("x")
    check(ui.notice.visible and "2 letras" in ui.notice.text, "busca curta mostra orientação")
    ui.search_input.text = "NinguemXYZ"
    ui.search_input.text_submitted.emit("NinguemXYZ")
    check(await wait_until(func(): return ui.screen == "search" and ui.results.is_empty() and texts(ui).any(func(t): return "Nenhum jogador" in t), 5.0), "nickname inexistente: 'Nenhum jogador encontrado'")
    press(ui, "VOLTAR PARA A LISTA")
    check(await wait_until(func(): return ui.screen == "list" and section_count(ui, "ONLINE") == 2, 5.0), "lista com 2 amigos online")
    # Perfil de amigo
    press(ui, "PeerAna", "PeerAna")
    check(await wait_until(func(): return ui.screen == "profile" and ui.profile.has("nickname"), 5.0), "abre o perfil de PeerAna")
    var t = texts(ui)
    check("PeerAna" in t and t.any(func(x): return "ONLINE" in x) and t.any(func(x): return x.begins_with("Maior liga: Madeira")) and t.any(func(x): return x.begins_with("RELÂMPAGO · Madeira")), "perfil: nickname, status, maior liga e Ranked por modo")
    check(buttons(ui, "REMOVER AMIGO").size() == 1 and buttons(ui, "BLOQUEAR").size() == 1 and buttons(ui, "MENSAGEM").size() == 1 and not buttons(ui, "MENSAGEM")[0].disabled and buttons(ui, "CONVIDAR PARA JOGAR").size() == 1 and not buttons(ui, "CONVIDAR PARA JOGAR")[0].disabled, "ações de amigo: MENSAGEM, CONVIDAR PARA JOGAR, REMOVER, BLOQUEAR")
    check(inside_view(ui), "perfil dentro da tela")
    await shot(ui, "3_perfil")
    press(ui, "REMOVER AMIGO")
    check(ui.screen == "confirm", "REMOVER pede confirmação")
    await shot(ui, "4_confirmar")
    press(ui, "CONFIRMAR")
    check(await wait_until(func(): return ui.screen == "profile" and ui.profile.get("relation") == "none" and buttons(ui, "ADICIONAR AMIGO").size() == 1, 5.0), "amizade removida: perfil volta a ADICIONAR AMIGO")
    press(ui, "BLOQUEAR")
    press(ui, "CONFIRMAR")
    check(await wait_until(func(): return ui.profile.get("relation") == "blocked" and buttons(ui, "DESBLOQUEAR").size() == 1, 5.0), "BLOQUEAR: perfil mostra DESBLOQUEAR")
    press(ui, "VOLTAR")
    check(await wait_until(func(): return ui.screen == "list" and section_count(ui, "BLOQUEADOS") == 1 and section_count(ui, "ONLINE") == 1, 5.0), "lista: 1 bloqueado, 1 amigo online")
    press(ui, "DESBLOQUEAR", "PeerAna")
    check(await wait_until(func(): return section_count(ui, "BLOQUEADOS") == -1, 5.0), "DESBLOQUEAR na lista")
    # Offline: PeerCadu continua amigo; checa ESC fechando
    var esc = InputEventKey.new()
    esc.keycode = KEY_ESCAPE
    esc.pressed = true
    Input.parse_input_event(esc)
    check(await wait_until(func(): return not ui.is_open(), 2.0), "ESC / VOLTAR fecha Amigos e volta à Home")
    check(stage.mode == "home", "continua na Home")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
