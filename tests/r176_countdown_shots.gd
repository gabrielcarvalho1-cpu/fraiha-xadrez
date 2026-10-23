extends SceneTree
## R176.9 · contagem 3 · 2 · 1 · VAI COMEÇAR antes do XEQUE e da MARCHA (FRAIHA_COUNTDOWN=1): aparece, segura a
## partida (abertura do XEQUE não anda) e some sozinha. Prints de cada passo.
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(2)
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
	ui.start_game()
	check(ui.counting(), "XEQUE: contagem aparece")
	var i0: float = ui.intro_anim
	for k in 6: ui._process(0.1)
	check(ui.counting() and ui.intro_anim == i0, "XEQUE: abertura espera a contagem")
	var seen := {}
	while ui.counting():
		var c = ui.countdown
		var key := str(mini(3, int(c.t / c.STEP)))
		if not seen.has(key):
			seen[key] = true
			await shot("xeque_passo_" + key)
		await process_frame
	check(seen.size() >= 3, "XEQUE: passos vistos %s" % str(seen.keys()))
	await create_timer(1.0).timeout
	await frames(3)
	check(not ui.counting() and root.find_child("MatchCountdown", true, false) == null, "XEQUE: contagem some sozinha")
	check(ui.intro_anim > i0 or ui.intro_anim < 0.0, "XEQUE: abertura começa depois")
	# MARCHA REAL
	ui.close() if ui.has_method("close") else null
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://marcha_access.cfg"))
	await hub.open_marcha()
	await frames(10)
	var mu = hub.marcha
	mu.tut_page = -1
	mu.start_game()
	for i in 30:
		await process_frame
		if mu.counting(): break
	check(mu.counting(), "MARCHA: contagem aparece")
	await create_timer(0.4).timeout
	await shot("marcha_contagem")
	var dl: int = mu.turn_deadline
	while mu.counting(): await process_frame
	await frames(4)
	check(mu.mode == "game" and mu.turn_deadline > 0, "MARCHA: partida começa depois da contagem")
	await shot("marcha_depois")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
