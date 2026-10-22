extends SceneTree
## R176.8 · XEQUE: cartas na mesa e tabuleiro sem serrilhado (prints PC e celular).
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
	var size := Vector2i(1672, 941)
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
	await shot("x1_mesa")
	ui.toggle_card(0); ui.toggle_card(1)
	ui.human_play()
	for i in 6:
		ui._process(0.3)
	await frames(3)
	await shot("x2_cartas_na_mesa")
	print("XQ OK")
	quit(0)
