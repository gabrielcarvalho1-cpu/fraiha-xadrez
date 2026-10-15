extends "res://ui_v022/home_modal.gd"
## R97 · TERMOS E PRIVACIDADE + EXCLUIR CONTA, na moldura do jogo. Abre pelas Configurações, pela SUA CONTA e
## pelo cadastro ("ao criar a conta você concorda…"). Excluir: digita o próprio nome e confirma; o servidor
## anonimiza a conta e bloqueia o login (online_v021: acct_delete).
const Legal = preload("res://ui_v022/legal_text.gd")
const RED := Color("e0574a")
const TABS := [["termos", "TERMOS DE USO"], ["privacidade", "PRIVACIDADE"], ["excluir", "EXCLUIR CONTA"]]
const TABS_SHORT := {"termos": "TERMOS", "privacidade": "PRIVACIDADE", "excluir": "EXCLUIR"}

var tab := "termos"
var tab_buttons := {}
var scroll: ScrollContainer
var text: RichTextLabel
var del_box: VBoxContainer
var del_scroll: ScrollContainer
var del_info: Label
var del_input: LineEdit
var del_button: Button
var del_status: Label
var deleting := false

func setup(p_hub, acc):
	build(p_hub, "TERMOS E PRIVACIDADE")
	account = acc
	if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	for t in TABS:
		var lbl: String = TABS_SHORT[t[0]] if narrow() else t[1]
		var b := button(lbl, 11 if narrow() else 16, t[0] == tab)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = float(lbl.length() + 3)
		b.clip_text = true
		b.pressed.connect(func(): set_tab(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b
	scroll = ScrollContainer.new()
	preload("res://ui_v022/touch_scroll.gd").attach(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	text = RichTextLabel.new()
	text.bbcode_enabled = false
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("normal_font", FONT_SEMI)
	text.add_theme_font_size_override("normal_font_size", ts(15))
	text.add_theme_color_override("default_color", CREAM)
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(text)
	del_scroll = ScrollContainer.new()   # no celular o aviso é longo: rola junto com o campo e o botão
	preload("res://ui_v022/touch_scroll.gd").attach(del_scroll)
	del_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	del_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(del_scroll)
	del_box = VBoxContainer.new()
	del_box.add_theme_constant_override("separation", 10)
	del_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_scroll.add_child(del_box)
	del_info = label("", 13 if narrow() else 15, CREAM, true)
	del_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	del_box.add_child(del_info)
	del_input = LineEdit.new()
	del_input.placeholder_text = "Digite o seu nome de jogador"
	del_input.max_length = 32
	del_input.custom_minimum_size.y = 46
	del_input.add_theme_font_size_override("font_size", ts(17))
	del_input.add_theme_color_override("font_color", CREAM)
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color("1d1510")
	ist.border_color = Color("84754b")
	ist.set_border_width_all(1)
	ist.set_corner_radius_all(4)
	for side in ["left", "right"]: ist.set("content_margin_" + side, 10)
	input_style(del_input, ist)
	del_input.text_changed.connect(func(_t): _refresh_delete())
	del_box.add_child(del_input)
	del_button = button("EXCLUIR MINHA CONTA PARA SEMPRE", 15)
	_style_danger(del_button)
	del_button.pressed.connect(_confirm_delete)
	del_box.add_child(del_button)
	del_status = label("", 14, GOLD, true)
	del_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	del_box.add_child(del_status)
	preload("res://ui_v022/web_text_field.gd").attach(del_input)   # celular: campo HTML real (teclado no iPhone)

func input_style(e: LineEdit, st: StyleBoxFlat):
	e.add_theme_stylebox_override("normal", st)
	e.add_theme_stylebox_override("focus", st)

func _style_danger(b: Button):
	for pair in [["normal", Color("7a1f17")], ["hover", Color("9a2a1f")], ["pressed", Color("5e170f")], ["disabled", Color("2a1512")]]:
		var s := StyleBoxFlat.new()
		s.bg_color = pair[1]
		s.border_color = Color("ff9d86") if pair[0] != "disabled" else Color("5a3a30")
		s.set_border_width_all(2)
		s.set_corner_radius_all(3)
		for side in ["left", "right"]: s.set("content_margin_" + side, 12)
		for side in ["top", "bottom"]: s.set("content_margin_" + side, 8)
		b.add_theme_stylebox_override(pair[0], s)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(k, Color("fff1e6"))
	b.add_theme_color_override("font_disabled_color", Color("8a6a60"))

func show_legal(t := "termos"):
	open()
	set_tab(t)

func set_tab(t: String):
	tab = t
	for k in tab_buttons:
		style_button(tab_buttons[k], k == tab)
		if narrow():   # celular: menos margem para "PRIVACIDADE" caber inteira
			for st_name in ["normal", "hover", "pressed", "disabled"]:
				var st = tab_buttons[k].get_theme_stylebox(st_name)
				if st is StyleBoxFlat:
					st.content_margin_left = 2
					st.content_margin_right = 2
	var is_del := tab == "excluir"
	scroll.visible = not is_del
	del_scroll.visible = is_del
	if not is_del:
		text.text = Legal.termos() if tab == "termos" else Legal.privacidade()
		scroll.scroll_vertical = 0
	else:
		_refresh_delete()

func _nickname() -> String:
	return String(account.nickname()) if account != null and account.has_method("nickname") and account.has_profile() else ""

func _refresh_delete():
	var nick := _nickname()
	if nick.is_empty():
		del_info.text = "Para excluir uma conta, entre nela primeiro (convidados não têm conta para excluir)."
		del_input.visible = false
		del_button.visible = false
		return
	del_input.visible = true
	del_button.visible = true
	del_info.text = ("Excluir a conta é PERMANENTE.\n\n" +
		"Serão apagados: seu e-mail, nome, foto, amigos, pedidos, bloqueios, mensagens privadas, análises, progresso dos bots e personalização. Você não conseguirá mais entrar com esta conta.\n\n" +
		"Ficam, sem nada que identifique você: partidas e placares antigos (aparecem como \"excluido_…\") e registros de pagamento pelo prazo exigido por lei. Fundador, Club e tudo o que foi comprado são PERDIDOS e não voltam se você criar outra conta (compras feitas há menos de 7 dias: peça o reembolso pelo contato ANTES de excluir).\n\n" +
		"Para confirmar, digite o seu nome de jogador: %s" % nick)
	del_button.disabled = deleting or del_input.text.strip_edges().to_lower() != nick.to_lower()

func _confirm_delete():
	if del_button.disabled: return
	deleting = true
	del_status.add_theme_color_override("font_color", GOLD)
	del_status.text = "Excluindo a conta…"
	if account == null or not account.delete_account(del_input.text.strip_edges()):
		deleting = false
		del_status.add_theme_color_override("font_color", RED)
		del_status.text = "Sem conexão com o servidor. Tente de novo em instantes."
	_refresh_delete()

func _on_message(msg: Dictionary):
	match String(msg.get("type", "")):
		"acct_delete_error":
			deleting = false
			del_status.add_theme_color_override("font_color", RED)
			del_status.text = String(msg.get("message", "Não foi possível excluir a conta."))
			_refresh_delete()
		"acct_deleted":
			deleting = false
			del_input.text = ""
			del_status.text = ""
			close()
