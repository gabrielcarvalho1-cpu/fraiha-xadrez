extends Button
## Entrada do CLUB FRAIHA na Home: placa de OURO maciço no canto superior esquerdo do HUD (desktop)
## ou no topo do menu do celular. Separada dos botões do menu; abre direto a página do Club.
## Inativo: "CLUB FRAIHA · Jogue. Analise. Evolua."   Ativo: "CLUB ATIVO · Análises ilimitadas".
## Visual: moldura dourada metálica (gradiente + bisel), interior verde profundo, medalhão com
## coroa, brilho percorrendo o ouro e, quando ativo, selo dourado com ✓ e faíscas.
const Art := preload("res://monetization/premium_art.gd")

var active := false
var compact := false   # celular: fita mais baixa, texto menor
## R36 · Home v7: a placa (moldura de madeira/ouro e medalhão com coroa) é da própria arte de referência;
## aqui só entram os textos vivos, o selo ✓ (ativo) ou a seta (inativo) e o brilho do hover.
var over_art := false
## R47 · medidas do texto sobre a placa da arte (padrão = Home do PC; a Home do celular troca:
## só o título, maior, e a seta na ponta da placa do celular).
var art_tx := 79.0
var art_title_y := 31.0
var art_title_size := 23
var art_title_room := 196.0
var art_sub := true
var art_sub_y := 50.0
var art_seal := Vector2(291, 30)
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

## R52f · Animação sem redesenho por quadro (Web: cada redesenho recriava os polígonos/círculos da placa como
## buffers novos de GPU — no celular deitado a placa procedural redesenhava todo quadro: ~56 buffers/quadro).
## A placa é dividida em camadas desenhadas UMA vez (só redesenham quando o estado visual muda: ativo, hover/foco,
## clique, tamanho). O que anima — brilho que percorre o ouro, halo e brilho do medalhão pulsando, faíscas e o
## pulso do selo — são nós próprios movidos/esmaecidos por position / scale / modulate, que não redesenham.
## Ordem de pintura idêntica à anterior (halo atrás; base; brilho; meio; brilho do medalhão; frente; faíscas).
var _halo: Node2D        # atrás de tudo (show_behind_parent)
var _shine: Node2D       # brilho que percorre o ouro (desenhado uma vez, só anda em x)
var _mid: Node2D         # cravos, sombra do clique, aros e fundo do medalhão
var _glow: Node2D        # brilho pulsante do medalhão (ativo)
var _front: Node2D       # coroa, louros, textos, selo ✓ (ativo)
var _sparks: Array = []  # 5 faíscas (ativo)
var _seal_pulse: Node2D  # placa da arte: pulso do selo (ativo)
var _seal_top: Node2D    # placa da arte: arco de luz e ✓ por cima do pulso
var _state := []

func set_active(value: bool):
    if active == value: return
    active = value
    text = "CLUB ATIVO" if active else "CLUB FRAIHA"
    _refresh()

func _ready():
    _build_layers()
    _refresh()

func _layer(n: String, painter: Callable, behind := false) -> Node2D:
    var l := Node2D.new()
    l.name = n
    l.show_behind_parent = behind
    l.draw.connect(painter.bind(l))
    add_child(l, false, Node.INTERNAL_MODE_FRONT if behind else Node.INTERNAL_MODE_BACK)
    return l

func _build_layers():
    if _shine != null: return
    _halo = _layer("Halo", _paint_halo, true)
    _shine = _layer("Shine", _paint_shine)
    _mid = _layer("Mid", _paint_mid)
    _glow = _layer("Glow", _paint_glow)
    _front = _layer("Front", _paint_front)
    for i in 5: _sparks.append(_layer("Spark%d" % i, _paint_spark))
    _seal_pulse = _layer("SealPulse", _paint_seal_pulse)
    _seal_top = _layer("SealTop", _paint_seal_top)

func _lit() -> bool:
    return is_hovered() or has_focus()

func _down() -> bool:
    return button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))

## Redesenha as camadas fixas (só quando algo visual muda) e liga/desliga as camadas de cada modo.
func _refresh():
    queue_redraw()
    if _shine == null: return
    var lit := _lit()
    var down := _down()
    _state = [active, lit, down, size, over_art, compact]
    var plate := not over_art
    _halo.visible = plate and (active or lit)
    _shine.visible = plate
    _mid.visible = plate
    _glow.visible = plate and active
    _front.visible = plate
    for sp in _sparks: sp.visible = plate and active
    _seal_pulse.visible = over_art and active
    _seal_top.visible = over_art and active
    var off := Vector2(0, 2) if (plate and down) else Vector2.ZERO
    for l in [_halo, _mid, _glow, _front]:
        l.position = off
        l.queue_redraw()
    _seal_pulse.queue_redraw()
    _seal_top.queue_redraw()
    _shine.queue_redraw()
    for sp in _sparks: sp.queue_redraw()
    _animate()

func _process(delta):
    if not is_visible_in_tree(): return
    t += delta
    if _shine == null: return
    if _state != [active, _lit(), _down(), size, over_art, compact]: _refresh()
    else: _animate()

## Só position / scale / modulate: nada aqui redesenha.
func _animate():
    var pulse := 0.5 + 0.5 * sin(t * 2.4)
    if over_art:
        if active: _seal_pulse.modulate.a = 0.35 * pulse
        return
    var m := _metrics()
    var w: float = m.w
    var h: float = m.h
    var notch: float = m.notch
    var border: float = m.border
    var down_y := 2.0 if _down() else 0.0
    _shine.position = Vector2(fmod(t * (150.0 if active else 95.0), w + 220.0) - 110.0, down_y)
    _halo.modulate.a = 0.6 + 0.4 * pulse
    if not active: return
    _glow.modulate.a = 0.10 + 0.14 * pulse
    for i in 5:
        var sp: Node2D = _sparks[i]
        var ph := t * 1.7 + i * 1.3
        var a := 0.5 + 0.5 * sin(ph)
        var px := notch + 10.0 + fmod(i * 61.7 + t * 9.0, maxf(1.0, w - notch * 2.0 - 20.0))
        var py := border * 0.5 if i % 2 == 0 else h - border * 0.5   # só sobre o ouro, nunca sobre o texto
        sp.position = Vector2(px, py + down_y)
        sp.scale = Vector2.ONE * (1.5 + 1.8 * a)
        sp.modulate.a = 0.8 * a if a >= 0.35 else 0.0

func _notification(what):
    if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT, NOTIFICATION_RESIZED, NOTIFICATION_THEME_CHANGED]: _refresh()

func _gui_input(event):
    if event is InputEventMouseButton or event is InputEventScreenTouch: _refresh()

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

func _metrics() -> Dictionary:
    var h := size.y
    var border := 4.0 if compact else 5.0
    var ms := h - border * 2.0 - 2.0
    var notch := minf(h * 0.42, 15.0)
    return {"w": size.x, "h": h, "notch": notch, "border": border, "ms": ms,
        "mc": Vector2(notch + border + ms / 2.0 - 2.0, h / 2.0)}

func _draw():
    if over_art:
        _draw_over_art()
        return
    var lit := _lit()
    if _down(): draw_set_transform(Vector2(0, 2))   # pressionado: a placa "afunda" 2 px (as camadas descem junto)
    var m := _metrics()
    var w: float = m.w
    var h: float = m.h
    var notch: float = m.notch
    var border: float = m.border
    # sombra + contorno escuro externo (descola a placa do fundo da floresta)
    _draw_shifted(ribbon(w, h, notch, 0.0), Vector2(0, 0 if _down() else 4), Color(0, 0, 0, 0.55))
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

## halo (ativo ou hover): alfa base aqui; o pulso vem do modulate da camada
func _paint_halo(l: Node2D):
    var m := _metrics()
    for i in 3:
        var g := 3.0 + i * 3.0
        var a := 0.16 - i * 0.045
        var p := ribbon(m.w + g * 2.0, m.h + g * 2.0, m.notch + g * 0.4, 0.0)
        var out := PackedVector2Array()
        for v in p: out.append(v + Vector2(-g, -g))
        l.draw_colored_polygon(out, Color(1.0, 0.86, 0.45, a))

## brilho que percorre o ouro: desenhado em x = 0; a camada anda (position.x)
func _paint_shine(l: Node2D):
    var h: float = size.y
    l.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(34, 0), Vector2(10, h), Vector2(-24, h)]), Color(1, 0.97, 0.8, 0.16 if active else 0.10))

func _paint_mid(l: Node2D):
    var m := _metrics()
    var w: float = m.w
    var h: float = m.h
    var border: float = m.border
    var ms: float = m.ms
    var mc: Vector2 = m.mc
    var lit := _lit()
    # cravos dourados nas pontas da placa
    for tip in [Vector2(border * 0.9, h / 2.0), Vector2(w - border * 0.9, h / 2.0)]:
        l.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -4), tip + Vector2(4, 0), tip + Vector2(0, 4), tip + Vector2(-4, 0)]), Color("fff3cf"))
        l.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -2), tip + Vector2(2, 0), tip + Vector2(0, 2), tip + Vector2(-2, 0)]), Color("8f6a22"))
    if _down(): l.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.12))
    # medalhão com coroa (esquerda)
    for i in 4:
        var rr := ms / 2.0 - i * (ms / 10.0)
        l.draw_circle(mc, rr, gold_at(0.15 + i * 0.22, lit))
    l.draw_circle(mc, ms / 2.0 - 2.0, Color("0b2416"))
    l.draw_arc(mc, ms / 2.0 - 2.0, 0, TAU, 32, Color("f1d58a"), 1.0)

## brilho do medalhão (ativo): alfa vem do modulate da camada
func _paint_glow(l: Node2D):
    var m := _metrics()
    l.draw_circle(m.mc, m.ms * 0.36, Color(1.0, 0.85, 0.4, 1.0))

func _paint_front(l: Node2D):
    var m := _metrics()
    var w: float = m.w
    var h: float = m.h
    var notch: float = m.notch
    var border: float = m.border
    var ms: float = m.ms
    var mc: Vector2 = m.mc
    var lit := _lit()
    Art.icon(l, "crown", Rect2(mc - Vector2(ms, ms) * 0.31, Vector2(ms, ms) * 0.62), Color("ffe6a0"))
    # ramos de louro em volta do medalhão
    for side in [-1.0, 1.0]:
        for i in 4:
            var ang := deg_to_rad(110.0 + i * 24.0) if side < 0 else deg_to_rad(70.0 - i * 24.0)
            var lp := mc + Vector2(cos(ang), sin(ang)) * (ms / 2.0 + 1.0)
            l.draw_circle(lp, 1.8, Color("d8b35a"))
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
    l.draw_string_outline(Art.FONT_BOLD, Vector2(fx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 4, Color(0.05, 0.03, 0.0, 0.9))
    l.draw_string(Art.FONT_BOLD, Vector2(fx, ty - 1), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color("fff1c4"))
    l.draw_string(Art.FONT_BOLD, Vector2(fx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color("f6d27a") if not lit else Color("ffe6a0"))
    if two_lines:
        l.draw_string(f, Vector2(fx, h * 0.80 + 1), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color("d9f0c6") if active else Color("e6dcc0"))
    else:
        var tw := Art.FONT_BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
        l.draw_string(f, Vector2(fx + tw + 10.0, ty), "· " + sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color("d9f0c6") if active else Color("e6dcc0"))
    # selo dourado "✓" quando ativo
    if active:
        var ss := h * 0.55
        var sc := Vector2(w - notch - border - ss / 2.0 - 2.0, h / 2.0)
        l.draw_circle(sc + Vector2(0, 1), ss / 2.0 + 1.0, Color(0, 0, 0, 0.4))
        for i in 3:
            l.draw_circle(sc, ss / 2.0 - i * (ss / 8.0), gold_at(0.1 + i * 0.3, lit))
        Art.icon(l, "check", Rect2(sc - Vector2(ss, ss) * 0.28, Vector2(ss, ss) * 0.56), Color("1a3a12"))

## faísca (ativo): estrela de raio 1 na origem; a camada anda/escala/esmaece
func _paint_spark(l: Node2D):
    Art.star(l, Vector2.ZERO, 1.0, Color(1.0, 0.98, 0.85, 1.0))

func _draw_shifted(p: PackedVector2Array, d: Vector2, col: Color):
    var out := PackedVector2Array()
    for v in p: out.append(v + d)
    draw_colored_polygon(out, col)

## Coordenadas medidas na arte v7 (placa em x 18–352, y 8–80; o botão fica em 22,16 com 330×62).
func _draw_over_art():
    var lit := _lit()
    var down := _down()
    if lit:   # luz quente por dentro da placa
        draw_rect(Rect2(art_tx - 5.0, 7, size.x - art_tx - 3.0, size.y - 12.0), Color(1.0, 0.86, 0.45, 0.07))
    var f := get_theme_default_font()
    var title := "CLUB ATIVO" if active else "CLUB FRAIHA"
    var sub := "Análises ilimitadas · moldura premium" if active else "Jogue. Analise. Evolua."
    var tx := art_tx
    var dy := 1.0 if down else 0.0
    var tfs := Art.fit(f, title, art_title_size, art_title_room, 14)
    var gold := Color("ffd76e") if lit else Color("f2c65a")
    draw_string_outline(f, Vector2(tx, art_title_y + dy), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 5, Color(0.08, 0.05, 0.0, 0.85))
    draw_string_outline(f, Vector2(tx, art_title_y + dy), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 1, gold)   # traço mais encorpado
    draw_string(f, Vector2(tx, art_title_y + dy), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, gold)
    if art_sub:
        var sfs := Art.fit(f, sub, 12, 196.0, 9)
        draw_string_outline(f, Vector2(tx, art_sub_y + dy), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, 3, Color(0.05, 0.03, 0.0, 0.8))
        draw_string(f, Vector2(tx, art_sub_y + dy), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color("f1ead6"))
    var sc := art_seal + Vector2(0, dy)
    if active:
        # selo dourado com ✓ (igual à referência); o leve pulso é a camada SealPulse por cima do disco base
        draw_circle(sc + Vector2(0, 2), 19.0, Color(0, 0, 0, 0.45))
        draw_circle(sc, 19.0, Color("6e4210"))
        draw_circle(sc, 17.5, Color("e9a321"))
        draw_circle(sc, 15.0, Color("f7b62a"))
    else:
        # seta dourada (abre a página do Club)
        var c := sc + Vector2(4 if lit else 0, 0)
        draw_polyline(PackedVector2Array([c + Vector2(-5, -9), c + Vector2(5, 0), c + Vector2(-5, 9)]), Color(0.1, 0.06, 0.0, 0.8), 7.0)
        draw_polyline(PackedVector2Array([c + Vector2(-5, -9), c + Vector2(5, 0), c + Vector2(-5, 9)]), gold, 4.0)

## pulso do selo: f7b62a -> ffd25c em 0,35*pulso = disco ffd25c por cima com alfa 0,35*pulso (modulate)
func _paint_seal_pulse(l: Node2D):
    var sc := art_seal + Vector2(0, 1.0 if _down() else 0.0)
    l.draw_circle(sc, 15.0, Color("ffd25c"))

func _paint_seal_top(l: Node2D):
    var sc := art_seal + Vector2(0, 1.0 if _down() else 0.0)
    l.draw_arc(sc, 14.0, PI * 1.1, PI * 1.9, 16, Color(1, 0.95, 0.7, 0.75), 2.0)
    l.draw_polyline(PackedVector2Array([sc + Vector2(-8, 0), sc + Vector2(-2, 6), sc + Vector2(9, -7)]), Color("0f3518"), 5.0)
