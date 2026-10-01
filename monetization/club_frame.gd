extends Control
## MOLDURA CLUB — benefício visual do CLUB FRAIHA (nunca do Fundador).
## Desenhada POR CIMA do retrato (Home, Perfil, cartão do jogador, Amigos/Chat futuramente):
## borda dupla dourada com verde FRAIHA, cantos em losango, coroinha no alto e brilho suave.
## Nunca cobre o rosto: só a borda e a coroa na aresta superior.
## Liga/desliga pelo entitlements.club_active() (servidor OU simulação dev_mock_club).
const Art := preload("res://monetization/premium_art.gd")

var t := 0.0
var round_shape := false   # true no medalhão redondo (cartão da conta)
var compact := false       # retratos pequenos: linhas mais finas, sem coroa
var fill_parent := true    # false: quem cria posiciona/dimensiona manualmente

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

func _draw():
    var w := size.x
    var h := size.y
    var pulse := 0.5 + 0.5 * sin(t * 2.0)
    var gold := Color("f1d58a")
    var gold_mid := Color("c99a45")
    var green := Color("2f8a4a")
    var thick := 2.0 if compact else 3.0
    if round_shape:
        var c := size / 2.0
        var r := minf(w, h) / 2.0
        draw_arc(c, r - 1.0, 0, TAU, 72, Color(green.r, green.g, green.b, 0.9), thick + 2.0)
        draw_arc(c, r - 1.0, 0, TAU, 72, gold, thick)
        draw_arc(c, r - thick - 3.0, 0, TAU, 72, Color(gold.r, gold.g, gold.b, 0.45), 1.0)
        draw_arc(c, r + 1.5, 0, TAU, 72, Color(1.0, 0.85, 0.4, 0.18 + 0.16 * pulse), 2.0)
        for i in 8:
            var a := TAU * i / 8.0
            Art.diamond(self, c + Vector2(cos(a), sin(a)) * (r - 1.0), 2.5 if compact else 3.5, gold)
        if not compact:
            var cs := r * 0.42
            var cr := Rect2(Vector2(c.x - cs / 2.0, -cs * 0.15), Vector2(cs, cs))
            draw_circle(cr.get_center(), cs * 0.62, Color(0.03, 0.10, 0.06, 0.95))
            draw_arc(cr.get_center(), cs * 0.62, 0, TAU, 24, gold, 1.5)
            Art.icon(self, "crown", cr.grow(-cs * 0.1), gold)
        return
    var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
    # verde FRAIHA por baixo, ouro por cima, filete interno e brilho pulsando por fora
    draw_rect(rect.grow(1.0), Color(1.0, 0.85, 0.4, 0.22 + 0.18 * pulse), false, 5.0)
    draw_rect(rect, Color(green.r, green.g, green.b, 0.95), false, thick + 3.0)
    draw_rect(rect, gold, false, thick)
    draw_rect(rect.grow(-(thick + 3.0)), Color(gold.r, gold.g, gold.b, 0.55), false, 1.0)
    var ds := 3.5 if compact else 5.0
    for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
        Art.diamond(self, p, ds, gold)
        Art.diamond(self, p, ds * 0.45, gold_mid)
    # meio das arestas laterais
    for p in [Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y)]:
        Art.diamond(self, p, ds * 0.8, gold)
    if not compact:
        var cs := minf(w, h) * 0.30
        var cr := Rect2(Vector2(w / 2.0 - cs / 2.0, -cs * 0.42), Vector2(cs, cs))
        draw_circle(cr.get_center(), cs * 0.60, Color(0.03, 0.10, 0.06, 0.96))
        draw_arc(cr.get_center(), cs * 0.60, 0, TAU, 28, gold, 1.5)
        Art.icon(self, "crown", cr.grow(-cs * 0.12), gold)
