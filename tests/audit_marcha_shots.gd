extends SceneTree
## Auditoria visual · MARCHA REAL: tutorial (todas as páginas), salão, partida com cartas na mão, carta escolhida,
## peões andando e resultado. Só prints.
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path . -s tests/audit_marcha_shots.gd [-- --mobile-test]
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))

func run():
	var size := Vector2i(1672, 941)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://marcha_access.cfg"))
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	await hub.open_marcha()
	await frames(10)
	var ui = hub.marcha
	var page := 0
	while ui.tut_page >= 0 and page < 12:
		await shot("m0%d_tutorial" % page)
		ui._on_hit("tut_next")
		await frames(3)
		page += 1
	await shot("m10_salao")
	await ui.start_game()
	await frames(10)
	for i in 40: ui._process(0.1)
	await shot("m11_partida")
	var g = ui.g
	if g != null and ui.awaiting_play():
		for i in g.hands[0].size():
			ui.pick_card(i)
			await frames(2)
			if ui.can_play() or ui.needs_pieces(): break
	await shot("m12_carta_escolhida")
	var guard := 0
	var mid := false
	while ui.mode == "game" and guard < 4000:
		guard += 1
		ui._process(0.2)
		if not mid and guard == 200:
			await frames(3)
			await shot("m13_meio_partida")
			mid = true
		if ui.awaiting_play() and g.turn == 0: ui._auto_play()
	await frames(10)
	await shot("m14_resultado")
	print("AUDIT MARCHA OK")
	quit(0)
