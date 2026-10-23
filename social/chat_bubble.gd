extends PanelContainer
## R180e · balão de MENSAGEM de texto na partida (celular): aparece perto do cartão de quem mandou por alguns
## segundos, no lugar da janela grande do chat (que não abre mais no celular — só a barra de digitar).

const FONT := preload("res://account/fonts/Cinzel-Bold.woff")
const BODY := preload("res://ui_kit/fonts/Alegreya-Bold.woff")

static func make(who: String, text: String, max_w: float, mine: bool) -> PanelContainer:
	var b = load("res://social/chat_bubble.gd").new()
	b._build(who, text, max_w, mine)
	return b

func _build(who: String, text: String, max_w: float, mine: bool) -> void:
	name = "ChatBubble"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.09, 0.2, 0.95) if not mine else Color(0.12, 0.09, 0.04, 0.95)
	st.border_color = Color("c99a45")
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 6
	for side in ["left", "right"]: st.set("content_margin_" + side, 10)
	for side in ["top", "bottom"]: st.set("content_margin_" + side, 6)
	add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var n := Label.new()
	n.text = ("VOCÊ" if mine else who.to_upper()).left(24)
	n.add_theme_font_override("font", FONT)
	n.add_theme_font_size_override("font_size", 12)
	n.add_theme_color_override("font_color", Color("f4ce7f"))
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(n)
	var t := Label.new()
	t.text = text.left(200)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.max_lines_visible = 4
	t.add_theme_font_override("font", BODY)
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", Color("f3ede0"))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := minf(max_w, BODY.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 4.0)
	w = maxf(w, FONT.get_string_size(n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 4.0)
	var hh := BODY.get_multiline_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, w, 16, 4).y
	t.custom_minimum_size = Vector2(w, maxf(hh, BODY.get_height(16)) + 2.0)
	col.add_child(t)
	reset_size()

## some depois de alguns segundos (mais tempo para texto longo)
func play(tree_owner: Node) -> void:
	modulate.a = 0.0
	var tw := tree_owner.create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.tween_interval(clampf(2.5 + get_child(0).get_child(1).text.length() * 0.06, 3.0, 7.0))
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
