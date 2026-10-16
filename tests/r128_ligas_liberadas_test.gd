extends SceneTree
## R128 · Admin LIBERA TODAS AS LIGAS (aviso do servidor 'leagues_preview'): o jogo libera cenários/tabuleiros/peças
## de todas as ligas na hora, a partida usa o visual escolhido, PL/liga do cartão continuam os reais; ao voltar ao
## normal, quem estava num visual não conquistado volta para a Madeira. Fundador/Club continuam exclusivos.
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/r128_ligas_liberadas_test.gd [-- --mobile-test] [SHOT_DIR=pasta]
var failures := 0
var checks := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func shot(n: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + n + ".png"))
func _initialize(): call_deferred("run")
func run():
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.close()
	var acc = stage.account
	var tm = stage.theme_manager
	var hub = stage.hub
	check(not acc.leagues_preview and not tm.is_unlocked("gold"), "normal: convidado só com a Madeira")
	acc._receive({"type": "leagues_preview", "enabled": true})
	await frames(4)
	check(acc.leagues_preview, "aviso do servidor recebido")
	var all_open := true
	for id in ["iron", "bronze", "silver", "gold", "platina", "esmeralda", "diamante", "mestre", "grande_mestre", "challenger"]:
		if not tm.is_unlocked(id): all_open = false
	check(all_open, "todas as ligas liberadas (Ferro ao Challenger)")
	check(not tm.is_unlocked("fundador") and not tm.is_unlocked("club"), "Fundador e Club continuam exclusivos")
	check(hub.league_unlocked("challenger"), "página das ligas: Challenger disponível")
	hub.show_page("ranking")
	hub._select_league("ouro")
	await frames(3)
	await shot("1_ligas_ouro")
	# R139 · padrão único: a liga não troca o visual; libera a COR de tabuleiro dela (TABULEIRO E PEÇAS)
	check(tm.active_theme == "wood" and not (is_instance_valid(hub.notice_modal) and hub.notice_modal.visible), "escolher Ouro não troca o visual nem pergunta")
	hub.set_board_colors("ouro", "")
	check(hub.board_color_pref == "ouro" and hub.effective_board_color() == "ouro", "Ouro liberado: cor de tabuleiro Ouro disponível")
	stage._start_bot("madeira", "w")
	stage.bot_controller.stop()
	await frames(6)
	check(stage.game.visual_theme == "wood" and stage.game.board_color_material != null, "partida: Madeira com as casas na cor Ouro")
	await shot("2_partida_ouro")
	stage.open_home()
	await frames(4)
	acc._receive({"type": "leagues_preview", "enabled": false})
	await frames(4)
	check(not acc.leagues_preview and not tm.is_unlocked("gold"), "Admin voltou ao normal: Ouro bloqueado de novo")
	check(tm.active_theme == "wood" and hub.effective_board_color() == "madeira", "a cor Ouro volta para a Madeira (escolha guardada)")
	acc._receive({"type": "guest_state", "token": "x", "nickname": "Convidado 1", "leagues_preview": true})
	await frames(3)
	check(acc.leagues_preview and tm.is_unlocked("challenger"), "guest_state também libera (quem entra depois)")
	print("RESULT " + ("%d/%d OK" % [checks, checks] if failures == 0 else "%d FALHAS" % failures))
	quit(0 if failures == 0 else 1)
