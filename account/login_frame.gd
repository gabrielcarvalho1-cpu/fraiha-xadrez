extends Control
## Moldura da tela de conta: painel verde-profundo, moldura dourada em camadas, cantos
## esculpidos, brasão com coroa no topo, estandartes laterais e os dois cavalos do jogo
## (preto à esquerda olhando para o centro, branco à direita). Só desenho; não recebe clique.
const Art := preload("res://account/login_art.gd")
const KNIGHT_B := preload("res://visual_v018/pieces/bN.tres")
const KNIGHT_W := preload("res://visual_v018/pieces/wN.tres")
var compact := false   # celular: ornamentos menores
var time := 0.0

func _init():
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta):
    if not is_visible_in_tree(): return
    time += delta
    queue_redraw()

func _draw():
    var r := Rect2(Vector2.ZERO, size)
    var k := 0.7 if compact else 1.0
    # Sombra projetada suave.
    for i in 6:
        var g := (6 - i) * 5.0 * k
        draw_rect(r.grow(g), Color(0, 0, 0, 0.07))
    # Fundo: verde profundo com leve vinheta.
    var bg := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
    draw_polygon(bg, PackedColorArray([Art.GREEN_TOP, Art.GREEN_TOP, Art.GREEN_BOTTOM, Art.GREEN_BOTTOM]))
    # Textura discreta (losangos tênues) para não parecer chapado.
    var step := 34.0 * k
    var y := r.position.y + step
    var row := 0
    while y < r.end.y - 10.0:
        var x := r.position.x + step * (0.5 if row % 2 else 1.0)
        while x < r.end.x - 10.0:
            Art.diamond(self, Vector2(x, y), 3.0 * k, Color(0.55, 0.75, 0.45, 0.035))
            x += step
        y += step * 0.8
        row += 1
    # Moldura dourada em camadas (bronze escuro, ouro, brilho, filete interno).
    draw_rect(r, Art.GOLD_DEEP, false, 11.0 * k)
    draw_rect(r.grow(-2.0 * k), Art.GOLD_DARK, false, 7.0 * k)
    draw_rect(r.grow(-3.5 * k), Art.GOLD_MID, false, 3.5 * k)
    draw_rect(r.grow(-2.2 * k), Color(1, 0.93, 0.7, 0.55), false, 1.0)
    draw_rect(r.grow(-13.0 * k), Color(Art.GOLD_MID.r, Art.GOLD_MID.g, Art.GOLD_MID.b, 0.55), false, 1.2)
    # Cantos esculpidos.
    for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
        _corner(r, corner, k)
    # Losangos no meio das laterais e da base.
    for p in [Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Vector2(r.get_center().x, r.end.y)]:
        Art.diamond(self, p, 10.0 * k, Art.GOLD_MID)
        Art.diamond(self, p, 6.0 * k, Art.GOLD)
        Art.diamond(self, p, 2.6 * k, Art.GOLD_DEEP)
    _filigree(r, k)
    _banners(r, k)
    _knights(r, k)
    _crest(r, k)

func _corner(r: Rect2, corner: Vector2, k: float):
    var dir := Vector2(1 - corner.x * 2, 1 - corner.y * 2)       # aponta para dentro
    var p := r.position + r.size * corner
    var arm := 46.0 * k
    var col := Art.GOLD_MID
    # Cantoneira em L grossa.
    draw_line(p, p + Vector2(dir.x * arm, 0), Art.GOLD_DEEP, 9.0 * k)
    draw_line(p, p + Vector2(0, dir.y * arm), Art.GOLD_DEEP, 9.0 * k)
    draw_line(p, p + Vector2(dir.x * arm, 0), col, 5.0 * k)
    draw_line(p, p + Vector2(0, dir.y * arm), col, 5.0 * k)
    # Folhas douradas ao longo das cantoneiras e uma pequena flor no canto interno.
    for d in [18.0, 32.0]:
        Art.diamond(self, p + Vector2(dir.x * d * k, 0), 3.2 * k, Art.GOLD)
        Art.diamond(self, p + Vector2(0, dir.y * d * k), 3.2 * k, Art.GOLD)
    var inner := p + dir * 17.0 * k
    for a in [0.0, PI * 0.5, PI, PI * 1.5]:
        draw_circle(inner + Vector2(cos(a), sin(a)) * 4.5 * k, 2.6 * k, Art.GOLD_MID)
    draw_circle(inner, 2.4 * k, Art.GOLD)
    Art.diamond(self, p, 8.0 * k, Art.GOLD)
    Art.diamond(self, p, 3.5 * k, Art.GOLD_DEEP)
    Art.star4(self, p + Vector2(dir.x * (arm + 8.0 * k), 0), 5.0 * k, Art.GOLD_MID)
    Art.star4(self, p + Vector2(0, dir.y * (arm + 8.0 * k)), 5.0 * k, Art.GOLD_MID)

func _filigree(r: Rect2, k: float):
    # Ramagem dourada ondulada no topo e na base, entre o brasão e os cantos.
    for edge in [r.position.y + 13.0 * k, r.end.y - 13.0 * k]:
        for s in [-1.0, 1.0]:
            var x0: float = r.get_center().x + s * 150.0 * k
            var x1: float = (r.position.x if s < 0.0 else r.end.x) - s * 70.0 * k
            var pts := PackedVector2Array()
            var n := 40
            for i in n + 1:
                var t := float(i) / n
                pts.append(Vector2(lerpf(x0, x1, t), edge + sin(t * TAU * 3.0) * 3.5 * k))
            draw_polyline(pts, Color(Art.GOLD_MID.r, Art.GOLD_MID.g, Art.GOLD_MID.b, 0.75), 1.4 * k, true)
            for i in 6:
                var t := (float(i) + 0.25) / 6.0
                Art.diamond(self, Vector2(lerpf(x0, x1, t), edge + sin(t * TAU * 3.0) * 3.5 * k), 2.2 * k, Art.GOLD)

func _banners(r: Rect2, k: float):
    # Estandartes verdes pendurados logo abaixo dos cavalos, um de cada lado.
    var w := 34.0 * k
    var h := 150.0 * k
    for side in [0, 1]:
        var x := r.position.x - w * 0.55 if side == 0 else r.end.x - w * 0.45
        var top := r.position.y + 58.0 * k
        var pts := PackedVector2Array([Vector2(x, top), Vector2(x + w, top), Vector2(x + w, top + h), Vector2(x + w / 2.0, top + h - 16.0 * k), Vector2(x, top + h)])
        Art.vertical_gradient(self, pts, Color("1d4a2c"), Color("0c2415"))
        var outline := pts.duplicate()
        outline.append(pts[0])
        draw_polyline(outline, Art.GOLD_MID, 2.0 * k)
        draw_rect(Rect2(x - 4.0 * k, top - 5.0 * k, w + 8.0 * k, 7.0 * k), Art.GOLD_MID)
        # Flor-de-lis estilizada: losango + duas folhas.
        var c := Vector2(x + w / 2.0, top + h * 0.42)
        Art.diamond(self, c, 7.0 * k, Art.GOLD)
        draw_arc(c + Vector2(-6.0 * k, 4.0 * k), 5.0 * k, -PI * 0.2, PI * 0.9, 8, Art.GOLD, 2.0 * k)
        draw_arc(c + Vector2(6.0 * k, 4.0 * k), 5.0 * k, PI * 0.1, PI * 1.2, 8, Art.GOLD, 2.0 * k)
        draw_line(c + Vector2(-7.0 * k, 11.0 * k), c + Vector2(7.0 * k, 11.0 * k), Art.GOLD, 2.0 * k)

func _knights(r: Rect2, k: float):
    var h := 118.0 * k
    var w := h * 236.0 / 330.0
    for side in [0, 1]:
        var base_x := r.position.x + 30.0 * k if side == 0 else r.end.x - 30.0 * k - w
        var rect := Rect2(base_x, r.position.y - h + 22.0 * k, w, h)
        # Pedestal dourado.
        var ped := Rect2(rect.position.x - 6.0 * k, rect.end.y - 8.0 * k, rect.size.x + 12.0 * k, 12.0 * k)
        draw_rect(ped, Art.GOLD_DEEP)
        draw_rect(ped.grow(-2.0 * k), Art.GOLD_MID)
        draw_line(ped.position + Vector2(2, 3) * k, Vector2(ped.end.x - 2.0 * k, ped.position.y + 3.0 * k), Art.GOLD, 1.5)
        # Sombra/brilho atrás do cavalo.
        draw_circle(rect.get_center() + Vector2(0, 10.0 * k), w * 0.55, Color(0.95, 0.75, 0.3, 0.06))
        if side == 0:
            # Preto à esquerda, espelhado para olhar para o centro.
            draw_texture_rect(KNIGHT_B, Rect2(rect.position + Vector2(rect.size.x, 0), Vector2(-rect.size.x, rect.size.y)), false)
        else:
            draw_texture_rect(KNIGHT_W, rect, false)

func _crest(r: Rect2, k: float):
    var c := Vector2(r.get_center().x, r.position.y + 6.0 * k)
    var w := 88.0 * k
    var h := 104.0 * k
    # Volutas ao lado do brasão.
    for s in [-1.0, 1.0]:
        var base := c + Vector2(s * w * 0.5, 4.0 * k)
        draw_line(base, base + Vector2(s * 70.0 * k, 0), Art.GOLD_DEEP, 7.0 * k)
        draw_line(base, base + Vector2(s * 70.0 * k, 0), Art.GOLD_MID, 3.5 * k)
        Art.diamond(self, base + Vector2(s * 76.0 * k, 0), 4.0 * k, Art.GOLD)
        Art.star4(self, base + Vector2(s * 96.0 * k, 4.0 * k), 5.0 * k, Art.GOLD_MID)
    # Escudo: topo reto, laterais que afinam até a ponta.
    var top := c.y - h * 0.46
    var shield := PackedVector2Array([
        Vector2(c.x - w / 2.0, top), Vector2(c.x - w * 0.18, top - 10.0 * k), Vector2(c.x, top + 4.0 * k),
        Vector2(c.x + w * 0.18, top - 10.0 * k), Vector2(c.x + w / 2.0, top),
        Vector2(c.x + w / 2.0, top + h * 0.45), Vector2(c.x + w * 0.3, top + h * 0.78), Vector2(c.x, top + h),
        Vector2(c.x - w * 0.3, top + h * 0.78), Vector2(c.x - w / 2.0, top + h * 0.45)])
    var outer := PackedVector2Array()
    for p in shield: outer.append(c + (p - c) * 1.12)
    Art.vertical_gradient(self, outer, Art.GOLD, Art.GOLD_DARK)
    Art.vertical_gradient(self, shield, Color("1e4a2c"), Color("0b2214"))
    var inner := PackedVector2Array()
    for p in shield: inner.append(c + (p - c) * 0.86)
    inner.append(inner[0])
    draw_polyline(inner, Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.6), 1.5 * k)
    # Coroa.
    var cc := Vector2(c.x, top + h * 0.47)
    var cw := w * 0.52
    var ch := h * 0.26
    var crown := PackedVector2Array([
        cc + Vector2(-cw / 2.0, ch / 2.0), cc + Vector2(-cw / 2.0, -ch * 0.25), cc + Vector2(-cw * 0.27, ch * 0.05),
        cc + Vector2(0, -ch / 2.0), cc + Vector2(cw * 0.27, ch * 0.05), cc + Vector2(cw / 2.0, -ch * 0.25), cc + Vector2(cw / 2.0, ch / 2.0)])
    var glow := 0.5 + 0.5 * sin(time * 1.6)
    Art.vertical_gradient(self, crown, Art.GOLD.lerp(Color.WHITE, 0.15 * glow), Art.GOLD_MID)
    draw_rect(Rect2(cc + Vector2(-cw / 2.0, ch / 2.0 - 1.0), Vector2(cw, ch * 0.28)), Art.GOLD_MID)
    for p in [cc + Vector2(-cw / 2.0, -ch * 0.25), cc + Vector2(0, -ch / 2.0), cc + Vector2(cw / 2.0, -ch * 0.25)]:
        draw_circle(p, 3.2 * k, Art.GOLD)
    Art.diamond(self, cc + Vector2(0, ch * 0.22), 3.5 * k, Color("2f7a3c"))
