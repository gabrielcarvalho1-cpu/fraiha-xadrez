extends SceneTree
## R176.1 · prints dos botões de saída no vinho do jogo: JOGAR ONLINE, SUA CONTA, Configurações e contra o computador.
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(3)
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
	var hub = stage.hub
	hub.show_page("bot")
	await create_timer(0.6).timeout
	await shot("bot")
	stage._open_casual()
	await create_timer(0.8).timeout
	await shot("online")
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.email = "contato@fraihaxadrez.com"
	acc.profile = {"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior"}
	stage.open_home()
	await frames(6)
	stage.account_ui.open("account")
	await create_timer(0.8).timeout
	await shot("conta")
	quit(0)
