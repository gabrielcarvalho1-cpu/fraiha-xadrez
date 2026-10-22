extends SceneTree
## R176.2 · INSTAGRAM dentro da COMUNIDADE (pergunta com DISCORD / INSTAGRAM / AGORA NÃO); fora da tela do jogo.
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
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var IG = load("res://social/instagram_link.gd")
	var DC = load("res://social/community_link.gd")
	var opened := []
	IG.opener = func(u): opened.append(u)
	DC.opener = func(u): opened.append(u)
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	await create_timer(0.5).timeout
	check(root.find_child("InstagramButton", true, false) == null and root.find_child("InstagramMais", true, false) == null, "sem botão de Instagram solto na tela do jogo")
	stage.hub.open_community()
	await create_timer(1.5).timeout
	await shot("comunidade")
	var alt: Button = root.find_child("NoticeAlt", true, false)
	check(alt != null and alt.is_visible_in_tree() and alt.text == "INSTAGRAM", "COMUNIDADE: botão INSTAGRAM")
	if alt != null: alt.pressed.emit()
	check(opened.size() == 1 and String(opened[0]) == IG.URL, "INSTAGRAM abre o @fraihaxadrez")
	stage.hub.open_community()
	await frames(4)
	var yes: Button = root.find_child("NoticeYes", true, false)
	if yes != null: yes.pressed.emit()
	check(opened.size() == 2 and String(opened[1]) == DC.URL, "DISCORD continua abrindo o servidor")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
