extends SceneTree
## R112 · COROAS: saldo no topo da Home (PC e celular), painel COROAS (missões, sequência, limite, como ganhar,
## últimos ganhos) e o aviso "+N COROAS". Sem rede: as respostas do servidor são simuladas (server_message).
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path . -s tests/r112_coroas_shots.gd [-- --mobile-test]
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
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func find_named(n: Node, prefix: String) -> Array:
	var out := []
	if n.name.begins_with(prefix) and n is Control and n.is_visible_in_tree(): out.append(n)
	for c in n.get_children(): out.append_array(find_named(c, prefix))
	return out

func run():
	var size := Vector2i(1672, 941)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.get_node("MainHub")
	var acc = stage.account
	acc.user_id = "u-me"
	acc.access_token = "teste"
	acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	hub.show_page("main")
	await frames(10)
	var chips := find_named(root, "CrownsTopButton")
	check(chips.size() >= 1, "botão de Coroas no topo da Home")
	var st := {"type": "crowns_state", "available": true, "day": "2026-10-15", "balance": 1285, "earned_total": 1400, "streak": 5, "daily_claimed": true,
		"match_today": 63, "match_cap": 150, "resets_in_s": 8 * 3600 + 12 * 60,
		"missions": [
			{"id": "play3", "title": "Jogue 3 partidas online", "target": 3, "reward": 20, "progress": 3, "done": true},
			{"id": "win3", "title": "Vença 3 partidas online", "target": 3, "reward": 40, "progress": 1, "done": false},
			{"id": "xeque1", "title": "Jogue 1 partida de XEQUE", "target": 1, "reward": 20, "progress": 0, "done": false}],
		"recent": [
			{"delta": 20, "reason": "mission", "label": "Missão do dia", "at": "2026-10-15T18:42:00Z"},
			{"delta": 10, "reason": "game", "label": "Partida", "at": "2026-10-15T18:42:00Z"},
			{"delta": 3, "reason": "game", "label": "Partida", "at": "2026-10-15T18:20:00Z"},
			{"delta": 10, "reason": "game", "label": "Partida", "at": "2026-10-15T17:55:00Z"},
			{"delta": 10, "reason": "daily", "label": "Entrada do dia", "at": "2026-10-15T12:01:00Z"},
			{"delta": 50, "reason": "streak", "label": "Sequência de dias", "at": "2026-10-11T12:01:00Z"}],
		"rules": {"win": 10, "play": 3, "match_cap": 150, "club_bonus_pct": 25, "daily": 10, "streak3": 20, "streak7": 50, "min_moves": 5}}
	acc.server_message.emit(st)
	await frames(6)
	check(find_named(root, "CrownsTopButton").any(func(b): return b.text == "1.285"), "saldo 1.285 no botão")
	await shot("01_home")
	hub.crowns_client().open_panel()
	await frames(8)
	check(find_named(root, "CrownsMissions").size() == 1, "painel com as missões do dia")
	check(find_named(root, "Mission_play3").size() == 1, "missão feita aparece")
	await shot("02_painel")
	hub.crowns_client().panel.close()
	await frames(4)
	acc.server_message.emit({"type": "crowns_reward", "gained": 30, "lines": ["Vitória +10", "Missão: Jogue 3 partidas online +20"], "balance": 1315})
	await frames(10)
	check(find_named(root, "CrownsToast").size() == 1, "aviso +30 COROAS")
	await shot("03_aviso")
	# conta sem a 0016 no servidor
	acc.server_message.emit({"type": "crowns_state", "available": false})
	hub.crowns_client().open_panel()
	await frames(8)
	await shot("04_indisponivel")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
