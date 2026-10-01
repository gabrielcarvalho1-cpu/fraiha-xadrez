extends Button
## Entrada do CLUB FRAIHA na Home: fita dourada pendurada no cartão de perfil (desktop) ou
## linha própria no menu do celular. Separada dos botões do menu; abre direto a página do Club.
## Inativo: "CLUB FRAIHA · Jogue. Analise. Evolua."   Ativo: "♛ CLUB ATIVO".
const Art := preload("res://monetization/premium_art.gd")

var active := false
var compact := false   # celular: fita mais baixa, texto menor
var t := 0.0

func _init():
    name = "ClubHomeEntry"
    text = "CLUB FRAIHA"
    tooltip_text = "Club FRAIHA"
    focus_mode = Control.FOCUS_ALL
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
    for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
        add_theme_color_override(c, Color(0, 0, 0, 0))

func set_active(value: bool):
    if active == value: return
    active = value
    text = "CLUB ATIVO" if active else "CLUB FRAIHA"
    queue_redraw()

func _process(delta):
    if is_visible_in_tree():
        t += delta
        queue_redraw()

func _notification(what):
    if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]: queue_redraw()

func _draw():
    var lit := is_hovered() or has_focus()
    var w := size.x
    var h := size.y
    var notch := minf(h * 0.42, 14.0)
    # Fita com pontas em "V" (como os estandartes da Home).
    var pts := PackedVector2Array([Vector2(notch, 0), Vector2(w - notch, 0), Vector2(w, h / 2.0), Vector2(w - notch, h), Vector2(notch, h), Vector2(0, h / 2.0)])
    var top := Color("1d4a2a") if active else Color("102617")
    var bottom := Color("0a2212") if active else Color("06110a")
    if lit:
        top = top.lightened(0.14)
    var cols := PackedColorArray()
    for p in pts: cols.append(top.lerp(bottom, clampf(p.y / maxf(1.0, h), 0.0, 1.0)))
    # sombra
    draw_colored_polygon(_shift(pts, Vector2(0, 3)), Color(0, 0, 0, 0.45))
    draw_polygon(pts, cols)
    var rim := Color("f1d58a") if (lit or active) else Color("c99a45")
    var line := pts.duplicate()
    line.append(line[0])
    draw_polyline(line, rim, 2.0)
    var inner := PackedVector2Array([Vector2(notch + 2, 4), Vector2(w - notch - 2, 4), Vector2(w - 5, h / 2.0), Vector2(w - notch - 2, h - 4), Vector2(notch + 2, h - 4), Vector2(5, h / 2.0)])
    inner.append(inner[0])
    draw_polyline(inner, Color(rim.r, rim.g, rim.b, 0.35), 1.0)
    # brilho que percorre a fita (ativo: mais vivo)
    var x := fmod(t * (170.0 if active else 110.0), w + 200.0) - 100.0
    draw_colored_polygon(PackedVector2Array([Vector2(x, 2), Vector2(x + 26, 2), Vector2(x + 6, h - 2), Vector2(x - 20, h - 2)]), Color(1, 0.92, 0.6, 0.14 if active else 0.08))
    # coroa
    var cs := h * 0.74
    var crown_rect := Rect2(Vector2(notch + 6.0, (h - cs) / 2.0), Vector2(cs, cs))
    var pulse := 0.5 + 0.5 * sin(t * 2.6)
    if active:
        draw_circle(crown_rect.get_center(), cs * 0.62, Color(1.0, 0.85, 0.4, 0.10 + 0.10 * pulse))
    Art.icon(self, "crown", crown_rect, Color("ffe6a0") if (active or lit) else Color("f6d27a"))
    # textos
    var fx := crown_rect.end.x + 10.0
    var room := w - fx - notch - 8.0
    var title := "CLUB ATIVO" if active else "CLUB FRAIHA"
    var tfs := Art.fit(Art.FONT_BOLD, title, 17 if compact else 19, room, 11)
    var sub := "Jogue. Analise. Evolua." if not active else "Análises ilimitadas · moldura premium"
    var f := get_theme_default_font()
    var sfs := Art.fit(f, sub, 12 if compact else 13, room, 9)
    var two_lines := h >= 40.0
    var ty := (h * 0.46 if two_lines else h * 0.5 + tfs * 0.36)
    if two_lines: ty = h * 0.42 + tfs * 0.32
    draw_string_outline(Art.FONT_BOLD, Vector2(fx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 4, Color(0.1, 0.05, 0.0, 0.85))
    draw_string(Art.FONT_BOLD, Vector2(fx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color("ffe6a0") if (lit or active) else Color("f6d27a"))
    if two_lines:
        draw_string(f, Vector2(fx, h * 0.82 + 1), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color("bfe8a8") if active else Color("e6dcc0"))
    else:
        var tw := Art.FONT_BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
        draw_string(f, Vector2(fx + tw + 10.0, ty), "· " + sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color("bfe8a8") if active else Color("e6dcc0"))
    # selo "✓" quando ativo
    if active:
        var ck := Rect2(Vector2(w - notch - h * 0.62 - 4.0, (h - h * 0.5) / 2.0), Vector2(h * 0.5, h * 0.5))
        draw_circle(ck.get_center(), ck.size.x * 0.62, Color(0.10, 0.36, 0.18, 0.95))
        draw_arc(ck.get_center(), ck.size.x * 0.62, 0, TAU, 24, Color("8fe08a"), 1.5)
        Art.icon(self, "check", ck, Color("eaffd8"))

static func _shift(p: PackedVector2Array, d: Vector2) -> PackedVector2Array:
    var out := PackedVector2Array()
    for v in p: out.append(v + d)
    return out
