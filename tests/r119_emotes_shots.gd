extends SceneTree
## R119 · EMOTES na partida online (PC com a arte do tabuleiro e celular): fileira de emotes (grátis + comprados),
## balão grande quando chega, linha no chat. Sem rede: as mensagens do servidor são simuladas.
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
func find_named(n: Node, prefix: String) -> Array:
	var out := []
	if n.name.begins_with(prefix) and n is Control and n.is_visible_in_tree(): out.append(n)
	for c in n.get_children(): out.append_array(find_named(c, prefix))
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
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	preload("res://profile/premium_cosmetics.gd").shop_owned = ["emote_lenda", "emote_rei_chegou"]
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "league": 0, "pl": 90, "connected": true}
	var opp := {"nickname": "SextoSen1", "avatar_id": "warrior", "league": 0, "pl": 40, "connected": true}
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	stage._open_casual()
	await frames(6)
	acc.server_message.emit({"type": "casual_found", "match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "opponent": opp})
	acc.server_message.emit({"type": "casual_state", "match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": me, "black": opp, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0},
		"in_check": false, "last_move": null, "clock": {"w_ms": 300000, "b_ms": 300000, "active": "w"}})
	await frames(12)
	var chat = stage.match_chat
	check(chat != null and chat.active(), "chat da partida ativo")
	if chat == null or not chat.active():
		print("RESULT FALHOU"); quit(1); return
	if chat.minimized: chat.set_minimized(false)
	if stage.has_method("_layout"): stage._layout()
	chat.set_mobile_open(true)
	await frames(6)
	chat._toggle_emotes()
	await frames(6)
	check(find_named(root, "Emote_").size() == 6, "4 emotes de graça + 2 comprados")
	await shot("01_emotes_abertos")
	chat._toggle_emotes()
	acc.server_message.emit({"type": "chat_msg", "match_id": chat.match_id, "id": 1, "from_color": "b", "nickname": "SextoSen1", "text": "Boa jogada!", "emote": "emote_boa_jogada", "ts": ""})
	await frames(4)
	check(chat.bubble_layer != null and chat.bubble_layer.get_child_count() == 1, "balão do emote do adversário")
	await shot("02_emote_recebido")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
