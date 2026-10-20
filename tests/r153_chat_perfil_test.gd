extends SceneTree
## R153 · CHAT GLOBAL no celular: um toque numa mensagem abre VER PERFIL / SILENCIAR / DENUNCIAR e ela FICA
## aberta (o celular manda o toque duas vezes: toque + clique emulado; antes abria e fechava junto).
## Depois, um toque em VER PERFIL abre o perfil na tela de Amigos. Toques de verdade (push_input).
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func tap(pos: Vector2):
	# como o navegador do celular: toque (ScreenTouch) e, logo depois, o clique emulado (MouseButton)
	for pressed in [true, false]:
		var t := InputEventScreenTouch.new(); t.index = 0; t.position = pos; t.pressed = pressed
		root.push_input(t)
		var m := InputEventMouseButton.new(); m.button_index = MOUSE_BUTTON_LEFT; m.position = pos; m.global_position = pos; m.pressed = pressed
		root.push_input(m)
		await frames(2)
func run():
	var sz := OS.get_environment("SHOT_SIZE")
	if sz == "": sz = "390x844"
	var p := sz.split("x")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(int(p[0]), int(p[1])); root.content_scale_size = root.size
	await process_frame
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	var acc = stage.account
	var sent: Array = []
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior"}
	acc.send_hook = func(m): sent.append(m)
	hub.open_global_chat()
	await frames(4)
	var gc = hub.global_chat_ui
	acc.server_message.emit({"type": "gchat_history", "can_send": true, "online": 2, "messages": [
		{"id": 1, "user_id": "u2", "nickname": "Isabela_Godoy", "text": "Oi mor, tá aí?", "ts": "2026-10-19T23:42:00.000Z"},
		{"id": 2, "user_id": "u1", "nickname": "SextoSentro", "text": "Oiii", "ts": "2026-10-19T23:43:00.000Z"}]})
	await frames(8)
	var rows: Array = gc.list.get_children().filter(func(n): return not n.is_queued_for_deletion())
	var line: Control = rows[0].get_child(0)
	await tap(line.get_global_rect().get_center())
	await frames(6)
	check(gc.selected == 1, "um toque na mensagem: botões abertos e continuam abertos")
	var prof: Button = gc.list.find_child("GchatProfile", true, false)
	check(prof != null and prof.is_visible_in_tree(), "VER PERFIL aparece")
	if prof == null:
		print("FAILS ", failures); quit(1); return
	sent.clear()
	await tap(prof.get_global_rect().get_center())
	await frames(8)
	var soc = stage.social_ui
	check(not gc.visible and soc.is_open() and soc.profile_id == "u2" and soc.screen == "profile", "um toque em VER PERFIL abre o perfil de quem escreveu")
	check(sent.any(func(m): return String(m.get("type", "")) == "social_profile" and String(m.get("user_id", "")) == "u2"), "perfil pedido ao servidor")
	# R161 · SILENCIAR e depois REATIVAR (antes não tinha como voltar a ver)
	hub.open_global_chat()
	await frames(4)
	acc.server_message.emit({"type": "gchat_history", "can_send": true, "online": 2, "messages": [
		{"id": 1, "user_id": "u2", "nickname": "Isabela_Godoy", "text": "Oi mor, tá aí?", "ts": "2026-10-19T23:42:00.000Z"},
		{"id": 2, "user_id": "u1", "nickname": "SextoSentro", "text": "Oiii", "ts": "2026-10-19T23:43:00.000Z"}]})
	await frames(8)
	rows = gc.list.get_children().filter(func(n): return not n.is_queued_for_deletion())
	await tap(rows[0].get_child(0).get_global_rect().get_center())
	await frames(6)
	var mute: Button = null
	for b in gc.list.find_children("*", "Button", true, false):
		if (b as Button).text == "SILENCIAR": mute = b
	check(mute != null, "SILENCIAR aparece")
	if mute != null:
		await tap(mute.get_global_rect().get_center())
		await frames(6)
	var live := func(): return gc.list.get_children().filter(func(n): return not n.is_queued_for_deletion()).size()
	check(live.call() == 1 and gc.muted_bar.visible, "silenciado: some a mensagem e aparece a faixa Silenciados")
	if OS.get_environment("SHOT_DIR") != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("chat_silenciados.png"))
	var un: Button = gc.muted_bar.find_child("GchatUnmute_u2", true, false)
	check(un != null and un.is_visible_in_tree() and "REATIVAR" in un.text, "botão REATIVAR com o nome")
	if un != null:
		await tap(un.get_global_rect().get_center())
		await frames(6)
	check(live.call() == 2 and not gc.muted_bar.visible, "REATIVAR: as mensagens voltam")
	print("FAILS ", failures)
	quit(1 if failures else 0)
