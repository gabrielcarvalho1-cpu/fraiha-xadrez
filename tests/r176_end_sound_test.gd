extends SceneTree
## R176 · som de fim (voz "checkmate" + espada) na vitória e na derrota — contra o computador e online
## (VITÓRIA/DERROTA do servidor, mesmo chegando depois do estado "finished"). Empate: som do empate.
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 4):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func run():
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	var audio = stage.get_node_or_null("GameAudio")
	if audio == null:
		for c in stage.get_children(): if c.get_script() != null and String(c.get_script().resource_path).ends_with("game_audio.gd"): audio = c
	check(audio != null and audio.streams.has("fim"), "som de fim carregado")
	var g = stage.game
	for case in [["XEQUE-MATE! BRANCAS VENCEM", true], ["DERROTA — VOCÊ DESISTIU", true], ["VITÓRIA — TEMPO DO BOT ESGOTOU", true],
			["EMPATE — MATERIAL INSUFICIENTE", false], ["VITÓRIA", true], ["DERROTA", true], ["EMPATE", false]]:
		g.game_started = true
		g.game_over = false
		g.status = "SUA VEZ"
		await frames()
		audio.last_cue = ""
		g.game_over = true   # estado "finished" primeiro, resultado depois
		await frames()
		g.status = case[0]
		await frames()
		var want: String = "fim" if case[1] else "empate"
		check(audio.last_cue == want, "%s → %s" % [case[0], want])
		await frames()
		audio.last_cue = ""
		await frames()
		check(audio.last_cue == "", "%s: toca uma vez só" % case[0])
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
