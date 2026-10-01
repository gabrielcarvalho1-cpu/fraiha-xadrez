extends RefCounted
## FRAIHA PREMIUM — arte desenhada em código (molduras, ícones, selos, botões, partículas).
## Paleta FRAIHA: verde, verde-escuro, preto e dourado. Fundador = mais majestoso
## (preto + ouro); Club = verde FRAIHA + pergaminho.
const FONT_BOLD := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")
const GOLD := Color("f1d58a")
const GOLD_MID := Color("c99a45")
const GOLD_DARK := Color("6e4b18")
const CREAM := Color("f4e8c8")
const MUTED := Color("c9c2a8")
const GREEN := Color("1f6b3a")
const GREEN_DEEP := Color("0b2416")
const BLACK := Color("07100b")
const PARCH := Color("e9d7a8")
const INK := Color("3a2a12")
const EMBER := Color("e0703c")
## Largura máxima dos selos (0 = livre). O Premium define isto em telas estreitas.
static var stamp_cap := 0.0

# ======================================================================
# Ícones (linhas/formas simples, no estilo dos ícones dourados da Home)
# ======================================================================
static func icon(ci: CanvasItem, kind: String, r: Rect2, c: Color):
    var s := minf(r.size.x, r.size.y)
    var o := r.get_center()
    var w := maxf(1.5, s * 0.07)
    match kind:
        "crown":
            var b := o.y + s * 0.26
            var pts := PackedVector2Array([
                Vector2(o.x - s * 0.42, b), Vector2(o.x - s * 0.46, o.y - s * 0.20),
                Vector2(o.x - s * 0.22, o.y + s * 0.02), Vector2(o.x, o.y - s * 0.34),
                Vector2(o.x + s * 0.22, o.y + s * 0.02), Vector2(o.x + s * 0.46, o.y - s * 0.20),
                Vector2(o.x + s * 0.42, b)])
            ci.draw_colored_polygon(pts, c)
            ci.draw_rect(Rect2(o.x - s * 0.42, b + s * 0.05, s * 0.84, s * 0.10), c)
            for p in [Vector2(o.x - s * 0.46, o.y - s * 0.24), Vector2(o.x, o.y - s * 0.38), Vector2(o.x + s * 0.46, o.y - s * 0.24)]:
                ci.draw_circle(p, s * 0.06, c)
            ci.draw_circle(Vector2(o.x, o.y + s * 0.08), s * 0.06, Color(0.75, 0.1, 0.1, 0.9))
        "shield":
            var pts := PackedVector2Array([
                Vector2(o.x - s * 0.36, o.y - s * 0.40), Vector2(o.x + s * 0.36, o.y - s * 0.40),
                Vector2(o.x + s * 0.36, o.y + s * 0.02), Vector2(o.x, o.y + s * 0.44),
                Vector2(o.x - s * 0.36, o.y + s * 0.02)])
            ci.draw_colored_polygon(pts, c.darkened(0.55))
            var line := pts.duplicate(); line.append(pts[0])
            ci.draw_polyline(line, c, w * 1.2)
            ci.draw_line(Vector2(o.x, o.y - s * 0.40), Vector2(o.x, o.y + s * 0.42), c, w)
            ci.draw_line(Vector2(o.x - s * 0.36, o.y - s * 0.08), Vector2(o.x + s * 0.36, o.y - s * 0.08), c, w)
        "book":
            ci.draw_rect(Rect2(o.x - s * 0.44, o.y - s * 0.30, s * 0.42, s * 0.58), c)
            ci.draw_rect(Rect2(o.x + s * 0.02, o.y - s * 0.30, s * 0.42, s * 0.58), c)
            for i in 3:
                var y := o.y - s * 0.16 + i * s * 0.13
                ci.draw_line(Vector2(o.x - s * 0.36, y), Vector2(o.x - s * 0.10, y), c.darkened(0.6), w * 0.7)
                ci.draw_line(Vector2(o.x + s * 0.10, y), Vector2(o.x + s * 0.36, y), c.darkened(0.6), w * 0.7)
        "chart":
            for i in 4:
                var h := s * (0.22 + 0.16 * i)
                ci.draw_rect(Rect2(o.x - s * 0.40 + i * s * 0.21, o.y + s * 0.36 - h, s * 0.14, h), c)
            ci.draw_line(Vector2(o.x - s * 0.44, o.y + s * 0.40), Vector2(o.x + s * 0.44, o.y + s * 0.40), c, w)
        "scroll":
            ci.draw_rect(Rect2(o.x - s * 0.30, o.y - s * 0.32, s * 0.60, s * 0.64), c)
            ci.draw_circle(Vector2(o.x - s * 0.30, o.y - s * 0.32), s * 0.08, c)
            ci.draw_circle(Vector2(o.x + s * 0.30, o.y + s * 0.32), s * 0.08, c)
            for i in 3:
                var y := o.y - s * 0.14 + i * s * 0.13
                ci.draw_line(Vector2(o.x - s * 0.18, y), Vector2(o.x + s * 0.18, y), c.darkened(0.6), w * 0.8)
        "chat":
            ci.draw_circle(Vector2(o.x, o.y - s * 0.04), s * 0.36, c)
            ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x - s * 0.30, o.y + s * 0.16), Vector2(o.x - s * 0.40, o.y + s * 0.42), Vector2(o.x - s * 0.06, o.y + s * 0.28)]), c)
            for i in 3: ci.draw_circle(Vector2(o.x - s * 0.16 + i * s * 0.16, o.y - s * 0.04), s * 0.05, c.darkened(0.65))
        "pawn":
            ci.draw_circle(Vector2(o.x, o.y - s * 0.24), s * 0.13, c)
            ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x - s * 0.10, o.y - s * 0.12), Vector2(o.x + s * 0.10, o.y - s * 0.12), Vector2(o.x + s * 0.20, o.y + s * 0.24), Vector2(o.x - s * 0.20, o.y + s * 0.24)]), c)
            ci.draw_rect(Rect2(o.x - s * 0.30, o.y + s * 0.24, s * 0.60, s * 0.14), c)
        "castle":
            ci.draw_rect(Rect2(o.x - s * 0.36, o.y - s * 0.10, s * 0.72, s * 0.50), c)
            for i in 4: ci.draw_rect(Rect2(o.x - s * 0.36 + i * s * 0.20, o.y - s * 0.24, s * 0.12, s * 0.16), c)
            ci.draw_rect(Rect2(o.x - s * 0.08, o.y + s * 0.14, s * 0.16, s * 0.26), c.darkened(0.7))
        "frame":
            ci.draw_rect(Rect2(o - Vector2(s, s) * 0.40, Vector2(s, s) * 0.80), c, false, w * 1.6)
            ci.draw_rect(Rect2(o - Vector2(s, s) * 0.26, Vector2(s, s) * 0.52), c, false, w)
            for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
                ci.draw_circle(o + d * s * 0.40, s * 0.07, c)
        "seal":
            ci.draw_circle(o, s * 0.40, c)
            ci.draw_circle(o, s * 0.30, c.darkened(0.5))
            star(ci, o, s * 0.20, c)
        "star":
            star(ci, o, s * 0.44, c)
        "hourglass":
            ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x - s * 0.30, o.y - s * 0.40), Vector2(o.x + s * 0.30, o.y - s * 0.40), Vector2(o.x, o.y)]), c)
            ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x, o.y), Vector2(o.x + s * 0.30, o.y + s * 0.40), Vector2(o.x - s * 0.30, o.y + s * 0.40)]), c)
        "target":
            ci.draw_arc(o, s * 0.40, 0, TAU, 32, c, w)
            ci.draw_arc(o, s * 0.24, 0, TAU, 24, c, w)
            ci.draw_circle(o, s * 0.09, c)
        "magnifier":
            ci.draw_arc(o - Vector2(s, s) * 0.08, s * 0.26, 0, TAU, 28, c, w * 1.4)
            ci.draw_line(o + Vector2(s, s) * 0.12, o + Vector2(s, s) * 0.38, c, w * 2.2)
        "sword":
            ci.draw_line(o + Vector2(-s * 0.34, s * 0.34), o + Vector2(s * 0.36, -s * 0.36), c, w * 1.8)
            ci.draw_line(o + Vector2(-s * 0.30, s * 0.06), o + Vector2(-s * 0.06, s * 0.30), c, w * 1.8)
        "trophy":
            ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x - s * 0.28, o.y - s * 0.36), Vector2(o.x + s * 0.28, o.y - s * 0.36), Vector2(o.x + s * 0.18, o.y + s * 0.04), Vector2(o.x - s * 0.18, o.y + s * 0.04)]), c)
            ci.draw_arc(Vector2(o.x - s * 0.28, o.y - s * 0.20), s * 0.12, PI * 0.5, PI * 1.5, 10, c, w)
            ci.draw_arc(Vector2(o.x + s * 0.28, o.y - s * 0.20), s * 0.12, -PI * 0.5, PI * 0.5, 10, c, w)
            ci.draw_rect(Rect2(o.x - s * 0.05, o.y + s * 0.04, s * 0.10, s * 0.20), c)
            ci.draw_rect(Rect2(o.x - s * 0.22, o.y + s * 0.24, s * 0.44, s * 0.12), c)
        "gem":
            ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x - s * 0.36, o.y - s * 0.12), Vector2(o.x - s * 0.20, o.y - s * 0.32), Vector2(o.x + s * 0.20, o.y - s * 0.32), Vector2(o.x + s * 0.36, o.y - s * 0.12), Vector2(o.x, o.y + s * 0.38)]), c)
            ci.draw_line(Vector2(o.x - s * 0.36, o.y - s * 0.12), Vector2(o.x + s * 0.36, o.y - s * 0.12), c.darkened(0.5), w * 0.8)
        "brush":
            ci.draw_line(o + Vector2(s * 0.34, -s * 0.36), o + Vector2(-s * 0.08, s * 0.06), c, w * 1.8)
            ci.draw_circle(o + Vector2(-s * 0.18, s * 0.18), s * 0.16, c)
        "tag":
            ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x - s * 0.40, o.y - s * 0.10), Vector2(o.x - s * 0.10, o.y - s * 0.40), Vector2(o.x + s * 0.40, o.y - s * 0.40), Vector2(o.x + s * 0.40, o.y + s * 0.10), Vector2(o.x + s * 0.10, o.y + s * 0.40)]), c)
            ci.draw_circle(Vector2(o.x + s * 0.22, o.y - s * 0.22), s * 0.07, c.darkened(0.7))
        "calendar":
            ci.draw_rect(Rect2(o.x - s * 0.38, o.y - s * 0.30, s * 0.76, s * 0.66), c)
            ci.draw_rect(Rect2(o.x - s * 0.38, o.y - s * 0.30, s * 0.76, s * 0.16), c.darkened(0.35))
            for i in 3:
                for j in 2:
                    ci.draw_rect(Rect2(o.x - s * 0.26 + i * s * 0.20, o.y - s * 0.04 + j * s * 0.18, s * 0.12, s * 0.10), c.darkened(0.6))
        "megaphone":
            ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x - s * 0.36, o.y - s * 0.10), Vector2(o.x + s * 0.30, o.y - s * 0.36), Vector2(o.x + s * 0.30, o.y + s * 0.36), Vector2(o.x - s * 0.36, o.y + s * 0.10)]), c)
            ci.draw_rect(Rect2(o.x - s * 0.24, o.y + s * 0.08, s * 0.12, s * 0.26), c)
        "heart":
            ci.draw_circle(Vector2(o.x - s * 0.16, o.y - s * 0.10), s * 0.20, c)
            ci.draw_circle(Vector2(o.x + s * 0.16, o.y - s * 0.10), s * 0.20, c)
            ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x - s * 0.35, o.y - s * 0.02), Vector2(o.x + s * 0.35, o.y - s * 0.02), Vector2(o.x, o.y + s * 0.38)]), c)
        "server":
            for i in 3:
                ci.draw_rect(Rect2(o.x - s * 0.36, o.y - s * 0.38 + i * s * 0.27, s * 0.72, s * 0.20), c)
                ci.draw_circle(Vector2(o.x + s * 0.24, o.y - s * 0.28 + i * s * 0.27), s * 0.04, c.darkened(0.7))
        "hammer":
            ci.draw_rect(Rect2(o.x - s * 0.36, o.y - s * 0.36, s * 0.46, s * 0.20), c)
            ci.draw_line(Vector2(o.x - s * 0.06, o.y - s * 0.18), Vector2(o.x + s * 0.32, o.y + s * 0.38), c, w * 2.0)
        "people":
            for dx in [-0.20, 0.20]:
                ci.draw_circle(Vector2(o.x + s * dx, o.y - s * 0.18), s * 0.13, c)
                ci.draw_colored_polygon(PackedVector2Array([Vector2(o.x + s * (dx - 0.20), o.y + s * 0.34), Vector2(o.x + s * (dx - 0.14), o.y + s * 0.02), Vector2(o.x + s * (dx + 0.14), o.y + s * 0.02), Vector2(o.x + s * (dx + 0.20), o.y + s * 0.34)]), c)
        "check":
            ci.draw_polyline(PackedVector2Array([o + Vector2(-s * 0.34, 0), o + Vector2(-s * 0.08, s * 0.26), o + Vector2(s * 0.38, -s * 0.30)]), c, w * 2.0)
        "lock":
            ci.draw_arc(Vector2(o.x, o.y - s * 0.10), s * 0.20, PI, TAU, 14, c, w * 1.4)
            ci.draw_rect(Rect2(o.x - s * 0.30, o.y - s * 0.08, s * 0.60, s * 0.46), c)
        "card":
            ci.draw_rect(Rect2(o.x - s * 0.44, o.y - s * 0.28, s * 0.88, s * 0.56), c, false, w * 1.3)
            ci.draw_rect(Rect2(o.x - s * 0.44, o.y - s * 0.14, s * 0.88, s * 0.12), c)
            ci.draw_rect(Rect2(o.x - s * 0.34, o.y + s * 0.10, s * 0.24, s * 0.08), c)
        "pix":
            # Losango estilizado (sem logotipo oficial).
            var d := s * 0.40
            ci.draw_polyline(PackedVector2Array([o + Vector2(0, -d), o + Vector2(d, 0), o + Vector2(0, d), o + Vector2(-d, 0), o + Vector2(0, -d)]), c, w * 1.6)
            diamond(ci, o, s * 0.14, c)
        _:
            diamond(ci, o, s * 0.2, c)

static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color):
    ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)

static func star(ci: CanvasItem, c: Vector2, r: float, col: Color):
    var pts := PackedVector2Array()
    for i in 10:
        var a := -PI / 2.0 + i * PI / 5.0
        var rr := r if i % 2 == 0 else r * 0.45
        pts.append(c + Vector2(cos(a), sin(a)) * rr)
    ci.draw_colored_polygon(pts, col)

static func fit(font: Font, text: String, size: int, width: float, minimum := 10) -> int:
    while size > minimum and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width: size -= 1
    return size

static func label(parent: Node, text: String, size: int, color := CREAM, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var l := Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    l.horizontal_alignment = align
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
    l.add_theme_constant_override("shadow_offset_y", 1)
    l.add_theme_constant_override("line_spacing", 3)
    if font != null: l.add_theme_font_override("font", font)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if parent != null: parent.add_child(l)
    return l

# ======================================================================
# Moldura ornamentada (cartões e seções)
# ======================================================================
class Frame extends PanelContainer:
    ## founder | club | parchment | dark | reward | test
    var variant := "dark"
    var glow := false
    var t := 0.0
    func _init(v := "dark", pad := 22):
        variant = v
        var st := StyleBoxFlat.new()
        st.set_corner_radius_all(6)
        st.set_border_width_all(3 if v in ["founder", "reward"] else 2)
        st.content_margin_left = pad
        st.content_margin_right = pad
        st.content_margin_top = pad
        st.content_margin_bottom = pad
        st.shadow_color = Color(0, 0, 0, 0.55)
        st.shadow_size = 10
        match v:
            "founder":
                st.bg_color = Color(0.03, 0.05, 0.04, 0.95)
                st.border_color = Color("d9ad55")
            "club":
                st.bg_color = Color(0.05, 0.20, 0.11, 0.94)
                st.border_color = Color("c99a45")
            "parchment":
                st.bg_color = Color("e6d3a0")
                st.border_color = Color("8a6224")
            "reward":
                st.bg_color = Color(0.10, 0.12, 0.05, 0.96)
                st.border_color = Color("ffd76a")
            "test":
                st.bg_color = Color(0.20, 0.07, 0.03, 0.92)
                st.border_color = Color("e0703c")
            _:
                st.bg_color = Color(0.03, 0.10, 0.06, 0.92)
                st.border_color = Color(0.79, 0.6, 0.27, 0.75)
        add_theme_stylebox_override("panel", st)
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _process(delta):
        if glow:
            t += delta
            queue_redraw()
    func _draw():
        var r := Rect2(Vector2.ZERO, size)
        var gold := Color("f1d58a") if variant != "parchment" else Color("8a6224")
        if variant == "test": gold = Color("f2a070")
        draw_rect(r.grow(-7), Color(gold.r, gold.g, gold.b, 0.30), false, 1.0)
        if variant in ["founder", "reward"]:
            draw_rect(r.grow(-11), Color(gold.r, gold.g, gold.b, 0.14), false, 1.0)
        for c in [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, size.y), size]:
            PremiumArtRef.diamond(self, c, 7.0 if variant in ["founder", "reward"] else 5.0, gold)
        if glow:
            var a := 0.18 + 0.14 * sin(t * 2.4)
            draw_rect(r.grow(2), Color(1.0, 0.85, 0.4, a), false, 3.0)

# Referência estática usada dentro das classes internas.
class PremiumArtRef:
    static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color):
        ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)

# ======================================================================
# Ícone como Control
# ======================================================================
class Glyph extends Control:
    var kind := "star"
    var color := Color("f1d58a")
    var ring := false
    func _init(k := "star", side := 44.0, col := Color("f1d58a"), with_ring := false):
        kind = k
        color = col
        ring = with_ring
        custom_minimum_size = Vector2(side, side)
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _draw():
        var r := Rect2(Vector2.ZERO, size)
        if ring:
            var c := r.get_center()
            var rad := minf(size.x, size.y) * 0.5
            draw_circle(c, rad, Color(0.02, 0.06, 0.04, 0.9))
            draw_arc(c, rad - 1.5, 0, TAU, 40, color, 2.0)
            draw_arc(c, rad - 6.0, 0, TAU, 40, Color(color.r, color.g, color.b, 0.35), 1.0)
            r = r.grow(-minf(size.x, size.y) * 0.22)
        load("res://monetization/premium_art.gd").icon(self, kind, r, color)

# ======================================================================
# Selo de texto (MODO TESTE, NOVO, RECOMENDADO, EM BREVE…)
# ======================================================================
class Stamp extends Control:
    var text := ""
    var tone := "test"   # test | new | info | soon | ok
    var font_size := 14
    func _init(t := "", tn := "test", fs := 14):
        text = t
        tone = tn
        font_size = fs
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        size_flags_vertical = Control.SIZE_SHRINK_CENTER
        _measure()
    var lines: Array = []
    func _measure():
        var f: Font = load("res://account/fonts/Cinzel-Bold.woff")
        var cap: float = load("res://monetization/premium_art.gd").stamp_cap
        var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        lines = [text]
        if cap > 0.0 and w + 26.0 > cap:
            # Quebra em linhas pelos separadores " · " (ou espaços) para caber na tela estreita.
            var parts: Array = Array(text.split(" · ")) if " · " in text else Array(text.split(" "))
            var sep := " · " if " · " in text else " "
            lines = []
            var cur := ""
            for part in parts:
                var trial: String = part if cur.is_empty() else cur + sep + part
                if not cur.is_empty() and f.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 26.0 > cap:
                    lines.append(cur)
                    cur = part
                else:
                    cur = trial
            if not cur.is_empty(): lines.append(cur)
        var mw := 0.0
        for l in lines: mw = maxf(mw, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
        custom_minimum_size = Vector2(mw + 26.0 if cap <= 0.0 else minf(mw + 26.0, cap), font_size + 14.0 + (lines.size() - 1) * (font_size + 3.0))
    func set_text(t: String):
        text = t
        _measure()
        queue_redraw()
    func _colors() -> Array:
        match tone:
            "new": return [Color("f6c85a"), Color("3a2408"), Color("fff1c0")]
            "info": return [Color(0.08, 0.30, 0.16, 0.95), Color("f1d58a"), Color("f1d58a")]
            "soon": return [Color(0.12, 0.13, 0.10, 0.92), Color("c9c2a8"), Color("8c8569")]
            "ok": return [Color(0.10, 0.36, 0.18, 0.96), Color("eaffd8"), Color("8fe08a")]
            _: return [Color(0.42, 0.10, 0.05, 0.95), Color("ffe2c8"), Color("f2a070")]
    func _draw():
        var col := _colors()
        var r := Rect2(Vector2.ZERO, size)
        var notch := minf(size.y * 0.32, 9.0)
        var pts := PackedVector2Array([Vector2(notch, 0), Vector2(size.x - notch, 0), Vector2(size.x, size.y / 2.0), Vector2(size.x - notch, size.y), Vector2(notch, size.y), Vector2(0, size.y / 2.0)])
        draw_colored_polygon(pts, col[0])
        pts.append(pts[0])
        draw_polyline(pts, col[2], 1.5)
        var f: Font = load("res://account/fonts/Cinzel-Bold.woff")
        var lh := font_size + 3.0
        var y0 := size.y / 2.0 - (lines.size() - 1) * lh / 2.0 + f.get_ascent(font_size) * 0.36
        for i in lines.size():
            var fs := font_size
            while fs > 9 and f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 18.0: fs -= 1
            var w := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
            draw_string(f, Vector2((size.x - w) / 2.0, y0 + i * lh), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col[1])

# ======================================================================
# Botão de ação (CTA) com pontas, gradiente e brilho
# ======================================================================
class Cta extends Button:
    var style := "gold"   # gold | green | dark | ember
    var font_size := 22
    var icon_kind := ""
    var t := 0.0
    var shimmer := false
    func _init(label_text := "", st := "gold", height := 64.0, fs := 22):
        text = label_text
        style = st
        font_size = fs
        custom_minimum_size = Vector2(0, height)
        clip_text = true   # o texto é desenhado (com ajuste de tamanho); não impõe largura mínima
        focus_mode = Control.FOCUS_NONE
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
        for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
            add_theme_color_override(c, Color(0, 0, 0, 0))
        add_theme_font_override("font", load("res://account/fonts/Cinzel-Bold.woff"))
        add_theme_font_size_override("font_size", fs)
    func _notification(what):
        if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT]: queue_redraw()
    func _process(delta):
        if shimmer and is_visible_in_tree():
            t += delta
            queue_redraw()
    func _draw():
        var lit := is_hovered() and not disabled
        var down := is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
        var notch := minf(size.y * 0.42, 26.0)
        var outer := _pointed(Rect2(Vector2.ZERO, size), notch)
        var top: Color
        var bottom: Color
        var rim := Color("f1d58a")
        var ink := Color("fff4d6")
        match style:
            "gold":
                top = Color("f2cf6e"); bottom = Color("a8741f"); ink = Color("2a1a04")
            "green":
                top = Color("2f8a4a"); bottom = Color("0f3d1d")
            "ember":
                top = Color("b4462a"); bottom = Color("5a1b0c")
            _:
                top = Color("1b2a21"); bottom = Color("070d0a"); ink = Color("f1d58a")
        if disabled:
            top = Color("3a3d36"); bottom = Color("1c1e1a"); ink = Color("8b8f86"); rim = Color("6d6656")
        elif lit:
            top = top.lightened(0.12); bottom = bottom.lightened(0.08)
        if down: top = top.darkened(0.12)
        draw_colored_polygon(outer, rim.darkened(0.25))
        var inner := _pointed(Rect2(Vector2.ZERO, size).grow(-3), notch - 2.0)
        var cols := PackedColorArray()
        for p in inner: cols.append(top.lerp(bottom, clampf(p.y / maxf(1.0, size.y), 0.0, 1.0)))
        draw_polygon(inner, cols)
        var line := _pointed(Rect2(Vector2.ZERO, size).grow(-8), notch - 5.0)
        line.append(line[0])
        draw_polyline(line, Color(rim.r, rim.g, rim.b, 0.45), 1.0)
        if shimmer and not disabled:
            var x := fmod(t * 260.0, size.x + 200.0) - 100.0
            draw_colored_polygon(PackedVector2Array([Vector2(x, 4), Vector2(x + 34, 4), Vector2(x + 4, size.y - 4), Vector2(x - 30, size.y - 4)]), Color(1, 1, 1, 0.16))
        var f: Font = get_theme_font("font")
        var icon_w := size.y * 0.46 if not icon_kind.is_empty() else 0.0
        var gap := 12.0 if icon_w > 0.0 else 0.0
        var room := size.x - notch * 2.0 - 12.0 - icon_w - gap
        var fs := font_size
        while fs > 11 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room: fs -= 1
        var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
        var x0 := (size.x - tw - icon_w - gap) / 2.0
        if icon_w > 0.0:
            load("res://monetization/premium_art.gd").icon(self, icon_kind, Rect2(Vector2(x0, (size.y - icon_w) / 2.0), Vector2(icon_w, icon_w)), ink)
        var base := Vector2(x0 + icon_w + gap, size.y / 2.0 + f.get_ascent(fs) * 0.36)
        if style != "gold" or disabled:
            draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.55))
        draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
    static func _pointed(r: Rect2, notch: float) -> PackedVector2Array:
        return PackedVector2Array([Vector2(r.position.x + notch, r.position.y), Vector2(r.end.x - notch, r.position.y), Vector2(r.end.x, r.get_center().y), Vector2(r.end.x - notch, r.end.y), Vector2(r.position.x + notch, r.end.y), Vector2(r.position.x, r.get_center().y)])

# ======================================================================
# Partículas douradas discretas
# ======================================================================
class Sparkles extends Control:
    var motes: Array = []
    var count := 36
    var tint := Color("f1d58a")
    func _init(n := 36, col := Color("f1d58a")):
        count = n
        tint = col
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _ready():
        set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    func _process(delta):
        if not is_visible_in_tree(): return
        if motes.size() < count and size.x > 0:
            motes.append({"p": Vector2(randf() * size.x, size.y + randf() * 40.0), "v": randf_range(12.0, 34.0), "s": randf_range(1.2, 3.2), "ph": randf() * TAU, "life": randf_range(0.6, 1.0)})
        for m in motes:
            m.p.y -= m.v * delta
            m.ph += delta * 1.7
            m.p.x += sin(m.ph) * 0.25
        motes = motes.filter(func(m): return m.p.y > -10.0)
        queue_redraw()
    func _draw():
        for m in motes:
            var a: float = clampf(m.p.y / maxf(1.0, size.y), 0.0, 1.0) * 0.75 * m.life * (0.6 + 0.4 * sin(m.ph * 2.0))
            draw_circle(m.p, m.s * 2.4, Color(tint.r, tint.g, tint.b, a * 0.18))
            draw_circle(m.p, m.s, Color(tint.r, tint.g, tint.b, a))
