extends SceneTree
## R176 · fim de partida: a posição final (o mate) fica visível ~2 s antes da animação VITÓRIA/DERROTA e do painel;
## o painel da recompensa que chegar antes espera a pausa; nova partida durante a pausa cancela a tela.
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 3):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func rec(result: String) -> Dictionary:
	return {"human_color": "w", "result": result, "mode": "bot", "result_reason": "MATE", "start_fen": "", "moves": PackedStringArray(["f2f3", "e7e5", "g2g4", "d8h4"])}
func run():
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	stage._start_bot("madeira", "w")
	stage.bot_controller.stop()
	await frames(2)
	stage._on_match_finished(rec("loss"))
	await create_timer(1.0).timeout
	check(not stage.result_overlay.is_showing() and not stage.reward_modal.is_open(), "1 s depois do mate: tabuleiro ainda livre (sem DERROTA nem painel)")
	await create_timer(1.6).timeout
	check(stage.result_overlay.is_showing(), "depois da pausa: animação de DERROTA")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
