extends SceneTree
## R52f · Celular: CONFIGURAÇÕES e CONHEÇA O FRAIHA montados pelo adaptador do celular (mobile_hub) com o
## contrato atual das páginas do PC (arte de referência). Toques de verdade (InputEventScreenTouch).
## Uso: xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/mobile_pages_test.gd -- --mobile-test --size 390x844
##      [SHOT_DIR=<pasta> SHOT_TAG=<prefixo> para salvar capturas]
var failures := 0
var stage
var hub
var mob

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

func shot(name: String):
	if OS.get_environment("SHOT_DIR").is_empty(): return
	await frames(10)
	await RenderingServer.frame_post_draw
	var p := OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "_" + name)
	root.get_texture().get_image().save_png(p)
	print("SHOT ", p)

func on_screen(c: Control) -> bool:
	return c.is_visible_in_tree() and root.get_visible_rect().grow(1).encloses(c.get_global_rect())

## rola a lista até o controle ficar inteiro na tela (o conteúdo pode passar da altura do celular)
func reveal(c: Control):
	mob.scroll.ensure_control_visible(c)
	await frames(3)

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
	hub = stage.get_node("MainHub")
	mob = hub.mobile_ui
	check(is_instance_valid(mob) and mob.is_visible_in_tree(), "Home do celular ativa (%dx%d)" % [size.x, size.y])

	# ---------------- CONFIGURAÇÕES (Home → Mais → Configurações)
	hub.show_page("settings")
	await frames(6)
	var music: HSlider = mob.find_child("MusicVolumeMobile", true, false)
	var fx: HSlider = mob.find_child("EffectsVolumeMobile", true, false)
	var premove: BaseButton = mob.find_child("PremoveToggleMobile", true, false)
	var premium = mob.find_child("PremiumEntryMobile", true, false)
	var ml: Label = mob.find_child("MusicVolumeLabelMobile", true, false)
	var fl: Label = mob.find_child("EffectsVolumeLabelMobile", true, false)
	check(music != null and fx != null and premove != null and premium != null, "Configurações: controles presentes (música, efeitos, pré-move, Premium)")
	if music == null or fx == null or premove == null:
		print("RESULT FALHAS=%d" % failures)
		quit(1)
		return
	check(ml.text == "MÚSICA  ·  %d%%" % round(hub.music_volume * 100), "Música mostra o valor salvo: " + ml.text)
	await shot("config.png")
	await reveal(music)
	check(on_screen(music), "slider de música alcançável na tela (rolando)")
	await reveal(fx)
	check(on_screen(fx), "slider de efeitos alcançável na tela (rolando)")
	var before_music: float = hub.music_volume
	music.value = 37
	await frames(2)
	check(is_equal_approx(hub.music_volume, 0.37) and ml.text == "MÚSICA  ·  37%", "slider de música muda o volume de verdade (%s)" % ml.text)
	fx.value = 64
	await frames(2)
	check(is_equal_approx(hub.volume, 0.64) and fl.text == "EFEITOS SONOROS  ·  64%", "slider de efeitos muda o volume de verdade (%s)" % fl.text)
	var cfg := ConfigFile.new()
	var saved := cfg.load(hub.PREFS) == OK
	check(saved and _prefs_has(cfg, 0.37), "volume salvo nas preferências (user://home_preferences.cfg)")
	await reveal(premove)
	var pm_before: bool = hub.premove_enabled
	await tap(premove)
	check(hub.premove_enabled != pm_before, "toque no PRÉ-MOVE alterna (agora %s)" % ("ligado" if hub.premove_enabled else "desligado"))
	var lab: Label = premove.get_child(0).get_child(0).get_child(0)
	check(lab.text == "PRÉ-MOVE: " + ("LIGADO" if hub.premove_enabled else "DESLIGADO"), "rótulo do pré-move acompanha: " + lab.text)
	await tap(premove)
	check(hub.premove_enabled == pm_before, "segundo toque volta ao estado anterior")
	music.value = round(before_music * 100)
	await frames(2)
	await shot("config_rolada.png")
	await tap(mob.back_button)
	await frames(4)
	check(hub.page == "main", "VOLTAR sai das Configurações")

	# ---------------- CONHEÇA O FRAIHA
	# R53 · painel da referência do celular (mobile_ref_page.gd): os 6 tópicos empilhados no cartão (título +
	# texto de cada um, rolando com o dedo), VOLTAR desenhado na arte.
	hub.show_page("about")
	await frames(6)
	var rp = mob.ref_page
	check(rp != null and rp.visible and rp.page_id == "about", "Conheça o FRAIHA abre o painel da referência")
	var expected := ["O PROJETO", "COMO JOGAR", "SISTEMA DE LIGAS", "MODOS DE JOGO", "PERSONALIZAÇÃO", "COMUNIDADE E SUPORTE"]
	await shot("conheca.png")
	for k in expected.size():
		var title: Label = mob.find_child("AboutTitleMobile%d" % k, true, false)
		var body: RichTextLabel = mob.find_child("AboutTextMobile%d" % k, true, false)
		check(title != null and title.text == expected[k], "tópico %d: título %s" % [k, expected[k]])
		check(body != null and body.get_parsed_text().length() > 40, "tópico %s com o texto do PC" % expected[k])
		if body != null:
			rp.scroll.ensure_control_visible(body)
			await frames(3)
			check(on_screen(body) or body.size.y > root.get_visible_rect().size.y * 0.8, "texto de %s alcançável rolando" % expected[k])
	check(not mob.heading.is_visible_in_tree() and not mob.scroll.is_visible_in_tree(), "página antiga do celular não aparece por trás")
	await shot("conheca_ultimo.png")
	rp.scroll.scroll_vertical = 0
	await frames(3)
	var back: Button = rp.find_child("Ref_VOLTAR", true, false)
	check(back != null and on_screen(back), "VOLTAR da arte visível")
	if back != null: await tap(back)
	await frames(4)
	check(hub.page == "main" and not rp.visible, "VOLTAR sai do Conheça o FRAIHA")
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)

func _prefs_has(cfg: ConfigFile, v: float) -> bool:
	for sec in cfg.get_sections():
		for k in cfg.get_section_keys(sec):
			var x = cfg.get_value(sec, k)
			if String(k).contains("music") and (x is float or x is int) and absf(float(x) - v) < 0.011: return true
	return false
