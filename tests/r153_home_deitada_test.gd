extends SceneTree
## R153 · HOME DEITADA (celular deitado largo): menu ocupando a altura da tela; SEJA MEMBRO, ícones, perfil, conta e
## COMUNIDADE nas laterais, inteiros na tela, sem cobrir o menu, e funcionando no toque. Sair da Home desfaz.
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func click(pos: Vector2):
	for pressed in [true, false]:
		var m := InputEventMouseButton.new(); m.button_index = MOUSE_BUTTON_LEFT; m.position = pos; m.global_position = pos; m.pressed = pressed
		root.push_input(m)
		await frames(2)
func grect(n: Control) -> Rect2:
	var r := n.get_global_rect()
	return Rect2(r.position, n.size * n.get_global_transform_with_canvas().get_scale())
func run():
	var sz := OS.get_environment("SHOT_SIZE")
	if sz == "": sz = "915x360"
	var p := sz.split("x")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(int(p[0]), int(p[1])); root.content_scale_size = root.size
	await process_frame
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(30)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	await frames(5)
	var hub = stage.hub
	var vs: Vector2 = root.get_visible_rect().size
	check(hub._wide_on, "Home deitada larga ativa (%s)" % sz)
	var sc: float = hub.canvas.scale.x
	check(sc * (hub.WIDE_BAND.y - hub.WIDE_BAND.x) >= vs.y - 1.0, "faixa do menu ocupa a altura da tela (escala %.3f)" % sc)
	var screen := Rect2(Vector2.ZERO, vs).grow(1.0)
	var menu_l: float = hub.canvas.position.x + hub.WIDE_MENU_X.x * sc
	var menu_r: float = hub.canvas.position.x + hub.WIDE_MENU_X.y * sc
	for nm in ["ClubHomeEntry", "SoundButton", "FullscreenButton", "TrophyTopButton", "ChatTopButton", "CrownsTopButton", "RefProfileButton", "AccountCard", "CommunityButton"]:
		var n: Control = hub.canvas.get_node(nm)
		var r := grect(n)
		var side_ok: bool = r.end.x <= menu_l + 1.0 or r.position.x >= menu_r - 1.0
		check(n.is_visible_in_tree() and screen.encloses(r) and side_ok, "%s inteiro na tela e fora do menu" % nm)
	# toques de verdade
	var com: Control = hub.canvas.get_node("CommunityButton")
	await click(grect(com).get_center())
	await frames(3)
	check(is_instance_valid(hub.notice_modal) and hub.notice_modal.visible, "COMUNIDADE responde ao toque")
	if is_instance_valid(hub.notice_modal): hub.notice_modal.close()
	await frames(3)
	var got := [false]
	hub.account_requested.connect(func(): got[0] = true)
	await click(grect(hub.canvas.get_node("AccountCard")).get_center())
	check(got[0], "CONTA responde ao toque")
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	await frames(3)
	await click(grect(hub.canvas.get_node("RefProfileButton")).get_center())
	await frames(6)
	check(not hub._wide_on and hub.canvas.get_node("RefProfileButton").position.x > 1100.0, "abrir o Perfil desfaz o arranjo da Home deitada")
	hub.open_home()
	await frames(8)
	check(hub._wide_on, "voltando à Home: arranjo deitado de novo")
	# celular em pé: nada disso
	root.size = Vector2i(390, 844); root.content_scale_size = root.size
	await frames(10)
	check(not hub._wide_on and hub.canvas.get_node("ClubHomeEntry").position == Vector2(22, 16), "em pé: posições originais")
	print("FAILS ", failures)
	quit(1 if failures else 0)
