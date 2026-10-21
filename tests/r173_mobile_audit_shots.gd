extends SceneTree
## R173 · AUDITORIA MOBILE/UX (só leitura: prints + checagem geométrica, sem assert de regra).
## Telas: Home/MAIS/Perfil, Amigos (lista, perfil do amigo, escolher tempo), cartão de convite (recebido, enviado,
## iniciando, recusado), partida Ranked e Casual com a voz (mock) falando, partida contra o bot.
## Uso: SHOT_DIR=<pasta> SHOT_TAG=<prefixo> xvfb-run godot --rendering-driver opengl3 --path . \
##        -s tests/r173_mobile_audit_shots.gd -- --mobile-test --size 390x844 [--only home,friends,invite,ranked,casual,bot]
var stage
var hub
var acc
var only: PackedStringArray = []
var screen := Vector2.ZERO

func _initialize(): call_deferred("run")

func frames(n := 6):
	for i in n: await process_frame

func shot(name: String):
	await frames(12)
	await RenderingServer.frame_post_draw
	var p := OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "_" + name + ".png")
	root.get_texture().get_image().save_png(p)
	audit(name)

func want(k: String) -> bool:
	return only.is_empty() or k in only

## Checagem geométrica dos Controls visíveis: botão fora da tela, texto que não cabe, botões sobrepostos.
func _clip_of(c: Control) -> Rect2:
	var clip := Rect2(Vector2.ZERO, screen)
	var p = c.get_parent()
	while p != null:
		if p is Control and (p as Control).clip_contents and (p as Control).is_visible_in_tree():
			var pc := p as Control
			clip = clip.intersection(pc.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, pc.size))
		p = p.get_parent()
	return clip

func audit(name: String):
	var issues: Array = []
	var buttons: Array = []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c == null or not c.is_visible_in_tree(): continue
		var r: Rect2 = c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)
		if r.size.x < 2 or r.size.y < 2: continue
		var clip := _clip_of(c)
		if clip.size.x <= 0 or clip.size.y <= 0 or not clip.intersects(r): continue   # rolado para fora / escondido
		var on := r.intersection(Rect2(Vector2.ZERO, screen))
		var frac := (on.size.x * on.size.y) / maxf(1.0, r.size.x * r.size.y)
		var scr_clip := clip.size.x >= screen.x - 1 and clip.size.y >= screen.y - 1   # sem rolagem por cima
		if c is BaseButton and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			buttons.append([c, r.intersection(clip)])
			if frac < 0.85 and scr_clip:
				issues.append("BOTAO_FORA %s '%s' %s (%.0f%% visível)" % [c.name, _txt(c), _rs(r), frac * 100.0])
			if minf(r.size.x, r.size.y) < 30.0:
				issues.append("ALVO_PEQUENO %s '%s' %s" % [c.name, _txt(c), _rs(r)])
		elif c is Label and String(c.text).strip_edges() != "":
			var l := c as Label
			if frac < 0.9 and scr_clip:
				issues.append("TEXTO_FORA %s '%s' %s" % [l.name, _txt(l), _rs(r)])
			if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
				var f := l.get_theme_font("font")
				var fs := l.get_theme_font_size("font_size")
				var k: float = r.size.x / maxf(1.0, l.size.x)
				var w := 0.0
				for line in String(l.text).split("\n"):
					w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
				if w * k > r.size.x + 3.0 and (l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING):
					issues.append("TEXTO_CORTADO %s '%s' precisa %.0f, tem %.0f" % [l.name, _txt(l), w * k, r.size.x])
			elif l.max_lines_visible > 0 and l.get_line_count() > l.max_lines_visible:
				issues.append("TEXTO_TRUNCADO %s '%s' linhas %d>%d" % [l.name, _txt(l), l.get_line_count(), l.max_lines_visible])
	for a in range(buttons.size()):
		for b in range(a + 1, buttons.size()):
			var ca: Control = buttons[a][0]
			var cb: Control = buttons[b][0]
			if ca.is_ancestor_of(cb) or cb.is_ancestor_of(ca): continue
			var ra: Rect2 = buttons[a][1]
			var rb: Rect2 = buttons[b][1]
			var inter := ra.intersection(rb)
			var small := minf(ra.size.x * ra.size.y, rb.size.x * rb.size.y)
			if inter.size.x * inter.size.y > 0.2 * small and _layer(ca) == _layer(cb):
				issues.append("SOBREPOSTOS %s '%s' x %s '%s'" % [ca.name, _txt(ca), cb.name, _txt(cb)])
	print("AUDIT %s %s: %d" % [OS.get_environment("SHOT_TAG"), name, issues.size()])
	for s in issues: print("  - ", s)

func _layer(c: Node) -> int:
	var p = c
	while p != null:
		if p is CanvasLayer: return (p as CanvasLayer).layer
		p = p.get_parent()
	return 0

func _txt(c) -> String:
	var t := String(c.get("text")) if c.get("text") != null else ""
	return t.replace("\n", " ").substr(0, 28)

func _rs(r: Rect2) -> String:
	return "[%d,%d %dx%d]" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(390, 844)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	i = args.find("--only")
	if i >= 0: only = args[i + 1].split(",")
	screen = Vector2(size)
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
	acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior", "status": "Bora jogar uma partida hoje à noite?"}
	acc.ranked = {"ranked_3min": {"league": 3, "pl": 47, "highest_league": 3, "wins": 30, "losses": 8, "draws": 2, "matches": 40},
		"ranked_5min": {"league": 0, "pl": 12, "highest_league": 0, "wins": 4, "losses": 2, "draws": 0, "matches": 6}}
	stage._sync_theme_unlocks()
	await frames()
	if want("home"):
		hub.show_page("main")
		await shot("home")
		if hub.get("mobile_ui") != null:
			hub.mobile_ui.show_page("mais")
			await shot("mais")
		hub.show_page("profile")
		await shot("perfil")
		hub.show_page("main")
		await frames()
	if want("friends"): await _friends()
	if want("invite"): await _invite_cards()
	if want("ranked"): await _online("ranked")
	if want("casual"): await _online("casual")
	if want("bot"):
		stage._start_bot("madeira", "w")
		await frames(20)
		await shot("bot")
		stage.open_home()
		await frames(8)
	quit()

func _friends():
	var s = stage.social_ui
	stage.hub.friends_requested.emit()
	await frames()
	s.data = {"friends": [
		{"user_id": "u7", "nickname": "SextoSentroComNomeLongo", "avatar_id": "warrior", "presence": "online"},
		{"user_id": "u8", "nickname": "Isabela_Godoy", "avatar_id": "archer", "presence": "in_match"},
		{"user_id": "u9", "nickname": "DaSilva", "avatar_id": "warrior", "presence": "offline"}],
		"received": [{"user_id": "u10", "nickname": "Cleocides", "avatar_id": "warrior"}], "sent": [], "blocked": []}
	s.has_list = true
	s._show("list")
	await shot("amigos")
	s.profile = {"user_id": "u7", "nickname": "SextoSentroComNomeLongo", "avatar_id": "warrior", "presence": "online", "highest_league": 3, "relation": "friend",
		"status": "Treinando aberturas todo dia, quem topa?", "ranked": {"ranked_3min": {"league": 3, "pl": 47, "wins": 30, "losses": 8, "draws": 2, "matches": 40}}}
	s.profile_id = "u7"
	s._show("profile")
	await shot("amigo_perfil")
	s.open_invite("u7", s.data.friends[0])
	await shot("convidar_tempo")
	s.invite_sending = true
	s._show("invite_pick")
	await shot("convidar_enviando")
	s.close()
	await frames()

func _invite_cards():
	var inv := {"id": "i1", "role": "recipient", "status": "pending", "expires_in_ms": 54000, "game": "chess", "mode_name": "Rápida", "minutes": 5,
		"from": {"user_id": "u7", "nickname": "SextoSentroComNomeLongo", "avatar_id": "warrior"}, "to": {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}}
	acc.server_message.emit({"type": "invite_received", "invite": inv})
	await shot("convite_recebido")
	var inv2 := inv.duplicate(true)
	inv2.status = "starting"
	acc.server_message.emit({"type": "invite_updated", "invite": inv2})
	await shot("convite_iniciando")
	inv2.status = "declined"
	acc.server_message.emit({"type": "invite_updated", "invite": inv2})
	await shot("convite_final")
	await frames(10)
	var inv3 := {"id": "i2", "role": "sender", "status": "pending", "expires_in_ms": 41000, "game": "marcha", "table": "online",
		"to": {"user_id": "u7", "nickname": "SextoSentroComNomeLongo", "avatar_id": "warrior"}, "from": {"user_id": "u1", "nickname": "Gabriel"}}
	acc.server_message.emit({"type": "invite_sent", "invite": inv3})
	await shot("convite_enviado")
	acc.server_message.emit({"type": "invite_snapshot", "invites": []})
	await frames(4)

func _online(kind: String):
	var rules = load("res://chess/rules.gd").new()
	rules.reset()
	var board := []
	for c in rules.board: board.append([c.x, c.y, rules.board[c]])
	var mid := "00000000-0000-4000-8000-0000000000a" + ("1" if kind == "ranked" else "2")
	var opp := {"nickname": "SextoSentroComNomeLongo", "avatar_id": "warrior", "league": 3, "pl": 47, "connected": true}
	var me := {"nickname": "Gabriel", "avatar_id": "warrior", "league": 3, "pl": 40, "connected": true}
	var mode := "ranked_5min" if kind == "ranked" else "casual_5min"
	acc.server_message.emit({"type": kind + "_found", "match_id": mid, "mode": mode, "mode_name": "Rápida", "you": "w", "opponent": opp})
	await frames(4)
	acc.server_message.emit({"type": kind + "_state", "match_id": mid, "mode": mode, "mode_name": "Rápida", "you": "w", "status": "playing", "revision": 1, "starts_in_ms": 0,
		"white": me, "black": opp, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0},
		"in_check": false, "last_move": null, "clock": {"w_ms": 296000, "b_ms": 300000, "active": "w"}})
	await frames(12)
	await shot(kind)
	# voz (provedor mock): eu e o adversário na sala, os dois falando
	var v = stage.voice
	var mock = load("res://voice/mock_voice_provider.gd").new()
	v.use_provider(mock)
	v.ctx = {"kind": kind, "match_id": mid}
	v.state = "CONNECTED"
	v.my_uid = 1
	v.remote = [2]
	v.speaking = [1, 2]
	v.changed.emit()
	await frames(10)
	await shot(kind + "_voz_falando")
	v.speaking = []
	v.state = "MUTED"
	v.changed.emit()
	await shot(kind + "_voz_mudo")
	v.ctx = {}
	v.state = "DISCONNECTED"
	v.remote = []
	v.changed.emit()
	var ctl = stage.ranked_ui.controller if kind == "ranked" else stage.casual_ui.controller
	acc.server_message.emit({"type": kind + "_state", "match_id": mid, "mode": mode, "mode_name": "Rápida", "you": "w", "status": "finished", "revision": 2,
		"result": {"winner": "w", "reason": "resign"}, "white": me, "black": opp, "position": {"board": board, "turn": "w", "rights": "KQkq", "ep": [-1, -1], "halfmove": 0, "ply": 0},
		"in_check": false, "last_move": null, "clock": {"w_ms": 296000, "b_ms": 300000, "active": ""}})
	await frames(40)
	await shot(kind + "_fim")
	stage.open_home()
	await frames(10)
	await shot(kind + "_volta_home")
