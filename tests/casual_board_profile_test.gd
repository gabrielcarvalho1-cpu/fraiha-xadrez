extends SceneTree
## R54 · (1) partida Casual no PC usa a MESMA arte do Ranked Madeira (ranked/board_skin.gd), com os cartões da
## casual_ui; ao sair, tudo volta. (2) Perfil: o detalhe do avatar acompanha o visual EM USO (foto enviada,
## foto removida, ao abrir o Perfil), sem perder o "tocar só inspeciona".
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/casual_board_profile_test.gd
var failures := 0
var stage

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize(): call_deferred("run")

func frames(n := 6):
	for i in n: await process_frame

func run():
	root.size = Vector2i(1920, 1080)
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	stage.theme_manager.apply_theme("wood", false)
	# ---------------- Casual na arte do Ranked
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	var opp := {"nickname": "SextoSen1", "avatar_id": "warrior", "connected": true}
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "connected": true}
	stage._open_casual()
	await frames(6)
	acc.server_message.emit({"type": "casual_found", "match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "opponent": opp})
	await frames(4)
	acc.server_message.emit({"type": "casual_state", "match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": me, "black": opp, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0},
		"in_check": false, "last_move": null, "clock": {"w_ms": 300000, "b_ms": 300000, "active": "w"}})
	await frames(14)
	var skin = stage.board_skin
	var cui = stage.casual_ui
	check(stage.mode == "casual" and skin.on and skin.kind == "pc", "Casual no PC: arte do Ranked Madeira ligada")
	check(skin.match_ui() == cui, "Casual usa os cartões da casual_ui")
	var top: Dictionary = cui.strips.top
	var expect: Rect2 = skin.R(skin.PC.clock)
	check(top.clock.top_level and top.clock.position.distance_to(expect.position) < 2.0, "relógio do adversário no lugar da arte")
	check(skin.R(skin.PC.resign).position.distance_to(cui.resign_button.position) < 2.0 and cui.resign_button.visible, "DESISTIR do Casual no lugar da arte")
	check(stage.game.piece_override == skin.PECAS, "peças em pixel art do Ranked")
	check(String(top.sub.text).to_upper().contains("CASUAL"), "cartão diz CASUAL (sem liga/PL): " + String(top.sub.text))
	stage.open_home()
	await frames(10)
	check(not skin.on and not top.clock.top_level, "saindo da partida a arte é desfeita")
	# ---------------- Perfil: detalhe acompanha o visual em uso
	var hub = stage.hub
	hub.show_page("profile")
	await frames(4)
	hub._inspect_avatar("paladin")
	await frames(2)
	check(hub.avatar_detail.title.text == "PALADINO" or hub.inspected_avatar == "paladin", "tocar num avatar só inspeciona")
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.2, 0.2))
	hub._on_photo_saved(img, img.save_png_to_buffer())
	await frames(3)
	check(hub.avatar_detail.title.text == "SUA FOTO" and hub.avatar_detail.pic.texture == hub.custom_avatar(), "foto enviada: o detalhe mostra a foto EM USO")
	check(hub.avatar_detail.apply.disabled and hub.avatar_detail.apply.text == "EM USO", "foto em uso: botão EM USO")
	hub.remove_custom_avatar()
	await frames(3)
	var cur: String = hub.avatar_id
	check(hub.avatar_detail.title.text == String(hub.AvatarCatalog.entry(cur).get("name", cur)).to_upper() and hub.avatar_detail.status.text.begins_with("EM USO"), "foto removida: detalhe volta ao avatar em uso (" + hub.avatar_detail.title.text + ")")
	hub._inspect_avatar("paladin")
	hub.show_page("home")
	await frames(2)
	hub.show_page("profile")
	await frames(3)
	check(hub.inspected_avatar == "" and hub.avatar_detail.status.text.begins_with("EM USO"), "abrir o Perfil de novo mostra o avatar em uso")
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
