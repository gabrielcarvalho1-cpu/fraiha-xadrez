extends SceneTree
## R134 · a TELA INICIAL é sempre a da Madeira (lobby completo) em qualquer liga escolhida; a liga muda a PARTIDA.
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/r134_home_fixa_test.gd [-- --mobile-test]
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
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(25)
	if stage.account_ui.is_open(): stage.account_ui.close()
	stage.account._receive({"type": "leagues_preview", "enabled": true})
	await frames(4)
	var hub = stage.hub
	for t in ["gold", "challenger", "iron"]:
		check(stage.theme_manager.apply_theme(t), "liga %s aplicada" % t)
		hub.show_page("main")
		await frames(10)
		check(hub.ref_mode, "%s: Home continua no lobby da Madeira (ref_mode)" % t)
		var shot := OS.get_environment("SHOT_DIR")
		if shot != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot.path_join("home_%s.png" % t))
		stage._start_bot("madeira", "w")
		stage.bot_controller.stop()
		await frames(8)
		check(stage.game.visual_theme == t, "%s: partida com o tabuleiro/cenário da liga (%s)" % [t, stage.game.visual_theme])
		if shot != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot.path_join("partida_%s.png" % t))
		stage.open_home()
		await frames(6)
	check(hub.selected_league == "ferro", "página das Ligas lembra a liga escolhida (%s)" % hub.selected_league)
	print("RESULT " + ("%d/%d OK" % [checks, checks] if failures == 0 else "%d FALHAS" % failures))
	quit(0 if failures == 0 else 1)
