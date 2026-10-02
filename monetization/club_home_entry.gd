extends Button
## Entrada do CLUB FRAIHA na Home: placa de OURO maciço no canto superior esquerdo do HUD (desktop)
## ou no topo do menu do celular. Separada dos botões do menu; abre direto a página do Club.
## Inativo: "CLUB FRAIHA · Jogue. Analise. Evolua."   Ativo: "CLUB ATIVO · Análises ilimitadas".
## Visual: moldura dourada metálica (gradiente + bisel), interior verde profundo, medalhão com
## coroa, brilho percorrendo o ouro e, quando ativo, selo dourado com ✓ e faíscas.
const Art := preload("res://monetization/premium_art.gd")

var active := false
var compact := false   # celular: fita mais baixa, texto menor
var t := 0.0

# Gradiente metálico do ouro (de cima para baixo)
const GOLD_STOPS := [
    [0.00, Color("fff3cf")], [0.18, Color("f3d98a")], [0.42, Color("c99a45")],
    [0.50, Color("8f6a22")], [0.56, Color("d8b35a")], [0.80, Color("c99a45")], [1.00, Color("6e4b18")]]

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

func _gui_input(event):
    if event is InputEventMouseButton or event is InputEventScreenTouch: queue_redraw()

static func gold_at(k: float, lit := false) -> Color:
    k = clampf(k, 0.0, 1.0)
    for i in range(GOLD_STOPS.size() - 1):
        var a: Array = GOLD_STOPS[i]
        var b: Array = GOLD_STOPS[i + 1]
        if k <= float(b[0]):
            var c: Color = (a[1] as Color).lerp(b[1], (k - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])))
            return c.lightened(0.12) if lit else c
    return GOLD_STOPS[-1][1]

## Hexágono da fita: pontas em "V" nas laterais. inset = margem para dentro.
static func ribbon(w: float, h: float, notch: float, inset: float) -> PackedVector2Array:
    var n := maxf(0.0, notch - inset * 0.6)
    return PackedVector2Array([
        Vector2(inset + n, inset), Vector2(w - inset - n, inset), Vector2(w - inset, h / 2.0),
        Vector2(w - inset - n, h - inset), Vector2(inset + n, h - inset), Vector2(inset, h / 2.0)])

## Largura da fita numa linha y (para pintar o gradiente em faixas horizontais).
static func span(w: float, h: float, notch: float, y: float) -> Vector2:
    var k := absf(y - h / 2.0) / (h / 2.0)
    return Vector2(notch * k, w - notch * k)

func _draw():
    var lit := is_hovered() or has_focus()
    var down := button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
    if down: draw_set_transform(Vector2(0, 2))   # pressionado: a placa "afunda" 2 px
    var w := size.x
    var h := size.y
    var notch := minf(h * 0.42, 15.0)
    var border := 4.0 if compact else 5.0
    var pulse := 0.5 + 0.5 * sin(t * 2.4)
    # halo (ativo: pulsando)
    if active or lit:
        for i in 3:
            var g := 3.0 + i * 3.0
            var a := (0.16 - i * 0.045) * (0.6 + 0.4 * pulse)
            _draw_shifted(ribbon(w + g * 2.0, h + g * 2.0, notch + g * 0.4, 0.0), Vector2(-g, -g), Color(1.0, 0.86, 0.45, a))
    # sombra + contorno escuro externo (descola a placa do fundo da floresta)
    _draw_shifted(ribbon(w, h, notch, 0.0), Vector2(0, 0 if down else 4), Color(0, 0, 0, 0.55))
    _draw_shifted(ribbon(w + 4.0, h + 4.0, notch + 1.0, 0.0), Vector2(-2, -2), Color("2a1a05"))
    # ouro maciço: faixas horizontais com gradiente metálico
    var y := 0.0
    while y < h:
        var y2 := minf(h, y + 2.0)
        var sp := span(w, h, notch, (y + y2) / 2.0)
        draw_rect(Rect2(sp.x, y, sp.y - sp.x, y2 - y), gold_at(y / h, lit))
        y = y2
    # bisel: luz em cima, sombra embaixo
    var outer := ribbon(w, h, notch, 0.0)
    draw_line(outer[0] + Vector2(0, 1), outer[1] + Vector2(0, 1), Color(1, 1, 0.9, 0.55), 1.5)
    draw_line(outer[4] - Vector2(0, 1), outer[3] - Vector2(0, 1), Color(0.25, 0.15, 0.02, 0.6), 1.5)
    var rim := outer.duplicate()
    rim.append(rim[0])
    draw_polyline(rim, Color("5a3d10"), 1.2)
    # interior verde profundo (gradiente vertical) emoldurado pelo ouro
    var inner := ribbon(w, h, notch, border)
    var top := Color("1f5a30") if active else Color("12331c")
    var bottom := Color("07180c")
    if lit: top = top.lightened(0.10)
    var cols := PackedColorArray()
    for p in inner: cols.append(top.lerp(bottom, clampf((p.y - border) / maxf(1.0, h - border * 2.0), 0.0, 1.0)))
    draw_polygon(inner, cols)
    var hair := inner.duplicate()
    hair.append(hair[0])
    draw_polyline(hair, Color(0.35, 0.2, 0.03, 0.9), 1.0)
    var hair2 := ribbon(w, h, notch, border + 2.0)
    hair2.append(hair2[0])
    draw_polyline(hair2, Color(0.95, 0.84, 0.54, 0.35), 1.0)
    # brilho que percorre o ouro
    var x := fmod(t * (150.0 if active else 95.0), w + 220.0) - 110.0
    draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 34, 0), Vector2(x + 10, h), Vector2(x - 24, h)]), Color(1, 0.97, 0.8, 0.16 if active else 0.10))
    # cravos dourados nas pontas da placa
    for tip in [Vector2(border * 0.9, h / 2.0), Vector2(w - border * 0.9, h / 2.0)]:
        draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -4), tip + Vector2(4, 0), tip + Vector2(0, 4), tip + Vector2(-4, 0)]), Color("fff3cf"))
        draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -2), tip + Vector2(2, 0), tip + Vector2(0, 2), tip + Vector2(-2, 0)]), Color("8f6a22"))
    if down: draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.12))
    # medalhão com coroa (esquerda)
    var ms := h - border * 2.0 - 2.0
    var mc := Vector2(notch + border + ms / 2.0 - 2.0, h / 2.0)
    for i in 4:
        var rr := ms / 2.0 - i * (ms / 10.0)
        draw_circle(mc, rr, gold_at(0.15 + i * 0.22, lit))
    draw_circle(mc, ms / 2.0 - 2.0, Color("0b2416"))
    draw_arc(mc, ms / 2.0 - 2.0, 0, TAU, 32, Color("f1d58a"), 1.0)
    if active:
        draw_circle(mc, ms * 0.36, Color(1.0, 0.85, 0.4, 0.10 + 0.14 * pulse))
    Art.icon(self, "crown", Rect2(mc - Vector2(ms, ms) * 0.31, Vector2(ms, ms) * 0.62), Color("ffe6a0"))
    # ramos de louro em volta do medalhão
    for side in [-1.0, 1.0]:
        for i in 4:
            var ang := deg_to_rad(110.0 + i * 24.0) if side < 0 else deg_to_rad(70.0 - i * 24.0)
            var lp := mc + Vector2(cos(ang), sin(ang)) * (ms / 2.0 + 1.0)
            draw_circle(lp, 1.8, Color("d8b35a"))
    # textos
    var fx := mc.x + ms / 2.0 + 8.0
    var right_pad := notch + border + (h * 0.55 + 10.0 if active else 6.0)
    var room := w - fx - right_pad
    var title := "CLUB ATIVO" if active else "CLUB FRAIHA"
    var tfs := Art.fit(Art.FONT_BOLD, title, 16 if compact else 18, room, 11)
    var sub := "Jogue. Analise. Evolua." if not active else "Análises ilimitadas · moldura premium"
    var f := get_theme_default_font()
    var sfs := Art.fit(f, sub, 11 if compact else 12, room, 9)
    var two_lines := h >= 40.0
    var ty := (h * 0.42 + tfs * 0.32) if two_lines else (h * 0.5 + tfs * 0.36)
    draw_string_outline(Art.FONT_BOLD, Vector2(fx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 4, Color(0.05, 0.03, 0.0, 0.9))
    draw_string(Art.FONT_BOLD, Vector2(fx, ty - 1), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color("fff1c4"))
    draw_string(Art.FONT_BOLD, Vector2(fx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color("f6d27a") if not lit else Color("ffe6a0"))
    if two_lines:
        draw_string(f, Vector2(fx, h * 0.80 + 1), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color("d9f0c6") if active else Color("e6dcc0"))
    else:
        var tw := Art.FONT_BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
        draw_string(f, Vector2(fx + tw + 10.0, ty), "· " + sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color("d9f0c6") if active else Color("e6dcc0"))
    # selo dourado "✓" quando ativo + faíscas
    if active:
        var ss := h * 0.55
        var sc := Vector2(w - notch - border - ss / 2.0 - 2.0, h / 2.0)
        draw_circle(sc + Vector2(0, 1), ss / 2.0 + 1.0, Color(0, 0, 0, 0.4))
        for i in 3:
            draw_circle(sc, ss / 2.0 - i * (ss / 8.0), gold_at(0.1 + i * 0.3, lit))
        Art.icon(self, "check", Rect2(sc - Vector2(ss, ss) * 0.28, Vector2(ss, ss) * 0.56), Color("1a3a12"))
        for i in 5:
            var ph := t * 1.7 + i * 1.3
            var a := 0.5 + 0.5 * sin(ph)
            if a < 0.35: continue
            var px := notch + 10.0 + fmod(i * 61.7 + t * 9.0, maxf(1.0, w - notch * 2.0 - 20.0))
            var py := border * 0.5 if i % 2 == 0 else h - border * 0.5   # só sobre o ouro, nunca sobre o texto
            Art.star(self, Vector2(px, py), 1.5 + 1.8 * a, Color(1.0, 0.98, 0.85, 0.8 * a))

func _draw_shifted(p: PackedVector2Array, d: Vector2, col: Color):
    var out := PackedVector2Array()
    for v in p: out.append(v + d)
    draw_colored_polygon(out, col)
