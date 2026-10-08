extends SceneTree
## R53 · Capturas da partida no celular (HUD novo): contra o computador e Ranked simulado (mesmas mensagens do
## servidor), com AÇÕES fechado e aberto. Uso:
## SHOT_DIR=<pasta> SHOT_TAG=<prefixo> xvfb-run godot --rendering-driver opengl3 --path <proj> \
##   -s tests/mobile_match_shots.gd -- --mobile-test --size 390x844
var stage
var hud

func _initialize(): call_deferred("run")

func frames(n := 6):
	for i in n: await process_frame

func shot(name: String):
	await frames(12)
	await RenderingServer.frame_post_draw
	var p := OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "_" + name + ".png")
	root.get_texture().get_image().save_png(p)
	print("SHOT ", p)

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(390, 844)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	hud = stage.mobile_hud
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_3min": {"league": 1, "pl": 12, "wins": 30, "losses": 8, "draws": 0, "matches": 38}}
	stage._sync_theme_unlocks()
	stage._start_bot("madeira", "w")
	await frames(20)
	await shot("bot")
	hud.open()
	await shot("bot_acoes")
	hud.close_actions()
	stage.open_home()
	await frames(8)
	# Ranked simulado
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	var mid := "00000000-0000-4000-8000-0000000000aa"
	var opp := {"nickname": "SextoSen1", "avatar_id": "warrior", "league": 2, "pl": 35, "connected": true}
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "league": 1, "pl": 12, "connected": true}
	acc.server_message.emit({"type": "ranked_found", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "w", "opponent": opp})
	await frames(4)
	acc.server_message.emit({"type": "ranked_state", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "w", "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": me, "black": opp, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0},
		"in_check": false, "last_move": null, "clock": {"w_ms": 176000, "b_ms": 180000, "active": "w"}})
	await frames(10)
	var ti := args.find("--theme")
	if ti >= 0:
		stage.theme_manager.review_all = true
		stage.theme_manager.apply_theme(args[ti + 1], false)
		stage._layout()
		await frames(6)
	await shot("ranked")
	hud.open()
	await shot("ranked_acoes")
	quit()
