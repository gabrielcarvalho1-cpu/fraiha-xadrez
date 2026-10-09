extends SceneTree
## R55.2 · XEQUE no PC: painéis/molduras/cantoneiras e a placa do XEQUE pré-compostos (xeque/desk_paint.gd).
## Confere que as imagens NÃO são refeitas a cada quadro (só quando muda estado/tamanho), que redimensionar
## refaz na escala nova sem acumular cache, e que os draw calls/frame ficam na meta (≤ 430; R55.1 ≈ 590).
## R55.3: a entrada da partida monta no máximo DeskPaint.BUDGET imagens por quadro e o resto (vinheta e cartas)
## já vem preparado da tela "Como jogar".
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/xeque_desk_cache_test.gd
const DeskPaint := preload("res://xeque/desk_paint.gd")
var failures := 0

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize(): call_deferred("run")

func frames(n := 6):
	for i in n: await process_frame

func draw_calls(n := 60) -> float:
	var s := 0.0
	for i in n:
		await process_frame
		s += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	return s / n

func run():
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	stage.hub.menu_buttons[5].pressed.emit()
	await frames(10)
	var ui = stage.hub.xeque
	# R55.3 · preparo na tela "Como jogar": vinheta e cartas nos tamanhos da mesa, um item por quadro
	await frames(40)
	var Crisp := preload("res://ui_v022/crisp_tex.gd")
	check(ui._prewarm.is_empty() and ui.view.vignette != null and Crisp._cache.size() >= 12, "Como jogar: vinheta e cartas preparadas antes da partida (%d cartas)" % Crisp._cache.size())
	ui.seed_override = 77
	ui.start_game()
	var pior := 0
	var c_ini: int = Crisp._cache.size()
	for i in 12:
		var bb: int = DeskPaint.builds
		await process_frame
		pior = maxi(pior, DeskPaint.builds - bb)
	check(pior <= DeskPaint.BUDGET and Crisp._cache.size() == c_ini, "entrada da partida: no máximo %d painéis por quadro (pior %d) e nenhuma carta reduzida na hora" % [DeskPaint.BUDGET, pior])
	for k in 900:
		await process_frame
		if ui.mode == "game" and ui.g != null and ui.g.turn == 0 and ui.can_human_play(): break
	await frames(30)
	check(ui.layout == "desktop", "PC 1920x1080: layout do PC")
	# (o render por software deste teste é lento: o tempo da vez é renovado antes de cada etapa para a vez
	#  não acabar no meio e trocar o estado visual)
	ui.turn_left_ms = 30000
	await frames(4)
	var b0: int = DeskPaint.builds
	check(b0 > 0 and b0 < 40, "painéis montados uma vez (%d imagens)" % b0)
	ui.turn_left_ms = 30000
	var dc := await draw_calls()
	check(dc <= 430.0, "draw calls/frame na sua vez parada: %.1f (meta ≤ 430; R55.1 ≈ 590)" % dc)
	check(DeskPaint.builds == b0, "60 quadros parados: nenhuma imagem refeita (timer e animações seguem ao vivo)")
	ui.turn_left_ms = 30000
	var t0: float = ui.turn_left_ms
	await frames(6)
	check(ui.turn_left_ms < t0, "timer continua correndo (%.0f → %.0f ms)" % [t0, ui.turn_left_ms])
	# seleção / hover: no máximo poucas imagens novas (estado visual novo), e depois param
	ui.turn_left_ms = 30000
	ui.toggle_card(0)
	ui.hover_id = "play"
	await frames(6)
	var b1: int = DeskPaint.builds
	ui.turn_left_ms = 30000
	await frames(40)
	check(DeskPaint.builds == b1 and b1 - b0 <= 4, "seleção + hover: %d imagem(ns) nova(s) e depois estável" % (b1 - b0))
	ui.hover_id = ""
	# redimensionar: refaz na escala nova e não acumula
	var k0: float = ui.k
	root.size = Vector2i(1366, 768)
	ui.turn_left_ms = 30000
	await frames(10)
	var b3: int = DeskPaint.builds
	print("INFO k %.4f -> %.4f  viewport %s" % [k0, ui.k, str(ui.root.get_viewport_rect().size)])
	if absf(ui.k - k0) > 0.0005:
		check(b3 > b1, "janela redimensionada (escala %.3f → %.3f): painéis refeitos na escala nova (%d novas)" % [k0, ui.k, b3 - b1])
	else:
		check(b3 == b1, "janela redimensionada com a mesma escala do jogo (tela esticada pelo Godot): nada refeito")
	ui.turn_left_ms = 30000
	await frames(30)
	check(DeskPaint.builds == b3, "depois de redimensionar: estável")
	check(DeskPaint._cache.size() <= 48, "cache pequeno (%d imagens)" % DeskPaint._cache.size())
	root.size = Vector2i(1920, 1080)
	await frames(6)
	# jogar + XEQUE + relógio: poucas imagens novas (bordas de estado: pensando, risco, com o relógio…)
	var b4: int = DeskPaint.builds
	ui.human_play()
	for k in 3000:
		await process_frame
		if ui.can_human_challenge(): break
	ui.human_challenge()
	for k in 900:
		await process_frame
		if ui.phase in ["safe", "mate", "elim"]: break
	await frames(20)
	check(DeskPaint.builds - b4 <= 16, "jogar + XEQUE + relógio: poucas imagens novas por estado (%d)" % (DeskPaint.builds - b4))
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
