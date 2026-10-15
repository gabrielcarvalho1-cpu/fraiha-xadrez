extends SceneTree
## R118 · TORNEIO DA SEMANA: placar XEQUE / MARCHA, prêmios, minha posição; botão no painel COROAS.
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
	var size := Vector2i(1672, 941)
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
	var hub = stage.get_node("MainHub")
	var acc = stage.account
	acc.user_id = "u-me"
	acc.access_token = "teste"
	acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	hub.show_page("main")
	await frames(6)
	acc.server_message.emit({"type": "crowns_state", "available": true, "balance": 420, "streak": 2, "daily_claimed": true, "missions": [], "recent": [], "match_today": 20, "match_cap": 150, "rules": {}})
	var cl = hub.crowns_client()
	cl.open_panel()
	await frames(6)
	check(find_named(root, "CrownsOpenTournament").size() == 1, "painel COROAS com TORNEIO DA SEMANA")
	cl.open_tournament("xeque")
	await frames(4)
	var names := ["ReiDoBlefe", "DamaDeFerro", "Gabriel", "TorreAlta", "BispoVeloz", "CavaloLouco", "PeaoValente", "XequeMate", "RoqueLongo", "GambitoRei"]
	var pts := [31, 27, 22, 19, 16, 14, 11, 9, 7, 5]
	var prizes := [500, 300, 200, 100, 100, 100, 100, 100, 100, 100]
	var top := []
	for i in names.size(): top.append({"pos": i + 1, "user_id": "u-me" if names[i] == "Gabriel" else "u%d" % i, "nickname": names[i], "points": pts[i], "wins": pts[i] / 3, "games": pts[i] / 2, "prize": prizes[i]})
	acc.server_message.emit({"type": "tourn_state", "available": true, "game": "xeque", "week": "2026-W42", "ends_in_s": 3 * 86400 + 8 * 3600,
		"top": top, "me": {"pos": 3, "points": 22, "wins": 7, "games": 11, "prize": 200}, "players": 34,
		"rules": {"win": 3, "play": 1, "daily_games": 8, "prizes": prizes}})
	await frames(6)
	check(find_named(root, "TournRow_").size() == 10, "top 10 no placar")
	check(String(find_named(root, "TournMe")[0].text).contains("3º lugar"), "minha posição")
	await shot("01_torneio_xeque")
	acc.server_message.emit({"type": "tourn_state", "available": true, "game": "marcha", "week": "2026-W42", "ends_in_s": 5000, "top": [], "me": {"pos": null, "points": 0, "wins": 0, "games": 0, "prize": 0}, "rules": {"win": 3, "play": 1, "daily_games": 8, "prizes": prizes}})
	cl.tourn_panel.set_game("marcha")
	await frames(6)
	await shot("02_torneio_marcha_vazio")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
