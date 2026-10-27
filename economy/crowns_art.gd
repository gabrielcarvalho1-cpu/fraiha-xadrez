extends CanvasLayer
## R198 · painel COROAS no PC com a ARTE do dono (economy/art/coroas_r198/painel.png, preparada por
## tools/art/coroas_r198.py): a placa, os 5 botões, COMO GANHAR e os títulos são da imagem; o jogo escreve por cima
## o saldo, a sequência de dias, a barra, as missões feitas, a nota e os ÚLTIMOS GANHOS (tudo do servidor).
## Tocar fora ou ESC fecha. No celular em pé continua o painel antigo (crowns_ui.gd).
const DIR := "res://economy/art/coroas_r198/"
const ART := Vector2(1942, 809)
const F_BOLD := preload("res://account/fonts/Cinzel-Bold.woff")
const F_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")
const F_TEXT := preload("res://ui_kit/fonts/Alegreya-Medium.woff")
const CREAM := Color("f4ecd8")
const GOLD := Color("f9cf5c")
const BTNS := [Rect2(143, 248, 925, 82), Rect2(143, 340, 925, 78), Rect2(143, 428, 925, 80), Rect2(143, 520, 925, 85), Rect2(143, 612, 925, 83)]

var client
var hub
var _root: Control
var k := 1.0

static func available() -> bool:
	return ResourceLoader.exists(DIR + "painel.png")

func setup(p_hub, p_client):
	hub = p_hub
	client = p_client
	name = "CrownsArt"
	layer = 95
	client.changed.connect(func(): if visible: _rebuild())
	get_viewport().size_changed.connect(func(): if visible: _rebuild())
	hide()

func show_crowns():
	show()
	_rebuild()

func close():
	hide()
	if _root != null: _root.queue_free(); _root = null

func _unhandled_input(e):
	if visible and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func _p(v: Vector2) -> Vector2: return v * k

func _label(text: String, pos: Vector2, px: float, col: Color, font: Font = F_SEMI, w := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.position = _p(pos)
	if w > 0.0:
		l.size.x = w * k
		l.clip_text = true
	l.horizontal_alignment = align
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", maxi(8, int(round(px * k))))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.06, 0.9))
	l.add_theme_constant_override("outline_size", maxi(1, int(round(outline * k))))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(2 * k))))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l

func _rebuild():
	if _root != null: _root.queue_free()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	k = minf((vs.x - 24.0) / ART.x, (vs.y - 24.0) / ART.y) * 0.96
	k = minf(k, 1.0)
	_root = Control.new()
	_root.name = "CrownsArtRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e): if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed: close())
	_root.add_child(dim)
	var holder := Control.new()
	holder.name = "CrownsArtPanel"
	holder.size = ART * k
	holder.position = ((vs - holder.size) / 2.0).round()
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(holder)
	var art := TextureRect.new()
	art.texture = load(DIR + "painel.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size = holder.size
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(art)
	var keep := _root
	_root = holder   # os textos vão no painel (coordenadas da arte × k)
	_fill()
	_root = keep

func _fill():
	var st: Dictionary = client.state
	var logged: bool = client.logged_in()
	var on: bool = logged and client.available()
	var r: Dictionary = st.get("rules", {}) if st.get("rules") is Dictionary else {}
	if not logged:
		_label("ENTRE NA SUA CONTA", Vector2(365, 84), 44, CREAM, F_BOLD, 620)
		_label("PARA GANHAR COROAS JOGANDO", Vector2(365, 140), 21, CREAM, F_SEMI, 620)
		_label("AS COROAS FICAM GUARDADAS NA SUA CONTA, EM QUALQUER APARELHO.", Vector2(365, 203), 15, Color("d9d2c0"), F_SEMI, 630)
	elif not on:
		_label("ABRINDO O SEU COFRE…" if st.is_empty() else "COROAS EM BREVE", Vector2(365, 84), 44, CREAM, F_BOLD, 620)
	else:
		var bal := _label("%s COROAS" % client.fmt(int(st.get("balance", 0))), Vector2(365, 80), 50, CREAM, F_BOLD, 620)
		bal.name = "CrownsBalanceValue"
		var streak := int(st.get("streak", 0))
		var s_txt := ("%d DIA%s SEGUIDO%s" % [streak, "" if streak == 1 else "S", "" if streak == 1 else "S"]) if streak > 0 else "SEM SEQUÊNCIA AINDA"
		var daily := "ENTRADA DO DIA: RECEBIDA" if bool(st.get("daily_claimed", false)) else "ENTRADA DO DIA: VOLTE AMANHÃ"
		_label("%s  ·  %s" % [s_txt, daily], Vector2(365, 140), 21, Color("ece4cf"), F_SEMI, 640).name = "CrownsStreak"
		var pos := streak % 7
		var goal := 3 if pos < 3 else 7
		var left := goal - pos
		var bonus := int(r.get("streak3", 20)) if goal == 3 else int(r.get("streak7", 50))
		# barra: quanto falta para o próximo bônus da sequência
		var frac := float(pos) / float(goal)
		if pos == 0 and streak > 0: frac = 1.0
		var bw := 626.0 * frac
		if bw > 2.0:
			var f1 := ColorRect.new(); f1.color = Color("f3ac22"); f1.position = _p(Vector2(366, 177)); f1.size = _p(Vector2(bw, 18)); f1.mouse_filter = Control.MOUSE_FILTER_IGNORE; _root.add_child(f1)
			var f2 := ColorRect.new(); f2.color = Color("ffd969"); f2.position = _p(Vector2(366, 178)); f2.size = _p(Vector2(bw, 7)); f2.mouse_filter = Control.MOUSE_FILTER_IGNORE; _root.add_child(f2)
		if pos == 0 and streak > 0:
			_label("BÔNUS DE 7 DIAS RECEBIDO! A SEQUÊNCIA CONTINUA.", Vector2(365, 203), 16, GOLD, F_SEMI, 630)
		else:
			var a := _label("FALTAM %d DIA%s PARA" % [left, "" if left == 1 else "S"], Vector2(365, 203), 16, GOLD, F_SEMI)
			var w0: float = F_SEMI.get_string_size(a.text, HORIZONTAL_ALIGNMENT_LEFT, -1, a.get_theme_font_size("font_size")).x / k
			_label(" O BÔNUS DE +%d (%d DIAS SEGUIDOS)" % [bonus, goal], Vector2(365 + w0, 203), 16, Color("ece4cf"), F_SEMI)
		# missões feitas
		var done := 0
		var total := 0
		for m in st.get("missions", []):
			if m is Dictionary:
				total += 1
				if bool(m.get("done", false)): done += 1
		if total > 0: _label("-  %d/%d" % [done, total], Vector2(590, 270), 29, Color("2a1606"), F_SEMI, 0.0, HORIZONTAL_ALIGNMENT_LEFT, 0)
	# nota (as regras do servidor)
	var note := "Valem partidas online contra outra pessoa (Casual e Ranqueada, a partir de %d lances de cada lado) e mesas de XEQUE e MARCHA REAL jogadas até o fim. Até %d Coroas por dia vindas de partidas." % [int(r.get("min_moves", 5)), int(r.get("match_cap", 150))]
	if int(r.get("club_bonus_pct", 25)) > 0: note += " Club FRAIHA: +%d%% nas Coroas de partida." % int(r.get("club_bonus_pct", 25))
	var nl := _label(note, Vector2(1136, 386), 19, Color("dfe6f2"), F_TEXT, 660, HORIZONTAL_ALIGNMENT_LEFT, 2)
	nl.clip_text = false
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size.x = 660.0 * k
	nl.size = Vector2(660.0 * k, 80.0 * k)
	# últimos ganhos
	var items: Array = st.get("recent", []) if st.get("recent") is Array else []
	if not on:
		_label("Entre e jogue online para ganhar Coroas." if not logged else "", Vector2(1210, 560), 21, Color("cfe1f5"), F_TEXT, 560)
	elif items.is_empty():
		_label("Jogue uma partida online para ganhar as primeiras Coroas.", Vector2(1150, 560), 21, Color("cfe1f5"), F_TEXT, 620)
	else:
		var y := 545.0
		for it in items.slice(0, 4):
			var lab := String(it.get("label", ""))
			var ico := "ico_dia.png"
			var low := lab.to_lower()
			if "sequ" in low or "dias seguidos" in low: ico = "ico_fogo.png"
			elif "torneio" in low or "prêmio" in low or "premio" in low: ico = "ico_torneio.png"
			var tr := TextureRect.new()
			tr.texture = load(DIR + ico)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.position = _p(Vector2(1135, y - 2))
			tr.size = _p(Vector2(42, 39))
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_root.add_child(tr)
			_label("%s  -  %s" % [lab, _when(String(it.get("at", "")))], Vector2(1210, y), 22, Color("cfe1f5"), F_TEXT, 470, HORIZONTAL_ALIGNMENT_LEFT, 2)
			var d := int(it.get("delta", 0))
			_label(("+" if d > 0 else "") + client.fmt(d), Vector2(1600, y), 23, GOLD, F_BOLD, 165, HORIZONTAL_ALIGNMENT_RIGHT, 3)
			y += 37.5
	# os 5 botões da arte
	var acts := [func(): client.open_missions(), func(): client.open_store("title"), func(): client.open_pass(), func(): client.open_creator(), func(): client.open_tournament("chess")]
	var names := ["CrownsOpenMissions", "CrownsOpenStore", "CrownsOpenPass", "CrownsOpenCreator", "CrownsOpenTournament"]
	for i in 5:
		var b := Button.new()
		b.name = names[i]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var lit := StyleBoxFlat.new()
		lit.bg_color = Color(1, 0.95, 0.75, 0.10)
		lit.set_corner_radius_all(int(10 * k))
		for s in ["normal", "focus", "disabled"]: b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
		for s in ["hover", "pressed"]: b.add_theme_stylebox_override(s, lit)
		var rr: Rect2 = BTNS[i]
		b.position = _p(rr.position)
		b.size = _p(rr.size)
		var cb: Callable = acts[i]
		b.pressed.connect(func():
			cb.call()   # a tela aberta fecha este painel e guarda o VOLTAR para cá (crowns_client._leave_panel)
			if visible: close())
		_root.add_child(b)

func _when(iso: String) -> String:
	if iso.length() < 16: return ""
	var t := Time.get_unix_time_from_datetime_string(iso.substr(0, 19)) - 3 * 3600   # horário de Brasília
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%02d/%02d %02d:%02d" % [d.day, d.month, d.hour, d.minute]
