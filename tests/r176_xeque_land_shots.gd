extends SceneTree
## R176.2 · XEQUE no celular deitado (iPhone): mão escolhida + vez. Prints para conferir tamanhos.\n## R177b · também online (botão CHAT da mesa).
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(2000, 924)
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
	var hub = stage.hub
	await hub.open_xeque()
	await frames(10)
	var ui = hub.xeque
	ui.seed_override = 77
	ui.start_game()
	await frames(4)
	ui._process(ui.INTRO_T); ui._process(3.0); ui._process(3.0)
	var g = ui.g
	g.turn = 0
	g.last_play = {}
	ui._begin_turn()
	ui._process(3.0); ui._process(3.0)
	await frames(4)
	ui.toggle_card(0)
	print("layout ", ui.layout, " k ", ui.k, " extra ", ui.get("wide_extra"))
	await shot("xeque_deitado")
	# R177b · online: botão CHAT da mesa no lugar reservado (não pode cobrir nada nem sair da tela)
	ui.online = true
	var pc = stage.get("party_chat")
	if pc != null:
		pc.bind("room-t", "xeque", ["Gabriel", "Torre Velha", "Dama de Ferro", "SextoSentro"])
		pc.unread = 2
	ui._sync_chat_dock()
	await frames(6)
	if pc != null:
		var tr: Rect2 = pc.toggle.get_global_rect()
		print("chat ", tr, " vs ", Vector2(size))
	await shot("xeque_deitado_online")
	quit(0)
