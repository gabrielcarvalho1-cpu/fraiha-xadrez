extends SceneTree
## R176.2 · CRIAR CONTA e RECUPERAR SENHA no celular: tudo dentro da moldura; VOLTAR no padrão.
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(390, 844)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	var ui = stage.account_ui
	for pg in ["signup", "recover"]:
		ui.open(pg)
		await create_timer(0.6).timeout
		var box: Control = ui.box
		var inner_bottom: float = ui.INNER.end.y
		var content_bottom: float = box.position.y + box.get_combined_minimum_size().y * box.scale.y
		check(content_bottom <= inner_bottom + 1.0, "%s: conteúdo dentro da moldura (%.0f ≤ %.0f)" % [pg, content_bottom, inner_bottom])
		await shot(pg)
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
