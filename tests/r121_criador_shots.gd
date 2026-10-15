extends SceneTree
## R121 · APOIE UM CRIADOR: sem criador, apoiando (com presente), código inválido.
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
func find_named(n: Node, prefix: String) -> Array:
	var out := []
	if n.name.begins_with(prefix) and n is Control and n.is_visible_in_tree(): out.append(n)
	for c in n.get_children(): out.append_array(find_named(c, prefix))
	return out
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
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.get_node("MainHub")
	var acc = stage.account
	acc.user_id = "u-me"; acc.access_token = "teste"; acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	hub.show_page("main")
	await frames(6)
	var cl = hub.crowns_client()
	cl.open_panel()
	await frames(6)
	check(find_named(root, "CrownsOpenCreator").size() == 1, "painel COROAS com APOIE UM CRIADOR")
	cl.open_creator()
	acc.server_message.emit({"type": "creator_state", "available": true, "link_days": 30, "linked": null})
	await frames(6)
	await shot("01_sem_criador")
	acc.server_message.emit({"type": "creator_state", "available": true, "link_days": 30, "linked": {"code": "XADREZDOJOAO", "name": "João Xadrez", "expires_at": "2026-11-14T15:00:00Z"}, "just_linked": "João Xadrez", "gift": 200})
	await frames(6)
	check(String(find_named(root, "CreatorCurrent")[0].text).contains("JOÃO XADREZ"), "mostra quem apoia")
	check(String(find_named(root, "CreatorMsg")[0].text).contains("200 Coroas"), "presente avisado")
	var box: Rect2 = cl.creator_panel._body_rect.grow(1.0)
	check(cl.creator_panel.body.size.x <= box.size.x, "conteúdo cabe na moldura")
	await shot("02_apoiando")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
