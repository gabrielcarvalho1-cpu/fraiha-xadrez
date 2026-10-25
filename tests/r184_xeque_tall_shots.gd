extends SceneTree
## R184e · XEQUE no celular alto (app Android 1080x2400): prévia da mesa na sua vez.
## Uso: SHOT_DIR=<pasta> SHOT_TAG=x_ SHOT_SIZE=540x1200 xvfb-run godot --rendering-driver opengl3 --path . -s tests/r184_xeque_tall_shots.gd -- --mobile-test
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(540, 1200)
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
	ui._process(ui.INTRO_T * 0.5)
	await frames(20)
	ui._process(ui.INTRO_T)
	ui._process(3.0)
	ui._process(3.0)
	await frames(10)
	var g = ui.g
	if g == null:
		print("FAIL sem partida")
		quit(1)
		return
	g.turn = 0
	g.last_play = {}
	ui._begin_turn()
	ui._process(3.0); ui._process(3.0)
	await frames(4)
	ui.toggle_card(0); ui.toggle_card(2)
	if ui.view != null: ui.view.hand_zoom = 1.0; ui.view._zoom_ms = Time.get_ticks_msec(); ui.view.queue_redraw()
	await shot("mesa_sua_vez")
	quit(0)
