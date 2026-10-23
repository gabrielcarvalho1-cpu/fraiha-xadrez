extends "res://ui_v022/home_modal.gd"
## R161 · NOVIDADES: abre ao tocar no outdoor da Home. Abas ATUALIZAÇÕES / NOTÍCIAS / CAMPEONATOS / EVENTOS,
## cada item num cartão (data, título, texto e, se o Admin quiser, um botão: abrir Torneios, Ranking, Loja ou um link).
const NewsFeed := preload("res://ui_v022/news_feed.gd")
var feed
var tab := "atualizacao"
var tab_buttons := {}
var tabs_box: GridContainer
var scroll: ScrollContainer
var list: VBoxContainer
var empty_label: Label
var _open_ids := {}

func setup(p_hub, p_feed):
	build(p_hub, "NOVIDADES")
	name = "NewsUI"
	feed = p_feed
	tabs_box = GridContainer.new()
	tabs_box.name = "NewsTabs"
	tabs_box.add_theme_constant_override("h_separation", 6)
	tabs_box.add_theme_constant_override("v_separation", 6)
	body.add_child(tabs_box)
	for k in NewsFeed.KINDS:
		var b := button(k[1], 13, k[0] == tab)
		b.name = "NewsTab_" + k[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		var kind: String = k[0]
		b.pressed.connect(func(): set_tab(kind))
		tabs_box.add_child(b)
		tab_buttons[kind] = b
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "NewsList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	if feed != null: feed.changed.connect(func(): if visible: _rebuild())

func show_news(which := ""):
	if not which.is_empty(): tab = which
	elif feed != null and feed.of_kind(tab).is_empty():
		for k in NewsFeed.KINDS:
			if not feed.of_kind(k[0]).is_empty():
				tab = k[0]
				break
	open()
	if feed != null: feed.fetch()
	_refresh_tabs()
	_rebuild()

func set_tab(t: String):
	tab = t
	_refresh_tabs()
	_rebuild()
	scroll.scroll_vertical = 0

func _refresh_tabs():
	tabs_box.columns = 2 if narrow() else 4
	for k in tab_buttons:
		style_button(tab_buttons[k], k == tab)
		tab_buttons[k].add_theme_font_size_override("font_size", ts(14 if narrow() else 17))

func _rebuild():
	for c in list.get_children(): c.queue_free()
	var rows: Array = feed.of_kind(tab) if feed != null else []
	if rows.is_empty():
		var l := label("Nada por aqui ainda.\nVolte em breve!" if (feed != null and feed.loaded) else "Carregando novidades…", 16, DIM, true)
		l.name = "NewsEmpty"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.y = 120
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(l)
		return
	for it in rows: list.add_child(_card(it))

func _card(it: Dictionary) -> Control:
	var id := String(it.get("id", ""))
	var card := PanelContainer.new()
	card.name = "NewsCard_" + id
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.15, 0.92)
	sb.border_color = Color("c99a45") if not bool(it.get("pinned", false)) else Color("ffd877")
	sb.set_border_width_all(2 if not bool(it.get("pinned", false)) else 3)
	sb.set_corner_radius_all(8)
	for side in ["left", "right"]: sb.set("content_margin_" + side, 16)
	for side in ["top", "bottom"]: sb.set("content_margin_" + side, 12)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var date := label(NewsFeed.date_br(String(it.get("published_at", ""))), 13, DIM)
	date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(date)
	if bool(it.get("pinned", false)):
		var pin := label("DESTAQUE", 12, Color("1a1206"))
		var ps := StyleBoxFlat.new()
		ps.bg_color = GOLD
		ps.set_corner_radius_all(4)
		ps.content_margin_left = 8; ps.content_margin_right = 8
		pin.add_theme_stylebox_override("normal", ps)
		head.add_child(pin)
	var title := label(String(it.get("title", "")), 20, GOLD)
	title.name = "NewsTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	var text := String(it.get("body", ""))
	var long := text.length() > 220 or text.count("\n") > 3
	var open_full: bool = _open_ids.has(id) or not long
	var bl := RichTextLabel.new()
	bl.name = "NewsBody"
	bl.bbcode_enabled = false
	bl.fit_content = true
	bl.scroll_active = false
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.add_theme_font_size_override("normal_font_size", ts(16))
	bl.add_theme_color_override("default_color", CREAM)
	bl.mouse_filter = Control.MOUSE_FILTER_PASS
	bl.text = text if open_full else (text.substr(0, 200).strip_edges() + "…")
	v.add_child(bl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	if long:
		var more := button("LER MENOS" if open_full else "LER MAIS", 13)
		more.pressed.connect(func():
			if _open_ids.has(id): _open_ids.erase(id)
			else: _open_ids[id] = true
			_rebuild())
		row.add_child(more)
	var bl_label := String(it.get("button_label", "")).strip_edges()
	var act := String(it.get("button_action", "")).strip_edges()
	if not bl_label.is_empty() and not act.is_empty():
		var go := button(bl_label.to_upper(), 14, true)
		go.name = "NewsAction"
		go.pressed.connect(func(): run_action(act))
		row.add_child(go)
	return card

## Botão do item (Admin): "torneios", "ranking", "loja", "premium", "loja_coroas", "suporte", "passe" ou um link https://
func run_action(act: String):
	if act.begins_with("https://"):
		OS.shell_open(act)
		return
	close()
	match act:
		"torneios": hub.crowns_client().open_tournament("chess")
		"loja_coroas": hub.crowns_client().open_store()
		"ranking": hub.open_leaderboard()
		"loja", "premium": hub.open_premium()
		"suporte": hub.open_support()   # R180 · beta: reportar bug/problema
		"passe": hub.crowns_client().open_pass()   # R180
		_: pass

func _layout():
	super._layout()
	if tabs_box != null: _refresh_tabs()
