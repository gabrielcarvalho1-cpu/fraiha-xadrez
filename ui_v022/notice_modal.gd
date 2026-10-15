extends "res://ui_v022/home_modal.gd"
## R104 · aviso importante na moldura do jogo (ex.: CONTA SUSPENSA). Título na placa, texto no meio e ENTENDI.
## R123 · o texto fica num cartão centralizado (letra maior), em vez de solto num painel enorme e vazio.

var text_label: Label
var card: PanelContainer
var ok_button: Button

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
	col.add_child(ok_button)

func show_notice(title: String, text: String):
	title_label.text = title
	text_label.text = text
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
	text_label.custom_minimum_size.x = w - 72.0
	text_label.add_theme_font_size_override("font_size", ts(26) if not narrow() else 16)
	ok_button.add_theme_font_size_override("font_size", ts(22) if not narrow() else 16)
	ok_button.custom_minimum_size = Vector2(ts(300) if not narrow() else 200, ts(58) if not narrow() else 46)
