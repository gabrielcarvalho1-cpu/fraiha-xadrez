extends SceneTree
## R152 · cartão de convite NO MEIO da tela, com fundo escurecido, e os campos HTML de baixo (busca de amigos)
## escondidos enquanto ele está aberto (no celular o "Buscar jogador" aparecia por cima do cartão).
const WebText := preload("res://ui_v022/web_text_field.gd")
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func shot(name: String):
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var sz := OS.get_environment("SHOT_SIZE")
	if sz != "":
		var p := sz.split("x")
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(int(p[0]), int(p[1])); root.content_scale_size = root.size
		await process_frame
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior"}
	acc.send_hook = func(_m): pass
	var soc = stage.social_ui
	soc.open()
	soc.data = {"friends": [{"user_id": "u2", "nickname": "Isabela_Godoy", "avatar_id": "warrior", "presence": "online"}], "received": [], "sent": [], "blocked": []}
	soc.has_list = true
	soc._show("list")
	await frames(6)
	await shot("lista_antes")
	var iv = stage.invite_ui
	var inv := {"id": "i1", "role": "sender", "from": {"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior"},
		"to": {"user_id": "u2", "nickname": "Isabela_Godoy", "avatar_id": "warrior"}, "mode": "", "game": "marcha", "mode_name": "MARCHA REAL",
		"minutes": 0, "expires_in_ms": 59000, "status": "pending", "table": "bots"}
	acc.server_message.emit({"type": "invite_sent", "invite": inv})
	await frames(6)
	var vs: Vector2 = root.get_visible_rect().size
	var r: Rect2 = iv.panel.get_global_rect()
	r.size *= iv.panel.scale
	check(iv.panel.visible and iv.dim.visible, "cartão de convite e fundo escurecido aparecem")
	check(absf(r.get_center().y - vs.y / 2.0) < vs.y * 0.08, "cartão no MEIO da tela (centro %d de %d)" % [r.get_center().y, vs.y])
	check(r.position.x >= 0 and r.end.x <= vs.x + 1 and r.position.y >= 0 and r.end.y <= vs.y + 1, "cartão inteiro dentro da tela")
	var search = soc.get("search_input")
	check(search == null or WebText._covered_for(search), "campo de busca (HTML no celular) escondido enquanto o convite está aberto")
	await shot("convite_meio")
	acc.server_message.emit({"type": "invite_updated", "invite": inv.merged({"status": "cancelled"}, true)})
	await frames(4)
	var t0 := Time.get_ticks_msec()
	while iv.panel.visible and Time.get_ticks_msec() - t0 < 6000: await process_frame
	check(not iv.panel.visible and not iv.dim.visible, "convite encerrado: cartão e fundo somem")
	check(search == null or not WebText._covered_for(search), "campo de busca volta a aparecer")
	print("FAILS ", failures)
	quit(1 if failures else 0)
