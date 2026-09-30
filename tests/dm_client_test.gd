extends SceneTree
## Mensagens privadas (DM) no cliente Godot contra servidor real (FRAIHA_DEV_AUTH) e PeerAna (tests/server/social_peer.cjs,
## que responde "eco: …"). Uso: /tmp/run_friends_client.sh tests/dm_client_test.gd [--mobile-test] [--size WxH] [--shots prefixo]
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

func bubbles(ui) -> Array:
    if not is_instance_valid(ui.dm_list): return []
    return ui.dm_list.get_children().filter(func(c): return c.has_meta("dm_id"))
func bubble_texts(ui) -> Array:
    return bubbles(ui).map(func(b): return b.find_child("DmBody", true, false).text)

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
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil GodotAmigo pronto")
    acc.user_id = String(acc.user_id)
    stage.hub.friends_requested.emit()
    check(await wait_until(func(): return section_count(ui, "PEDIDOS RECEBIDOS") == 2, 25.0), "pedidos de PeerAna e PeerBia chegaram")
    press(ui, "ACEITAR", "PeerAna")
    press(ui, "RECUSAR", "PeerBia")
    check(await wait_until(func(): return section_count(ui, "ONLINE") == 1 and buttons(ui, "MENSAGEM", "PeerAna").size() == 1, 6.0), "amiga PeerAna com botão MENSAGEM na lista")
    # Abrir conversa
    press(ui, "MENSAGEM", "PeerAna")
    check(ui.screen == "dm", "MENSAGEM abre a conversa")
    check(await wait_until(func(): return not ui.dm_loading and ui.dm_can_send, 6.0), "conversa carregada e envio liberado")
    check(texts(ui).has("PeerAna") and ui.box.find_child("DmPeer", true, false) != null, "cabeçalho com nickname e avatar do amigo")
    check(texts(ui).any(func(t): return "Nenhuma mensagem" in t), "conversa vazia mostra orientação")
    ui.dm_input.text = "   "
    ui.dm_input.text_submitted.emit(ui.dm_input.text)
    await process_frame
    check(bubbles(ui).is_empty(), "mensagem vazia não é enviada")
    ui.dm_input.text = "Olá Ana! Tudo bem? ação 😀"
    ui.dm_input.text_submitted.emit(ui.dm_input.text)
    check(await wait_until(func(): return bubble_texts(ui).has("Olá Ana! Tudo bem? ação 😀"), 5.0), "Enter envia; minha mensagem aparece (acentos/emoji)")
    check(ui.dm_input.text.is_empty(), "campo limpo após confirmação do servidor")
    check(bubbles(ui)[0].get_meta("mine") == true, "enviada marcada como minha (à direita)")
    check(await wait_until(func(): return bubble_texts(ui).has("eco: Olá Ana! Tudo bem? ação 😀"), 6.0), "resposta da amiga chega em tempo real")
    check(bubbles(ui)[-1].get_meta("mine") == false, "recebida à esquerda")
    await process_frame
    check(ui.dm_list.find_child("DmEmpty", false, false) == null, "aviso de conversa vazia some ao chegar a 1ª mensagem")
    check(ui.dm_input.max_length == 500, "campo limita a 500 caracteres")
    check(inside_view(ui), "painel da conversa dentro da tela")
    await shot(ui, "5_conversa")
    # Não lidas: envia e sai da conversa antes do eco
    ui.dm_input.text = "teste de não lida"
    ui.send_dm()
    check(await wait_until(func(): return bubble_texts(ui).has("teste de não lida"), 5.0), "segunda mensagem enviada")
    press(ui, "VOLTAR")
    check(ui.screen == "list", "VOLTAR retorna à lista")
    check(await wait_until(func(): return buttons(ui, "MENSAGEM (1)", "PeerAna").size() == 1, 6.0), "lista mostra 1 não lida (MENSAGEM (1)) em tempo real")
    check(ui.toast.visible and "Nova mensagem de PeerAna" in ui.toast_label.text, "aviso de nova mensagem")
    await shot(ui, "6_nao_lida")
    press(ui, "MENSAGEM (1)", "PeerAna")
    check(await wait_until(func(): return not ui.dm_loading and bubbles(ui).size() == 4, 6.0), "histórico completo (4 mensagens) ao reabrir")
    await wait_until(func(): return false, 1.0)
    press(ui, "VOLTAR")
    check(await wait_until(func(): return buttons(ui, "MENSAGEM", "PeerAna").size() == 1, 6.0), "abrir a conversa zera as não lidas")
    # Reconexão: histórico persistido
    acc.socket.close()
    check(await wait_until(func(): return not acc.server_ready, 5.0), "conexão caiu")
    check(await wait_until(func(): return acc.has_profile(), 12.0), "reconectou com a conta")
    ui.open_dm(ui.data["friends"][0]["user_id"], ui.data["friends"][0], "list")
    check(await wait_until(func(): return not ui.dm_loading and bubbles(ui).size() == 4, 6.0), "após reconectar, o histórico persistido volta")
    # Bloqueio: histórico visível, sem envio
    var ana_id = ui.dm_id
    ui.open_profile(ana_id)
    check(await wait_until(func(): return ui.screen == "profile" and ui.profile.has("nickname"), 5.0), "perfil de PeerAna")
    press(ui, "BLOQUEAR")
    press(ui, "CONFIRMAR")
    check(await wait_until(func(): return ui.profile.get("relation") == "blocked", 5.0), "PeerAna bloqueada")
    check(buttons(ui, "MENSAGEM").is_empty(), "sem botão MENSAGEM para bloqueado")
    ui.open_dm(ana_id, ui.profile, "profile")
    check(await wait_until(func(): return not ui.dm_loading, 5.0) and not ui.dm_can_send and not ui.dm_input.editable, "bloqueado: conversa sem envio")
    check(bubbles(ui).size() == 4 and ui.box.find_child("DmReason", true, false) != null, "histórico antigo visível com o motivo")
    ui.dm_can_send = true  # força o envio pelo cliente: o servidor precisa recusar
    ui.dm_input.editable = true
    ui.dm_input.text = "fura bloqueio"
    ui.send_dm()
    check(await wait_until(func(): return ui.notice.visible and "bloqueou" in ui.notice.text, 5.0), "servidor recusa DM com bloqueio (mesmo se o cliente tentar)")
    await shot(ui, "7_bloqueado")
    press(ui, "VOLTAR")
    check(ui.screen == "profile", "VOLTAR da conversa volta ao perfil")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
