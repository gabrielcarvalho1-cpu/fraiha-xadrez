extends SceneTree
## R54 · Telas do PC na arte de referência (ranked/desk_art_modal.gd): DESISTIR?, ADVERSÁRIO ENCONTRADO,
## VITÓRIA/DERROTA Ranked e Casual (Casual sem PL), vitória e derrota contra o bot. Confere conteúdo vivo,
## ações dos botões (as mesmas do painel antigo) e que a partida do PC perdeu MARCAR e ANALISAR.
## Também confere que no celular nada disso abre (o celular segue o layout próprio).
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/desk_art_modal_test.gd [-- --mobile-test --size 390x844]
var failures := 0
var stage

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize(): call_deferred("run")

func frames(n := 6):
	for i in n: await process_frame

func node(root_node: Node, n: String) -> Node:
	return root_node.find_child(n, true, false)

func txt(root_node: Node, n: String) -> String:
	var l = node(root_node, n)
	return String(l.text) if l != null else "<sem " + n + ">"

func run():
	var args := OS.get_cmdline_user_args()
	var mobile := "--mobile-test" in args
	var size := Vector2i(1920, 1080)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	if mobile: root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_3min": {"league": 0, "pl": 72, "wins": 3, "losses": 1, "draws": 0, "matches": 4}}
	var ui = stage.ranked_ui
	var da = ui.desk_art
	# ---------------- contra o bot: DESISTIR? e partida
	stage._start_bot("madeira", "w")
	await frames(20)
	ui._confirm_resign()
	await frames(4)
	if mobile:
		check(not da.is_open() and ui.panel.visible, "celular: DESISTIR? continua no painel próprio (arte do PC não abre)")
		ui.close_panel()
		print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
		quit(0 if failures == 0 else 1)
		return
	check(da.is_open() and da.kind == "resign" and not ui.panel.visible, "bot: DESISTIR? abre na arte de referência")
	check("contra o computador" in txt(da, "DeskResignText"), "bot: texto da desistência fala do computador")
	check(not stage.desk_mark.visible, "partida no PC: sem MARCAR PARA REVISAR")
	check(not stage.desk_analyze.visible, "partida no PC: sem ANALISAR PARTIDA")
	check(ui.resign_button.text == "" and ui.resign_button.get_theme_stylebox("normal") is StyleBoxTexture, "DESISTIR da partida é o botão da arte aprovada")
	(node(da, "DeskContinue") as Button).pressed.emit()
	await frames(3)
	check(not da.is_open() and not stage.game.game_over, "CONTINUAR JOGANDO fecha e a partida segue")
	ui._confirm_resign()
	await frames(3)
	(node(da, "DeskResign") as Button).pressed.emit()
	await frames(6)
	check(stage.game.game_over, "DESISTIR (modal) encerra a partida contra o bot")
	check(not stage.desk_analyze.visible, "fim contra o bot: ANALISAR fica na tela de resultado, não na barra")
	if stage.result_overlay != null: stage.result_overlay.hide_result()
	# ---------------- derrota contra o bot
	stage.reward_modal.show_defeat("madeira")
	await frames(4)
	var rm = stage.reward_modal
	check(rm.is_open() and node(rm, "DeskBotMain") != null and node(rm, "DeskBotAnalyze") != null and node(rm, "DeskBotHome") != null, "derrota contra o bot: tela com ENFRENTAR NOVAMENTE / ANALISAR / INÍCIO")
	check(txt(rm, "DeskBotMainText") == "ENFRENTAR O BOT NOVAMENTE" and "BOT MADEIRA" in txt(rm, "DeskBotSub"), "derrota contra o bot: textos")
	check("BOT FERRO" in txt(rm, "DeskBotInfo"), "derrota contra o bot: diz qual bot a vitória libera")
	(node(rm, "DeskBotMain") as Button).pressed.emit()
	await frames(10)
	check(stage.mode == "bot" and String(stage.bot_controller.bot_id) == "madeira" and not stage.game.game_over and not rm.is_open(), "ENFRENTAR O BOT NOVAMENTE começa outra partida contra o mesmo bot")
	# ---------------- vitória contra o bot (revanche e 1ª vitória)
	rm.show_progress("madeira", {"type": "avatar", "id": "madeira_reward"}, false)
	await frames(4)
	check(txt(rm, "DeskBotNext") == "BOT FERRO" and txt(rm, "DeskBotMainText") == "JOGAR PRÓXIMO BOT · BOT FERRO", "vitória contra o bot: próximo adversário e botão")
	check(node(rm, "DeskBotShield") != null and node(rm, "DeskBotNextShield") != null, "vitória contra o bot: brasões do bot vencido e do próximo")
	check("sem recompensa nova" in txt(rm, "DeskBotRewardText"), "revanche: sem recompensa nova")
	rm.show_progress("madeira", {"type": "avatar", "id": "madeira_reward"}, true)
	await frames(4)
	check(txt(rm, "DeskBotMainText") == "AVANÇAR PARA O BOT FERRO" and txt(rm, "DeskBotRewardTitle") == "Recompensa desbloqueada!", "1ª vitória: avançar + recompensa desbloqueada")
	(node(rm, "DeskBotMain") as Button).pressed.emit()
	await frames(10)
	check(String(stage.bot_controller.bot_id) == "ferro" and not rm.is_open(), "AVANÇAR começa a partida contra o próximo bot")
	rm.show_progress("challenger", {}, true)
	await frames(4)
	check(txt(rm, "DeskBotMainText") == "JOGAR NOVAMENTE" and node(rm, "DeskBotNextShield") == null, "último bot: desafio concluído, JOGAR NOVAMENTE")
	(node(rm, "DeskBotHome") as Button).pressed.emit()
	await frames(8)
	check(not rm.is_open() and stage.mode != "bot", "VOLTAR PARA O INÍCIO")
	# ---------------- Ranked (simulado com as mensagens do servidor)
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	var mid := "00000000-0000-4000-8000-0000000000bb"
	var opp := {"nickname": "SextoSen1", "avatar_id": "warrior", "league": 0, "pl": 82, "connected": true}
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "league": 0, "pl": 72, "connected": true}
	stage._open_ranked()
	await frames(4)
	acc.server_message.emit({"type": "ranked_found", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "b", "opponent": opp})
	await frames(4)
	check(da.is_open() and da.kind == "found", "Ranked: ADVERSÁRIO ENCONTRADO na arte")
	check(txt(da, "DeskFoundName") == "SextoSen1" and "82/100 PL" in txt(da, "DeskFoundLeague") and "PRETAS" in txt(da, "DeskFoundMode"), "encontrado: nome, liga/PL e cor")
	acc.server_message.emit({"type": "ranked_state", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "b", "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": opp, "black": me, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0},
		"in_check": false, "last_move": null, "clock": {"w_ms": 176000, "b_ms": 180000, "active": "w"}})
	await frames(6)
	check(not da.is_open(), "a partida começou: o modal sai")
	ui._confirm_resign()
	await frames(3)
	check(da.kind == "resign" and "nesta modalidade" in txt(da, "DeskResignText"), "Ranked: DESISTIR? (mesmo modal, texto do Ranked)")
	ui.close_panel()
	acc.server_message.emit({"type": "ranked_result", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "saved": true, "outcome": "win", "reason": "resign",
		"reason_text": "Desistência", "pl_change": 18, "pl_before": 72, "pl_after": 90, "league_before": 0, "league_after": 0})
	await frames(4)
	check(da.is_open() and da.kind == "result_win", "Ranked: VITÓRIA na arte")
	check(txt(da, "DeskResultPl") == "+18 PL" and txt(da, "DeskResultLeague") == "MADEIRA" and txt(da, "DeskResultCount") == "90 / 100 PL", "vitória Ranked: +PL, liga e PL atual")
	check(txt(da, "DeskResultSub") == "RELÂMPAGO · Desistência" and txt(da, "DeskBackText") == "VOLTAR AO RANKED", "vitória Ranked: modo · motivo e VOLTAR AO RANKED")
	check(node(da, "DeskPlayAgain") != null and node(da, "DeskAnalyze") != null and node(da, "DeskBack") != null, "vitória Ranked: JOGAR NOVAMENTE / ANALISAR / VOLTAR")
	await frames(70)
	check(absf(da.bar_value() - 90.0) < 0.5, "barra de PL anima até o PL novo (%.1f)" % da.bar_value())
	ui.controller.last_result = {"match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "outcome": "loss", "reason_text": "Xeque-mate", "pl_change": -10, "pl_before": 82, "pl_after": 72, "league_before": 0, "league_after": 0}
	ui._show("result")
	await frames(3)
	check(da.kind == "result_loss" and txt(da, "DeskResultPl") == "-10 PL", "Ranked: DERROTA com -PL")
	(node(da, "DeskBack") as Button).pressed.emit()
	await frames(4)
	check(not da.is_open() and ui.screen == "modes", "VOLTAR AO RANKED volta para a escolha de ritmo")
	ui.controller.last_result = {"match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "outcome": "draw", "reason_text": "Afogamento"}
	ui._show("result")
	await frames(3)
	check(not da.is_open() and ui.panel.visible, "empate continua na tela própria")
	ui.close_panel()
	stage.open_home()
	await frames(4)
	# ---------------- Casual: mesmo padrão, sem PL
	var cui = stage.casual_ui
	var cda = cui.desk_art
	stage._open_casual()
	await frames(4)
	acc.server_message.emit({"type": "casual_found", "match_id": "c9", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "opponent": opp})
	await frames(4)
	check(cda.kind == "found" and "SEM PL" in txt(cda, "DeskFoundLeague"), "Casual: encontrado sem liga/PL")
	cui.controller.last_result = {"match_id": "c9", "mode": "casual_5min", "mode_name": "Rápida", "outcome": "win", "reason_text": "Xeque-mate"}
	cui._show("result")
	await frames(3)
	check(cda.kind == "result_win" and node(cda, "DeskResultPl") == null and node(cda, "PlBar") == null, "Casual: VITÓRIA sem PL e sem barra")
	check(txt(cda, "DeskBackText") == "VOLTAR AO CASUAL" and node(cda, "DeskAnalyze") != null, "Casual: VOLTAR AO CASUAL e ANALISAR PARTIDA")
	cui.close_panel()
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
