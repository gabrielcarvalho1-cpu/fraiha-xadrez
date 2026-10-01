extends Control
## Plaqueta do topo da partida contra o BOT: "ADVERSÁRIO · BOT <nível>" com marcadores de
## dificuldade, divisor com losango e "VOCÊ JOGA DE" + peça do rei + cor. Só apresentação.
const GOLD := Color("f4ce7f")
const GOLD_DIM := Color("b99555")
const CREAM := Color("f1e4c2")
const MUTED := Color("b9b08f")
const LEVELS := ["easy", "medium", "hard", "expert"]
var level_id := "easy"
var level_name := "FÁCIL"
var side_name := "BRANCAS"
var king: Texture2D

func _init():
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_info(level: String, level_label: String, side_label: String, king_texture: Texture2D):
    level_id = level
    level_name = level_label.to_upper()
    side_name = side_label.to_upper()
    king = king_texture
    custom_minimum_size = Vector2(_content_width(), 62)
    size = custom_minimum_size
    queue_redraw()

func _font() -> Font:
    return get_theme_default_font()

func _left_width() -> float:
    var f := _font()
    return maxf(f.get_string_size("ADVERSÁRIO", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, f.get_string_size(_main_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + (60.0 if level_id in LEVELS else 8.0))

## Bots da escada já trazem o nome completo ("BOT MADEIRA"); níveis antigos recebem o prefixo.
func _main_text() -> String:
    return level_name if level_name.begins_with("BOT ") else "BOT " + level_name

func _right_width() -> float:
    var f := _font()
    return maxf(f.get_string_size("VOCÊ JOGA DE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, f.get_string_size(side_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 32.0)

func _content_width() -> float:
    return 34.0 + _left_width() + 44.0 + _right_width() + 34.0

func _draw():
    var f := _font()
    var rect := Rect2(Vector2.ZERO, size)
    var body := StyleBoxFlat.new()
    body.bg_color = Color(0.06, 0.13, 0.09, 0.94)
    body.border_color = GOLD_DIM
    body.set_border_width_all(2)
    body.set_corner_radius_all(10)
    body.shadow_color = Color(0, 0, 0, 0.5)
    body.shadow_size = 8
    body.shadow_offset = Vector2(0, 3)
    draw_style_box(body, rect)
    # Filete interno e pontas em losango (plaqueta).
    var inner := StyleBoxFlat.new()
    inner.draw_center = false
    inner.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.28)
    inner.set_border_width_all(1)
    inner.set_corner_radius_all(7)
    draw_style_box(inner, rect.grow(-5))
    for x in [0.0, size.x]:
        var c := Vector2(x, size.y / 2.0)
        draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)]), GOLD)
        draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), Color("3a2a12"))
    var x0 := 34.0
    draw_string(f, Vector2(x0, 23), "ADVERSÁRIO", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
    var main := _main_text()
    draw_string_outline(f, Vector2(x0, 47), main, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, 4, Color("0b150f"))
    draw_string(f, Vector2(x0, 47), main, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, GOLD)
    # Marcadores de nível: losangos cheios até a dificuldade escolhida.
    var filled := LEVELS.find(level_id) + 1
    var px := x0 + f.get_string_size(main, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 14.0
    for i in (4 if level_id in LEVELS else 0):
        var c := Vector2(px + i * 13.0, 40.0)
        var pts := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
        if i < filled: draw_colored_polygon(pts, GOLD)
        else: draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(GOLD.r, GOLD.g, GOLD.b, 0.45), 1.5)
    # Divisor vertical com losango.
    var dx := x0 + _left_width() + 22.0
    draw_line(Vector2(dx, 12), Vector2(dx, size.y - 12), Color(GOLD.r, GOLD.g, GOLD.b, 0.45), 1.5)
    var dc := Vector2(dx, size.y / 2.0)
    draw_colored_polygon(PackedVector2Array([dc + Vector2(0, -5), dc + Vector2(5, 0), dc + Vector2(0, 5), dc + Vector2(-5, 0)]), GOLD)
    var x1 := dx + 22.0
    draw_string(f, Vector2(x1, 23), "VOCÊ JOGA DE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
    if king != null:
        draw_texture_rect(king, Rect2(x1 - 2, 27, 26, 26), false)
    draw_string_outline(f, Vector2(x1 + 30, 47), side_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, 4, Color("0b150f"))
    draw_string(f, Vector2(x1 + 30, 47), side_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, CREAM)
