extends SceneTree
## R139 · TABULEIRO E PEÇAS: padrão Madeira em todas as partidas; só as cores mudam (casas pelo shader, peças
## coloridas). Confere aplicação, bloqueios (liga / Fundador / Club) e que as Ligas não trocam mais o visual.
## Uso: xvfb-run godot ... -s tests/r139_cores_test.gd [-- --mobile-test]  (SHOT_DIR/SHOT_TAG/SHOT_SIZE opcionais)
const BoardColors := preload("res://cosmetics/board_colors.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func shot(name: String):
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var sz := OS.get_environment("SHOT_SIZE")
	if sz != "":
		var p := sz.split("x")
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(int(p[0]), int(p[1])); root.content_scale_size = root.size
		await process_frame
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(25)
	if stage.account_ui.is_open(): stage.account_ui.close()
	var hub = stage.hub
	var g = stage.game
	# ligas liberadas (admin): escolher uma liga NÃO troca o visual
	stage.account._receive({"type": "leagues_preview", "enabled": true})
	await frames(3)
	hub.show_page("ranking")
	hub._select_league("ouro")
	await frames(3)
	check(stage.theme_manager.active_theme == "wood" and not (is_instance_valid(hub.notice_modal) and hub.notice_modal.visible), "Ligas: escolher Ouro não troca o visual nem pergunta")
	hub.show_page("main")
	stage._start_bot("madeira", "w")
	stage.bot_controller.stop()
	await frames(12)
	check(g.visual_theme == "wood" and g.board_color_material == null, "padrão: Madeira com a arte de sempre")
	check(g.piece_override.has("wK") and g.piece_override.wK[0] == preload("res://ranked/board_skin.gd").PECAS.wK[0], "padrão: peças da Madeira")
	await shot("madeira")
	hub.set_board_colors("verde", "branco_preto")
	await frames(6)
	check(g.board_color_material != null and Color(g.board_color_material.get_shader_parameter("dark_color")).is_equal_approx(Color("#769656")), "Verde: casas com a cor (shader)")
	check(g.piece_override.wK[0].resource_path.contains("cores_pecas/branco_preto"), "Branco e preto: peças coloridas")
	await shot("verde_branco_preto")
	hub.set_board_colors("ouro", "")
	await frames(6)
	check(hub.board_color_pref == "ouro" and Color(g.board_color_material.get_shader_parameter("dark_color")).is_equal_approx(Color("#b08a2e")), "Ouro (liga liberada): casas douradas")
	await shot("ouro")
	hub.set_board_colors("", "classicas")
	await frames(6)
	check(g.piece_override.is_empty(), "Peças clássicas: conjunto original do jogo")
	await shot("ouro_classicas")
	# bloqueios
	stage.account._receive({"type": "leagues_preview", "enabled": false})
	await frames(3)
	check(hub.effective_board_color() == "madeira" or hub.league_unlocked("ouro"), "liga não conquistada: cai para a Madeira sem apagar a escolha")
	var before: String = hub.board_color_pref
	hub.set_board_colors("fundador", "club")
	check(hub.board_color_pref == before and hub.piece_color_pref == "classicas", "Fundador/Club bloqueados: escolha recusada")
	check(not BoardColors.lock_reason("founder", hub).is_empty() and not BoardColors.lock_reason("club", hub).is_empty(), "motivo do bloqueio Fundador/Club")
	hub.set_board_colors("madeira", "original")
	await frames(6)
	check(g.board_color_material == null, "volta ao padrão")
	stage.open_home()
	await frames(4)
	# janela TABULEIRO E PEÇAS: abre, escolhe pela amostra, bloqueado só avisa
	stage.account._receive({"type": "leagues_preview", "enabled": true})
	hub.open_board_colors()
	await frames(6)
	var ui = hub.board_colors_ui
	check(ui != null and ui.visible and ui.find_child("Casas_verde", true, false) != null and ui.find_child("Pecas_classicas", true, false) != null, "janela TABULEIRO E PEÇAS abre com casas e peças")
	ui.find_child("Casas_azul", true, false).pressed.emit()
	await frames(3)
	check(hub.board_color_pref == "azul" and ui.find_child("Casas_azul", true, false) != null, "amostra Azul escolhe e a janela se atualiza")
	ui.find_child("Pecas_creme_marrom", true, false).pressed.emit()
	await frames(3)
	check(hub.piece_color_pref == "creme_marrom", "amostra Creme e marrom escolhe as peças")
	ui.find_child("Casas_fundador", true, false).pressed.emit()
	await frames(3)
	check(hub.board_color_pref == "azul" and ui.status.text.contains("Fundador"), "Fundador bloqueado: só avisa o motivo")
	ui.close()
	hub.set_board_colors("madeira", "original")
	print("RESULT " + ("%d/%d OK" % [checks, checks] if failures == 0 else "%d FALHAS" % failures))
	quit(0 if failures == 0 else 1)
