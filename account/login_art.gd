extends RefCounted
## Desenho vetorial da tela de entrada (moldura, brasão, ícones). Tudo com primitivas do
## CanvasItem: nada de imagem nova, escala limpa em qualquer tela.
const GOLD := Color("f1d58a")
const GOLD_MID := Color("c99a45")
const GOLD_DARK := Color("6e4b18")
const GOLD_DEEP := Color("3a270c")
const GREEN_TOP := Color("151f33")
const GREEN_BOTTOM := Color("0a101c")
const CREAM := Color("f4e8c8")
const FONT_BOLD := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")

static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color):
    ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)

static func star4(ci: CanvasItem, c: Vector2, r: float, col: Color):
    var k := r * 0.28
    ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(k, -k), c + Vector2(r, 0), c + Vector2(k, k), c + Vector2(0, r), c + Vector2(-k, k), c + Vector2(-r, 0), c + Vector2(-k, -k)]), col)

## Filete dourado horizontal com losango central e pontas afinando.
static func divider(ci: CanvasItem, a: Vector2, b: Vector2, col := GOLD_MID):
    var mid := (a + b) / 2.0
    for side in [-1.0, 1.0]:
        var end: Vector2 = a if side < 0.0 else b
        var steps := 10
        for i in steps:
            var t0 := float(i) / steps
            var t1 := float(i + 1) / steps
            var p0 := mid.lerp(end, t0)
            var p1 := mid.lerp(end, t1)
            ci.draw_line(p0, p1, Color(col.r, col.g, col.b, col.a * (1.0 - t0 * 0.85)), 1.6)
    diamond(ci, mid, 6.0, GOLD)
    diamond(ci, mid, 2.6, GOLD_DEEP)
    for s in [-1.0, 1.0]:
        diamond(ci, mid + Vector2(s * 13.0, 0), 2.4, GOLD_MID)

## Polígono de retângulo com pontas em "V" (botões da referência).
static func pointed(rect: Rect2, notch: float) -> PackedVector2Array:
    var p := rect.position
    var e := rect.end
    var cy := rect.get_center().y
    return PackedVector2Array([Vector2(p.x + notch, p.y), Vector2(e.x - notch, p.y), Vector2(e.x, cy), Vector2(e.x - notch, e.y), Vector2(p.x + notch, e.y), Vector2(p.x, cy)])

static func vertical_gradient(ci: CanvasItem, pts: PackedVector2Array, top: Color, bottom: Color):
    var ys := []
    for p in pts: ys.append(p.y)
    var y0: float = ys.min()
    var y1: float = ys.max()
    var cols := PackedColorArray()
    for p in pts: cols.append(top.lerp(bottom, (p.y - y0) / maxf(1.0, y1 - y0)))
    ci.draw_polygon(pts, cols)

# ---------------- Ícones (caixa quadrada de lado s, cor c) ----------------
static func icon(ci: CanvasItem, kind: String, rect: Rect2, c: Color):
    var s := minf(rect.size.x, rect.size.y)
    var o := rect.get_center()
    var w := maxf(1.6, s / 13.0)
    match kind:
        "mail":
            var r := Rect2(o - Vector2(s * 0.42, s * 0.29), Vector2(s * 0.84, s * 0.58))
            ci.draw_rect(r, c, false, w)
            ci.draw_polyline(PackedVector2Array([r.position, Vector2(o.x, o.y + s * 0.04), Vector2(r.end.x, r.position.y)]), c, w)
        "lock":
            ci.draw_arc(o + Vector2(0, -s * 0.08), s * 0.2, PI, TAU, 14, c, w * 1.2)
            ci.draw_line(o + Vector2(-s * 0.2, -s * 0.08), o + Vector2(-s * 0.2, s * 0.02), c, w * 1.2)
            ci.draw_line(o + Vector2(s * 0.2, -s * 0.08), o + Vector2(s * 0.2, s * 0.02), c, w * 1.2)
            var body := Rect2(o + Vector2(-s * 0.32, s * 0.0), Vector2(s * 0.64, s * 0.44))
            ci.draw_rect(body, c)
            ci.draw_circle(o + Vector2(0, s * 0.17), s * 0.06, GOLD_DEEP)
            ci.draw_line(o + Vector2(0, s * 0.19), o + Vector2(0, s * 0.3), GOLD_DEEP, w)
        "eye", "eye_off":
            var pts := PackedVector2Array()
            for i in 25:
                var t := float(i) / 24.0
                pts.append(o + Vector2(lerpf(-s * 0.45, s * 0.45, t), -sin(t * PI) * s * 0.26))
            for i in 25:
                var t := float(i) / 24.0
                pts.append(o + Vector2(lerpf(s * 0.45, -s * 0.45, t), sin(t * PI) * s * 0.26))
            ci.draw_polyline(pts, c, w)
            ci.draw_circle(o, s * 0.13, c)
            if kind == "eye_off": ci.draw_line(o + Vector2(-s * 0.4, s * 0.34), o + Vector2(s * 0.4, -s * 0.34), c, w * 1.2)
        "person_add":
            ci.draw_circle(o + Vector2(-s * 0.1, -s * 0.18), s * 0.17, c)
            ci.draw_colored_polygon(_shoulders(o + Vector2(-s * 0.1, s * 0.32), s * 0.34, s * 0.26), c)
            ci.draw_line(o + Vector2(s * 0.3, s * 0.02), o + Vector2(s * 0.3, s * 0.34), c, w * 1.3)
            ci.draw_line(o + Vector2(s * 0.14, s * 0.18), o + Vector2(s * 0.46, s * 0.18), c, w * 1.3)
        "key":
            var head := o + Vector2(s * 0.22, -s * 0.22)
            ci.draw_circle(head, s * 0.17, c, false, w * 1.4)
            var tail := o + Vector2(-s * 0.36, s * 0.36)
            ci.draw_line(head + Vector2(-s * 0.12, s * 0.12), tail, c, w * 1.5)
            for k in [0.45, 0.7]:
                var p: Vector2 = (head + Vector2(-s * 0.12, s * 0.12)).lerp(tail, k)
                ci.draw_line(p, p + Vector2(-s * 0.1, -s * 0.1), c, w * 1.3)
        "persons":
            for dx in [-0.17, 0.17]:
                ci.draw_circle(o + Vector2(s * dx, -s * 0.18), s * 0.14, c)
                ci.draw_colored_polygon(_shoulders(o + Vector2(s * dx, s * 0.3), s * 0.28, s * 0.24), c)
        "info":
            ci.draw_arc(o, s * 0.4, 0, TAU, 28, c, w)
            ci.draw_circle(o + Vector2(0, -s * 0.18), s * 0.05, c)
            ci.draw_line(o + Vector2(0, -s * 0.05), o + Vector2(0, s * 0.22), c, w * 1.2)
        "apple":   # R190 · logo da Apple (botão "Iniciar sessão com a Apple", só no app de iPhone)
            var tex := apple_logo()
            var hh := s * 0.74
            var ww := hh * tex.get_width() / float(tex.get_height())
            ci.draw_texture_rect(tex, Rect2(o - Vector2(ww / 2.0, hh * 0.54), Vector2(ww, hh)), false, Color.BLACK)
        "google":
            var r2 := s * 0.36
            var th := s * 0.15
            var seg := [[0.0, 45.0, Color("4285f4")], [45.0, 135.0, Color("34a853")], [135.0, 205.0, Color("fbbc05")], [205.0, 318.0, Color("ea4335")]]
            for sg in seg:
                ci.draw_arc(o, r2, deg_to_rad(sg[0]), deg_to_rad(sg[1]), 16, sg[2], th, true)
            ci.draw_rect(Rect2(o + Vector2(-s * 0.02, -th / 2.0), Vector2(r2 + th / 2.0 + s * 0.02, th)), Color("4285f4"))

## R190 · logo da Apple em branco (recolorido no desenho), gerado uma vez do contorno vetorial
const APPLE_SVG := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#ffffff" d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/></svg>'
static var _apple: Texture2D
static func apple_logo() -> Texture2D:
    if _apple == null:
        var img := Image.new()
        img.load_svg_from_string(APPLE_SVG, 8.0)
        _apple = ImageTexture.create_from_image(img)
    return _apple

static func _shoulders(base: Vector2, half: float, h: float) -> PackedVector2Array:
    var pts := PackedVector2Array()
    for i in 13:
        var t := PI + PI * float(i) / 12.0
        pts.append(base + Vector2(cos(t) * half, sin(t) * h))
    return pts
