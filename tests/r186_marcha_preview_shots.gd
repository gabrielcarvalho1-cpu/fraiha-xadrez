extends SceneTree
## R186 · prévia: casas do caminho (X roxo / X preto / antigo), ABATER com o 5 na peça da aliada, botões de voz/chat.
const Layout := preload("res://marcha/board_layout.gd")
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(name + ".png"))
func run():
	var size := Vector2i(1080, 2340)
	root.size = size
	root.content_scale_size = size
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	hub.monetization_state.mock_reset()
	hub.open_marcha() if hub.has_method("open_marcha") else hub.menu_buttons[4].pressed.emit()
	await frames(6)
	var ui = hub.marcha
	ui.tut_page = -1
	await ui.start_game()
	var t0 := Time.get_ticks_msec()
	while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 30000: await process_frame
	var g = ui.g
	for s in 4:
		for i in 4: g.pawns[s][i] = {"zone": "home", "pos": i}
	g.pawns[0][0] = {"zone": "track", "pos": Layout.gate_index(0) + 3}
	var pp := Layout.gate_index(2) + 8
	g.pawns[2][0] = {"zone": "track", "pos": pp}
	g.pawns[1][0] = {"zone": "track", "pos": pp + 5}
	g.hands[0] = ["9", "5", "6", "3"]
	ui.online = true
	var pc = stage.get("party_chat")
	if pc != null: pc.bind("r186", "marcha", ["Você", "Rubi", "Ônix", "Esmeralda"])
	ui.sel_card = 0
	var mvs: Array = g.legal_moves(0, 0)
	ui.pending = mvs[0] if not mvs.is_empty() else {}
	print("PENDING ", ui.pending)
	await frames(4)
	for st in ["x_purple", "x_black", "gold"]:
		ui.path_style = st
		ui._redraw()
		await shot("marcha_caminho_" + st)
	var land := Vector2i(2340, 1080)
	root.size = land
	root.content_scale_size = land
	await frames(10)
	ui._relayout()
	ui.pending = {}
	ui.sel_card = -1
	await frames(40)
	await shot("marcha_deitado_suavez")
	g.turn = 1
	await frames(40)
	await shot("marcha_deitado_espera")
	g.turn = 0
	g.hands[0] = ["5"]
	await frames(40)
	await shot("marcha_deitado_1carta")
	quit(0)
