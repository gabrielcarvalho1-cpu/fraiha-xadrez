extends SceneTree
## R177f · XEQUE: telas de VITÓRIA / DERROTA no celular (em pé e deitado) e no PC.
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
	var size := Vector2i(430, 932)
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
	await frames(6)
	var ui = hub.xeque
	ui.start_game()
	await frames(4)
	for w in [0, 1]:
		var g = ui.g
		g.winner = w
		g.finish_order = [2, 3, 1] if w == 0 else [3, 2, 0]
		g.eliminated_round = [-1, 17, 6, 1] if w == 0 else [8, -1, 6, 1]
		ui._finish()
		ui.over_t = 3.0
		await frames(10)
		await shot("vitoria" if w == 0 else "derrota")
	quit(0)
