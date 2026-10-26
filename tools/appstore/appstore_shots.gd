extends SceneTree
## R191 · prints da página da App Store (iPhone 6,9"): a tela do jogo no celular, em alta resolução.
## Uso: SHOT_DIR=<pasta> xvfb-run -a -s "-screen 0 1400x3000x24" godot --rendering-driver opengl3 --path . \
##        -s tools/appstore/appstore_shots.gd -- --mobile-test
## Contas e nomes mostrados são FICTÍCIOS (nenhum jogador real aparece nos prints).
var stage
const LOGICAL := Vector2i(430, 932)
const PIXELS := Vector2i(1290, 2796)

func _initialize(): call_deferred("run")

func frames(n := 6):
	for i in n: await process_frame

func wait_s(s: float):
	await create_timer(s).timeout

func shot(name: String):
	await frames(14)
	await RenderingServer.frame_post_draw
	var p := OS.get_environment("SHOT_DIR").path_join(name + ".png")
	root.get_texture().get_image().save_png(p)
	print("SHOT ", p)

static func sq(s: String) -> Vector2i:
	return Vector2i(s.unicode_at(0) - 97, 8 - int(s.substr(1, 1)))

func run():
	root.mode = Window.MODE_WINDOWED
	root.size = PIXELS
	root.content_scale_size = LOGICAL
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "ReiDaFloresta", "avatar_id": "warrior"}
	acc.ranked = {"ranked_3min": {"league": 3, "pl": 64, "wins": 52, "losses": 21, "draws": 3, "matches": 76},
		"ranked_10min": {"league": 2, "pl": 40, "wins": 18, "losses": 9, "draws": 1, "matches": 28}}
	stage._sync_theme_unlocks()
	stage.open_home()
	await wait_s(2.0)
	await shot("01_home")

	# Ranked em andamento (posição de meio-jogo, italiana)
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var last := {}
	for mv in ["e2e4","e7e5","g1f3","b8c6","f1c4","f8c5","c2c3","g8f6","d2d4","e5d4","c3d4","c5b4","b1c3","f6e4","e1g1","b4c3","d4d5","c3f6"]:
		var m := {"from": sq(mv.substr(0, 2)), "to": sq(mv.substr(2, 2)), "promotion": "Q"}
		if not rules.play(m): print("lance ilegal ", mv)
		last = m
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	var mid := "00000000-0000-4000-8000-0000000000aa"
	var opp := {"nickname": "TorreSombria", "avatar_id": "archer", "league": 3, "pl": 71, "connected": true}
	var me := {"nickname": "ReiDaFloresta", "avatar_id": "warrior", "league": 3, "pl": 64, "connected": true}
	acc.server_message.emit({"type": "ranked_found", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "w", "opponent": opp})
	await frames(4)
	acc.server_message.emit({"type": "ranked_state", "match_id": mid, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "w", "status": "playing", "revision": 18, "starts_in_ms": 0,
		"white": me, "black": opp, "position": {"board": board, "turn": rules.turn, "rights": rules.rights, "ep": [-1, -1], "halfmove": rules.halfmove, "ply": rules.ply},
		"in_check": false, "last_move": {"from": [last.from.x, last.from.y], "to": [last.to.x, last.to.y]}, "clock": {"w_ms": 131000, "b_ms": 118000, "active": "w"}})
	await frames(12)
	await shot("02_ranked")
	stage.open_home()
	await wait_s(1.0)

	# Contra o computador: escada de bots
	stage.hub.show_page("bot")
	await wait_s(1.5)
	await shot("03_bots")
	stage.open_home()
	await wait_s(1.0)

	# Ligas e ranking
	stage.hub.show_page("ranking")
	await wait_s(1.5)
	await shot("04_ligas")
	stage.open_home()
	await wait_s(1.0)

	# MARCHA REAL jogando
	await stage.hub.open_marcha()
	var m2 = stage.hub.marcha
	if m2 != null:
		var guard := 0
		while m2.tut_page >= 0 and guard < 15:
			m2._on_hit("tut_next"); guard += 1
			await wait_s(0.1)
		await m2.start_game()
		var t := 0.0
		while t < 30.0 and m2.mode == "game":
			if m2.g != null and m2.awaiting_play() and m2.g.turn == 0: m2._auto_play()
			await wait_s(0.5)
			t += 0.5
		await shot("05_marcha")
		m2.close()
		await wait_s(1.0)

	# XEQUE jogando
	await stage.hub.open_xeque()
	var x = stage.hub.xeque
	if x != null:
		await wait_s(1.0)
		x._on_hit("tut_bots")
		await wait_s(5.0)
		var t2 := 0.0
		while t2 < 20.0 and x.mode == "game":
			if x.phase != "": x.skip_presentation()
			elif x.g != null and x.g.state == x.Rules.TURN_WAITING and x.g.turn == 0:
				x.toggle_card(0)
				x.human_play()
			await wait_s(0.5)
			t2 += 0.5
		await shot("06_xeque")
	quit()
