extends SceneTree
## R177f · XEQUE/MARCHA: caixa COMO VOCÊ QUER JOGAR? (moldura ornamentada, ícones lisos)
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func run():
	var size := Vector2i(1600, 900)
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
	var po = stage.find_child("PartyOnlineUI", true, false)
	po.open_choice("xeque")
	await frames(8)
	var bt = po.find_child("PartyChoiceOnline", true, false)
	if bt != null: bt.mouse_entered.emit()
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "escolha.png"))
	quit(0)
