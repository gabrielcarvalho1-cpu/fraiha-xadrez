extends SceneTree
## R122 · COMUNIDADE: botão do Discord na Home (PC e celular) — aparece, cabe na tela, não cobre outros
## botões e abre o convite permanente. O link é capturado (sem abrir navegador).
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path . -s tests/r122_comunidade_shots.gd [-- --mobile-test]
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
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func find_named(n: Node, prefix: String) -> Array:
	var out := []
	if n.name.begins_with(prefix) and n is Control and n.is_visible_in_tree(): out.append(n)
	for c in n.get_children(): out.append_array(find_named(c, prefix))
	return out
func buttons(n: Node) -> Array:
	var out := []
	if n is BaseButton and n.is_visible_in_tree() and not String(n.name).begins_with("Community"): out.append(n)
	for c in n.get_children(): out.append_array(buttons(c))
	return out

func run():
	var size := Vector2i(1672, 941)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var CL = load("res://social/community_link.gd")
	var opened := []
	CL.opener = func(u): opened.append(u)
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(14)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	await frames(8)
	var mobile := "--mobile-test" in OS.get_cmdline_user_args()
	var hub = stage.get_node("MainHub")
	# topo: som, (tela cheia), troféu, chat e coroas — todos do mesmo tamanho e com a moldura azul
	var tops := []
	for prefix in ["SoundButton", "FullscreenButton", "TrophyTopButton", "ChatTopButton", "CrownsTopButton"]:
		for n in find_named(root, prefix): tops.append(n)
	var sizes := {}
	for n in tops: sizes[str(Vector2i(n.get_global_rect().size.round()))] = true
	check(tops.size() >= 4 and sizes.size() == 1, "botões do topo do mesmo tamanho %s" % str(sizes.keys()))
	check(tops.all(func(n): return n.framed), "botões do topo com a moldura azul")
	var crown = find_named(root, "CrownsTopButton")
	check(crown.size() == 1 and crown[0].sub_text != "", "coroa quadrada com o saldo embaixo (%s)" % (crown[0].sub_text if crown.size() else "?"))
	await shot("01_home")
	if mobile:
		check(find_named(root, "CommunityButton").is_empty(), "celular: COMUNIDADE fora da Home")
		hub.mobile_ui.show_page("mais")
		await frames(10)
		var rows := find_named(root, "Ref_COMUNIDADE")
		check(rows.size() == 1, "celular: linha COMUNIDADE no MAIS")
		var vis := Rect2(Vector2.ZERO, Vector2(size))
		for name in ["Ref_VOLTAR", "Ref_COMUNIDADE", "Ref_SAIR"]:
			var r := find_named(root, name)
			check(r.size() == 1 and vis.grow(1).encloses(r[0].get_global_rect()), "%s dentro da tela" % name)
		await shot("02_mais")
		if rows.size() == 1: rows[0].pressed.emit()
	else:
		var cs := find_named(root, "CommunityButton")
		check(cs.size() == 1, "PC: um botão COMUNIDADE visível (%d)" % cs.size())
		if cs.is_empty():
			quit(1)
			return
		var b: Button = cs[0]
		var r: Rect2 = b.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(size)).encloses(r), "botão dentro da tela %s" % r)
		var hits := []
		for o in buttons(root):
			var orr: Rect2 = o.get_global_rect()
			if orr.size.x > 0 and orr.size.x < size.x * 0.9 and orr.intersects(r.grow(-2)): hits.append(String(o.name))
		check(hits.is_empty(), "não cobre outros botões %s" % str(hits))
		var font: Font = b.get_theme_font("font")
		check(font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x <= b.size.x - b.icon_box - 16.0, "texto COMUNIDADE cabe")
		check(b.framed, "COMUNIDADE com a moldura azul")
		b.pressed.emit()
	await frames(6)
	check(opened.is_empty(), "R124: não abre direto — pergunta antes")
	var nm = hub.notice_modal
	check(nm != null and nm.is_open() and nm.yes_button.visible and "Discord" in nm.text_label.text, "R124: pergunta se quer ir para o Discord")
	await shot("03_pergunta_discord")
	if nm != null: nm.yes_button.pressed.emit()
	check(opened == [CL.URL], "abre o convite do Discord %s" % str(opened))
	check(String(CL.URL).begins_with("https://discord.gg/"), "link é convite do Discord")
	print("RESULTADO: %s" % ("OK" if fails == 0 else "%d FALHA(S)" % fails))
	quit(fails)
