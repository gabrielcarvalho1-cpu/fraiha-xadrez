extends SceneTree
## R124 · EMPATE: partida contra o bot que termina empatada (afogamento) abre a tela de EMPATE e, no PC, o painel
## de resultado (enfrentar de novo / analisar / início). Também o painel de EMPATE do Casual/Ranked (online).
## Uso: SHOT_DIR=<pasta> xvfb-run godot --rendering-driver opengl3 --path . -s tests/r124_empate_shots.gd [-- --mobile-test]
var fails := 0
var stage
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func frames(n := 6):
	for i in n: await process_frame
func wait(sec: float):
	var end = Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < end: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func _initialize(): call_deferred("run")

func run():
	var mobile := "--mobile-test" in OS.get_cmdline_user_args()
	root.size = Vector2i(375, 812) if mobile else Vector2i(1672, 941)
	root.content_scale_size = root.size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var ov = stage.result_overlay
	stage._start_bot("wood", "w")
	stage.bot_controller.stop()
	await frames(4)
	var rec = stage.recorder.current()
	stage.game.game_over = true
	stage.game.status = "EMPATE — AFOGAMENTO"
	stage.game.queue_redraw()
	await frames(4)
	check(rec.finished and rec.result == "draw", "registro: empate")
	check(ov.visible and ov.is_showing() and ov.result == "draw", "tela de EMPATE aparece")
	await wait(1.6)
	await shot("01_tela_empate")
	ov.hide_result()
	await wait(0.8)
	await frames(6)
	var rm = stage.reward_modal
	if not mobile:
		check(rm != null and rm.root != null and rm.root.is_visible_in_tree(), "PC: painel de EMPATE contra o bot abre depois da animação")
		var sub = rm.root.find_child("DeskBotSub", true, false) if rm.root != null else null
		check(sub != null and "NINGUÉM VENCEU" in sub.text, "texto: ninguém venceu")
		var info = rm.root.find_child("DeskBotInfo", true, false) if rm.root != null else null
		check(info != null and "afogamento" in info.text, "motivo: empate por afogamento (%s)" % (info.text if info else "?"))
		await shot("02_painel_bot_empate")
		rm.close()
	# online (Casual): painel de resultado com EMPATE
	var rui = stage.ranked_ui
	if rui != null and not mobile:
		rui.controller.last_result = {"outcome": "draw", "mode": "casual_10min", "mode_name": "Normal", "reason_text": "Empate por acordo"}
		rui.kind = "casual"
		var ok = rui._desk_art("result")
		await frames(8)
		check(bool(ok), "Casual: painel de EMPATE aberto")
		await shot("03_painel_online_empate")
	print("RESULTADO: %s" % ("OK" if fails == 0 else "%d FALHA(S)" % fails))
	quit(fails)
