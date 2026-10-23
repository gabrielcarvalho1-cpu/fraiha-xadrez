extends SceneTree
## R178 · prints da tela de início (PC e celular) — para o botão do PASSE.
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(30)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	await frames(20)
	await shot("home")
	# conta logada no nível 7 da temporada
	stage.account.server_message.emit({"type": "pass_state", "available": true, "name": "Temporada de Outubro", "level": 7, "xp": 7 * 150 + 90,
		"xp_per_level": 150, "levels": 30, "ends_in_s": 8 * 86400 + 3600})
	await frames(10)
	await shot("home_nivel7")
	var card = stage.hub.canvas.get_node_or_null("PassHomeCard") if stage.hub.get("canvas") != null else null
	var strip = _find(stage, "PassHomeStrip")
	if strip != null: card = strip
	print(("PASS " if card != null else "FAIL ") + "PASSE na Home")
	if card != null:
		card.pressed.emit()
		await frames(10)
		var pp = stage.hub.crowns_client().pass_panel
		var ok: bool = pp != null and is_instance_valid(pp) and pp.visible
		print(("PASS " if ok else "FAIL ") + "tocar no PASSE abre o Passe")
		var f := FileAccess.open("res://tests/fixtures_pass_state.json", FileAccess.READ)
		if f != null:
			stage.account.server_message.emit(JSON.parse_string(f.get_as_text()))
			await frames(12)
		await shot("passe_aberto")
	quit(0)

func _find(n: Node, nm: String) -> Node:
	if n.name == nm and n.is_visible_in_tree(): return n
	for c in n.get_children():
		var r = _find(c, nm)
		if r != null: return r
	return null
