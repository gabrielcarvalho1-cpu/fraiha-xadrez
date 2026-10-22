extends SceneTree
## R176 · prints dos botões de saída com o tom avermelhado (no pico da "respiração").
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	for p in root.find_children("BackPulse", "", true, false): p._t = 1.0   # pico (PERIOD/2)
	await frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
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
	await create_timer(1.2).timeout
	var hub = stage.hub
	for id in ["settings", "bot", "profile"]:
		hub.show_page(id)
		await create_timer(0.4).timeout
		await shot("pagina_" + id)
	hub.open_premium("founder")
	await create_timer(0.4).timeout
	hub.premium.open_payment("founder")
	await create_timer(0.4).timeout
	await shot("pagamento")
	stage._start_bot("easy", "w")
	await create_timer(0.6).timeout
	await shot("partida_bot")
	quit(0)
