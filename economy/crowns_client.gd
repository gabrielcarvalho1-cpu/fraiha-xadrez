extends Node
## R112 · COROAS no cliente: guarda o último estado do servidor (crowns_state), atualiza os botões de saldo do topo
## da Home (PC e celular), abre o painel COROAS e mostra o aviso "+N COROAS" quando o servidor paga
## (crowns_reward: entrada do dia, partida, missão). O servidor decide tudo; aqui só se mostra.
signal changed

const FONT := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")
const GOLD := Color("f4ce7f")
const CREAM := Color("efe3c4")

var hub
var account
var state: Dictionary = {}
var store_state: Dictionary = {}   # R116 · LOJA DE COROAS (store_state do servidor)
var store_panel = null
signal store_changed
signal store_result(ok: bool, item: String, message: String)
var chips: Array = []
var panel = null
var _asked_for := ""
var _toast_layer: CanvasLayer
var _toast: PanelContainer
var _toast_title: Label
var _toast_lines: Label
var _toast_tween: Tween

func setup(p_hub, acc):
	hub = p_hub
	account = acc
	name = "CrownsClient"
	if account == null: return
	if account.has_signal("server_message"): account.server_message.connect(_on_message)
	if account.has_signal("changed"): account.changed.connect(_on_account_changed)
	_on_account_changed.call_deferred()

static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

func available() -> bool:
	return bool(state.get("available", false))

func balance() -> int:
	return int(state.get("balance", 0))

func logged_in() -> bool:
	return account != null and account.has_method("has_profile") and account.has_profile()

func _on_account_changed():
	if not logged_in():
		if not state.is_empty() or not store_state.is_empty():
			state = {}
			store_state = {}
			preload("res://profile/premium_cosmetics.gd").shop_owned = []
			_asked_for = ""
			_refresh_chips()
			changed.emit()
		return
	var uid := String(account.user_id)
	if _asked_for != uid:
		_asked_for = uid
		request()

func request():
	if logged_in() and account.has_method("send_server"):
		account.send_server({"type": "crowns_get"})
		# R121 · abriu pelo link de um criador já tendo conta: aplica o código uma vez
		var IL := preload("res://social/invite_link.gd")
		var cr: String = IL.stored_creator()
		if not cr.is_empty():
			account.send_server({"type": "creator_set", "code": cr})
			IL.clear_creator()
		account.send_server({"type": "store_get"})   # R116 · também diz quais títulos/itens a conta já tem

func buy(item_id: String):
	if logged_in() and account.has_method("send_server"): account.send_server({"type": "store_buy", "item": item_id})

func owned(item_id: String) -> bool:
	return item_id in (store_state.get("owned", []) as Array) if store_state.get("owned") is Array else false

func store_available() -> bool:
	return bool(store_state.get("available", false))

var creator_panel = null
## R121 · APOIE UM CRIADOR
func open_creator():
	if not is_instance_valid(creator_panel):
		creator_panel = load("res://economy/creator_ui.gd").new()
		hub.add_child(creator_panel)
		creator_panel.setup(hub, account, self)
	if is_instance_valid(panel) and panel.is_open(): panel.close()
	creator_panel.show_creator()

var pass_panel = null
## R120 · PASSE DA TEMPORADA
func open_pass():
	if not is_instance_valid(pass_panel):
		pass_panel = load("res://economy/season_pass_ui.gd").new()
		hub.add_child(pass_panel)
		pass_panel.setup(hub, account, self)
	if is_instance_valid(panel) and panel.is_open(): panel.close()
	pass_panel.show_pass()

var tourn_panel = null
## R118 · TORNEIO DA SEMANA (XEQUE / MARCHA REAL)
func open_tournament(g := "xeque"):
	if not is_instance_valid(tourn_panel):
		tourn_panel = load("res://economy/tournament_ui.gd").new()
		hub.add_child(tourn_panel)
		tourn_panel.setup(hub, account, self)
	if is_instance_valid(panel) and panel.is_open(): panel.close()
	tourn_panel.show_tournament(g)

func open_store(tab := "title"):
	if not is_instance_valid(store_panel):
		store_panel = load("res://economy/crown_store_ui.gd").new()
		hub.add_child(store_panel)
		store_panel.setup(hub, account, self)
	if is_instance_valid(panel) and panel.is_open(): panel.close()
	store_panel.show_store(tab)
	request()

func _on_message(m: Dictionary):
	match String(m.get("type", "")):
		"crowns_state":
			state = m
			_refresh_chips()
			changed.emit()
		"store_state":
			store_state = m
			preload("res://profile/premium_cosmetics.gd").shop_owned = (m.get("owned", []) as Array).duplicate() if m.get("owned") is Array else []
			if hub != null and hub.has_method("refresh_club"): hub.refresh_club()   # título comprado e em uso volta a aparecer
			store_changed.emit()
		"store_bought":
			if m.has("balance") and m.get("balance") != null:
				state["balance"] = int(m.get("balance"))
				_refresh_chips()
			store_result.emit(true, String(m.get("item", "")), "")
		"store_error":
			store_result.emit(false, String(m.get("item", "")), String(m.get("message", "Não foi possível concluir.")))
		"crowns_reward":
			if m.has("balance") and m.get("balance") != null:
				state["balance"] = int(m.get("balance"))
				_refresh_chips()
			if int(m.get("gained", 0)) > 0: show_toast(int(m.get("gained", 0)), m.get("lines", []))

## botão do topo da Home: coroa + saldo, no mesmo estilo do troféu e do balão.
func make_chip(h: float, w: float) -> Button:
	var b: Button = preload("res://ui_v022/hud_button.gd").make("crown", "—")
	b.name = "CrownsTopButton"
	b.icon_box = h * 0.78
	b.size = Vector2(w, h)
	b.custom_minimum_size = Vector2(w, h)
	b.tooltip_text = "Coroas"
	b.clip_text = true
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", int(clampf(h * 0.4, 13.0, 26.0)))
	b.add_theme_color_override("font_color", GOLD)
	if w <= h * 1.2:   # R122 · quadrado: coroa em cima e o saldo pequeno embaixo
		b.icon_only = true
		b.sub_font = FONT
		b.text = ""
	b.pressed.connect(open_panel)
	chips.append(b)
	_refresh_chips()
	return b

func _refresh_chips():
	var t := fmt(balance()) if available() else "—"
	for b in chips.duplicate():
		if not is_instance_valid(b):
			chips.erase(b)
			continue
		b.tooltip_text = "Coroas: %s" % t
		if b.sub_font != null:   # R122 · botão quadrado
			b.sub_text = t
			var ss := int(clampf(b.size.y * 0.24, 11.0, 20.0))
			while ss > 9 and FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x > b.size.x - 12.0: ss -= 1
			b.sub_size = ss
			b.queue_redraw()
			continue
		b.text = t
		# o número diminui até caber (1.285 ou 12.345 no mesmo botão)
		var room: float = b.size.x - b.icon_box - 8.0
		var fs := int(clampf(b.size.y * 0.4, 13.0, 26.0))
		while fs > 10 and FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room - 4.0: fs -= 1
		b.add_theme_font_size_override("font_size", fs)
		for sn in ["normal", "hover", "pressed", "disabled"]:
			var sb = b.get_theme_stylebox(sn)
			if sb != null: sb.content_margin_right = 6.0

func open_panel():
	if not is_instance_valid(panel):
		panel = load("res://economy/crowns_ui.gd").new()
		hub.add_child(panel)
		panel.setup(hub, account, self)
	panel.show_crowns()
	request()

# ---------- aviso "+N COROAS" (não bloqueia nada, some sozinho) ----------
func show_toast(gained: int, lines):
	if _toast_layer == null:
		_toast_layer = CanvasLayer.new()
		_toast_layer.layer = 120
		_toast_layer.name = "CrownsToastLayer"
		add_child(_toast_layer)
		_toast = PanelContainer.new()
		_toast.name = "CrownsToast"
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# R113 · na moldura dos botões do jogo (dourada, fundo azul, joias nos cantos)
		var st := StyleBoxTexture.new()
		st.texture = preload("res://ui_kit/art/fr_btn_azul.png")
		for side in ["left", "right", "top", "bottom"]: st.set("texture_margin_" + side, 18.0)
		for side in ["left", "right"]: st.set("content_margin_" + side, 30.0)
		for side in ["top", "bottom"]: st.set("content_margin_" + side, 16.0)
		_toast.add_theme_stylebox_override("panel", st)
		_toast_layer.add_child(_toast)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast.add_child(row)
		var g := TextureRect.new()   # a coroa dourada da arte do jogo
		g.texture = preload("res://ui_kit/mobile/bots_crown.png")
		g.custom_minimum_size = Vector2(46, 42)
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(g)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		_toast_title = Label.new()
		_toast_title.add_theme_font_override("font", FONT)
		_toast_title.add_theme_font_size_override("font_size", 26)
		_toast_title.add_theme_color_override("font_color", GOLD)
		_toast_title.add_theme_color_override("font_outline_color", Color(0.10, 0.05, 0.0))
		_toast_title.add_theme_constant_override("outline_size", 5)
		col.add_child(_toast_title)
		_toast_lines = Label.new()
		_toast_lines.add_theme_font_override("font", FONT_SEMI)
		_toast_lines.add_theme_font_size_override("font_size", 15)
		_toast_lines.add_theme_color_override("font_color", CREAM)
		_toast_lines.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.10))
		_toast_lines.add_theme_constant_override("outline_size", 3)
		col.add_child(_toast_lines)
	_toast_title.text = "+%s COROAS" % fmt(gained)
	var ls := PackedStringArray()
	if lines is Array:
		for l in lines: ls.append(String(l))
	_toast_lines.text = "\n".join(ls)
	_toast_lines.visible = not ls.is_empty()
	_toast.reset_size()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var sz := _toast.get_combined_minimum_size()
	_toast.size = sz
	var y := 92.0 if vs.x >= 900.0 else 64.0
	_toast.position = Vector2(floorf((vs.x - sz.x) * 0.5), y)
	if _toast_tween != null and _toast_tween.is_valid(): _toast_tween.kill()
	_toast.visible = true
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(4.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): _toast.visible = false)
