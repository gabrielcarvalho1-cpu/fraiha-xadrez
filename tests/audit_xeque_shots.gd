extends SceneTree
## Auditoria visual · XEQUE: tutorial, apresentação do baralho, mão com cartas escolhidas, cartas viradas na mesa,
## XEQUE (revelação), relógio, XEQUE-MATE e tela de resultado. Só tira prints (sem asserts de regra).
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path . -s tests/audit_xeque_shots.gd [-- --mobile-test]
const Rules := preload("res://xeque/rules.gd")
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))

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
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	await hub.open_xeque()
	await frames(10)
	var ui = hub.xeque
	await shot("x01_tutorial")
	ui.seed_override = 77
	ui._on_hit("tut_play")
	await frames(4)
	ui._process(ui.INTRO_T * 0.5)
	await shot("x02_apresentacao")
	ui._process(ui.INTRO_T)
	ui._process(3.0)
	ui._process(3.0)
	var g: Rules = ui.g
	g.turn = 0
	g.last_play = {}
	ui._begin_turn()
	ui._process(3.0); ui._process(3.0)
	await frames(4)
	ui.toggle_card(0); ui.toggle_card(2)
	await shot("x03_mao_escolhida")
	ui.menu_open = true
	ui._redraw()
	await shot("x03b_menu")
	ui.menu_open = false
	ui._redraw()
	ui.human_play()
	await frames(2)
	await shot("x04_cartas_na_mesa")
	# XEQUE em cima da jogada de outro (revela as cartas viradas)
	g.turn = 0
	g.target = "rainha"
	g.last_play = {"seat": 3, "cards": ["rei", "rainha"], "count": 2}
	g.plays.append(g.last_play)
	g.clocks[3] = [Rules.MATE, Rules.SAFE, Rules.SAFE, Rules.SAFE, Rules.SAFE, Rules.SAFE]
	ui._begin_turn()
	ui._process(3.0); ui._process(3.0)
	await frames(3)
	ui.human_challenge()
	await frames(2)
	ui._process(0.6)
	await shot("x05_xeque_revela")
	ui._advance_phase()
	ui._process(0.6)
	await shot("x06_relogio")
	ui._advance_phase()
	for tt in [0.1, 0.4, 1.2]:
		ui.phase_t = tt
		ui._redraw()
		await shot("x07_xeque_mate_%d" % int(tt * 10))
	ui.skip_presentation()
	# termina a partida para ver o resultado
	var guard := 0
	while ui.mode == "game" and guard < 6000:
		guard += 1
		if ui.phase != "": ui.skip_presentation()
		elif g.state == Rules.TURN_WAITING and g.turn == 0:
			ui.toggle_card(0)
			ui.human_play()
		else: ui._process(0.25)
	await frames(6)
	ui._process(1.0)
	await shot("x08_resultado")
	print("AUDIT XEQUE OK")
	quit(0)
