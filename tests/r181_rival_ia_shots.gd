extends SceneTree
## R181 · RIVAL DE IA NA FILA (cliente): busca com tempo + dica amigável; adversário de IA com o selo "· IA"
## na tela de encontrado e no cartão durante a partida (PC e celular).
## Uso: SHOT_DIR=<pasta> SHOT_TAG=<prefixo> SHOT_SIZE=1920x1080 xvfb-run godot --path . -s tests/r181_rival_ia_shots.gd
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

func state(mid: String, rules, me: Dictionary, opp: Dictionary) -> Dictionary:
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	return {"type": "ranked_state", "match_id": mid, "mode": "ranked_5min", "mode_name": "Rápida", "you": "w", "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": me, "black": opp, "position": {"board": board, "turn": rules.turn, "rights": rules.rights, "ep": [rules.ep.x, rules.ep.y], "halfmove": rules.halfmove, "ply": rules.ply},
		"in_check": false, "last_move": null, "clock": {"w_ms": 300000, "b_ms": 300000, "active": "w"}}

func run():
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	root.content_scale_size = Vector2i.ZERO
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.ranked = {"ranked_5min": {"league": 0, "pl": 40, "wins": 3, "losses": 1, "draws": 0, "matches": 4}}
	var RUI = load("res://ranked/ranked_ui.gd")
	check(RUI.search_hint("RÁPIDA · 5 min", 3) == "RÁPIDA · 5 min", "busca: primeiros segundos mostram só o ritmo")
	check(RUI.search_hint("RÁPIDA · 5 min", 13) == "Procurando adversário da sua liga…", "busca 13 s: texto neutro")
	check(not RUI.search_hint("RÁPIDA · 5 min", 21).contains("IA"), "busca: nada de 'rival de IA' na tela de busca")
	var ui = stage.ranked_ui
	ui.controller.set("mode", "ranked_5min")
	ui.last_mode = "ranked_5min"
	ui._show("searching")
	ui.search_started = Time.get_ticks_msec() - 21500
	await frames(12)
	check(ui.search_time_label.text.begins_with("0:2"), "tempo de fila visível (%s)" % ui.search_time_label.text)
	var mob: bool = load("res://ui_v022/mobile_layout.gd").active(root)
	check(not ui.search_mode_label.text.contains("IA"), "tela de busca sem 'IA': " + ui.search_mode_label.text)
	await shot("busca_21s")
	ui.close_panel()
	# rival de IA encontrado
	var Rules = load("res://chess/rules.gd")
	var rules = Rules.new()
	rules.reset()
	var mid := "00000000-0000-4000-8000-0000000000ab"
	var opp := {"user_id": "", "nickname": "Sir Gambito", "avatar_id": "madeira_reward", "league": 0, "pl": 50, "connected": true, "ai": true}
	var me := {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior", "league": 0, "pl": 40, "connected": true}
	stage._open_ranked()
	await frames(4)
	acc.server_message.emit({"type": "ranked_found", "match_id": mid, "mode": "ranked_5min", "mode_name": "Rápida", "you": "w", "opponent": opp, "vs_ai": true, "ai_wait_ms": 25200})
	await frames(10)
	var ctl = ui.controller
	check(ctl.vs_ai and String(ctl.opponent.nickname) == "Sir Gambito · IA", "encontrado: nome com selo IA (%s)" % ctl.opponent.nickname)
	await shot("encontrado_ia")
	acc.server_message.emit(state(mid, rules, me, opp))
	await frames(14)
	check(String(ctl.player("b").nickname) == "Sir Gambito · IA", "na partida: dado do adversário com selo IA")
	var strip = ui.strips["top"]
	if mob: check(strip.name.text == "Sir Gambito" and strip.ai.visible, "celular: nome + ÍCONE de IA (%s, ícone=%s)" % [strip.name.text, strip.ai.visible])
	else: check(strip.name.text == "Sir Gambito · IA" and not strip.ai.visible, "PC: texto ' · IA' (congelado)")
	check(bool(ui.strip_info("b").get("bot", false)), "cartão de perfil da IA: sem 'adicionar amigo' (bot)")
	await shot("partida_ia")
	if mob and stage.mobile_hud != null and stage.mobile_hud.on and stage.mobile_hud.nav.visible:
		for id in stage.mobile_hud.nav_buttons:
			var b: Button = stage.mobile_hud.nav_buttons[id]
			var cap: Label = b.get_node("Caption")
			var fs := cap.get_theme_font_size("font_size")
			check(b.size.y >= 48.0 and fs >= 16, "celular: %s toque %.0f px (≥48), letra %d px (≥16)" % [cap.text, b.size.y, fs])
	print("R181_RIVAL_IA FAILS=", fails)
	quit(1 if fails else 0)
