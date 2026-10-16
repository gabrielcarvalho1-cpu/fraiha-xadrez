extends SceneTree
## R124 · letras na escala REAL do jogo (desenho 1920x1080 reduzido para a janela): Home, Ranking, partida
## contra o bot, XEQUE (como jogar) e Marcha (salão). Só prints.
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1366x768 xvfb-run godot --rendering-driver opengl3 --path . -s tests/r124_letras_shots.gd [-- --mobile-test]
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var mobile := "--mobile-test" in OS.get_cmdline_user_args()
	var p := OS.get_environment("SHOT_SIZE").split("x") if OS.get_environment("SHOT_SIZE") != "" else PackedStringArray(["1366", "768"])
	root.size = Vector2i(int(p[0]), int(p[1]))
	if not mobile: root.content_scale_size = Vector2i(1920, 1080)
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(14)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	await shot("01_home")
	hub.open_leaderboard()
	await frames(8)
	await shot("02_ranking")
	hub.leaderboard_ui.close()
	stage._start_bot("wood", "w")
	stage.bot_controller.stop()
	await frames(10)
	await shot("03_partida_bot")
	stage._go_home() if stage.has_method("_go_home") else null
	await frames(6)
	await hub.open_xeque()
	await frames(10)
	await shot("04_xeque_como_jogar")
	hub.xeque.close()
	await frames(4)
	await hub.open_marcha()
	await frames(10)
	await shot("05_marcha")
	print("AUDIT LETRAS OK")
	quit(0)
