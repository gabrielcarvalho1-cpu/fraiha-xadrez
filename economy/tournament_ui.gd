extends "res://ui_v022/home_modal.gd"
## R118 · TORNEIO DA SEMANA (XEQUE e MARCHA REAL): entrada grátis, prêmio em Coroas. O servidor monta o placar
## (online_v021/economy/tournaments.js → tourn_state); aqui só se mostra: tempo até acabar, prêmios, top 10 e a sua posição.
const CROWN := preload("res://ui_kit/mobile/bots_crown.png")
## R157 · XADREZ: torneios de evento com CÓDIGO (criados no Admin). Só entra quem tem o código.
const TABS := [["chess", "XADREZ"], ["xeque", "XEQUE"], ["marcha", "MARCHA REAL"]]
const MEDAL := [Color("f4ce7f"), Color("d6dde3"), Color("d79a5b")]

var client
var game := "xeque"
var tab_buttons := {}
var info_label: Label
var prizes_label: Label
var scroll: ScrollContainer
var list: VBoxContainer
var me_label: Label
var cache := {}
var code_row: HBoxContainer
var code_input: LineEdit
var code_status: Label
var ev_state := {}

func setup(p_hub, acc, p_client):
	build(p_hub, "TORNEIOS")
	account = acc
	client = p_client
	if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	for t in TABS:
		var b := button(t[1], 14 if narrow() else 17, t[0] == game)
		b.name = "TournTab_" + t[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): set_game(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b
	# R157 · XADREZ: entrar com o código do torneio
	code_row = HBoxContainer.new()
	code_row.name = "EventCodeRow"
	code_row.add_theme_constant_override("separation", 8)
	body.add_child(code_row)
	code_input = LineEdit.new()
	code_input.name = "EventCode"
	code_input.placeholder_text = "Código do torneio"
	code_input.max_length = 20
	code_input.custom_minimum_size.y = ts(44)
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_input.add_theme_font_size_override("font_size", ts(17))
	code_input.add_theme_color_override("font_color", CREAM)
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color("101a33")
	ist.border_color = Color("c99a45")
	ist.set_border_width_all(1)
	ist.set_corner_radius_all(4)
	for side in ["left", "right"]: ist.set("content_margin_" + side, 10)
	code_input.add_theme_stylebox_override("normal", ist)
	code_input.add_theme_stylebox_override("focus", ist)
	code_input.text_submitted.connect(func(_t): _join())
	code_row.add_child(code_input)
	var jb := button("ENTRAR", 15 if narrow() else 17, true)
	jb.name = "EventJoin"
	jb.pressed.connect(_join)
	code_row.add_child(jb)
	preload("res://ui_v022/web_text_field.gd").attach(code_input)
	code_status = label("", 14, GOLD, true)
	code_status.name = "EventStatus"
	code_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(code_status)
	info_label = label("", 14, CREAM, true)
	info_label.name = "TournInfo"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(info_label)
	prizes_label = label("", 13, GOLD, true)
	prizes_label.name = "TournPrizes"
	prizes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prizes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(prizes_label)
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "TournList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var line := ColorRect.new()
	line.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	body.add_child(line)
	me_label = label("", 15, GOLD)
	me_label.name = "TournMe"
	me_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(me_label)

func show_tournament(g := "chess"):
	game = g
	open()
	_render()
	_request()

func set_game(g: String):
	game = g
	_render()
	_request()

func _request():
	if account == null or not account.has_method("send_server"): return
	if game == "chess": account.send_server({"type": "tev_list"})
	else: account.send_server({"type": "tourn_get", "game": game})

func _join():
	var c := code_input.text.strip_edges().to_upper()
	if c.length() < 4:
		code_status.text = "Digite o código que o organizador passou."
		return
	code_status.text = "Procurando o torneio…"
	if account != null and account.has_method("send_server"): account.send_server({"type": "tev_join", "code": c})

func _on_message(m: Dictionary):
	var ty := String(m.get("type", ""))
	if ty == "tev_state":
		ev_state = m
		if m.has("joined_id"):
			code_input.text = ""
			code_status.text = "Inscrição feita! Boa sorte no torneio."
		if visible: _render()
		return
	if ty == "tev_error":
		code_status.text = String(m.get("message", "Não foi possível entrar."))
		return
	if ty != "tourn_state": return
	cache[String(m.get("game", ""))] = m
	if visible: _render()

func _layout():
	super._layout()

static func _left(secs: int) -> String:
	var d := secs / 86400
	var h := (secs % 86400) / 3600
	var mi := (secs % 3600) / 60
	if d > 0: return "%dd %dh" % [d, h]
	if h > 0: return "%dh %02dmin" % [h, mi]
	return "%d min" % mi

func _render():
	for k in tab_buttons: style_button(tab_buttons[k], k == game)
	for c in list.get_children(): c.queue_free()
	var chess := game == "chess"
	code_row.visible = chess
	code_status.visible = chess
	prizes_label.visible = not chess
	if chess:
		_render_events()
		return
	var st: Dictionary = cache.get(game, {})
	var r: Dictionary = st.get("rules", {}) if st.get("rules") is Dictionary else {}
	var prizes: Array = r.get("prizes", [500, 300, 200, 100]) if r.get("prizes") is Array else [500, 300, 200, 100]
	prizes_label.text = "PRÊMIOS: 1º %d · 2º %d · 3º %d · 4º ao 10º %d COROAS" % [int(prizes[0]), int(prizes[1]), int(prizes[2]), int(prizes[3])]
	if st.is_empty():
		info_label.text = "Carregando o placar…"
		me_label.text = ""
		return
	if not bool(st.get("available", false)):
		info_label.text = "O Torneio da Semana ainda não está ligado neste servidor. Volte em breve!"
		me_label.text = ""
		return
	info_label.text = "Entrada grátis · termina em %s · vitória %d pontos, partida até o fim %d (mesa online com amigos; até %d partidas por dia contam)" % [
		_left(int(st.get("ends_in_s", 0))), int(r.get("win", 3)), int(r.get("play", 1)), int(r.get("daily_games", 8))]
	var top: Array = st.get("top", []) if st.get("top") is Array else []
	if top.is_empty():
		var e := label("Ninguém pontuou ainda nesta semana. Jogue uma mesa online com amigos e seja o primeiro!", 16, CREAM, true)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(e)
	var me_id := String(account.user_id) if account != null else ""
	for row in top:
		list.add_child(_row(row, String(row.get("user_id", "")) == me_id))
	var me = st.get("me")
	if me is Dictionary:
		if me.get("pos") == null: me_label.text = "VOCÊ: ainda sem pontos nesta semana."
		else: me_label.text = "VOCÊ: %dº lugar · %d pontos (%d vitórias em %d partidas)%s" % [int(me.pos), int(me.points), int(me.wins), int(me.games),
			("  ·  prêmio agora: %d COROAS" % int(me.prize)) if int(me.get("prize", 0)) > 0 else ""]
	else:
		me_label.text = "Entre na sua conta para participar."

func _row(r: Dictionary, mine: bool) -> Control:
	var p := PanelContainer.new()
	p.name = "TournRow_%d" % int(r.get("pos", 0))
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.10, 0.24, 0.92) if mine else Color(0.03, 0.06, 0.14, 0.82)
	s.border_color = GOLD if mine else Color(0.79, 0.6, 0.27, 0.45)
	s.set_border_width_all(2 if mine else 1)
	s.set_corner_radius_all(5)
	for side in ["left", "right"]: s.set("content_margin_" + side, 10)
	for side in ["top", "bottom"]: s.set("content_margin_" + side, 6)
	p.add_theme_stylebox_override("panel", s)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var pos := int(r.get("pos", 0))
	var pl := label("%dº" % pos, 18, MEDAL[pos - 1] if pos >= 1 and pos <= 3 else CREAM)
	pl.custom_minimum_size = Vector2(ts(38), 0)
	h.add_child(pl)
	var n := label(String(r.get("nickname", "")), 16, CREAM, true)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	h.add_child(label("%d pts" % int(r.get("points", 0)), 15, GOLD))
	var prize := int(r.get("prize", 0))
	if prize > 0 and not narrow():
		var g := TextureRect.new()
		g.texture = CROWN
		g.custom_minimum_size = Vector2(ts(18), ts(16))
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(g)
		h.add_child(label(str(prize), 14, GOLD))
	return p


# ---------- R157 · XADREZ: torneios de evento ----------
func _render_events():
	me_label.text = ""
	if account == null or not account.has_method("has_profile") or not account.has_profile():
		info_label.text = "Entre na sua conta para participar de torneios de xadrez."
		code_row.visible = false
		return
	if ev_state.is_empty():
		info_label.text = "Carregando seus torneios…"
		return
	if not bool(ev_state.get("available", false)):
		info_label.text = "Os torneios de xadrez ainda não estão ligados neste servidor. Volte em breve!"
		code_row.visible = false
		return
	info_label.text = "Tem um código de torneio? Digite acima para se inscrever. Só entra quem tem o código."
	var evs: Array = ev_state.get("events", []) if ev_state.get("events") is Array else []
	if evs.is_empty():
		var e := label("Você ainda não está em nenhum torneio.", 16, CREAM, true)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(e)
		return
	for ev in evs: list.add_child(_event_card(ev))

func _event_card(ev: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.name = "EventCard"
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.08, 0.18, 0.92)
	s.border_color = GOLD
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	for side in ["left", "right"]: s.set("content_margin_" + side, 12)
	for side in ["top", "bottom"]: s.set("content_margin_" + side, 10)
	p.add_theme_stylebox_override("panel", s)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var t := label(String(ev.get("name", "")).to_upper(), 18, GOLD)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var when := ""
	if ev.get("starts_at") is String and not String(ev.starts_at).is_empty():
		var unix := Time.get_unix_time_from_datetime_string(String(ev.starts_at).substr(0, 19))
		if unix > 0:
			var d := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
			when = " · %02d/%02d %02d:%02d" % [int(d.day), int(d.month), int(d.hour), int(d.minute)]
	var sub := label("%s · %s · %d/%d inscritos%s" % [String(ev.get("status_text", "")), String(ev.get("mode_name", "")), int(ev.get("players", 0)), int(ev.get("max_players", 0)), when], 14, CREAM, true)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	if not String(ev.get("notes", "")).is_empty():
		var n := label(String(ev.notes), 13, Color("c9bfa6"), true)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(n)
	var champ = ev.get("champion")
	if champ is String and not champ.is_empty():
		v.add_child(label("CAMPEÃO: " + champ, 16, GOLD))
	var br = ev.get("bracket")
	if br is Array and not br.is_empty():
		v.add_child(label("CHAVES", 15, GOLD))
		for r in br.size():
			var nm := "Final" if br.size() - r == 1 else ("Semifinal" if br.size() - r == 2 else ("Quartas de final" if br.size() - r == 3 else "Rodada %d" % (r + 1)))
			v.add_child(label(nm, 13, Color("c9bfa6")))
			for x in br[r]:
				var a = x.get("a")
				var b = x.get("b")
				var w = x.get("winner")
				var sa := String(a) if a is String else ("(passa direto)" if r == 0 else "—")
				var sb := String(b) if b is String else ("(passa direto)" if r == 0 else "—")
				if a is String and w is String and w == a: sa = "✔ " + sa
				if b is String and w is String and w == b: sb = "✔ " + sb
				var line := label("%s  x  %s" % [sa, sb], 14, GOLD if bool(x.get("mine", false)) else CREAM, true)
				line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				v.add_child(line)
		var tip := label("Combine a sua partida com o adversário (convite de amigo, no ritmo do torneio). O organizador registra o resultado.", 12, Color("c9bfa6"), true)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(tip)
	else:
		var ent: Array = ev.get("entrants", []) if ev.get("entrants") is Array else []
		if not ent.is_empty():
			var el := label("Inscritos: " + ", ".join(PackedStringArray(ent)), 13, Color("c9bfa6"), true)
			el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(el)
		v.add_child(label("As chaves aparecem aqui quando o organizador montar.", 12, Color("c9bfa6"), true))
	return p
