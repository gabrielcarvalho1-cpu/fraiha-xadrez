extends SceneTree
## R135 · partida de cada liga no layout da Madeira (PC e celular): casas e peças da liga em pixel art, cantos dourados
## por cima, arena antiga da liga escondida. Uso: xvfb-run godot ... -s tests/r135_ligas_partida_test.gd [-- --mobile-test] [SHOT_DIR]
const LeaguePixel := preload("res://cosmetics/league_pixel.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func run():
	var sz := OS.get_environment("SHOT_SIZE")
	if sz != "":
		var p := sz.split("x")
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(int(p[0]), int(p[1])); root.content_scale_size = root.size
		await process_frame
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(25)
	if stage.account_ui.is_open(): stage.account_ui.close()
	stage.account._receive({"type": "leagues_preview", "enabled": true})
	await frames(4)
	var mobile: bool = "--mobile-test" in OS.get_cmdline_user_args()
	for t in ["gold", "challenger", "esmeralda", "wood"]:
		check(stage.theme_manager.apply_theme(t), "liga %s" % t)
		stage._start_bot("madeira", "w")
		stage.bot_controller.stop()
		await frames(12)
		var g = stage.game
		if t != "wood":
			check(g.board_tiles != null, "%s: casas da liga em pixel art" % t)
			check(g.piece_override.has("wK") and g.piece_override.wK[0] == LeaguePixel.pieces(t).wK[0], "%s: peças da liga em pixel art" % t)
			if not mobile: check(g.board_corners.size() == 4, "%s: 4 enfeites dos cantos por cima" % t)
			check(not stage.theme_manager.iron_arena.visible, "%s: arena antiga escondida" % t)
		else:
			check(g.board_tiles == null, "madeira: casas da arte de sempre")
		var shot := OS.get_environment("SHOT_DIR")
		if shot != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot.path_join("%s%s.png" % [OS.get_environment("SHOT_TAG"), t]))
		stage.open_home()
		await frames(6)
	print("RESULT " + ("%d/%d OK" % [checks, checks] if failures == 0 else "%d FALHAS" % failures))
	quit(0 if failures == 0 else 1)
