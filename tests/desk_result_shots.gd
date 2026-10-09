extends SceneTree
## R54 · Capturas da partida e das telas de fim/confirmação no PC (Web desktop):
## partida contra o bot, DESISTIR?, adversário encontrado, VITÓRIA/DERROTA Ranked e Casual, vitória e
## derrota contra o bot. Ranked/Casual simulados com as mesmas mensagens do servidor. Uso:
## SHOT_DIR=<pasta> SHOT_TAG=<prefixo> xvfb-run godot --rendering-driver opengl3 --path <proj> \
##   -s tests/desk_result_shots.gd -- --size 1920x1080 [--only nome1,nome2]
var stage
var only: PackedStringArray = []

func _initialize(): call_deferred("run")

func frames(n := 6):
	for i in n: await process_frame

func shot(name: String):
	if not only.is_empty() and not name in only: return
	await frames(14)
	await RenderingServer.frame_post_draw
	var p := OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "_" + name + ".png")
	root.get_texture().get_image().save_png(p)
	print("SHOT ", p)

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(1920, 1080)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	i = args.find("--only")
	if i >= 0: only = args[i + 1].split(",")
	root.mode = Window.MODE_WINDOWED
	root.size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_3min": {"league": 0, "pl": 90, "wins": 30, "losses": 8, "draws": 0, "matches": 38}}
	stage._sync_theme_unlocks()
	# ---- contra o computador
	stage._start_bot("madeira", "w")
	await frames(24)
	await shot("bot_partida")
	stage.ranked_ui._confirm_resign()
	await shot("bot_desistir")
	stage.ranked_ui.close_panel()
	await frames(4)
	# vitória contra o bot (painel de progressão) e derrota
	if stage.result_overlay != null: stage.result_overlay.visible = false
	stage.reward_modal.show_progress("madeira", {"type": "avatar", "id": "madeira_reward"}, false)
	await shot("bot_vitoria")
	stage.reward_modal.close()
	await frames(4)
	stage.reward_modal.show_defeat("madeira")
	await shot("bot_derrota")
	stage.reward_modal.close()
	stage.reward_modal.show_progress("madeira", {"type": "avatar", "id": "madeira_reward"}, true)
	await shot("bot_vitoria_nova")
	stage.reward_modal.close()
	stage.open_home()
	await frames(8)
	# ---- Ranked simulado
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	var mid := "00000000-0000-4000-8000-0000000000aa"
	var opp := {"nickname": "SextoSen1", "avatar_id": "warrior", "league": 0, "pl": 82, "connected": true}
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "league": 0, "pl": 72, "connected": true}
	stage._open_ranked()
	await frames(6)
	acc.server_message.emit({"type": "ranked_found", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "b", "opponent": opp})
	await shot("ranked_encontrado")
	acc.server_message.emit({"type": "ranked_state", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "b", "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": opp, "black": me, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0},
		"in_check": false, "last_move": null, "clock": {"w_ms": 176000, "b_ms": 180000, "active": "w"}})
	await frames(12)
	await shot("ranked_partida")
	stage.ranked_ui._confirm_resign()
	await shot("ranked_desistir")
	stage.ranked_ui.close_panel()
	await frames(4)
	var base := {"type": "ranked_result", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "saved": true}
	var win := base.duplicate()
	win.merge({"outcome": "win", "reason": "resign", "reason_text": "Desistência", "pl_change": 18, "pl_before": 72, "pl_after": 90, "league_before": 0, "league_after": 0})
	acc.server_message.emit(win)
	await frames(6)
	if stage.result_overlay != null: stage.result_overlay.hide_result()
	await shot("ranked_vitoria")
	stage.ranked_ui.controller.last_result = base.duplicate()
	stage.ranked_ui.controller.last_result.merge({"outcome": "loss", "reason": "checkmate", "reason_text": "Xeque-mate", "pl_change": -10, "pl_before": 82, "pl_after": 72, "league_before": 0, "league_after": 0})
	stage.ranked_ui._show("result")
	await shot("ranked_derrota")
	stage.ranked_ui.close_panel()
	stage.open_home()
	await frames(6)
	# ---- Casual (mesmas telas, sem PL)
	var cui = stage.casual_ui
	stage._open_casual()
	await frames(6)
	acc.server_message.emit({"type": "casual_found", "match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "opponent": opp})
	await shot("casual_encontrado")
	acc.server_message.emit({"type": "casual_state", "match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": me, "black": opp, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0},
		"in_check": false, "last_move": null, "clock": {"w_ms": 300000, "b_ms": 300000, "active": "w"}})
	await frames(12)
	await shot("casual_partida")
	cui._confirm_resign()
	await shot("casual_desistir")
	cui.close_panel()
	cui.controller.last_result = {"match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "outcome": "win", "reason": "checkmate", "reason_text": "Xeque-mate"}
	cui._show("result")
	await shot("casual_vitoria")
	cui.controller.last_result = {"match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "outcome": "loss", "reason": "timeout", "reason_text": "Tempo esgotado"}
	cui._show("result")
	await shot("casual_derrota")
	quit()
