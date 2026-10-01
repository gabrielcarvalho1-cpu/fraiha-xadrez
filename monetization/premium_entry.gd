extends Button
## Entrada "FRAIHA PREMIUM" dentro de CONFIGURAÇÕES: coroa, moldura dourada, brilho e selo NOVO.
const Art := preload("res://monetization/premium_art.gd")

var t := 0.0
var show_new := true   # selo "NOVO" enquanto a Monetização V1 estiver em teste

func _init():
    name = "PremiumEntry"
    text = "FRAIHA PREMIUM"
    tooltip_text = ""
    custom_minimum_size = Vector2(0, 92)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    focus_mode = Control.FOCUS_ALL
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
    for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
        add_theme_color_override(c, Color(0, 0, 0, 0))

func _process(delta):
    if is_visible_in_tree():
        t += delta
        queue_redraw()

func _draw():
    var lit := is_hovered() or has_focus()
    var r := Rect2(Vector2(0, 8), size - Vector2(0, 8))
    # Fundo preto/verde com gradiente e borda dourada dupla.
    var top := Color("1a2a14") if lit else Color("0f1d10")
    var bottom := Color("050a06")
    var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
    draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))
    draw_rect(r, Color("e2b65a") if lit else Color("c99a45"), false, 2.5)
    draw_rect(r.grow(-5), Color(0.95, 0.8, 0.45, 0.30), false, 1.0)
    # Brilho que passa.
    var x := fmod(t * 140.0, r.size.x + 260.0) - 130.0
    draw_colored_polygon(PackedVector2Array([Vector2(x, r.position.y + 3), Vector2(x + 40, r.position.y + 3), Vector2(x + 10, r.end.y - 3), Vector2(x - 30, r.end.y - 3)]), Color(1, 0.9, 0.6, 0.10))
    for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
        Art.diamond(self, c, 5.0, Color("f1d58a"))
    # Brasão com coroa.
    var ib := Rect2(Vector2(14, r.position.y + (r.size.y - 60) / 2.0), Vector2(60, 60))
    var pulse := 0.5 + 0.5 * sin(t * 2.2)
    draw_circle(ib.get_center(), 30, Color(0.02, 0.05, 0.03))
    draw_arc(ib.get_center(), 29, 0, TAU, 36, Color(0.95, 0.78, 0.35, 0.7 + 0.3 * pulse), 2.0)
    Art.icon(self, "crown", ib.grow(-12), Color("f6d27a"))
    # Textos.
    var fx := ib.end.x + 14.0
    var room := size.x - fx - 34.0
    var fs := Art.fit(Art.FONT_BOLD, "FRAIHA PREMIUM", 24, room, 14)
    var title_y := r.position.y + r.size.y * 0.44
    draw_string_outline(Art.FONT_BOLD, Vector2(fx, title_y), "FRAIHA PREMIUM", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.12, 0.06, 0.0, 0.9))
    draw_string(Art.FONT_BOLD, Vector2(fx, title_y), "FRAIHA PREMIUM", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffe6a0") if lit else Color("f6d27a"))
    var sub := "Pacote Fundador  ·  Club FRAIHA"
    var f := get_theme_default_font()
    var ss := Art.fit(f, sub, 15, room, 11)
    draw_string(f, Vector2(fx, r.position.y + r.size.y * 0.78), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color("e6dcc0"))
    # Seta.
    var ax := size.x - 20.0
    var ay := r.get_center().y
    draw_polyline(PackedVector2Array([Vector2(ax - 8, ay - 10), Vector2(ax, ay), Vector2(ax - 8, ay + 10)]), Color("f1d58a"), 3.0)
    # Selo NOVO no canto.
    if show_new:
        var label := "NOVO"
        var nf := 13
        var w := Art.FONT_BOLD.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, nf).x + 18.0
        var nr := Rect2(Vector2(size.x - w - 34.0, 0), Vector2(w, 22))
        draw_rect(nr, Color("f6c85a"))
        draw_rect(nr, Color("6e4b18"), false, 1.5)
        draw_string(Art.FONT_BOLD, Vector2(nr.position.x + 9, nr.position.y + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, nf, Color("3a2408"))
