extends SceneTree
## R196 · prévia das abas do perfil no celular. SHOT_DIR=<pasta> xvfb-run godot --path . -s tools/appstore/perfil_abas_shots.gd -- --mobile-test
var stage
func _initialize(): call_deferred("run")
func frames(n := 8):
	for i in n: await process_frame
func shot(name: String):
	await frames(14)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(name + ".png"))
	print("SHOT ", name)
func run():
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	stage.hub.show_page("profile")
	await create_timer(1.5).timeout
	await shot("0_aberto")
	for id in ["icons", "frames", "titles", "emotes"]:
		var b = root.find_child("ProfileTabMobile_" + id, true, false)
		if b == null: print("SEM ABA ", id); continue
		b.pressed.emit()
		await create_timer(0.6).timeout
		await shot("1_" + id)
	quit()
