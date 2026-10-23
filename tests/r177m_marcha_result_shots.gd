extends SceneTree
## R177m · MARCHA: telas de VITÓRIA / DERROTA (a placa por cima e a tela de resultado) no celular.
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func wait(sec: float):
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0): await process_frame
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
	hub.monetization_state.mock_reset()
	hub.open_marcha() if hub.has_method("open_marcha") else hub.menu_buttons[4].pressed.emit()
	await frames(6)
	var ui = hub.marcha
	ui.tut_page = -1
	for w in [0, 1]:
		await ui.start_game()
		await frames(10)
		ui.g.winner = w
		ui._finish()
		await wait(2.5)
		await shot(("vitoria" if w == 0 else "derrota") + "_placa")
		var ov = stage.result_overlay
		if ov.has_method("hide_result"): ov.hide_result()
		ov.dismissed.emit("x")
		await wait(1.5)
		ui.over_t = 4.0
		await frames(8)
		await shot(("vitoria" if w == 0 else "derrota") + "_tela")
	quit(0)
