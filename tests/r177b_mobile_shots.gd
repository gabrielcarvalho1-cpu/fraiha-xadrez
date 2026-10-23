extends SceneTree
## R177b · prints do celular (ajustes do dono): COMUNIDADE, LIGAS E RANKING, JOGAR ONLINE, RANQUEADO e a
## pré-tela da ANÁLISE. Uso: SHOT_DIR=... SHOT_SIZE=430x860 xvfb-run godot ... -s tests/r177b_mobile_shots.gd -- --mobile-test
var fails := 0
var stage
var hub
func _initialize(): call_deferred("run")
func frames(n := 8):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))

## nenhum botão visível sai da tela
func inside(n: Node, area: Rect2, what: String):
	for b in n.find_children("*", "Button", true, false):
		if not b.is_visible_in_tree(): continue
		var r: Rect2 = b.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, b.size)
		if r.size.x < 2 or r.size.y < 2: continue
		if not area.grow(1.0).encloses(r):
			check(false, "%s: botão %s fora da tela %s" % [what, b.name, r])
			return
	check(true, what + ": botões dentro da tela")

func run():
	var size := Vector2i(430, 860)
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
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_3min": {"league": 0, "pl": 72, "wins": 3, "losses": 1, "draws": 0, "matches": 4}, "ranked_20min": {"league": 0, "pl": 0}}
	hub.show_page("main")
	await frames(10)
	# COMUNIDADE
	hub.open_community()
	await frames(8)
	var nm = hub.notice_modal
	var area := Rect2(Vector2.ZERO, Vector2(size))
	var fr: Rect2 = nm._body_rect
	var alt: Button = nm.alt_button
	var ar: Rect2 = alt.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, alt.size)
	var okb: Button = nm.ok_button
	var orr: Rect2 = okb.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, okb.size)
	check(fr.grow(2).encloses(ar) and fr.grow(2).encloses(orr), "COMUNIDADE: INSTAGRAM e AGORA NÃO dentro da moldura (%s · %s em %s)" % [ar, orr, fr])
	await shot("comunidade")
	nm.close()
	await frames(4)
	# LIGAS E RANKING
	hub.show_page("ranking")
	await frames(12)
	await shot("ligas")
	var sub = root.find_child("ClassicPiecesSubMobile", true, false)
	var chip = root.find_child("BoardColorsChip", true, false)
	if sub != null and chip != null:
		var sr: Rect2 = sub.get_global_rect()
		var font: Font = sub.get_theme_font("font")
		var tw: float = font.get_string_size(sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub.get_theme_font_size("font_size")).x
		check(sr.position.x + tw < chip.get_global_rect().position.x, "LIGAS: 'Cores das casas e das peças' não passa por baixo do ABRIR")
	hub.show_page("main")
	await frames(6)
	# RANQUEADO (lista de ritmos)
	stage._open_ranked()
	await frames(14)
	await shot("ranqueado")
	var nm20 = root.find_child("RankedName_ranked_20min", true, false)
	if nm20 != null:
		var f2: Font = nm20.get_theme_font("font")
		check(f2.get_string_size(nm20.text, HORIZONTAL_ALIGNMENT_LEFT, -1, nm20.get_theme_font_size("font_size")).x <= nm20.size.x, "RANQUEADO: CONVENCIONAL cabe inteiro")
	stage.ranked_ui.close_panel() if stage.ranked_ui.has_method("close_panel") else null
	await frames(6)
	# JOGAR ONLINE (casual)
	stage._open_casual()
	await frames(14)
	await shot("jogar_online")
	var sc = stage.casual_ui.find_child("RankedArtScroll", true, false)
	check(sc != null and sc.is_visible_in_tree(), "JOGAR ONLINE no visual do Ranqueado (celular)")
	if sc != null:
		sc.scroll_vertical = 100000
		await frames(6)
		await shot("jogar_online_fim")
	stage.casual_ui.close_panel() if stage.casual_ui.has_method("close_panel") else null
	await frames(4)
	# ANÁLISE: pré-tela ANALISANDO (sem rodar o motor)
	var rec = preload("res://analysis/match_record.gd").new()
	rec.start("ranked", "w", "Gabriel", "Isabela_Godoy")
	for u in ["e2e4", "e7e5", "g1f3", "b8c6"]: rec.add_move(u)
	rec.finish("win")
	var aui = stage.analysis_ui
	if aui == null:
		stage._ensure_analysis_ui()
		aui = stage.analysis_ui
	if aui != null:
		aui.record = rec
		aui.visible = true
		aui.root.visible = true
		aui._show_page("progress")
		await frames(10)
		await shot("analise_progresso")
		var pp = aui.find_child("ProgressPanel", true, false)
		if pp != null:
			var pr: Rect2 = pp.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, pp.size)
			check(pr.position.x >= -1 and pr.end.x <= area.end.x + 1, "ANÁLISE: painel dentro da largura da tela (%s)" % pr)
	else: print("(sem analysis_ui)")
	print("RESULT ", "OK" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
