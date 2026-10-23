extends SceneTree
## R176.9 · DICAS DOS BOTÕES no visual do jogo (ui_kit/tooltip_host.gd): mouse parado em cima mostra a placa fora do
## botão e dentro da tela; toque longo (celular) mostra a dica e NÃO aperta o botão.
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1600x900 xvfb-run godot --rendering-driver opengl3 --path . -s tests/r176_tooltips_shots.gd [-- --mobile-test]
var stage
var hub
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
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))

func find_named(n: Node, prefix: String) -> Control:
	if n.name.begins_with(prefix) and n is Control and n.is_visible_in_tree(): return n
	for c in n.get_children():
		var r = find_named(c, prefix)
		if r != null: return r
	return null

func mouse_to(p: Vector2, device := 0):
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.relative = Vector2(3, 3)
	m.device = device
	root.push_input(m)

func button(p: Vector2, pressed: bool, device := 0):
	var b := InputEventMouseButton.new()
	b.position = p
	b.global_position = p
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	b.device = device
	root.push_input(b)

func secs(s: float):
	await create_timer(s).timeout

func run():
	var size := Vector2i(1600, 900)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	hub = stage.get_node("MainHub")
	hub.show_page("main")
	await frames(20)
	var host = stage.find_child("FraihaTooltips", true, false)
	check(host != null, "dicas do jogo ligadas no palco")
	check(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec")) > 100.0, "dica nativa (cinza) desligada")
	var mobile := "--mobile-test" in OS.get_cmdline_user_args()
	var names := ["SupportTopButton", "SoundButton", "MailTopButton"] if not mobile else ["SoundButton", "SupportTopButtonMobile"]
	var n := 0
	for nm in names:
		var b := find_named(root, nm)
		if b == null:
			print("(sem %s nesta tela)" % nm)
			continue
		var r: Rect2 = b.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, b.size)
		if mobile:
			# toque longo: dedo parado 0,6 s
			var pressed_count := [0]
			if b is BaseButton: b.pressed.connect(func(): pressed_count[0] += 1)
			var ev := InputEventScreenTouch.new()
			ev.position = r.get_center()
			ev.pressed = true
			root.push_input(ev)
			mouse_to(r.get_center(), -1)
			button(r.get_center(), true, -1)
			await secs(0.75)
			var tip: Control = host.tip
			check(tip != null, "%s: toque longo mostra a dica" % nm)
			if tip != null: print("  btn ", r, " tip ", Rect2(tip.position, tip.size), " arrow ", tip.arrow_x, " vs ", root.get_visible_rect(), " k ", host._k())
			if tip != null:
				var tr := Rect2(tip.position, tip.size)
				check(not tr.grow(-2).intersects(r) and Rect2(Vector2.ZERO, Vector2(size)).encloses(tr), "%s: dica fora do botão e dentro da tela" % nm)
			n += 1
			await shot("dica_%d" % n)
			var up := InputEventScreenTouch.new()
			up.position = r.get_center()
			up.pressed = false
			root.push_input(up)
			button(r.get_center(), false, -1)
			await frames(6)
			check(pressed_count[0] == 0, "%s: soltar depois da dica NÃO aperta o botão" % nm)
			check(host.tip == null, "%s: a dica some ao soltar" % nm)
			if nm != names[-1]: continue
			# toque curto continua apertando (só no último: ele abre uma tela)
			root.push_input(ev)
			button(r.get_center(), true, -1)
			await frames(3)
			root.push_input(up)
			button(r.get_center(), false, -1)
			await frames(6)
			check(pressed_count[0] == 1 or not (b is BaseButton), "%s: toque curto aperta normalmente" % nm)
		else:
			mouse_to(Vector2(5, size.y - 5))
			await frames(3)
			mouse_to(r.get_center())
			await frames(3)
			check(host.tip == null, "%s: não abre na hora" % nm)
			await secs(0.7)
			var tip: Control = host.tip
			check(tip != null, "%s: mouse parado mostra a dica" % nm)
			if tip != null:
				var tr := Rect2(tip.position, tip.size)
				check(not tr.grow(-2).intersects(r) and Rect2(Vector2.ZERO, Vector2(size)).encloses(tr), "%s: dica fora do botão e dentro da tela" % nm)
				print("  dica: ", b.tooltip_text)
			n += 1
			await shot("dica_%d" % n)
	mouse_to(Vector2(5, size.y - 5))
	await frames(4)
	check(host.tip == null, "tirar o mouse esconde a dica")
	print("RESULT ", "OK" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
