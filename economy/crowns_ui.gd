extends "res://ui_v022/home_modal.gd"
## R112 · painel COROAS (botão de saldo no topo da Home): saldo, sequência de dias, entrada do dia,
## 3 MISSÕES DO DIA com progresso, Coroas de partidas hoje (limite), COMO GANHAR e ÚLTIMOS GANHOS.
## Tudo vem do servidor (crowns_state); a Loja de Coroas ainda não existe e aparece como EM BREVE.
const Art := preload("res://monetization/premium_art.gd")

var client
var content: VBoxContainer
var scroll: ScrollContainer

func setup(p_hub, acc, p_client):
	build(p_hub, "COROAS")
	account = acc
	client = p_client
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	client.changed.connect(func(): if visible: _rebuild())

func show_crowns():
	open()
	_rebuild()

func _layout():
	super._layout()
	if visible and content != null: _rebuild.call_deferred()

func _pc() -> bool:
	return not portrait()

func _rebuild():
	if scroll == null: return
	if content != null: content.queue_free()
	content = VBoxContainer.new()
	content.name = "CrownsContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	var st: Dictionary = client.state
	var logged: bool = client.logged_in()
	if _pc():
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 26)
		content.add_child(cols)
		var left := _col(cols, 1.15)
		var right := _col(cols, 1.0)
		_balance(left, st, logged)
		if logged and client.available(): _missions(left, st)
		_how(right, st)
		if logged and client.available(): _recent(right, st)
		_soon(left)
	else:
		_balance(content, st, logged)
		if logged and client.available(): _missions(content, st)
		_how(content, st)
		if logged and client.available(): _recent(content, st)
		_soon(content)

func _col(parent: Control, ratio: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = ratio
	v.add_theme_constant_override("separation", 10)
	parent.add_child(v)
	return v

func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _section(parent: Control, t: String, extra := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := label(t, 17, GOLD)
	row.add_child(l)
	if not extra.is_empty():
		# o texto da direita encolhe/corta antes de alargar o painel (celular estreito)
		var e := label(extra, 11 if narrow() else 13, DIM, true)
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.clip_text = true
		row.add_child(e)
	var line := ColorRect.new()
	line.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	parent.add_child(line)
	return row

func _panel(parent: Control, accent := false) -> VBoxContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.06, 0.14, 0.88) if not accent else Color(0.05, 0.10, 0.24, 0.92)
	s.border_color = Color("c99a45") if not accent else GOLD
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	for side in ["left", "right"]: s.set("content_margin_" + side, 14)
	for side in ["top", "bottom"]: s.set("content_margin_" + side, 10)
	p.add_theme_stylebox_override("panel", s)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v

func _bar(parent: Control, value: float, max_v: float, h := 10.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = maxf(1.0, max_v)
	b.value = clampf(value, 0.0, b.max_value)
	b.custom_minimum_size = Vector2(0, ts(int(h)))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.border_color = Color("6b5428")
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e2b24f")
	fill.set_corner_radius_all(4)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	parent.add_child(b)
	return b

func _balance(parent: Control, st: Dictionary, logged: bool):
	var v := _panel(parent, true)
	v.name = "CrownsBalance"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var g := TextureRect.new()   # a coroa dourada da arte do jogo
	g.texture = preload("res://ui_kit/mobile/bots_crown.png")
	g.custom_minimum_size = Vector2(ts(52), ts(47))
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(g)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	if not logged:
		col.add_child(_wrap(label("Entre na sua conta para ganhar Coroas jogando.", 17, CREAM)))
		col.add_child(_wrap(label("As Coroas ficam guardadas na sua conta, em qualquer aparelho.", 13, DIM, true)))
		return
	if not client.available():
		col.add_child(_wrap(label("Abrindo o seu cofre…" if st.is_empty() else "As Coroas ainda não estão ligadas neste servidor. Volte em breve!", 16, CREAM)))
		return
	var bal := label("%s COROAS" % client.fmt(int(st.get("balance", 0))), 22 if narrow() else 30, GOLD)
	bal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bal.name = "CrownsBalanceValue"
	bal.add_theme_constant_override("outline_size", 6)
	bal.add_theme_color_override("font_outline_color", Color(0.16, 0.08, 0.0))
	col.add_child(bal)
	var streak := int(st.get("streak", 0))
	var daily := "Entrada do dia: recebida ✓" if bool(st.get("daily_claimed", false)) else "Entrada do dia: entre amanhã de novo"
	var s_txt := ("%d dia%s seguido%s" % [streak, "" if streak == 1 else "s", "" if streak == 1 else "s"]) if streak > 0 else "Sem sequência ainda"
	var l := _wrap(label("%s  ·  %s" % [s_txt, daily], 14, CREAM, true))
	l.name = "CrownsStreak"
	col.add_child(l)
	# próximos prêmios da sequência (3º e 7º dia)
	var r: Dictionary = st.get("rules", {}) if st.get("rules") is Dictionary else {}
	var pos := streak % 7
	var next_txt := ""
	if pos < 3: next_txt = "Faltam %d dia%s para o bônus de +%d (3 dias seguidos)" % [3 - pos, "" if 3 - pos == 1 else "s", int(r.get("streak3", 20))]
	else: next_txt = "Faltam %d dia%s para o bônus de +%d (7 dias seguidos)" % [7 - pos, "" if 7 - pos == 1 else "s", int(r.get("streak7", 50))]
	if pos == 0 and streak > 0: next_txt = "Bônus de 7 dias recebido! A sequência continua."
	col.add_child(_wrap(label(next_txt, 12, DIM, true)))

func _missions(parent: Control, st: Dictionary):
	var secs := int(st.get("resets_in_s", 0))
	_section(parent, "MISSÕES DO DIA", "trocam em %dh%02d" % [secs / 3600, (secs % 3600) / 60] if secs > 0 else "")
	var list := VBoxContainer.new()
	list.name = "CrownsMissions"
	list.add_theme_constant_override("separation", 8)
	parent.add_child(list)
	for m in st.get("missions", []):
		if not (m is Dictionary): continue
		var v := _panel(list, bool(m.get("done", false)))
		v.name = "Mission_" + String(m.get("id", ""))
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		v.add_child(top)
		var t := _wrap(label(String(m.get("title", "")), 15, CREAM, true))
		top.add_child(t)
		if bool(m.get("done", false)):
			var s := Art.Stamp.new("FEITA", "ok", ts(11))
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			top.add_child(s)
		var rw := label("+%d" % int(m.get("reward", 0)), 16, GOLD)
		rw.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top.add_child(rw)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var bar := _bar(row, float(m.get("progress", 0)), float(m.get("target", 1)))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label("%d / %d" % [int(m.get("progress", 0)), int(m.get("target", 1))], 13, DIM, true))
	# Coroas de partidas hoje (limite do dia)
	var cap := int(st.get("match_cap", 150))
	var today := int(st.get("match_today", 0))
	var v2 := _panel(parent)
	v2.name = "CrownsMatchCap"
	var top2 := HBoxContainer.new()
	v2.add_child(top2)
	top2.add_child(_wrap(label("Coroas de partidas hoje", 14, CREAM, true)))
	top2.add_child(label("%d / %d" % [today, cap], 14, GOLD))
	_bar(v2, float(today), float(cap), 8.0)

func _how(parent: Control, st: Dictionary):
	_section(parent, "COMO GANHAR")
	var r: Dictionary = st.get("rules", {}) if st.get("rules") is Dictionary else {}
	var lines := [
		["Vitória online", "+%d" % int(r.get("win", 10))],
		["Derrota ou empate online", "+%d" % int(r.get("play", 3))],
		["Entrada do dia", "+%d" % int(r.get("daily", 10))],
		["3 dias seguidos", "+%d extra" % int(r.get("streak3", 20))],
		["7 dias seguidos", "+%d extra" % int(r.get("streak7", 50))],
		["Missões do dia", "+15 a +40"],
	]
	var grid := GridContainer.new()
	grid.name = "CrownsHow"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for p in lines:
		grid.add_child(_wrap(label(p[0], 14, CREAM, true)))
		var val := label(p[1], 14, GOLD)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)
	var note := "Valem partidas online contra outra pessoa (Casual e Ranqueada, a partir de %d lances de cada lado) e mesas de XEQUE e MARCHA REAL jogadas até o fim. Até %d Coroas por dia vindas de partidas." % [int(r.get("min_moves", 5)), int(r.get("match_cap", 150))]
	if int(r.get("club_bonus_pct", 25)) > 0: note += " Club FRAIHA: +%d%% nas Coroas de partida." % int(r.get("club_bonus_pct", 25))
	parent.add_child(_wrap(label(note, 12, DIM, true)))

func _recent(parent: Control, st: Dictionary):
	var items: Array = st.get("recent", []) if st.get("recent") is Array else []
	_section(parent, "ÚLTIMOS GANHOS")
	var list := VBoxContainer.new()
	list.name = "CrownsRecent"
	list.add_theme_constant_override("separation", 2)
	parent.add_child(list)
	if items.is_empty():
		list.add_child(_wrap(label("Jogue uma partida online para ganhar as primeiras Coroas.", 13, DIM, true)))
		return
	for it in items.slice(0, 4 if _pc() else 8):
		var row := HBoxContainer.new()
		list.add_child(row)
		row.add_child(_wrap(label("%s  ·  %s" % [String(it.get("label", "")), _when(String(it.get("at", "")))], 13, CREAM, true)))
		var d := int(it.get("delta", 0))
		row.add_child(label(("+" if d > 0 else "") + client.fmt(d), 14, GOLD))

func _when(iso: String) -> String:
	if iso.length() < 16: return ""
	var t := Time.get_unix_time_from_datetime_string(iso.substr(0, 19)) - 3 * 3600   # horário de Brasília
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%02d/%02d %02d:%02d" % [d.day, d.month, d.hour, d.minute]

func _soon(parent: Control):
	# R116 · a LOJA DE COROAS abriu: títulos já à venda; molduras, avatares e emotes chegam em seguida
	var b := button("ABRIR A LOJA DE COROAS", 15, true)
	b.name = "CrownsOpenStore"
	b.custom_minimum_size = Vector2(0, ts(44))
	b.pressed.connect(func(): client.open_store("title"))
	parent.add_child(b)
	# R118 · torneio grátis de XEQUE / MARCHA com prêmio em Coroas
	var tb := button("TORNEIO DA SEMANA", 15)
	tb.name = "CrownsOpenTournament"
	tb.custom_minimum_size = Vector2(0, ts(44))
	tb.pressed.connect(func(): client.open_tournament("xeque"))
	parent.add_child(tb)
