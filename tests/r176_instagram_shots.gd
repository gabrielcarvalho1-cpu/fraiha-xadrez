extends SceneTree
## R176 · INSTAGRAM ao lado da COMUNIDADE (Discord): Home do PC, MAIS do celular e CONHEÇA O FRAIHA. Prints + clique.
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
	for p in root.find_children("BackPulse", "", true, false): p._t = 1.0
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	var mobile := size.y > size.x
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var IG = load("res://social/instagram_link.gd")
	var opened := []
	IG.opener = func(u): opened.append(u)
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	await create_timer(0.6).timeout
	var hub = stage.hub
	if not mobile:
		await shot("home")
		var b: BaseButton = root.find_child("InstagramButton", true, false)
		check(b != null and b.is_visible_in_tree(), "Home do PC: botão INSTAGRAM ao lado da COMUNIDADE")
		if b != null: b.pressed.emit()
		check(opened.size() == 1 and String(opened[0]) == IG.URL, "INSTAGRAM abre direto o perfil @fraihaxadrez")
	else:
		hub.mobile_ui.show_page("mais")
		await create_timer(0.5).timeout
		await shot("mais")
		var bm: BaseButton = root.find_child("InstagramMais", true, false)
		check(bm != null and bm.is_visible_in_tree(), "MAIS do celular: INSTAGRAM na linha da COMUNIDADE")
		if bm != null: bm.pressed.emit()
		check(opened.size() == 1 and String(opened[0]) == IG.URL, "INSTAGRAM abre direto o perfil @fraihaxadrez")
	if mobile: hub.mobile_ui.show_page("about")
	else: hub.show_page("about")
	await create_timer(0.4).timeout
	if not mobile:
		var topics: Array = hub.ABOUT_TOPICS
		hub._show_about_topic(topics, topics.size() - 1)
		await frames(4)
	await shot("about")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
