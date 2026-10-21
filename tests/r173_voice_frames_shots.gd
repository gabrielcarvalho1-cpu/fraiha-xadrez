extends "res://tests/r173_mobile_audit_shots.gd"
## R173 · Indicador verde da voz (cartão do jogador no Ranked/Casual) com cada tipo de moldura e avatar.
## Recorta o cartão de cima (adversário falando) para cada combinação e o de baixo (eu falando, avatar normal).
## Uso: SHOT_DIR=<pasta> SHOT_TAG=<prefixo> xvfb-run godot --rendering-driver opengl3 --path . \
##        -s tests/r173_voice_frames_shots.gd -- [--mobile-test] --size 390x844
const COMBOS := [["warrior", "liga"], ["archer", "liga"], ["warrior", "club"], ["archer", "club"], ["warrior", "fundador"],
	["archer", "fundador"], ["warrior", "prata"], ["warrior", "elo_ouro"], ["archer", "m_chama_eterna"]]

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(390, 844)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	screen = Vector2(size)
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	hub = stage.get_node("MainHub")
	acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_5min": {"league": 3, "pl": 40, "highest_league": 3, "wins": 30, "losses": 8, "draws": 2, "matches": 40}}
	stage._sync_theme_unlocks()
	await frames()
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	var mid := "00000000-0000-4000-8000-0000000000b1"
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "league": 3, "pl": 40, "connected": true}
	acc.server_message.emit({"type": "ranked_found", "match_id": mid, "mode": "ranked_5min", "mode_name": "Rápida", "you": "w",
		"opponent": {"nickname": "SextoSentro", "avatar_id": "warrior", "league": 3, "pl": 47, "connected": true}})
	await frames(4)
	var v = stage.voice
	v.use_provider(load("res://voice/mock_voice_provider.gd").new())
	var rev := 1
	for combo in COMBOS:
		var opp := {"nickname": "SextoSentro", "avatar_id": combo[0], "frame": combo[1], "league": 3, "pl": 47, "connected": true}
		rev += 1
		acc.server_message.emit({"type": "ranked_state", "match_id": mid, "mode": "ranked_5min", "mode_name": "Rápida", "you": "w", "status": "playing", "revision": rev, "starts_in_ms": 0,
			"white": me, "black": opp, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0},
			"in_check": false, "last_move": null, "clock": {"w_ms": 296000, "b_ms": 300000, "active": "w"}})
		v.ctx = {"kind": "ranked", "match_id": mid}
		v.state = "CONNECTED"
		v.my_uid = 1
		v.remote = [2]
		v.speaking = [1, 2]
		v.changed.emit()
		await frames(14)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var name := "%s_%s" % [combo[0], combo[1]]
		for k in ["top", "bottom"]:
			if k == "bottom" and combo != COMBOS[0]: continue
			var bg: Control = stage.ranked_ui.strips[k].bg
			var r := Rect2i((bg.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bg.size)).grow(12))
			r = r.intersection(Rect2i(Vector2i.ZERO, size))
			img.get_region(r).save_png(OS.get_environment("SHOT_DIR").path_join("%s_%s_%s.png" % [OS.get_environment("SHOT_TAG"), k, name]))
		if combo == COMBOS[0]:
			img.save_png(OS.get_environment("SHOT_DIR").path_join("%s_full.png" % OS.get_environment("SHOT_TAG")))
			audit("voz_full")
	quit()
