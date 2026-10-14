extends SceneTree
## R100 · caixinha "Li e aceito os Termos" no cadastro e na escolha do nome (toda conta nova, inclusive Google).
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 8):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(1672, 941)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	var ui = stage.account_ui
	var acc = stage.account
	ui.open("signup")
	await frames(8)
	check(is_instance_valid(ui.terms_check) and not ui.terms_check.button_pressed, "cadastro: caixinha desmarcada")
	await shot("cadastro")
	check(not ui._terms_ok(), "cadastro sem marcar: não deixa criar")
	await frames(3)
	await shot("cadastro_aviso")
	ui.hide_ui()
	acc.user_id = "u-novo"; acc.access_token = "t"; acc.server_ready = true; acc.needs_nickname = true; acc.profile = {}
	acc.terms_accepted = false
	ui.open("nickname")
	await frames(8)
	check(is_instance_valid(ui.terms_check), "escolha do nome (Google): tem a caixinha")
	await shot("nome")
	ui.terms_check.button_pressed = true
	await frames(3)
	check(acc.terms_accepted and ui._terms_ok(), "marcou: libera criar")
	await shot("nome_marcado")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
