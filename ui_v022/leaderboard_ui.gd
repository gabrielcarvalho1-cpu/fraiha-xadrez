extends "res://ui_v022/home_modal.gd"
## R96 · RANKING (troféu no topo da Home). Abas XADREZ (Relâmpago · Rápida · Normal · Convencional),
## XEQUE e MARCHA REAL. O servidor monta o placar (online_v021/social/leaderboard.js): ordem por
## APROVEITAMENTO (vitória 1, empate ½), mínimo de partidas, top 50 + a sua posição.
const LEAGUES = ["Madeira", "Ferro", "Bronze", "Prata", "Ouro", "Platina", "Esmeralda", "Diamante", "Mestre", "Grande Mestre", "Challenger"]
const TABS := [["xadrez", "XADREZ"], ["xeque", "XEQUE"], ["marcha", "MARCHA REAL"]]
const CHESS := [["ranked_3min", "RELÂMPAGO"], ["ranked_5min", "RÁPIDA"], ["ranked_10min", "NORMAL"], ["ranked_20min", "CONVENCIONAL"]]
const MEDAL := [Color("f4ce7f"), Color("d6dde3"), Color("d79a5b")]

var tab := "xadrez"
var chess_board := "ranked_3min"
var tab_buttons := {}
var chess_buttons := {}
var chess_row: HBoxContainer
var head_row: HBoxContainer
var scroll: ScrollContainer
var list: VBoxContainer
var status: Label
var me_label: Label
var rule_label: Label
var cache := {}          # board -> {at, msg}
var waiting := ""

func setup(p_hub, acc):
	build(p_hub, "RANKING")
	account = acc
	if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	for t in TABS:
		var b := button(t[1], 17, t[0] == tab)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): set_tab(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b
	chess_row = HBoxContainer.new()
	chess_row.add_theme_constant_override("separation", 6)
	body.add_child(chess_row)
	for c in CHESS:
		var b := button(c[1], 13, c[0] == chess_board)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(func(): set_chess(c[0]))
		chess_row.add_child(b)
		chess_buttons[c[0]] = b
	head_row = _row_box(null, true)
	body.add_child(head_row)
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	status = label("", 16, DIM, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(status)
	var line := ColorRect.new()
	line.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	body.add_child(line)
	me_label = label("", 16, GOLD)
	me_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(me_label)
	rule_label = label("Ordem por aproveitamento (vitória = 1, empate = ½) · mínimo de 5 partidas", 12, DIM, true)
	rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(rule_label)

func board() -> String:
	return chess_board if tab == "xadrez" else tab

func show_ranking():
	open()
	_refresh_tabs()
	_request()

func set_tab(t: String):
	tab = t
	_refresh_tabs()
	_request()

func set_chess(b: String):
	chess_board = b
	_refresh_tabs()
	_request()

func _refresh_tabs():
	for k in tab_buttons: style_button(tab_buttons[k], k == tab)
	var narrow := get_viewport().get_visible_rect().size.x < 520.0
	for k in chess_buttons:
		style_button(chess_buttons[k], k == chess_board)
		chess_buttons[k].add_theme_font_size_override("font_size", 10 if narrow else 13)
		if narrow:
			for st_name in ["normal", "hover", "pressed", "disabled"]:
				var st: StyleBoxFlat = chess_buttons[k].get_theme_stylebox(st_name)
				st.content_margin_left = 3
				st.content_margin_right = 3
	chess_row.visible = tab == "xadrez"
	_fill_head()

func _request():
	var b := board()
	var c = cache.get(b)
	if c != null and Time.get_ticks_msec() - int(c.at) < 30000:
		_show(c.msg)
		return
	_clear()
	waiting = b
	var ok: bool = account != null and bool(account.get("server_ready")) and account.send_server({"type": "leaderboard_get", "board": b})
	status.text = "Carregando o ranking…" if ok else "Sem conexão com o servidor. Tente de novo em instantes."
	me_label.text = ""

func _on_message(msg: Dictionary):
	if String(msg.get("type", "")) != "leaderboard": return
	var b := String(msg.get("board", ""))
	cache[b] = {"at": Time.get_ticks_msec(), "msg": msg}
	if visible and b == board(): _show(msg)

func _clear():
	for ch in list.get_children():
		if ch != status: ch.queue_free()

func _show(msg: Dictionary):
	_clear()
	waiting = ""
	var rows: Array = msg.get("rows", []) if msg.get("rows") is Array else []
	var minm := int(msg.get("min_matches", 5))
	rule_label.text = "Ordem por aproveitamento (vitória = 1, empate = ½) · mínimo de %d partidas" % minm
	if not bool(msg.get("available", false)):
		status.text = "Ranking deste modo em breve." if String(msg.get("error", "")) != "server_error" else "Erro temporário no servidor. Tente de novo."
		status.visible = true
		me_label.text = ""
		return
	status.visible = rows.is_empty()
	status.text = "Ninguém com %d partidas ainda. Jogue e seja o primeiro!" % minm
	for r in rows: list.add_child(_row_box(r, false))
	var me = msg.get("me")
	if me is Dictionary:
		if int(me.get("pos", 0)) > 0:
			me_label.text = "SUA POSIÇÃO: %dº · %s · %dV %dD %dE" % [int(me.pos), _pct(me), int(me.wins), int(me.losses), int(me.draws)]
		else:
			var miss := int(me.get("missing", 0))
			me_label.text = ("Faltam %d partida%s para você entrar no ranking." % [miss, "" if miss == 1 else "s"]) if miss > 0 else "Você ainda não está no top."
	elif account != null and String(account.get("user_id")) != "":
		me_label.text = ""
	else:
		me_label.text = "Entre na sua conta para aparecer no ranking."

func _pct(r: Dictionary) -> String:
	var v := float(r.get("rate", 0.0))
	return ("%d%%" % roundi(v)) if is_equal_approx(v, roundf(v)) else ("%.1f%%" % v).replace(".", ",")

func _cols() -> Array:
	# [rótulo, largura mínima, alinhamento] — o nome estica
	var narrow := get_viewport().get_visible_rect().size.x < 520.0
	var c := [["#", 34 if narrow else 44], ["JOGADOR", 0], ["V", 34 if narrow else 46], ["D", 34 if narrow else 46], ["E", 30 if narrow else 40], ["%", 52 if narrow else 66]]
	if tab == "xadrez" and not narrow: c.insert(2, ["LIGA", 128])
	return c

func _fill_head():
	if head_row == null: return
	for ch in head_row.get_children(): ch.queue_free()
	for col in _cols():
		var l := label(col[0], 13, DIM)
		_size_col(l, col)
		head_row.add_child(l)

func _size_col(l: Label, col: Array):
	if int(col[1]) == 0:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		l.custom_minimum_size.x = col[1]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _row_box(r, head: bool) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if head: return box
	var pos := int(r.get("pos", 0))
	var mine: bool = account != null and String(r.get("user_id", "")) == String(account.get("user_id"))
	var bg := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.20, 0.13, 0.95) if pos % 2 == 1 else Color(0.06, 0.13, 0.09, 0.95)
	if pos >= 1 and pos <= 3:
		st.border_color = MEDAL[pos - 1]
		st.set_border_width_all(1)
	if mine:
		st.border_color = GOLD
		st.set_border_width_all(2)
	st.set_corner_radius_all(5)
	for side in ["left", "right"]: st.set("content_margin_" + side, 6)
	for side in ["top", "bottom"]: st.set("content_margin_" + side, 4)
	bg.add_theme_stylebox_override("panel", st)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	bg.add_child(inner)
	var cols := _cols()
	var values := []
	for col in cols:
		match col[0]:
			"#": values.append(["%dº" % pos, MEDAL[pos - 1] if pos <= 3 else CREAM])
			"JOGADOR": values.append([String(r.get("nickname", "Jogador")), GOLD if mine else CREAM])
			"LIGA":
				var lg = r.get("league")
				values.append([LEAGUES[clampi(int(lg), 0, LEAGUES.size() - 1)] + " · %d PL" % int(r.get("pl", 0)) if lg != null else "—", DIM])
			"V": values.append([str(int(r.get("wins", 0))), Color("8fd18a")])
			"D": values.append([str(int(r.get("losses", 0))), Color("e0837a")])
			"E": values.append([str(int(r.get("draws", 0))), DIM])
			"%": values.append([_pct(r), GOLD])
	for i in cols.size():
		var l := label(values[i][0], 15 if cols[i][0] != "LIGA" else 12, values[i][1], cols[i][0] == "LIGA")
		_size_col(l, cols[i])
		inner.add_child(l)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(bg)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

func _layout():
	super._layout()
	_fill_head()
	if visible and waiting == "" and cache.has(board()): _show(cache[board()].msg)
