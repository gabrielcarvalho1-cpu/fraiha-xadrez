extends SceneTree
## R98 · EMPATE (botão, oferta recebida, oferta enviada) e REVANCHE nas telas de resultado, Casual e Ranqueada.
## Mensagens simuladas iguais às do servidor. Uso:
## SHOT_DIR=<pasta> SHOT_TAG=<p> SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path . -s tests/draw_rematch_shots.gd [-- --mobile-test]
var stage
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
	await frames(14)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))

func run():
	var size := Vector2i(1672, 941)
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
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	var opp := {"nickname": "SextoSen1", "avatar_id": "warrior", "connected": true}
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "connected": true}
	var cui = stage.casual_ui
	var ctl = cui.controller
	stage._open_casual()
	await frames(6)
	acc.server_message.emit({"type": "casual_found", "match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "opponent": opp})
	var st := {"type": "casual_state", "match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": me, "black": opp, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 4},
		"in_check": false, "last_move": null, "clock": {"w_ms": 287000, "b_ms": 291000, "active": "w"}, "draw_offer": "", "draw_min_ply": 2}
	acc.server_message.emit(st)
	await frames(12)
	check(ctl.can_offer_draw(), "partida rolando: pode oferecer empate")
	await shot("1_partida_botao_empate")
	st.revision = 2; st.draw_offer = "b"
	acc.server_message.emit(st)
	await frames(6)
	check(cui.draw_ui.banner.visible, "oferta do adversário: faixa ACEITAR / RECUSAR")
	await shot("2_oferta_recebida")
	st.revision = 3; st.draw_offer = "w"
	acc.server_message.emit(st)
	await frames(6)
	check(not cui.draw_ui.banner.visible and not ctl.can_offer_draw(), "minha oferta: sem faixa, botão travado")
	await shot("3_oferta_enviada")
	if stage.mobile_hud != null and stage.mobile_hud.has_method("toggle_actions") and preload("res://ui_v022/mobile_layout.gd").active(root):
		stage.mobile_hud.toggle_actions()
		await shot("3b_acoes_celular")
		stage.mobile_hud.toggle_actions()
	# fim: vitória (arte do PC) + revanche
	st.revision = 4; st.status = "finished"; st.draw_offer = ""
	acc.server_message.emit(st)
	acc.server_message.emit({"type": "casual_result", "match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "you": "w", "outcome": "win", "reason": "checkmate", "reason_text": "Xeque-mate", "rated": false, "pl_change": 0})
	await frames(8)
	if stage.result_overlay != null: stage.result_overlay.hide_result()
	check(is_instance_valid(cui.rematch_btn), "resultado tem o botão de REVANCHE")
	await shot("4_vitoria_revanche")
	acc.server_message.emit({"type": "casual_rematch_status", "match_id": "c1", "mine": false, "theirs": true})
	await frames(4)
	check(cui.rematch_label.text.contains("quer revanche"), "pedido do adversário aparece")
	await shot("5_adversario_quer_revanche")
	ctl.last_result = {"match_id": "c1", "mode": "casual_5min", "mode_name": "Rápida", "outcome": "draw", "reason": "agreement", "reason_text": "Empate por acordo"}
	ctl.rematch = {"mine": true, "theirs": false, "closed": false, "message": "", "match_id": "c1"}
	cui._show("result")
	await frames(6)
	check(cui.rematch_label.text.contains("Aguardando"), "empate: pedi revanche, aguardando")
	await shot("6_empate_aguardando")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
