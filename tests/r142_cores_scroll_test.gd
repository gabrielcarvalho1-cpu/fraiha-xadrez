extends SceneTree
## R142 · TABULEIRO E PEÇAS no celular: arrastar o dedo em cima das amostras rola a LISTA (não a página das Ligas de trás).
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func touch(pos: Vector2, pressed: bool):
	var e := InputEventScreenTouch.new()
	e.index = 0; e.pressed = pressed; e.position = pos
	root.push_input(e)
func drag(pos: Vector2, rel: Vector2):
	var e := InputEventScreenDrag.new()
	e.index = 0; e.position = pos; e.relative = rel
	root.push_input(e)
func swipe(from: Vector2, dy: float):
	touch(from, true)
	await frames(2)
	for k in range(1, 11):
		drag(from + Vector2(0, dy * k / 10.0), Vector2(0, dy / 10.0))
		await frames(1)
	touch(from + Vector2(0, dy), false)
	await frames(3)
func run():
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(390, 844); root.content_scale_size = root.size
	await process_frame
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(25)
	if stage.account_ui.is_open(): stage.account_ui.close()
	var hub = stage.hub
	stage.account._receive({"type": "leagues_preview", "enabled": true})
	hub.show_page("ranking")
	await frames(8)
	var mob = hub.mobile_ui
	var back_scroll: ScrollContainer = mob.ref_page.scroll if mob != null and mob.ref_page != null else null
	hub.open_board_colors()
	await frames(10)
	var ui = hub.board_colors_ui
	var sc: ScrollContainer = ui.scroll
	var bar := sc.get_v_scroll_bar()
	check(bar.max_value > bar.page, "lista maior que o espaço: rola")
	var back0: int = back_scroll.scroll_vertical if back_scroll != null else 0
	var sw: Button = ui.find_child("Casas_madeira", true, false)
	var start: Vector2 = sw.get_global_rect().get_center()
	await swipe(start, -160.0)
	check(sc.scroll_vertical > 40, "arrastar em cima da amostra rola a lista (%d)" % sc.scroll_vertical)
	check(back_scroll == null or back_scroll.scroll_vertical == back0, "página das Ligas de trás não mexe (%d → %d)" % [back0, back_scroll.scroll_vertical if back_scroll else 0])
	check(hub.board_color_pref != "" and ui.visible, "arrastar não escolheu nada nem fechou")
	print("FAILS ", failures)
	quit()
