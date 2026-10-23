extends SceneTree
## R177f · XEQUE: telas de VITÓRIA / DERROTA no celular (em pé e deitado) e no PC.
var fails := 0
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
	await hub.open_xeque()
	await frames(6)
	var ui = hub.xeque
	ui.start_game()
	await frames(4)
	for w in [0, 1]:
		var g = ui.g
		g.winner = w
		g.finish_order = [2, 3, 1] if w == 0 else [3, 2, 0]
		g.eliminated_round = [-1, 17, 6, 1] if w == 0 else [8, -1, 6, 1]
		ui._finish()
		ui.over_t = 3.0
		await frames(10)
		await shot("vitoria" if w == 0 else "derrota")
		# R177j · os 3 botões da arte respondem dentro da tela
		var ids := []
		var vis := Rect2(-ui.origin / ui.k, Vector2(size) / ui.k)
		for h in ui.hits:
			if String(h.id) in ["again", "over_tutorial", "over_menu"] and vis.encloses(h.rect): ids.append(String(h.id))
		var ok := ids.size() == 3
		print(("PASS " if ok else "FAIL ") + "botões do resultado %s: %s" % [ui.layout, ids])
		if not ok: fails += 1
	print("RESULT ", "OK" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
