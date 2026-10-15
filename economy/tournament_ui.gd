extends "res://ui_v022/home_modal.gd"
## R118 · TORNEIO DA SEMANA (XEQUE e MARCHA REAL): entrada grátis, prêmio em Coroas. O servidor monta o placar
## (online_v021/economy/tournaments.js → tourn_state); aqui só se mostra: tempo até acabar, prêmios, top 10 e a sua posição.
const CROWN := preload("res://ui_kit/mobile/bots_crown.png")
const TABS := [["xeque", "XEQUE"], ["marcha", "MARCHA REAL"]]
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

func setup(p_hub, acc, p_client):
	build(p_hub, "TORNEIO DA SEMANA")
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

func show_tournament(g := "xeque"):
	game = g
	open()
	_render()
	_request()

func set_game(g: String):
	game = g
	_render()
	_request()

func _request():
	if account != null and account.has_method("send_server"): account.send_server({"type": "tourn_get", "game": game})

func _on_message(m: Dictionary):
	if String(m.get("type", "")) != "tourn_state": return
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
