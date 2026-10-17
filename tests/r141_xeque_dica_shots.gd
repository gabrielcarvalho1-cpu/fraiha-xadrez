extends SceneTree
## R141 · balão "DESCONFIOU? DÊ XEQUE!" sobre o botão XEQUE (3 primeiras partidas, até usar o XEQUE) + prints.
const Rules := preload("res://xeque/rules.gd")
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func check(c: bool, m: String):
	print(("OK " if c else "FAIL ") + m)
	if not c: fails += 1
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://xeque_dica.cfg"))
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	await hub.open_xeque()
	await frames(10)
	var ui = hub.xeque
	ui.seed_override = 77
	ui._on_hit("tut_play")
	await frames(4)
	check(ui.hint_on, "1ª partida: dica ligada")
	ui._process(ui.INTRO_T); ui._process(3.0); ui._process(3.0)
	var g: Rules = ui.g
	g.turn = 0
	g.last_play = {"seat": 3, "cards": ["rei", "rainha"], "count": 2}
	ui._begin_turn()
	ui._process(3.0); ui._process(3.0)
	await frames(4)
	check(ui.can_human_challenge(), "XEQUE possível na sua vez")
	ui.t = 0.2
	await shot("dica_a")
	ui.t = 1.4
	await shot("dica_b")
	ui.human_challenge()
	check(not ui.hint_on, "usou o XEQUE: dica some")
	var c := ConfigFile.new(); c.load("user://xeque_dica.cfg")
	check(bool(c.get_value("dica", "usou", false)), "uso gravado")
	ui._xeque_hint_new_game()
	check(not ui.hint_on, "partida seguinte: sem dica")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://xeque_dica.cfg"))
	for i in 3: ui._xeque_hint_new_game()
	ui._xeque_hint_new_game()
	check(not ui.hint_on, "depois de 3 partidas a dica para")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://xeque_dica.cfg"))
	print("FAILS ", fails)
	quit()
