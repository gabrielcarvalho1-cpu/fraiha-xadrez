extends SceneTree
## R184e · prévia: vitória contra o BOT MADEIRA no celular (arte padrão + efeitos + coroas da prévia).
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
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(15)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	stage._start_bot("madeira", "w")
	await frames(10)
	var rm = stage.reward_modal
	rm.crowns_preview = 50
	rm.show_progress("madeira", preload("res://bot/bot_ladder.gd").reward("madeira"), true)
	for i in 120: await process_frame
	await shot("vitoria_bot")
	quit(0)
