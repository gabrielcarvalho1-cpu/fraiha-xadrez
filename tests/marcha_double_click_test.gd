extends SceneTree
## R69 · Marcha: duplo clique na carta da mão joga a carta (igual ao JOGAR CARTA). Um clique só seleciona.
var failures := 0
func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _initialize(): call_deferred("run")
func frames(n := 4):
	for i in n: await process_frame
func run():
	root.size = Vector2i(1920, 1080)
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await frames(2)
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	hub.monetization_state.mock_reset()
	hub.open_marcha()
	await frames(6)
	var ui = hub.marcha
	ui.tut_page = -1
	await ui.start_game()
	var t0 := Time.get_ticks_msec()
	while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 30000: await process_frame
	await frames(2)
	# carta que tira peão da base (sempre jogável no começo): A ou K
	var idx := -1
	for i in ui.g.hands[0].size():
		if ui.g.hands[0][i] in ["K"]: idx = i
	if idx < 0:
		ui.g.hands[0][0] = "K"; idx = 0
	var n0: int = ui.g.hands[0].size()
	ui._on_hit("card_%d" % idx)
	await frames(2)
	check(ui.sel_card == idx and ui.g.hands[0].size() == n0, "1 clique: só seleciona")
	ui._on_hit("card_%d" % idx)
	var t1 := Time.get_ticks_msec()
	while ui.g.hands[0].size() == n0 and Time.get_ticks_msec() - t1 < 8000: await process_frame
	check(ui.g.hands[0].size() == n0 - 1, "duplo clique: carta jogada (mão %d → %d)" % [n0, ui.g.hands[0].size()])
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
