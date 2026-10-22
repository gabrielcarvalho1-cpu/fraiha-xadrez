extends SceneTree
## R176.6 · CHAT da mesa (XEQUE e MARCHA REAL) no celular, em pé e deitado: botão e chat aberto (prints).
func _initialize(): call_deferred("run")
func frames(n := 8):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(1170, 2532)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.get_node("MainHub")
	var pc = stage.party_chat
	for game in ["xeque", "marcha"]:
		var m
		if game == "marcha":
			await hub.open_marcha()
			m = hub.marcha
			m.tut_page = -1
			m.start_game()
		else:
			await hub.open_xeque()
			m = hub.xeque
			m.start_game()
		await frames(10)
		pc.bind("sala-teste", game, ["Você", "Ana", "Bia", "Caio"])
		m.online = true
		if m.has_method("_relayout"): m._relayout()
		await frames(8)
		pc.messages.clear()
		for msg in [["Ana", "boa sorte pessoal!", 1], ["Você", "valeu, bora!", 0], ["Caio", "essa jogada foi blefe hein", 3]]:
			pc._on_message({"type": "party_chat_msg", "room_id": "sala-teste", "nickname": msg[0], "text": msg[1], "from_seat": msg[2]})
		await shot(game + "_botao")
		pc.set_open(true)
		await frames(8)
		await shot(game + "_aberto")
		pc.set_open(false)
		if m.has_method("close"): m.close()
		await frames(10)
	quit(0)
