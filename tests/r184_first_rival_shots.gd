extends SceneTree
## R184e · prévia: tela "SEU PRIMEIRO RIVAL" do celular (com coroas, só para a prévia).
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(540, 1200)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(15)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var m = load("res://bot/first_rival_modal.gd").new()
	stage.add_child(m)
	m.open("madeira", func(id): return stage.hub.avatar_texture(id), 50)
	await frames(30)
	await shot("primeiro_rival")
	quit(0)
