extends SceneTree
## R176.8 · SUPORTE: botão em Conheça o FRAIHA → Comunidade e Suporte, tela de ticket (convidado e conta),
## envio (mensagem ticket_send) e MEUS TICKETS com a resposta. PC e celular (SHOT_SIZE).
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
	var hub = stage.hub
	if size.x > size.y:
		hub.show_page("about")
		await frames(6)
		hub._show_about_topic(hub.ABOUT_TOPICS, 5)
		await create_timer(0.4).timeout
		await shot("01_comunidade_suporte")
		check(root.find_child("AboutSupport", true, false) != null, "botão FALAR COM O SUPORTE no Conheça o FRAIHA")
	hub.open_support()
	await frames(8)
	check(hub.support_ui != null and hub.support_ui.is_open(), "tela SUPORTE abre")
	await shot("02_suporte_convidado")
	hub.support_ui.close()
	# com conta
	var acc = stage.account
	acc.user_id = "u-me"
	acc.access_token = "teste"
	acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	var orig_send = null
	hub.open_support()
	await frames(8)
	var ui = hub.support_ui
	check(root.find_child("SupportSend", true, false) != null, "conta: formulário com ENVIAR")
	ui._send()
	check(String(ui.status.text).contains("TIPO"), "sem tipo: pede o tipo")
	root.find_child("SupportCat_sugestao", true, false).pressed.emit()
	if ui.message_box != null: ui.message_box.text = "Coloquem o modo Xadrez 960, por favor!"
	else: ui.message_line.text = "Coloquem o modo Xadrez 960, por favor!"
	ui.subject.text = "Modo novo"
	await shot("03_suporte_preenchido")
	acc.server_message.emit({"type": "ticket_ok", "ticket": {"ticket_id": "t1"}})
	acc.server_message.emit({"type": "ticket_list", "available": true, "items": [
		{"ticket_id": "t1", "category": "sugestao", "category_label": "Sugestão", "subject": "Modo novo", "message": "Coloquem o modo Xadrez 960, por favor!", "status": "answered", "reply": "Boa ideia! Está na nossa lista para as próximas atualizações.", "created_at": "2026-10-22T18:40:00Z"},
		{"ticket_id": "t0", "category": "problema", "category_label": "Problema no jogo", "subject": "", "message": "A partida travou no fim e não contou o resultado.", "status": "open", "reply": "", "created_at": "2026-10-21T22:10:00Z"}]})
	await frames(6)
	check(String(ui.status.text).begins_with("Mensagem enviada"), "enviado: aviso de sucesso")
	check(root.find_child("TicketReply", true, false) != null, "MEUS TICKETS mostra a resposta")
	await shot("04_meus_tickets")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
