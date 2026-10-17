extends SceneTree
## R142 · PROMOÇÃO DO PEÃO: no celular o mesmo painel do PC (desenhado no tabuleiro), tocável; e prints.
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func shot(name: String):
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func tap(pos: Vector2):
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await frames(2)
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
	var g = stage.game
	stage._start_bot("madeira", "w")
	stage.bot_controller.stop()
	await frames(12)
	# peão branco em a7 prestes a promover (sem bot: partida local da mesa)
	g.bot = null
	g.pieces = {Vector2i(0, 0): "wP", Vector2i(4, 7): "wK", Vector2i(4, 0): "bK"}
	g.promotion_pending = true
	g.promotion_color = "w"
	g.promotion_cell = Vector2i(0, 0)
	g.queue_redraw()
	await frames(8)
	await shot("promocao")
	check(not (stage.mobile_promotion.visible), "painel simples antigo do celular não aparece")
	var r: Rect2 = g.promotion_choice_rect(2)   # bispo
	var center: Vector2 = g.get_global_transform_with_canvas() * r.get_center()
	await tap(center)
	await frames(4)
	check(not g.promotion_pending and g.pieces.get(Vector2i(0, 0), "") == "wB", "toque no BISPO promove para bispo (%s)" % g.pieces.get(Vector2i(0, 0), ""))
	print("FAILS ", failures)
	quit()
