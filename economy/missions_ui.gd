extends "res://economy/crowns_ui.gd"
## R176.8b · MISSÕES DO DIA em tela própria (antes ficavam misturadas no painel COROAS): as 3 missões com
## progresso, o limite de Coroas de partidas do dia e, ao lado, COMO FUNCIONA (o que vale, quando trocam,
## quanto rende). Mesmo estado do servidor (crowns_state) e o mesmo visual do painel COROAS.

func setup(p_hub, acc, p_client):
	build(p_hub, "MISSÕES DO DIA")
	account = acc
	client = p_client
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	client.changed.connect(func(): if visible: _rebuild())

func show_missions():
	open()
	_rebuild()

func _rebuild():
	if scroll == null: return
	if content != null: content.queue_free()
	content = VBoxContainer.new()
	content.name = "MissionsContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	var st: Dictionary = client.state
	var logged: bool = client.logged_in()
	var left: Control = content
	var right: Control = content
	if _pc():
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 26)
		content.add_child(cols)
		left = _col(cols, 1.15)
		right = _col(cols, 1.0)
	if not logged:
		left.add_child(_wrap(label("Entre na sua conta para fazer as Missões do dia e ganhar Coroas.", 17, CREAM)))
	elif not client.available():
		left.add_child(_wrap(label("Abrindo as suas missões…" if st.is_empty() else "As Missões ainda não estão ligadas neste servidor. Volte em breve!", 16, CREAM)))
	else:
		_missions(left, st)
		var done := 0
		var total := 0
		for m in st.get("missions", []):
			if m is Dictionary:
				total += 1
				if bool(m.get("done", false)): done += 1
		var sum := _wrap(label("%d de %d missões feitas hoje" % [done, total], 14, GOLD, true))
		sum.name = "MissionsDone"
		left.add_child(sum)
	_explain(right, st)
	var b := button("VER MINHAS COROAS", 15, true)
	b.name = "MissionsOpenCrowns"
	b.custom_minimum_size = Vector2(0, ts(44))
	b.pressed.connect(func():
		back_to = Callable()
		close()
		client.open_panel())
	right.add_child(b)

func _explain(parent: Control, st: Dictionary):
	_section(parent, "COMO FUNCIONA")
	var r: Dictionary = st.get("rules", {}) if st.get("rules") is Dictionary else {}
	var secs := int(st.get("resets_in_s", 0))
	var lines := [
		"Todo dia você recebe 3 missões novas. Elas trocam à meia-noite (horário de Brasília)%s." % ((" · faltam %dh%02d" % [secs / 3600, (secs % 3600) / 60]) if secs > 0 else ""),
		"Cada missão feita dá de +15 a +40 Coroas, direto no seu cofre (não precisa resgatar).",
		"Valem partidas online contra outra pessoa (Casual e Ranqueada, a partir de %d lances de cada lado) e mesas de XEQUE e MARCHA REAL jogadas até o fim." % int(r.get("min_moves", 5)),
		"As Coroas de partidas têm limite de %d por dia; as Coroas das missões contam à parte." % int(r.get("match_cap", 150)),
		"Use as Coroas na Loja de Coroas: títulos, molduras, avatares e emotes.",
	]
	for t in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		parent.add_child(row)
		var dot := label("•", 15, GOLD)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(dot)
		row.add_child(_wrap(label(t, 14, CREAM, true)))
