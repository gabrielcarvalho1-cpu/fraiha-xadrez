extends SceneTree
## R136 · prévia (aprovação): caixa "ativar o tema da liga?" sobre a página das Ligas. SHOT_DIR, SHOT_SIZE, SHOT_TAG.
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func run():
	var sz := OS.get_environment("SHOT_SIZE").split("x")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(int(sz[0]), int(sz[1])); root.content_scale_size = root.size
	await process_frame
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(25)
	if stage.account_ui.is_open(): stage.account_ui.close()
	stage.account._receive({"type": "leagues_preview", "enabled": true})
	await frames(4)
	var hub = stage.hub
	if stage.has_method("open_mobile_page") and "--mobile-test" in OS.get_cmdline_user_args(): pass
	hub.show_page("ranking")
	await frames(20)
	hub.ask("LIGA OURO", "Você deseja ativar o tema de peças e tabuleiro da Liga Ouro nas suas partidas?", "SIM", "NÃO", func(): pass)
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "tema_caixa.png"))
	quit(0)
