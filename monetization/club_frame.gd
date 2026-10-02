extends Control
## MOLDURA CLUB — benefício visual do CLUB FRAIHA (nunca do Fundador).
## Desenhada POR CIMA do retrato (Home, Perfil, cartão do jogador, Amigos/Chat futuramente):
## moldura de ouro maciço com bisel metálico, filete interno, ornamentos de canto, placa com
## coroa no alto, brilho percorrendo o ouro e halo pulsando. Nunca cobre o rosto: só a borda,
## os ornamentos e a coroa na aresta superior.
## Liga/desliga pelo entitlements.club_active() (servidor OU simulação dev_mock_club).
const Art := preload("res://monetization/premium_art.gd")
const Ribbon := preload("res://monetization/club_home_entry.gd")

var t := 0.0
var round_shape := false   # true no medalhão redondo (cartão da conta)
var compact := false       # retratos pequenos: moldura mais fina, sem coroa
var fill_parent := true    # false: quem cria posiciona/dimensiona manualmente
## R31: "club" (ouro maciço, medalhão esmeralda) | "fundador" (obsidiana e ouro, medalhão negro).
const FOUNDER_SEAL := preload("res://monetization/art/founder_badge_small.png")
var style := "club":
    set(v):
        style = v
        queue_redraw()

## Cor da faixa na posição k (0 = borda externa, 1 = interna).
func band_color(k: float) -> Color:
    if style != "fundador": return Ribbon.gold_at(0.08 + k * 0.84)
    if k < 0.22: return Ribbon.gold_at(0.15 + k * 2.0)
    if k > 0.8: return Ribbon.gold_at(0.35 + (k - 0.8) * 2.0)
    return Color("1b150e").lerp(Color("3a2c1a"), absf(k - 0.5) * 2.0)

func medallion_color() -> Color:
    return Color("140d06") if style == "fundador" else Color("0b2416")

func _init():
    name = "ClubFrame"
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready():
    if fill_parent: set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    resized.connect(queue_redraw)

func _process(delta):
    if is_visible_in_tree():
        t += delta
        queue_redraw()

## Espessura da faixa de ouro para este retrato.
func band() -> float:
    var m := minf(size.x, size.y)
    return clampf(m * (0.07 if compact else 0.10), 4.0, 14.0)

func _draw():
    var w := size.x
    var h := size.y
    var pulse := 0.5 + 0.5 * sin(t * 2.0)
    var gold := Color("f1d58a")
    var b := band()
    if round_shape:
        _draw_round(w, h, b, pulse, gold)
        return
    var rect := Rect2(Vector2.ZERO, size)
    # halo pulsando por fora
    for i in 3:
        draw_rect(rect.grow(2.0 + i * 3.0), Color(1.0, 0.85, 0.4, (0.16 - i * 0.045) * (0.5 + 0.5 * pulse)), false, 3.0)
    # faixa de ouro metálico: anéis concêntricos de fora para dentro (gradiente)
    var n := int(ceil(b))
    for i in n:
        var k := float(i) / maxf(1.0, n - 1)
        draw_rect(rect.grow(-float(i) - 0.5), band_color(k), false, 1.2)
    draw_rect(rect, Color("5a3d10"), false, 1.0)                     # aresta externa escura
    draw_rect(rect.grow(-b), Color("3a2608"), false, 1.0)            # aresta interna escura
    draw_rect(rect.grow(-b - 1.5), Color(gold.r, gold.g, gold.b, 0.55), false, 1.0)   # filete claro interno
    # brilho percorrendo o perímetro
    var per := 2.0 * (w + h)
    var d := fmod(t * per * 0.18, per)
    var p := _perimeter_point(rect, d)
    for i in 3:
        draw_circle(p, b * (0.9 + i * 0.5), Color(1.0, 0.97, 0.85, 0.18 - i * 0.05))
    # ornamentos de canto (losango grande + dois pequenos nas arestas)
    var ds := b * (0.9 if compact else 1.15)
    var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
    for c in corners:
        var cc: Vector2 = c
        var dirx := 1.0 if cc.x <= rect.position.x else -1.0
        var diry := 1.0 if cc.y <= rect.position.y else -1.0
        var o := cc + Vector2(dirx, diry) * b * 0.5
        Art.diamond(self, o, ds + 1.5, Color("5a3d10"))
        Art.diamond(self, o, ds, gold)
        Art.diamond(self, o, ds * 0.5, Color("1b150e") if style == "fundador" else Color("c99a45"))
        Art.diamond(self, o, ds * 0.22, Color("d8423a") if style == "fundador" else Color("fff3cf"))
        Art.diamond(self, o + Vector2(dirx * ds * 2.2, 0), ds * 0.45, gold)
        Art.diamond(self, o + Vector2(0, diry * ds * 2.2), ds * 0.45, gold)
    # meio das arestas laterais e inferior
    for m in [Vector2(rect.position.x + b * 0.5, rect.get_center().y), Vector2(rect.end.x - b * 0.5, rect.get_center().y), Vector2(rect.get_center().x, rect.end.y - b * 0.5)]:
        Art.diamond(self, m, ds * 0.75, Color("5a3d10"))
        Art.diamond(self, m, ds * 0.6, gold)
    if not compact:
        # placa com coroa no alto (fora do retrato, sobre a aresta superior)
        var cs := clampf(minf(w, h) * 0.34, 18.0, 44.0)
        var cc := Vector2(w / 2.0, -cs * 0.12)
        draw_circle(cc + Vector2(0, 2), cs * 0.62 + 2.0, Color(0, 0, 0, 0.45))
        for i in 4:
            draw_circle(cc, cs * 0.62 + 1.5 - i * 1.3, Ribbon.gold_at(0.1 + i * 0.25))
        draw_circle(cc, cs * 0.62 - 4.0, medallion_color())
        draw_arc(cc, cs * 0.62 - 4.0, 0, TAU, 32, Color(gold.r, gold.g, gold.b, 0.6), 1.0)
        draw_circle(cc, cs * 0.45, Color(1.0, 0.85, 0.4, 0.08 + 0.12 * pulse))
        if style == "fundador":
            draw_texture_rect(FOUNDER_SEAL, Rect2(cc - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), false)
        else:
            Art.icon(self, "crown", Rect2(cc - Vector2(cs, cs) * 0.36, Vector2(cs, cs) * 0.72), Color("ffe6a0"))
        # faíscas discretas
        for i in 4:
            var a := 0.5 + 0.5 * sin(t * 1.9 + i * 1.6)
            if a < 0.4: continue
            var ci: Vector2 = corners[i]
            var sp: Vector2 = ci - Vector2(1.0 if i in [1, 2] else -1.0, 1.0 if i >= 2 else -1.0) * (b * 1.8)
            Art.star(self, sp, 2.0 + 2.5 * a, Color(1.0, 0.98, 0.85, 0.8 * a))

func _draw_round(w: float, h: float, b: float, pulse: float, gold: Color):
    var c := size / 2.0
    var r := minf(w, h) / 2.0
    for i in 3:
        draw_arc(c, r + 2.0 + i * 3.0, 0, TAU, 72, Color(1.0, 0.85, 0.4, (0.16 - i * 0.045) * (0.5 + 0.5 * pulse)), 3.0)
    var n := int(ceil(b))
    for i in n:
        var k := float(i) / maxf(1.0, n - 1)
        draw_arc(c, r - float(i) - 0.5, 0, TAU, 96, band_color(k), 1.4)
    draw_arc(c, r, 0, TAU, 96, Color("5a3d10"), 1.0)
    draw_arc(c, r - b, 0, TAU, 96, Color("3a2608"), 1.0)
    draw_arc(c, r - b - 1.5, 0, TAU, 96, Color(gold.r, gold.g, gold.b, 0.55), 1.0)
    var ang := fmod(t * 1.4, TAU)
    var p := c + Vector2(cos(ang), sin(ang)) * (r - b / 2.0)
    for i in 3:
        draw_circle(p, b * (0.8 + i * 0.5), Color(1.0, 0.97, 0.85, 0.18 - i * 0.05))
    var ds := b * (0.7 if compact else 0.9)
    for i in 8:
        var a := TAU * i / 8.0 + PI / 8.0
        var o := c + Vector2(cos(a), sin(a)) * (r - b / 2.0)
        Art.diamond(self, o, ds + 1.0, Color("5a3d10"))
        Art.diamond(self, o, ds, gold)
        Art.diamond(self, o, ds * 0.4, Color("fff3cf"))
    if not compact:
        var cs := clampf(r * 0.5, 16.0, 40.0)
        var cc := Vector2(c.x, -cs * 0.1)
        for i in 4:
            draw_circle(cc, cs * 0.62 + 1.5 - i * 1.3, Ribbon.gold_at(0.1 + i * 0.25))
        draw_circle(cc, cs * 0.62 - 4.0, medallion_color())
        Art.icon(self, "crown", Rect2(cc - Vector2(cs, cs) * 0.36, Vector2(cs, cs) * 0.72), Color("ffe6a0"))

static func _perimeter_point(rect: Rect2, d: float) -> Vector2:
    var w := rect.size.x
    var h := rect.size.y
    if d < w: return rect.position + Vector2(d, 0)
    d -= w
    if d < h: return Vector2(rect.end.x, rect.position.y + d)
    d -= h
    if d < w: return Vector2(rect.end.x - d, rect.end.y)
    d -= w
    return Vector2(rect.position.x, rect.end.y - d)
