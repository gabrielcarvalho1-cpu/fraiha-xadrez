extends SceneTree
## R181 · conta nova: depois do apelido, convite do 1º desafio (BOT MADEIRA); aceitar abre a partida; pular vai ao menu.
var fails := 0
var sent: Array = []
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func evnames() -> Array:
	return sent.filter(func(m): return m.get("type") == "ui_event").map(func(m): return m.name)
func run():
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.send_hook = func(m): sent.append(m)
	# conta nova escolhe o apelido → servidor devolve o perfil
	acc._receive({"type": "acct_state", "user_id": "u1", "profile": null, "needs_nickname": true})
	acc.create_profile("Novato")
	acc._receive({"type": "acct_state", "user_id": "u1", "profile": {"user_id": "u1", "nickname": "Novato", "avatar_id": "warrior"}, "needs_nickname": false, "bots": {"available": true, "defeated": []}})
	await create_timer(1.2).timeout
	var nm = stage.hub.notice_modal
	check(nm != null and nm.visible and nm.title_label.text == "SEU PRIMEIRO RIVAL", "convite do 1º desafio aparece")
	check("first_bot_shown" in evnames(), "evento: viu o convite")
	await shot("01_primeiro_rival")
	nm.yes_button.pressed.emit()
	await frames(20)
	check(stage.mode == "bot" and String(stage.bot_controller.bot_id) == "madeira", "aceitou: partida contra o BOT MADEIRA")
	check("first_bot_accept" in evnames(), "evento: aceitou")
	await shot("02_partida")
	# conta antiga entrando de novo: nada aparece
	stage.open_home()
	await frames(10)
	acc._receive({"type": "acct_state", "user_id": "u1", "profile": {"user_id": "u1", "nickname": "Novato", "avatar_id": "warrior"}, "needs_nickname": false})
	await create_timer(1.2).timeout
	check(not nm.visible, "login normal (conta antiga): sem convite")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
