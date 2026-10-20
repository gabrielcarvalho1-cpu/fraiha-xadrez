extends SceneTree
## R168 · VOLTAR passo a passo: COROAS → LOJA/PASSE → VOLTAR volta para COROAS → VOLTAR volta para a Home.
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func run():
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.get_node("MainHub")
	var cl = hub.crowns_client()
	cl.open_panel()
	await frames()
	cl.open_store("title")
	await frames()
	check(cl.store_panel.is_open() and not cl.panel.is_open(), "loja aberta por cima de COROAS")
	if OS.get_environment("SHOT_DIR") != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("loja_voltar.png"))
	cl.store_panel.close_button.pressed.emit()
	await frames()
	check(not cl.store_panel.is_open() and cl.panel.is_open(), "VOLTAR da loja volta para COROAS")
	cl.panel.close_button.pressed.emit()
	await frames()
	check(not cl.panel.is_open(), "VOLTAR de COROAS volta para a Home")
	cl.open_panel()
	await frames()
	cl.open_pass()
	await frames()
	cl.pass_panel.esc_close()
	await frames()
	check(cl.panel.is_open(), "ESC no PASSE volta para COROAS")
	cl.panel.close()
	cl.open_store("frame")   # aberta direto (fora de COROAS): VOLTAR vai para a Home
	await frames()
	cl.store_panel.close_button.pressed.emit()
	await frames()
	check(not cl.panel.is_open() and not cl.store_panel.is_open(), "loja aberta direto: VOLTAR vai para a Home")
	print("RESULT " + ("OK" if fails == 0 else "FALHOU %d" % fails))
	quit(1 if fails else 0)
