extends SceneTree
## R54 · MARCHA REAL: 15 s por vez e relógio do turno em tempo REAL. Com a aba em segundo plano o navegador
## para de chamar _process; aqui isso é simulado parando o processamento da tela por ~1,2 s: ao voltar, o tempo
## mostrado já descontou o período parado (antes congelava). Online o prazo vem do servidor (turn_left_ms).
var failures := 0

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize(): call_deferred("run")

func frames(n := 3):
	for i in n: await process_frame

func pause_real(ms: int, ui):
	ui.set_process(false)
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end: await process_frame
	ui.set_process(true)
	await frames(2)

func run():
	root.size = Vector2i(1600, 900)
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	hub.monetization_state.mock_reset()
	hub.menu_buttons[4].pressed.emit()
	await frames(6)
	var ui = hub.marcha
	check(ui.TURN_MS == 15000, "vez de 15 segundos")
	ui.tut_page = -1
	await ui.start_game()
	await frames(4)
	# espera a vez do jogador (sem animação)
	var t0 := Time.get_ticks_msec()
	while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 30000: await process_frame
	await frames(2)
	var before: int = ui.turn_left_ms
	check(before > 12000 and before <= 15000, "local: vez começa com ~15 s (%d ms)" % before)
	await pause_real(1200, ui)
	var after: int = ui.turn_left_ms
	check(before - after >= 1100, "local: tela parada (aba em 2º plano) não congela o relógio (%d → %d)" % [before, after])
	# online: o prazo é o do servidor; parado ou não, o tempo mostrado segue o relógio real
	ui.online = true
	ui._apply_snapshot({"turn_left_ms": 9000, "my_turn": true, "turn": 0, "hand_counts": [4, 4, 4, 4], "my_hand": ui.g.hands[0]})
	await frames(2)
	var o1: int = ui.turn_left_ms
	await pause_real(1200, ui)
	var o2: int = ui.turn_left_ms
	check(o1 <= 9000 and o1 > 8500 and o1 - o2 >= 1100, "online: prazo do servidor, sem congelar (%d → %d)" % [o1, o2])
	ui.menu_open = true
	await frames(10)
	var o3: int = ui.turn_left_ms
	check(o3 < o2, "online: menu aberto não segura o relógio do servidor")
	ui.menu_open = false
	ui.online = false
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
