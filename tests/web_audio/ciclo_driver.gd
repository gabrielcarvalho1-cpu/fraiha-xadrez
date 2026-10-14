extends SceneTree
## R99 · Driver dos ciclos de memória de áudio no export Web (rodado por tests/web_audio/ciclos_audio.cjs com
## engine.preloadFile + --script; NÃO vai no export). Ciclo: Home → Bot → Home → XEQUE (rajada de efeitos
## simultâneos) → Home → Marcha (rajada + vitória/derrota) → resultado → Home. Variações: sair do modo com som
## tocando (a cada 3 ciclos) e entrar de novo na hora (a cada 4). Depois de cada ciclo publica window.__ciclo e
## espera o Node medir (window.__seguir == ciclo).
var stage
var hub
var total := 20

func _initialize():
	call_deferred("run")

func js(code: String):
	return JavaScriptBridge.eval(code, true)

func wait(s: float):
	await create_timer(s).timeout

func audio():
	return stage.get_node_or_null("GameAudio")

func burst(mode, kinds: Array):
	# vários efeitos quase juntos: 4 players → reproduções simultâneas (inclusive do mesmo som)
	for k in kinds:
		mode._cue(k)
		await wait(0.07)

func pick(d: Dictionary, i: int, n: int) -> Array:
	var keys := d.keys()
	keys.sort()
	var out := []
	for j in n: out.append(keys[(i * n + j) % keys.size()])
	return out

func report(i: int, extra := {}):
	var a = audio()
	var d := {"ciclo": i, "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"godot_texture": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"godot_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"music_override": String(a.music_override) if a != null else "", "mode_ids": a._mode_sample_ids.size() if a != null and a.get("_mode_sample_ids") != null else -1}
	d.merge(extra)
	js("window.__ciclo = %s" % JSON.stringify(d))
	while int(js("window.__seguir || 0")) < i:
		await wait(0.1)

func run():
	total = int(js("window.__total || 20"))
	stage = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(stage)
	current_scene = stage
	await wait(2.0)
	hub = stage.get_node_or_null("MainHub")
	if stage.account_ui != null and stage.account_ui.is_open(): stage.account_ui.hide_ui()
	await report(0)
	for i in range(1, total + 1):
		var extra := {}
		# ---- Bot
		stage._start_bot("easy", "w")
		await wait(0.9)
		stage.open_home()
		await wait(0.8)
		# ---- XEQUE
		hub.open_xeque()
		await wait(0.5)
		var x = hub.xeque
		x.start_game()
		await wait(1.5)
		extra["musica_xeque"] = String(audio().music_override)
		await burst(x, pick(x.SFX, i, 6))
		await wait(0.1 if i % 3 == 0 else 1.2)      # a cada 3: sai com som tocando
		x.close()
		await wait(0.9)
		# ---- Marcha + resultado
		hub.open_marcha()
		await wait(0.5)
		var m = hub.marcha
		m.tut_page = -1
		m.start_game()
		await wait(1.4)
		extra["musica_marcha"] = String(audio().music_override)
		await burst(m, ["promote", "swap", "capture", "arrive", "move", "exit"] if i % 2 else pick(m.SFX, i, 6))
		if m.g != null:
			m.g.winner = 0 if i % 2 else 1           # vitória e derrota alternadas
			m._finish()
		await wait(0.3 if i % 4 == 0 else 5.8)       # a cada 4: sai do resultado com a fanfarra tocando
		if stage.result_overlay != null and stage.result_overlay.visible: stage.result_overlay.hide_result()
		m.close()
		if i % 4 == 0:                               # e entra de novo na hora
			hub.open_marcha()
			await wait(0.4)
			hub.marcha.close()
		await wait(0.9)
		extra["musica_home"] = String(audio().music_override)
		await report(i, extra)
	js("window.__fim = true")
