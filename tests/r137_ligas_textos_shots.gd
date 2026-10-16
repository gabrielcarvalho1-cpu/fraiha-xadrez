extends SceneTree
## R137 · página das Ligas (PC): nome longo e descrição cabem (Challenger, Grande Mestre) e o brasão não cobre o texto.
## Confere tamanhos e salva prints em SHOT_DIR. Uso: xvfb-run godot ... -s tests/r137_ligas_textos_shots.gd
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func run():
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900); root.content_scale_size = root.size
	await process_frame
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(25)
	if stage.account_ui.is_open(): stage.account_ui.close()
	var hub = stage.hub
	hub.show_page("ranking")
	await frames(8)
	for id in ["madeira", "ouro", "grande_mestre", "challenger", "esmeralda"]:
		hub._select_league(id, false)
		await frames(4)
		var t: Label = hub.league_detail_title
		var tf: Font = t.get_theme_font("font")
		var tw := tf.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.get_theme_font_size("font_size")).x
		check(tw <= t.size.x and t.text.ends_with("PL"), "%s: título inteiro (%d de %d px, letra %d)" % [id, tw, t.size.x, t.get_theme_font_size("font_size")])
		var d: Label = hub.league_desc
		check(d.get_line_count() <= 3, "%s: descrição cabe (%d linhas, letra %d)" % [id, d.get_line_count(), d.get_theme_font_size("font_size")])
		check(hub.league_detail_badge.get_global_rect().end.x <= t.get_global_rect().position.x + 1, "%s: brasão não passa do texto" % id)
		var shot := OS.get_environment("SHOT_DIR")
		if shot != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot.path_join("r137_liga_%s.png" % id))
	print("RESULT " + ("OK" if failures == 0 else "%d FALHAS" % failures))
	quit(0 if failures == 0 else 1)
