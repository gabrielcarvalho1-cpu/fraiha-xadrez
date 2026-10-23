extends SceneTree
## R176.9 · CHAT MINIMIZADO no PC (Ranked/Casual e contra o computador): a moldura fica vazia com a lista de LANCES
## e um botão CHAT discreto (com o número de mensagens novas) reabre — nada de caixa azul por cima da arte.
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

func state(mid: String, rules, last, me: Dictionary, opp: Dictionary) -> Dictionary:
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	return {"type": "ranked_state", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "w", "status": "playing", "revision": rules.ply + 1, "starts_in_ms": 0,
		"white": me, "black": opp, "position": {"board": board, "turn": rules.turn, "rights": rules.rights, "ep": [rules.ep.x, rules.ep.y], "halfmove": rules.halfmove, "ply": rules.ply},
		"in_check": false, "last_move": last, "clock": {"w_ms": 176000, "b_ms": 180000, "active": rules.turn}}

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
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_3min": {"league": 0, "pl": 72, "wins": 3, "losses": 1, "draws": 0, "matches": 4}}
	var skin = stage.board_skin
	# ---------------- Ranked
	var Rules = load("res://chess/rules.gd")
	var rules = Rules.new()
	rules.reset()
	var mid := "00000000-0000-4000-8000-0000000000cc"
	var opp := {"nickname": "LadyTorre", "avatar_id": "warrior", "league": 0, "pl": 82, "connected": true, "title": "rei_do_blitz"}
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "league": 0, "pl": 72, "connected": true}
	stage._open_ranked()
	await frames(4)
	acc.server_message.emit({"type": "ranked_found", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "w", "opponent": opp})
	await frames(4)
	acc.server_message.emit(state(mid, rules, null, me, opp))
	await frames(8)
	var moves := [[Vector2i(4, 6), Vector2i(4, 4)], [Vector2i(4, 1), Vector2i(4, 3)], [Vector2i(6, 7), Vector2i(5, 5)], [Vector2i(1, 0), Vector2i(2, 2)], [Vector2i(5, 7), Vector2i(2, 4)]]
	for mv in moves:
		var ok: bool = rules.play({"from": mv[0], "to": mv[1], "promotion": "Q"})
		if not ok:
			# o tabuleiro do jogo pode ter as linhas invertidas: tenta o espelho
			ok = rules.play({"from": Vector2i(mv[0].x, 7 - mv[0].y), "to": Vector2i(mv[1].x, 7 - mv[1].y), "promotion": "Q"})
			mv = [Vector2i(mv[0].x, 7 - mv[0].y), Vector2i(mv[1].x, 7 - mv[1].y)]
		check(ok, "lance de teste válido")
		acc.server_message.emit(state(mid, rules, {"from": [mv[0].x, mv[0].y], "to": [mv[1].x, mv[1].y], "captured": ""}, me, opp))
		await frames(3)
	var ctl = stage.ranked_ui.controller
	print("  lances: ", ctl.san_log)
	check(ctl.san_log.size() == 5, "Ranked: lances anotados (%d)" % ctl.san_log.size())
	var chat = stage.match_chat
	check(chat.active(), "chat do Ranked ativo")
	chat.set_minimized(true)
	await frames(10)
	check(not chat.panel.visible, "minimizado: o painel do chat some")
	check(skin.bot_moves != null and skin.bot_moves.visible and "LANCES" in skin.bot_moves.text and "1." in skin.bot_moves.text, "minimizado: a moldura mostra os LANCES")
	var rb: Button = chat.restore_button
	var chat_r: Rect2 = skin.R(skin.PC.chat)
	check(rb.visible and chat_r.encloses(rb.get_global_rect()), "botão CHAT discreto dentro da moldura")
	check(skin.bg.chat_tex == skin.CHAT_BOX_EMPTY, "moldura vazia (sem EMOTES/SILENCIAR/ENVIAR desenhados)")
	await shot("ranked_chat_min")
	chat._on_message({"type": "chat_msg", "match_id": chat.match_id, "from_color": "b", "nickname": "LadyTorre", "text": "boa partida!"})
	await frames(6)
	check(chat.unread == 1 and "(1)" in rb.text, "mensagem nova: CHAT (1)")
	await shot("ranked_chat_min_nova")
	rb.pressed.emit()
	await frames(10)
	check(chat.panel.visible and not rb.visible and not skin.bot_moves.visible, "CHAT reabre o painel e os LANCES saem")
	await shot("ranked_chat_aberto")
	# ---------------- contra o computador
	stage.ranked_ui.close_panel() if stage.ranked_ui.has_method("close_panel") else null
	stage._start_bot("easy", "w")
	await frames(14)
	var c2 = stage.match_chat
	if c2.active():
		c2.set_minimized(true)
		await frames(10)
		check(not c2.panel.visible and skin.bot_moves.visible, "bot: minimizado mostra os LANCES")
		check(c2.restore_button.visible and skin.R(skin.PC.chat).encloses(c2.restore_button.get_global_rect()), "bot: botão CHAT dentro da moldura")
		await shot("bot_chat_min")
		c2.set_minimized(false)
		await frames(8)
		check(c2.panel.visible and not skin.bot_moves.visible, "bot: CHAT reabre")
	print("RESULT ", "OK" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
