extends SceneTree
## R176.8 · prints de TODOS os botões de saída vermelhos (placas limpas): recorte de cada botão com BackPulse.
var out := []
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func grab(tag: String):
	var d := OS.get_environment("SHOT_DIR")
	await create_timer(0.5).timeout
	await frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if d != "": img.save_png(d.path_join(OS.get_environment("SHOT_TAG") + tag + ".png"))
	var k := 0
	for p in root.find_children("BackPulse", "", true, false):
		var b := p.get_parent() as Control
		if b == null or not b.is_visible_in_tree(): continue
		var r := Rect2i(b.get_global_rect().grow(6)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x < 4 or r.size.y < 4: continue
		print("BTN %s/%d %s mode=%s rect=%s" % [tag, k, b.name, p._mode, r])
		if d != "": img.get_region(r).save_png(d.path_join("%s_btn%d.png" % [tag, k]))
		k += 1
func run():
	var size := Vector2i(1920, 1080)
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
	await create_timer(1.0).timeout
	await grab("home")
	var hub = stage.hub
	for id in ["settings", "bot", "history", "about", "profile"]:
		hub.show_page(id)
		await grab("pg_" + id)
	hub.show_page("main")
	hub.crowns_client().open_panel()
	await grab("coroas")
	hub.crowns_client().panel.close()
	stage._open_casual()
	await create_timer(0.8).timeout
	await grab("online")
	quit(0)
