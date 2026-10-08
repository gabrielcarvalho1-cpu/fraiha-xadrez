extends SceneTree
## R53 · HUD da partida no CELULAR (ranked/mobile_match_hud.gd), em pé e deitado, sem servidor:
## partida contra o computador (real) e Ranked/Casual simulados com as MESMAS mensagens do servidor.
## Confere: tabuleiro grande (e centrado deitado, sem coluna reservada), nada da interface antiga por trás,
## cartões com dados reais, painel AÇÕES (abre/fecha, só ações que existem, cada ladrilho chama a ação real,
## abrir/fechar não acumula nós), INÍCIO pede confirmação, CHAT, giro no meio da partida sem perder estado,
## pré-move por toque no Ranked, resultado fecha o painel AÇÕES.
## Uso: xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/mobile_match_hud_test.gd -- --mobile-test --size 390x844
var failures := 0
var stage
var hud
var tag := ""

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", "[%s] %s" % [tag, label])
	if not ok: failures += 1

func frames(n := 3):
	for i in n: await process_frame

func tap_at(p: Vector2):
	for down in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = p
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)

func tap(c: Control):
	await tap_at(c.get_global_rect().get_center())

func click_at(p: Vector2):
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = p
		e.global_position = p
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)

func _mk(p: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	return e

func count_nodes(n: Node) -> int:
	var c := 1
	for k in n.get_children(): c += count_nodes(k)
	return c

func screen() -> Rect2:
	return root.get_visible_rect()

func board_rect() -> Rect2:
	var g = stage.game
	return Rect2(g.position + g.ORIGIN * g.scale, Vector2.ONE * g.BOARD * g.scale.x)

func cell_center(cell: Vector2i) -> Vector2:
	var g = stage.game
	return g.position + g.square_center(cell) * g.scale.x

func visible_ctrl(c) -> bool:
	return c != null and is_instance_valid(c) and c.is_visible_in_tree()

func set_size(sz: Vector2i):
	root.size = sz
	root.content_scale_size = sz
	await frames(8)

func layout_checks(what: String):
	var vs := screen().size
	var b := board_rect()
	var portrait := vs.y > vs.x
	check(hud.on and hud.orient == ("p" if portrait else "l"), "%s: HUD novo ligado (%s)" % [what, hud.orient])
	if portrait: check(b.size.x >= vs.x * 0.86, "%s: tabuleiro grande em pé (%.0f de %.0f px)" % [what, b.size.x, vs.x])
	else:
		check(b.size.y >= vs.y * 0.86, "%s: tabuleiro na altura quase inteira deitado (%.0f de %.0f px)" % [what, b.size.y, vs.y])
		check(absf(b.get_center().x - vs.x / 2.0) <= 2.0, "%s: tabuleiro no meio, sem coluna reservada para o painel fechado" % what)
	check(screen().grow(1).encloses(b), "%s: tabuleiro inteiro na tela" % what)
	for n in [stage.mobile_actions, stage.home_button, stage.bot_info, stage.player_card, stage.mobile_status]:
		if visible_ctrl(n):
			check(false, "%s: interface antiga visível por trás (%s)" % [what, n.name])
	var u = hud.ui()
	for key in ["top", "bottom"]:
		var s: Dictionary = u.strips[key]
		var nm: Label = s.name
		var ck: Control = s.clock
		check(visible_ctrl(nm) and screen().encloses(nm.get_global_rect()) and not nm.text.is_empty(), "%s: nome do cartão %s visível (%s)" % [what, key, nm.text])
		check(visible_ctrl(ck) and screen().encloses(ck.get_global_rect()), "%s: relógio do cartão %s visível" % [what, key])
		check(not nm.get_global_rect().intersects(b.grow(-2)) and not ck.get_global_rect().intersects(b.grow(-2)), "%s: cartão %s não cobre o tabuleiro" % [what, key])

func actions_checks(what: String):
	var opener: Button = hud.nav_buttons.actions if hud.orient == "p" else hud.corner.tab
	check(visible_ctrl(opener) and screen().encloses(opener.get_global_rect()), "%s: botão AÇÕES visível" % what)
	var n0 := count_nodes(hud.layer) + count_nodes(hud.plate_layer) + count_nodes(hud.panel_layer)
	await tap(opener)
	check(hud.is_open() and screen().grow(1).encloses(hud.panel.get_global_rect()), "%s: toque em AÇÕES abre o painel inteiro na tela" % what)
	var shown: Array = []
	var av: Dictionary = hud._available()
	for t in hud.tiles:
		if t[0].visible: shown.append(t[1])
	var expect: Array = []
	for id in av:
		if av[id]: expect.append(id)
	expect.sort(); var got := shown.duplicate(); got.sort()
	check(got == expect, "%s: ladrilhos = ações que existem agora %s" % [what, str(got)])
	# MÚSICA e EFEITOS: a preferência de verdade muda e volta
	var ModeSound = load("res://ui_v022/mode_sound.gd")
	for pair in [["music", "music_muted"], ["fx", "effects_muted"]]:
		var b: Button = hud.panel.find_child("Action_" + pair[0], true, false)
		var before: bool = ModeSound.call(pair[1], stage.hub)
		await tap(b)
		check(ModeSound.call(pair[1], stage.hub) != before and hud.is_open(), "%s: %s alterna de verdade" % [what, pair[0]])
		await tap(b)
		check(ModeSound.call(pair[1], stage.hub) == before, "%s: %s volta" % [what, pair[0]])
	# MARCAR e TELA CHEIA: o toque chega ao botão antigo (a ação de sempre)
	for pair in [["mark", stage.mobile_mark], ["full", stage.mobile_fullscreen]]:
		var b: Button = hud.panel.find_child("Action_" + pair[0], true, false)
		if not b.visible: continue
		var hits := [0]
		var spy := func(): hits[0] += 1
		pair[1].pressed.connect(spy)
		await tap(b)
		pair[1].pressed.disconnect(spy)
		check(hits[0] == 1, "%s: %s chama a ação real (1 vez)" % [what, pair[0]])
	var close: Button = hud.panel.get_node("HudActionsClose")
	await tap(close)
	check(not hud.is_open(), "%s: X fecha o painel" % what)
	for i in 6:
		await tap(opener)
		await tap(opener)
	var n1 := count_nodes(hud.layer) + count_nodes(hud.plate_layer) + count_nodes(hud.panel_layer)
	check(not hud.is_open() and n1 == n0 and n0 > 10, "%s: abrir/fechar 6x não acumula nós (%d → %d)" % [what, n0, n1])

func home_check(what: String):
	var b: Button = hud.nav_buttons.home if hud.orient == "p" else hud.corner.back
	await tap(b)
	await frames(4)
	var asked: bool = stage.navigation_dialog.visible or (stage.medieval_modal != null and stage.medieval_modal.visible)
	check(asked, "%s: INÍCIO pede confirmação no meio da partida" % what)
	if asked:
		stage._cancel_navigation()
		stage.navigation_dialog.hide()
		await frames(4)
	check(stage.mode in ["bot", "ranked", "casual"] and stage.game.visible, "%s: cancelar mantém a partida" % what)

## Ranked/Casual simulado: as mesmas mensagens que o servidor manda (sem rede).
func fake_online(kind: String, you: String, turn: String):
	var ctrl = stage.ranked if kind == "ranked" else stage.casual
	var mid := "00000000-0000-4000-8000-0000000000%s" % ("01" if kind == "ranked" else "02")
	var opp := {"nickname": "SextoSen1", "avatar_id": "warrior", "league": 2, "pl": 35, "connected": true}
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "league": 1, "pl": 12, "connected": true}
	stage.account.server_message.emit({"type": kind + "_found", "match_id": mid, "mode": kind + "_3min", "mode_name": "Relâmpago", "you": you, "opponent": opp})
	await frames(4)
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	stage.account.server_message.emit({"type": kind + "_state", "match_id": mid, "mode": kind + "_3min", "mode_name": "Relâmpago", "you": you, "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": me if you == "w" else opp, "black": opp if you == "w" else me,
		"position": {"board": board, "turn": turn, "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0}, "in_check": false, "last_move": null,
		"clock": {"w_ms": 180000, "b_ms": 176000, "active": turn}})
	await frames(8)
	return ctrl

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(390, 844)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.mode = Window.MODE_WINDOWED
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await set_size(size)
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	hud = stage.mobile_hud
	var turned := Vector2i(size.y, size.x)
	# ---------------- contra o computador
	tag = "bot %dx%d" % [size.x, size.y]
	stage._start_bot("madeira", "w")
	await frames(20)
	await layout_checks("bot")
	check(not stage.board_skin.on, "bot: a pele antiga do celular não liga mais")
	await actions_checks("bot")
	# DESISTIR (em partida): a mesma confirmação de sempre
	var opener: Button = hud.nav_buttons.actions if hud.orient == "p" else hud.corner.tab
	await tap(opener)
	var rs: Button = hud.panel.find_child("Action_resign", true, false)
	check(rs.visible and (rs.get_node("Caption") as Label).text == "Desistir", "bot: ladrilho Desistir na partida contra o computador")
	await tap(rs)
	await frames(4)
	check(not hud.is_open() and stage.ranked_ui.screen == "confirm_resign", "bot: Desistir abre a confirmação de sempre e fecha AÇÕES")
	stage.ranked_ui.close_panel()
	await frames(2)
	await home_check("bot")
	# um lance de verdade por toque no tabuleiro (e2-e4) com o layout novo
	await click_at(cell_center(Vector2i(4, 6)))
	await click_at(cell_center(Vector2i(4, 4)))
	await frames(6)
	check(stage.game.move_count >= 1, "bot: lance e2-e4 por toque no tabuleiro (lances: %d)" % stage.game.move_count)
	var mc: int = stage.game.move_count
	# giro no meio da partida: nada se perde, layout certo dos dois lados
	await set_size(turned)
	tag = "bot %dx%d" % [turned.x, turned.y]
	await layout_checks("bot girado")
	check(stage.game.move_count >= mc and stage.mode == "bot", "bot girado: partida continua (lances %d)" % stage.game.move_count)
	await set_size(size)
	tag = "bot %dx%d" % [size.x, size.y]
	await layout_checks("bot de volta")
	# resultado tem prioridade: fim da partida com AÇÕES aberto fecha o painel
	await tap(hud.nav_buttons.actions if hud.orient == "p" else hud.corner.tab)
	check(hud.is_open(), "bot: AÇÕES aberto antes do fim")
	stage.bot_controller.resign()
	await frames(10)
	check(not hud.is_open(), "bot: fim da partida fecha AÇÕES (resultado por cima)")
	stage.result_overlay.hide_result()
	for w in 120:
		if not stage.result_overlay.visible: break
		await frames(1)
	await frames(4)
	await tap(hud.nav_buttons.actions if hud.orient == "p" else hud.corner.tab)
	rs = hud.panel.find_child("Action_resign", true, false)
	var az: Button = hud.panel.find_child("Action_analyze", true, false)
	check(hud.is_open() and rs.visible and (rs.get_node("Caption") as Label).text == "Jogar de novo", "bot: depois do fim, AÇÕES tem Jogar de novo")
	check(az.visible == stage.mobile_analyze.visible, "bot: Analisar aparece quando a análise existe")
	hud.close_actions()
	stage.open_home()
	await frames(10)
	check(not hud.on and not hud.layer.visible, "Home: HUD da partida desligado")
	# ---------------- Ranked simulado (dados reais da mensagem do servidor)
	for kind in ["ranked", "casual"]:
		tag = "%s %dx%d" % [kind, size.x, size.y]
		var acc = stage.account
		acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
		acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
		var ctrl = await fake_online(kind, "w", "b")
		check(stage.mode == kind and ctrl.in_match(), "%s: partida simulada aberta" % kind)
		await layout_checks(kind)
		var u = hud.ui()
		check(u == (stage.casual_ui if kind == "casual" else stage.ranked_ui), "%s: cartões da UI certa" % kind)
		check(u.strips.top.name.text.begins_with("SextoSen1") and u.strips.bottom.name.text == "Você", "%s: nomes reais (%s / %s)" % [kind, u.strips.top.name.text, u.strips.bottom.name.text])
		if kind == "ranked": check(u.strips.top.sub.text.begins_with("BRONZE") and "35 PL" in u.strips.top.sub.text, "ranked: liga/PL reais do adversário (%s)" % u.strips.top.sub.text)
		# pré-move: vez do adversário, toque em e2 e e4 marca o pré-move
		await click_at(cell_center(Vector2i(4, 6)))
		await click_at(cell_center(Vector2i(4, 4)))
		await frames(4)
		check(stage.game.premove_from == Vector2i(4, 6) and stage.game.premove_to == Vector2i(4, 4), "%s: pré-move por toque na vez do adversário (de %s para %s)" % [kind, stage.game.premove_from, stage.game.premove_to])
		stage.game.clear_premove()
		# CHAT
		var c = stage.match_chat
		var chat_btn: Button = hud.nav_buttons.chat if hud.orient == "p" else hud.corner.chat
		await frames(4)
		if c.active():
			check(visible_ctrl(chat_btn), "%s: botão CHAT visível" % kind)
			await tap(chat_btn)
			check(c.open_mobile and c.panel.visible, "%s: CHAT abre" % kind)
			await tap(chat_btn)
			check(not c.open_mobile, "%s: CHAT fecha" % kind)
		await actions_checks(kind)
		await tap(hud.nav_buttons.actions if hud.orient == "p" else hud.corner.tab)
		rs = hud.panel.find_child("Action_resign", true, false)
		check(rs.visible and (rs.get_node("Caption") as Label).text == "Desistir", "%s: Desistir (sem Reiniciar) na partida online" % kind)
		# giro com AÇÕES aberto: continua aberto e inteiro
		await set_size(turned)
		check(hud.orient == ("l" if turned.x > turned.y else "p") and screen().grow(1).encloses(hud.panel.get_global_rect()), "%s: giro com AÇÕES aberto mantém o painel na tela" % kind)
		check(ctrl.in_match() and stage.mode == kind, "%s: giro não mexe na partida" % kind)
		# o adversário desiste com AÇÕES aberto: resultado tem prioridade
		var mid: String = ctrl.match_id
		stage.account.server_message.emit({"type": kind + "_result", "match_id": mid, "mode": kind + "_3min", "mode_name": "Relâmpago", "you": "w", "outcome": "win", "reason": "resign", "reason_text": "Desistência", "rated": kind == "ranked", "pl_change": 15, "pl_before": 12, "pl_after": 27, "league_before": 1, "league_after": 1, "stats": {"league": 1, "pl": 27}, "saved": true})
		await frames(10)
		check(not hud.is_open() and ctrl.status == "finished" and stage.game.game_over, "%s: adversário desistiu com AÇÕES aberto → painel fecha, partida encerrada" % kind)
		await set_size(size)
		stage.result_overlay.hide_result()
		u.close_panel()
		stage.open_home()
		await frames(8)
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
