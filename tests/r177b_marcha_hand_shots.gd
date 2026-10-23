extends SceneTree
## R177b · MARCHA no celular em pé: sem cartas na mão, a faixa de baixo fica limpa (sem listras pretas).
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
	var size := Vector2i(430, 932)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
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
	await ui.start_game()
	var t0 := Time.get_ticks_msec()
	while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 30000: await process_frame
	await shot("marcha_com_mao")
	ui.online = true
	ui._apply_snapshot({"turn_left_ms": 9000, "my_turn": true, "turn": 0, "hand_counts": [0, 4, 4, 4], "my_hand": []})
	await frames(6)
	await shot("marcha_online_sem_mao")
	quit(0)
