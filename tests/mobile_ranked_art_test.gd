extends SceneTree
## R53 · JOGAR RANQUEADO no celular no visual da referência (ranked/mobile_ranked_art.gd): dados reais da conta
## (liga, PL, barra, V/D/E), BUSCAR PARTIDA e VOLTAR repassando para os botões reais, ritmos fechados pelo Admin
## somem sem buraco, giro do celular e nada recriado por quadro. Toques de verdade (InputEventScreenTouch).
## Uso: xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/mobile_ranked_art_test.gd -- --mobile-test --size 390x844
var failures := 0
var stage
var ui
var art

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func frames(n := 3):
	for i in n: await process_frame

func tap(c: Control):
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = p
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)

func on_screen(c: Control) -> bool:
	return c.is_visible_in_tree() and root.get_visible_rect().grow(1).encloses(c.get_global_rect())

func reveal_tap(name: String) -> bool:
	var b: Control = art.find_child(name, true, false)
	if b == null: return false
	art.scroll.ensure_control_visible(b)
	await frames(3)
	if not on_screen(b): return false
	await tap(b)
	await frames(3)
	return true

func count_nodes(n: Node) -> int:
	var c := 1
	for k in n.get_children(): c += count_nodes(k)
	return c

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(390, 844)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	# conta (estado que o acct_state preencheria, sem rede)
	var acc = stage.account
	acc.user_id = "u1"
	acc.access_token = "teste"
	acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_3min": {"league": 1, "pl": 0, "wins": 30, "losses": 8, "draws": 0, "matches": 38},
		"ranked_5min": {"league": 0, "pl": 12, "wins": 4, "losses": 2, "draws": 0, "matches": 6}}
	stage._open_ranked()
	await frames(8)
	ui = stage.ranked_ui
	art = ui.mobile_art
	var tag := "%dx%d" % [size.x, size.y]
	check(art != null and art.visible, "Ranqueado no celular abre o painel da referência (%s)" % tag)
	check(not ui.panel.visible and not ui.art_frame.visible, "lista/moldura antiga não aparece por trás")
	check(art.panel.size.x <= minf(size.x, 460.0) + 0.5, "painel cabe na largura")
	for m in ui.MODES:
		check(art.find_child("RankedCard_" + String(m[0]), true, false) != null, "cartão %s" % m[1])
	var l3: Label = art.find_child("RankedLeague_ranked_3min", true, false)
	var s3: Label = art.find_child("RankedStats_ranked_3min", true, false)
	var l5: Label = art.find_child("RankedLeague_ranked_5min", true, false)
	var b5: ColorRect = art.find_child("RankedBar_ranked_5min", true, false)
	var b3: ColorRect = art.find_child("RankedBar_ranked_3min", true, false)
	check(l3 != null and l3.text == "FERRO — 0/100 PL", "Relâmpago: liga e PL reais (%s)" % (l3.text if l3 else "-"))
	check(s3 != null and s3.text == "30V · 8D · 0E · 38 partidas · 79%", "Relâmpago: estatísticas reais (%s)" % (s3.text if s3 else "-"))
	check(l5 != null and l5.text == "MADEIRA — 12/100 PL", "Rápida: liga e PL reais")
	check(b5 != null and b3 != null and b5.size.x > 0.0 and is_zero_approx(b3.size.x) and absf(b5.size.x - 584.0 * 0.12 * art.s) < 1.0, "barra de PL acompanha o PL (12%)")
	# BUSCAR PARTIDA: o toque vai para o botão real Queue_<ritmo> (sem rede: só conta)
	var pressed := {}
	for m in ui.MODES:
		var id := String(m[0])
		var real: Button = ui.box.find_child("Queue_" + id, true, false)
		for c in real.pressed.get_connections(): real.pressed.disconnect(c.callable)
		real.pressed.connect(func(): pressed[id] = int(pressed.get(id, 0)) + 1)
	check(await reveal_tap("Ref_BUSCAR_ranked_5min") and int(pressed.get("ranked_5min", 0)) == 1 and pressed.size() == 1, "BUSCAR PARTIDA da Rápida aciona a fila da Rápida")
	check(await reveal_tap("Ref_BUSCAR_ranked_20min") and int(pressed.get("ranked_20min", 0)) == 1, "BUSCAR PARTIDA do Convencional alcançável rolando")
	var n0 := count_nodes(art)
	await frames(30)
	check(count_nodes(art) == n0, "sem nós novos por quadro")
	# Admin fecha ritmos: só os abertos aparecem, sem buraco
	acc.ranked_modes_known = true
	acc.ranked_modes = ["ranked_3min", "ranked_10min"]
	acc.changed.emit()
	await frames(4)
	check(art.visible and art.find_child("RankedCard_ranked_5min", true, false) == null and art.find_child("RankedCard_ranked_10min", true, false) != null, "ritmo fechado some; os abertos ficam")
	var c3: Control = art.find_child("RankedCard_ranked_3min", true, false)
	var c10: Control = art.find_child("RankedCard_ranked_10min", true, false)
	check(c3 != null and c10 != null and absf(c10.position.y - c3.position.y - 414.0 * art.s) < 1.0, "cartões seguidos (sem buraco)")
	acc.ranked_modes = []
	acc.changed.emit()
	await frames(4)
	var any_text := false
	for l in art.find_children("*", "Label", true, false):
		if l.text == ui.unavailable_title(): any_text = true
	check(any_text, "todos fechados: aviso de indisponível")
	acc.ranked_modes_known = false
	acc.changed.emit()
	await frames(4)
	# aviso de problema da fila aparece no celular
	ui._on_problem("Fila temporariamente indisponível.")
	await frames(2)
	check(art.notice_label != null and art.notice_label.visible and art.notice_label.text == "Fila temporariamente indisponível." and on_screen(art.notice_label), "aviso da fila visível no celular")
	# giro
	var turned := Vector2i(size.y, size.x)
	root.size = turned
	root.content_scale_size = turned
	await frames(8)
	check(art.visible and art.panel.size.x <= minf(turned.x, 460.0) + 0.5 and absf(art.panel.get_global_rect().get_center().x - turned.x / 2.0) < 2.0, "girou: painel refeito e centralizado")
	root.size = size
	root.content_scale_size = size
	await frames(8)
	# VOLTAR
	art.scroll.scroll_vertical = int(art.scroll.get_v_scroll_bar().max_value)
	await frames(3)
	check(await reveal_tap("Ref_VOLTAR") and stage.mode == "home" and not art.visible and not ui.panel_open(), "VOLTAR volta à Home")
	# Casual (JOGAR ONLINE) continua na lista de antes no celular
	stage._open_casual()
	await frames(6)
	check(not stage.casual_ui.mobile_art.visible and stage.casual_ui.panel.visible, "JOGAR ONLINE (casual) segue a lista do celular")
	stage.casual_ui.close_panel()
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
