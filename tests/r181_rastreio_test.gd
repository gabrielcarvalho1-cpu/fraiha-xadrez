extends SceneTree
## R181 · rastreamento (cliente): nomes de tela claros (Entrada / Login, Home, Vitória…), cliques com nome do botão,
## e TODO nome de tela que o jogo pode mandar está na lista que o servidor aceita (online_v021/admin/ui_names.json).
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 8):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1

func run():
	var Tracker = load("res://telemetry/screen_tracker.gd")
	var names := {}
	var f := FileAccess.open("res://online_v021/admin/ui_names.json", FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	for n in data.names: names[String(n)] = true
	var missing := []
	for dict in [Tracker.LABELS, Tracker.MODES, Tracker.PAGES, Tracker.ACCOUNT_PAGES, Tracker.RESULT_NAMES]:
		for k in dict:
			var label := String(dict[k]).to_upper()
			if not names.has(label): missing.append(label)
	check(missing.is_empty(), "todas as telas do rastreador estão na lista do servidor %s" % [missing])
	var b := Button.new()
	b.text = "Jogar como\nconvidado"
	check(Tracker.button_label(b) == "Jogar como convidado", "nome do botão: texto (quebra de linha vira espaço)")
	var b2 := Button.new()
	b2.tooltip_text = "Configurações"
	check(Tracker.button_label(b2) == "Configurações", "botão sem texto: usa a dica")
	var e: Node = LineEdit.new()
	check(not (e is BaseButton), "campo de texto não é botão (nada digitado é rastreado)")
	b.free(); b2.free(); e.free()
	DisplayServer.window_set_size(Vector2i(390, 844))
	root.size = Vector2i(390, 844)
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	var tr = stage.get("screen_tracker")
	if tr == null:
		for c in stage.get_children():
			if c.get_script() == Tracker: tr = c
	check(tr != null, "rastreador ativo no jogo")
	stage.account_ui.open("login")
	await frames(6)
	check(tr.compute() == "Entrada / Login", "tela de entrar = 'Entrada / Login' (%s)" % tr.compute())
	var guest = stage.account_ui.find_child("GuestButton", true, false)
	check(guest != null and guest.has_meta("fx_track"), "botão JOGAR COMO CONVIDADO é rastreado")
	stage.account_ui.close()
	await frames(6)
	check(tr.compute().begins_with("Home"), "Home = '%s'" % tr.compute())
	stage.result_overlay.show_result("victory")
	await frames(6)
	check(tr.compute().contains("Vitória"), "resultado: 'Vitória' (%s)" % tr.compute())
	print("R181_RASTREIO FAILS=", fails)
	quit(1 if fails else 0)
