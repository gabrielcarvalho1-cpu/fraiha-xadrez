extends "res://ui_v022/home_modal.gd"
## R116 · LOJA DE COROAS — itens só visuais (nunca vantagem de jogo). Abas TÍTULOS · MOLDURAS · AVATARES · EMOTES.
## O preço e a compra são do servidor (store_buy); aqui: comprar (com confirmação), USAR e EM USO.
const Art := preload("res://monetization/premium_art.gd")
const Catalog := preload("res://economy/crown_store_catalog.gd")
const CROWN := preload("res://ui_kit/mobile/bots_crown.png")
const TABS := [["title", "TÍTULOS"], ["frame", "MOLDURAS"], ["avatar", "AVATARES"], ["emote", "EMOTES"]]

var client
var tab := "title"
var tab_buttons := {}
var top_row: HBoxContainer
var balance_label: Label
var message_label: Label
var scroll: ScrollContainer
var grid: GridContainer
var confirm_id := ""
var confirm_until := 0

func setup(p_hub, acc, p_client):
	build(p_hub, "LOJA DE COROAS")
	account = acc
	client = p_client
	top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	body.add_child(top_row)
	var g := TextureRect.new()
	g.texture = CROWN
	g.custom_minimum_size = Vector2(ts(34), ts(31))
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top_row.add_child(g)
	balance_label = label("", 17 if narrow() else 22, GOLD)
	balance_label.clip_text = true
	balance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	balance_label.name = "StoreBalance"
	balance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(balance_label)
	var how := button("COMO GANHAR", 11 if narrow() else 13)
	how.pressed.connect(func(): close(); client.open_panel())
	top_row.add_child(how)
	var tabs := GridContainer.new()   # celular estreito: 2 × 2 (os nomes cabem inteiros)
	tabs.columns = 2 if narrow() else 4
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	body.add_child(tabs)
	for t in TABS:
		var b := button(t[1], 14 if narrow() else 16, t[0] == tab)
		b.name = "StoreTab_" + t[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(func(): set_tab(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b
	message_label = label("", 14, CREAM, true)
	message_label.name = "StoreMessage"
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(message_label)
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	client.store_changed.connect(func(): if visible: _rebuild())
	client.changed.connect(func(): if visible: _refresh_balance())
	client.store_result.connect(_on_result)
	if hub.has_signal("cosmetics_changed"): hub.cosmetics_changed.connect(func(): if visible: _rebuild.call_deferred())

func show_store(t := "title"):
	tab = t
	message_label.text = ""
	confirm_id = ""
	open()
	_rebuild()

func set_tab(t: String):
	tab = t
	confirm_id = ""
	message_label.text = ""
	_rebuild()

func _layout():
	super._layout()
	if visible and grid != null: _rebuild.call_deferred()

func _refresh_balance():
	if not client.logged_in(): balance_label.text = "ENTRE NA SUA CONTA"
	elif not client.available() and not client.store_available(): balance_label.text = "COROAS"
	else: balance_label.text = ("%s" if narrow() else "%s COROAS") % client.fmt(client.balance())   # celular: a coroa ao lado já diz o que é

func _rebuild():
	if scroll == null: return
	for k in tab_buttons: style_button(tab_buttons[k], k == tab)
	_refresh_balance()
	if grid != null: grid.queue_free()
	grid = GridContainer.new()
	grid.name = "StoreGrid"
	grid.columns = 1 if narrow() else (2 if portrait() else 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var items: Array = Catalog.of_kind(tab)
	if not client.logged_in():
		_info("Entre na sua conta para comprar com Coroas.")
		return
	if not client.store_available() and not client.store_state.is_empty():
		_info("A Loja de Coroas ainda não está ligada neste servidor. Volte em breve!")
		return
	if items.is_empty():
		_info({"frame": "Molduras novas para o seu retrato chegam em breve.", "avatar": "Avatares novos chegam em breve.",
			"emote": "Reações para usar nas partidas online chegam em breve."}.get(tab, "Em breve."))
		return
	for it in items: grid.add_child(_card(it))
	# aviso no fim da lista (fora dela encostava na moldura do celular)
	var note := label("Itens só de visual: nada na loja dá vantagem no jogo. Coroas se ganham jogando.", 11, DIM, true)
	note.name = "StoreNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(note)

func _info(t: String):
	var l := label(t, 16, CREAM, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l)

func _card(it: Dictionary) -> Control:
	var id := String(it.id)
	var price := int(it.price)
	var has: bool = client.owned(id)
	var in_use: bool = has and ((tab == "title" and hub.has_method("current_title") and hub.current_title() == id)
		or (tab == "frame" and hub.has_method("current_frame") and hub.current_frame() == id))
	var p := PanelContainer.new()
	p.name = "StoreItem_" + id
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.10, 0.24, 0.92) if has else Color(0.03, 0.06, 0.14, 0.88)
	s.border_color = GOLD if in_use else Color("c99a45")
	s.set_border_width_all(3 if in_use else 2)
	s.set_corner_radius_all(6)
	for side in ["left", "right"]: s.set("content_margin_" + side, 14)
	for side in ["top", "bottom"]: s.set("content_margin_" + side, 12)
	p.add_theme_stylebox_override("panel", s)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var kind := label({"title": "TÍTULO", "frame": "MOLDURA DO RETRATO", "emote": "EMOTE NAS PARTIDAS ONLINE"}.get(tab, ""), 11, DIM, true)
	v.add_child(kind)
	if tab == "frame": v.add_child(_frame_preview(id))
	var name_l := label(String(it.name), 17 if narrow() else 20, GOLD)
	name_l.add_theme_constant_override("outline_size", 5)
	name_l.add_theme_color_override("font_outline_color", Color(0.10, 0.05, 0.0))
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	if has:
		row.add_child(label("SEU", 14, Color("bcd4ff")))
	else:
		var g := TextureRect.new()
		g.texture = CROWN
		g.custom_minimum_size = Vector2(ts(22), ts(20))
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(g)
		row.add_child(label(client.fmt(price), 18, GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var b: Button
	if in_use:
		b = button("EM USO", 14)
		b.disabled = true
	elif has:
		b = button("USAR", 14, true)
		b.pressed.connect(func(): _use(id))
	else:
		var falta: int = price - int(client.balance())
		var confirming := confirm_id == id and Time.get_ticks_msec() < confirm_until
		if falta > 0:
			b = button("FALTAM %s" % client.fmt(falta), 13)
			b.disabled = true
		else:
			b = button(("CONFIRMAR %s" % client.fmt(price)) if confirming else "COMPRAR", 14, true)
			b.pressed.connect(func(): _buy(id))
	b.name = "StoreBtn_" + id
	row.add_child(b)
	return p

## a moldura no retrato do próprio jogador (como vai aparecer para todos)
func _frame_preview(id: String) -> Control:
	var holder := CenterContainer.new()
	var pic := TextureRect.new()
	pic.texture = hub.avatar_texture() if hub.has_method("avatar_texture") else null
	var side := 66.0 if narrow() else 84.0
	pic.custom_minimum_size = Vector2(side, side)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	holder.add_child(pic)
	var f = preload("res://monetization/club_frame.gd").new()
	f.style = id
	pic.add_child(f)
	var pad := Control.new()   # espaço para a coroa da moldura (fica acima do retrato)
	pad.custom_minimum_size = Vector2(0, side * 0.22)
	var box := VBoxContainer.new()
	box.add_child(pad)
	box.add_child(holder)
	return box

func _buy(id: String):
	if confirm_id == id and Time.get_ticks_msec() < confirm_until:
		confirm_id = ""
		message_label.text = "Comprando…"
		client.buy(id)
		return
	confirm_id = id
	confirm_until = Time.get_ticks_msec() + 4000
	message_label.text = "Toque de novo para confirmar a compra de \"%s\"." % String(Catalog.item(id).get("name", id))
	_rebuild()

func _use(id: String):
	if hub.has_method("set_cosmetic") and hub.set_cosmetic(tab, id):
		message_label.text = "Pronto: \"%s\" agora aparece no seu perfil." % String(Catalog.item(id).get("name", id))
	_rebuild()

func _on_result(ok: bool, item: String, msg: String):
	if not visible: return
	if ok: message_label.text = "Comprado! \"%s\" é seu para sempre — toque em USAR." % String(Catalog.item(item).get("name", item))
	else: message_label.text = msg
