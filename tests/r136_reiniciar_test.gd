extends SceneTree
## R136 · contra o bot no PC, o antigo botão REINICIAR (seta circular) voltava depois do 1º lance, sempre que o jogo
## se atualizava, e cobria a barra da voz. Com o layout da Madeira (e das ligas) ele não aparece nunca.
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/r136_reiniciar_test.gd [SHOT_DIR=...]
var failures := 0
var checks := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _click(p: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new(); e.pressed = true; e.button_index = MOUSE_BUTTON_LEFT; e.position = p
	return e
func _initialize(): call_deferred("run")
func run():
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900); root.content_scale_size = root.size
	await process_frame
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(25)
	if stage.account_ui.is_open(): stage.account_ui.close()
	stage.account._receive({"type": "leagues_preview", "enabled": true})
	for t in ["wood", "gold"]:
		check(stage.theme_manager.apply_theme(t), "tema %s" % t)
		stage._start_bot("bronze", "w")
		await frames(30)
		var g = stage.game
		g._handle_game_input(_click(g.square_center(Vector2i(4, 6))))
		await frames(2)
		g._handle_game_input(_click(g.square_center(Vector2i(4, 4))))
		await frames(90)
		check(g.game_started and g.move_count >= 1, "%s: partida andando" % t)
		stage._refresh_input()   # o stage se atualiza (janela, voz, ESC…): era aqui que o REINICIAR voltava
		check(not stage.desk_restart.visible, "%s: REINICIAR não volta logo depois da atualização" % t)
		await frames(3)
		check(not stage.desk_restart.is_visible_in_tree(), "%s: REINICIAR continua escondido" % t)
		var shot := OS.get_environment("SHOT_DIR")
		if shot != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot.path_join("r136_bot_%s.png" % t))
		stage.open_home()
		await frames(6)
	print("RESULT " + ("%d/%d OK" % [checks, checks] if failures == 0 else "%d FALHAS" % failures))
	quit(0 if failures == 0 else 1)
