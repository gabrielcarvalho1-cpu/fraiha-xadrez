extends SceneTree
## R180 · o jogo conta a TELA atual para o servidor (ui_screen, só o nome) e o aparelho (ui_hello) depois da identidade;
## aviso de NOVA ATUALIZAÇÃO só no lobby (nunca em partida). PC e celular (SHOT_SIZE).
var fails := 0
var sent: Array = []
func _initialize(): call_deferred("run")
func frames(n := 6):
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
func screens() -> Array:
	var out := []
	for m in sent: if m.get("type") == "ui_screen": out.append(m.name)
	return out
func settle(): await create_timer(1.4).timeout
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
	var acc = stage.account
	acc.send_hook = func(m): sent.append(m)
	await settle()
	check(screens().is_empty(), "sem identidade: nada de tela enviada")
	acc.server_message.emit({"type": "guest_state", "token": "x", "nickname": "Convidado 1"})
	await settle()
	var hello := sent.filter(func(m): return m.get("type") == "ui_hello")
	check(hello.size() == 1 and String(hello[0].get("version", "")) != "", "ui_hello com versão: %s" % [hello])
	print("telas: ", screens())
	check(screens().size() >= 1, "tela atual enviada depois da identidade: %s" % [screens()])
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	await settle()
	var hub = stage.hub
	hub.show_page("main")
	await settle()
	for v in stage.screen_tracker.debug_visible(): print("VIS ", v)
	check(screens().back() == "Início", "Início: %s" % [screens().back()])
	hub.crowns_client().open_pass()
	await settle()
	check(screens().back() == "Passe da Temporada", "Passe: %s" % [screens().back()])
	hub.crowns_client().pass_panel.close()
	await settle()
	hub.open_news()
	await settle()
	check(screens().back() == "Novidades", "Novidades: %s" % [screens().back()])
	hub.news_ui.close()
	hub.open_support()
	await settle()
	check(screens().back() == "Suporte", "Suporte: %s" % [screens().back()])
	hub.support_ui.close()
	await settle()
	check(screens().back() == "Início", "voltou ao Início: %s" % [screens().back()])
	var extra := [["open_leaderboard", "Ranking"], ["open_premium", "Seja Membro (Premium)"], ["open_xeque", "Xeque"], ["open_marcha", "Marcha Real"]]
	for e in extra:
		hub.call(e[0])
		await settle()
		check(screens().back() == e[1], "%s: %s" % [e[0], screens().back()])
		if e[1] in ["Xeque", "Marcha Real"]: check(stage.screen_tracker.in_game(), "%s conta como jogo (sem aviso de atualização)" % e[1])
		for v in stage.screen_tracker.debug_visible(): print("VIS ", v)
		await shot("00_" + e[0])
		# fecha o que abriu
		for n in [hub.get("leaderboard_ui"), hub.get("premium"), hub.get("xeque"), hub.get("marcha")]:
			if n != null and is_instance_valid(n) and n.has_method("close"): n.close()
		await settle()
	print("telas: ", screens())
	# aviso de atualização: em partida NÃO aparece
	var uw = stage.update_watch
	stage.mode = "bot"
	uw.test_force = true
	await settle()
	check(hub.notice_modal == null or not hub.notice_modal.visible, "em partida: sem aviso")
	stage.mode = "home"
	await settle()
	check(hub.notice_modal != null and hub.notice_modal.visible and hub.notice_modal.title_label.text == "NOVA ATUALIZAÇÃO", "no lobby: aviso NOVA ATUALIZAÇÃO")
	await shot("01_nova_atualizacao")
	check(screens().back().begins_with("Janela"), "tela do aviso: %s" % [screens().back()])
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
