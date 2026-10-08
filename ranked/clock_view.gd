extends PanelContainer
## Visual do relógio (separado da lógica, preparado para skins futuras).
var label: Label
var style: StyleBoxFlat
var is_active := false
var low := false

var pulse := 0.0
## R49 · pele da arte de referência: a ampulheta e a moldura já estão na arte; só os dígitos (cor = estado).
var bare := false

func _init():
    style = StyleBoxFlat.new()
    style.set_corner_radius_all(8)
    style.set_border_width_all(2)
    style.shadow_color = Color(0, 0, 0, 0.45)
    style.shadow_size = 5
    style.content_margin_left = 30
    style.content_margin_right = 12
    style.content_margin_top = 2
    style.content_margin_bottom = 2
    add_theme_stylebox_override("panel", style)
    label = Label.new()
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", 22)
    label.add_theme_font_override("font", preload("res://account/fonts/Cinzel-Bold.woff"))
    label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
    label.add_theme_constant_override("outline_size", 4)
    add_child(label)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _restyle()

func set_bare(on: bool):
    if bare == on: return
    bare = on
    add_theme_stylebox_override("panel", StyleBoxEmpty.new() if on else style)
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

func _process(delta):
    if is_active:
        pulse += delta
        queue_redraw()

func _draw():
    if bare: return
    # Ampulheta dourada à esquerda; gira suavemente quando o relógio está correndo.
    var c := Vector2(16, size.y / 2.0)
    var h := minf(size.y * 0.5, 20.0)
    var col := Color("ff7a5c") if (low and is_active) else (Color("f6d27a") if is_active else Color("9a906f"))
    var ang := sin(pulse * 2.0) * 0.12 if is_active else 0.0
    draw_set_transform(c, ang, Vector2.ONE)
    # R52e · triângulos em draw_primitive (mesmo desenho): o relógio ativo redesenha todo quadro e, na Web,
    # draw_colored_polygon criaria buffers de GPU novos a cada quadro.
    var w := h * 0.55
    draw_line(Vector2(-w, -h / 2), Vector2(w, -h / 2), col, 2.0)
    draw_line(Vector2(-w, h / 2), Vector2(w, h / 2), col, 2.0)
    draw_primitive(PackedVector2Array([Vector2(-w * 0.8, -h / 2 + 2), Vector2(w * 0.8, -h / 2 + 2), Vector2(0, 0)]), PackedColorArray([Color(col, 0.85), Color(col, 0.85), Color(col, 0.85)]), PackedVector2Array())
    draw_primitive(PackedVector2Array([Vector2(0, 1), Vector2(w * 0.8, h / 2 - 2), Vector2(-w * 0.8, h / 2 - 2)]), PackedColorArray([Color(col, 0.55), Color(col, 0.55), Color(col, 0.55)]), PackedVector2Array())
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if is_active:
        var glow := 0.5 + 0.5 * sin(pulse * (8.0 if low else 3.0))
        draw_rect(Rect2(Vector2.ZERO, size).grow(2), Color(col, 0.15 + 0.25 * glow), false, 2.0)

func _restyle():
    # Placa verde e ouro; da vez: dourada e viva; tempo baixo: vermelha pulsando.
    style.bg_color = Color("123a24") if is_active else Color(0.04, 0.09, 0.06, 0.88)
    style.border_color = Color("f1d58a") if is_active else Color("6e5a2a")
    if low and is_active:
        style.bg_color = Color("4a1410")
        style.border_color = Color("ff7a5c")
    var text = Color("fff1c4") if is_active else Color("b9b08f")
    if bare: text = Color("ffe9a8") if is_active else Color("f3ede0")   # arte: dígitos claros; da vez, dourado
    if low: text = Color("ffb3a1") if is_active else Color("ff9d86")
    label.add_theme_color_override("font_color", text)
    queue_redraw()
