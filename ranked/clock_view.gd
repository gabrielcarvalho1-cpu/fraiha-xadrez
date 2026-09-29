extends PanelContainer
## Visual do relógio (separado da lógica, preparado para skins futuras).
var label: Label
var style: StyleBoxFlat
var is_active := false
var low := false

func _init():
    style = StyleBoxFlat.new()
    style.set_corner_radius_all(6)
    style.set_border_width_all(1)
    style.content_margin_left = 10
    style.content_margin_right = 10
    style.content_margin_top = 2
    style.content_margin_bottom = 2
    add_theme_stylebox_override("panel", style)
    label = Label.new()
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", 22)
    add_child(label)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _restyle()

func set_font_size(size: int):
    label.add_theme_font_size_override("font_size", size)

func show_time(ms: int, active: bool):
    label.text = preload("res://ranked/clock_state.gd").format(ms)
    var now_low = ms < 30000
    if active != is_active or now_low != low:
        is_active = active
        low = now_low
        _restyle()

func _restyle():
    # Relógio da vez: destaque discreto; tempo baixo: tom avermelhado.
    style.bg_color = Color("f1e3b8") if is_active else Color(0.05, 0.08, 0.07, 0.85)
    style.border_color = Color("e5c37c") if is_active else Color("5d6b58")
    var text = Color("1b1a14") if is_active else Color("d9d2bd")
    if low: text = Color("b3261e") if is_active else Color("ff9d86")
    label.add_theme_color_override("font_color", text)
