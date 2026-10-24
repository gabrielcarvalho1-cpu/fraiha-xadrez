extends SceneTree
## R181 · fila do Ranked vazia: aviso aos 25 s com o BOT da liga do jogador (aceitar abre a partida contra o bot;
## recusar continua esperando e registra), tela de busca com tempo e mensagem amigável. PC e celular (SHOT_SIZE).
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
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func events() -> Array:
	var out := []
	for m in sent: if m.get("type") == "ui_event": out.append(m)
	return out
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
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_10min": {"league": 0, "pl": 0, "matches": 0}}
	acc.send_hook = func(m): sent.append(m)
	stage._open_ranked()
	await frames(6)
	var ui = stage.ranked_ui
	ui.controller.queue("ranked_10min")
	acc.server_message.emit({"type": "ranked_queued", "mode": "ranked_10min"})
	await frames(6)
	check(ui.screen == "searching", "tela BUSCANDO ADVERSÁRIO (%s)" % ui.screen)
	await create_timer(2.2).timeout
	await shot("01_buscando")
	# 24 s: ainda nada
	ui.search_started = Time.get_ticks_msec() - 24000
	await frames(10)
	check(not (stage.hub.notice_modal != null and stage.hub.notice_modal.visible), "24 s: sem aviso ainda")
	ui.search_started = Time.get_ticks_msec() - 25500
	await frames(10)
	var nm = stage.hub.notice_modal
	check(nm != null and nm.visible and String(nm.text_label.text).contains("BOT MADEIRA"), "25 s: aviso com o BOT MADEIRA")
	check(events().size() == 1 and events()[0].name == "queue_bot_offer", "evento: ofereceu bot (%s)" % [events()])
	await shot("02_aviso_bot")
	# recusar: continua buscando
	nm.ok_button.pressed.emit()
	await frames(10)
	check(ui.screen == "searching" and ui.controller.searching, "recusou: continua na fila")
	check(events().back().name == "queue_bot_decline", "evento: recusou")
	# oferece de novo mais tarde; aceitar abre a partida contra o bot
	check(ui._offer_at > ui.BOT_OFFER_SECS + ui.BOT_REOFFER_SECS - 1.0, "próxima oferta só daqui a %d s" % int(ui.BOT_REOFFER_SECS))
	ui.search_started = Time.get_ticks_msec() - int((ui._offer_at + 0.5) * 1000.0)
	await frames(10)
	check(nm.visible, "oferece de novo depois de %d s" % int(ui.BOT_REOFFER_SECS))
	nm.yes_button.pressed.emit()
	await frames(20)
	check(stage.mode == "bot", "aceitou: partida contra o bot (%s)" % stage.mode)
	check(String(stage.bot_controller.bot_id) == "madeira", "bot da liga Madeira (%s)" % stage.bot_controller.bot_id)
	check(sent.any(func(m): return m.get("type") == "ranked_cancel"), "saiu da fila do Ranked")
	check(events().back().name == "queue_bot_accept", "evento: aceitou")
	check(not ui.panel_open(), "tela da fila fechada")
	await shot("03_partida_bot")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
