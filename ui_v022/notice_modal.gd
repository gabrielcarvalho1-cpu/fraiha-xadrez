extends "res://ui_v022/home_modal.gd"
## R104 · aviso importante na moldura do jogo (ex.: CONTA SUSPENSA). Título na placa, texto no meio e ENTENDI.
## R123 · o texto fica num cartão centralizado (letra maior), em vez de solto num painel enorme e vazio.

var text_label: Label
var card: PanelContainer
var ok_button: Button
var yes_button: Button      # R124 · pergunta com SIM / NÃO (ex.: ir para o Discord)
var _yes_action: Callable

func setup(p_hub, title: String):
	build(p_hub, title)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	card = PanelContainer.new()
	card.name = "NoticeCard"
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.051, 0.094, 0.196, 0.96)
	st.border_color = Color("c99a45")
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 8
	for side in ["left", "right"]: st.set("content_margin_" + side, 36)
	for side in ["top", "bottom"]: st.set("content_margin_" + side, 30)
	card.add_theme_stylebox_override("panel", st)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	card.add_child(col)
	text_label = label("", 26, CREAM, true)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.add_theme_constant_override("line_spacing", 6)
	text_label.name = "NoticeText"
	col.add_child(text_label)
	ok_button = button("ENTENDI", 22, true)
	ok_button.name = "NoticeOk"
	ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_button.pressed.connect(close)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	yes_button = button("ABRIR", 22, true)
	yes_button.name = "NoticeYes"
	yes_button.pressed.connect(func():
		close()
		if _yes_action.is_valid(): _yes_action.call())
	row.add_child(yes_button)
	col.remove_child(ok_button)
	row.add_child(ok_button)
	yes_button.hide()

func show_notice(title: String, text: String):
	title_label.text = title
	text_label.text = text
	yes_button.hide()
	ok_button.text = "ENTENDI"
	style_button(ok_button, true)
	open()
	_fit_card()

## R124 · pergunta: botão principal (yes_text) faz a ação; o outro só fecha.
func ask(title: String, text: String, yes_text: String, no_text: String, action: Callable):
	title_label.text = title
	text_label.text = text
	_yes_action = action
	yes_button.text = yes_text
	yes_button.show()
	ok_button.text = no_text
	style_button(ok_button, false)
	open()
	_fit_card()

func _layout():
	super._layout()
	_fit_card()

## largura do cartão: até 860 px no PC (proporcional), a largura toda no celular
func _fit_card():
	if card == null or _body_rect.size == Vector2.ZERO: return
	var w := minf(_body_rect.size.x - 8.0, maxf(280.0, _body_rect.size.x * 0.62))
	if narrow(): w = _body_rect.size.x - 8.0
	var m := 36 if not narrow() else 14   # celular: margens menores (os dois botões cabem no cartão)
	var st: StyleBoxFlat = card.get_theme_stylebox("panel")
	for side in ["left", "right"]: st.set("content_margin_" + side, m)
	text_label.custom_minimum_size.x = w - 2.0 * m
	text_label.add_theme_font_size_override("font_size", ts(26) if not narrow() else 16)
	ok_button.add_theme_font_size_override("font_size", ts(22) if not narrow() else 16)
	var bw: int = (ts(300) if not narrow() else 200) if not yes_button.visible else (ts(240) if not narrow() else int((w - 2.0 * m - 12.0) / 2.0))
	for b in [ok_button, yes_button]:
		b.add_theme_font_size_override("font_size", ts(22) if not narrow() else 14)
		b.custom_minimum_size = Vector2(bw, ts(58) if not narrow() else 46)
