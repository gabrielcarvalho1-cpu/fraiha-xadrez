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

## R116 · molduras da LOJA DE COROAS: o mesmo desenho, com a faixa central na cor da pedra (bordas de ouro).
## [claro, escuro, pedra dos cantos, fundo do medalhão, brilho]
const GEMS := {
    "prata": [Color("eef2f6"), Color("6d7884"), Color("ffffff"), Color("1a2230"), Color(0.85, 0.92, 1.0)],
    "rubi": [Color("ff5a6e"), Color("5a0816"), Color("ff8a98"), Color("2a0710"), Color(1.0, 0.35, 0.42)],
    "safira": [Color("5aa8ff"), Color("0c2257"), Color("9ccaff"), Color("0a1838"), Color(0.4, 0.65, 1.0)],
    "jade": [Color("5fe0a8"), Color("0b4a35"), Color("a8f5d2"), Color("06261b"), Color(0.4, 1.0, 0.7)],
    "ametista": [Color("c38bff"), Color("37105e"), Color("e2c4ff"), Color("1c0a30"), Color(0.75, 0.5, 1.0)],
    "obsidiana": [Color("4a4f5c"), Color("07080b"), Color("ff6a3a"), Color("07080b"), Color(1.0, 0.45, 0.2)],
}
## R166 · MOLDURAS DE ARTE (pacote do dono): imagem por cima do retrato. [x, y, largura, altura] do buraco do meio,
## em fração da imagem (monetization/frames/<id>.png): o buraco encaixa no retrato e a arte sai para fora dele.
const ART := {
    "elo_madeira": [0.1311, 0.2052, 0.7359, 0.6622],
    "elo_ferro": [0.1631, 0.2031, 0.6728, 0.6337],
    "elo_bronze": [0.1371, 0.2074, 0.7248, 0.6542],
    "elo_prata": [0.1622, 0.2537, 0.6756, 0.6127],
    "elo_ouro": [0.1568, 0.2255, 0.6893, 0.6305],
    "elo_platina": [0.1415, 0.1766, 0.717, 0.6595],
    "elo_esmeralda": [0.1323, 0.2115, 0.7365, 0.6595],
    "elo_diamante": [0.1568, 0.2293, 0.6854, 0.6337],
    "elo_mestre": [0.1544, 0.2318, 0.6912, 0.6376],
    "elo_challenger": [0.1806, 0.2467, 0.6379, 0.5979],
    "elo_grande_mestre": [0.1672, 0.2635, 0.6656, 0.6225],
    "m_safira_real": [0.1958, 0.2509, 0.6064, 0.5901],
    "m_ametista_real": [0.1513, 0.2213, 0.6963, 0.6431],
    "m_diamante_dourado": [0.1747, 0.286, 0.6538, 0.5954],
    "m_esmeralda_real": [0.1749, 0.2635, 0.6502, 0.5871],
    "m_chama_eterna": [0.1833, 0.2707, 0.6335, 0.5864],
    "m_brasa": [0.1779, 0.2419, 0.6452, 0.6347],
    "m_rubi_real": [0.1818, 0.2531, 0.6474, 0.6141],
    "m_noite_estrelada": [0.1848, 0.2669, 0.6273, 0.587],
    "m_diamante_prata": [0.148, 0.2435, 0.7052, 0.6351],
    "m_marmore_esmeralda": [0.1657, 0.2572, 0.6687, 0.6228],
}
static func is_art(s: String) -> bool:
    return ART.has(s)
static var _art_cache := {}
static func art_texture(s: String) -> Texture2D:
    if not ART.has(s): return null
    if not _art_cache.has(s): _art_cache[s] = load("res://monetization/frames/%s.png" % s)
    return _art_cache[s]
## desenha a moldura de arte `s` em volta de `rect` (o retrato) no CanvasItem `c`
static func draw_art(c: CanvasItem, s: String, rect: Rect2) -> void:
    var tex := art_texture(s)
    if tex == null: return
    var h: Array = ART[s]
    var sz := Vector2(rect.size.x / float(h[2]), rect.size.y / float(h[3]))
    c.draw_texture_rect(tex, Rect2(rect.position - Vector2(float(h[0]) * sz.x, float(h[1]) * sz.y), sz), false)

static func is_gem(s: String) -> bool:
    return GEMS.has(s)

## Cor da faixa na posição k (0 = borda externa, 1 = interna).
func band_color(k: float) -> Color:
    if GEMS.has(style):
        var g: Array = GEMS[style]
        if style == "prata": return (g[0] as Color).lerp(g[1], absf(k - 0.3) * 1.4)
        if k < 0.2: return Ribbon.gold_at(0.15 + k * 2.0)
        if k > 0.82: return Ribbon.gold_at(0.35 + (k - 0.82) * 2.0)
        return (g[0] as Color).lerp(g[1], clampf(absf(k - 0.4) * 2.2, 0.0, 1.0))
    if style != "fundador": return Ribbon.gold_at(0.08 + k * 0.84)
    if k < 0.22: return Ribbon.gold_at(0.15 + k * 2.0)
    if k > 0.8: return Ribbon.gold_at(0.35 + (k - 0.8) * 2.0)
    return Color("1b150e").lerp(Color("3a2c1a"), absf(k - 0.5) * 2.0)

func medallion_color() -> Color:
    if GEMS.has(style): return GEMS[style][3]
    return Color("140d06") if style == "fundador" else Color("0f1b32")

func halo_color() -> Color:
    if GEMS.has(style): return GEMS[style][4]
    return Color(1.0, 0.85, 0.4)

func gem_color() -> Color:
    if GEMS.has(style): return GEMS[style][2]
    return Color("d8423a") if style == "fundador" else Color("fff3cf")

func _init():
    name = "ClubFrame"
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready():
    if fill_parent: set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    resized.connect(queue_redraw)

func _process(delta):
    if ART.has(style): return   # arte parada: não redesenha todo quadro
    if is_visible_in_tree():
        t += delta
        queue_redraw()

## Espessura da faixa de ouro para este retrato.
func band() -> float:
    var m := minf(size.x, size.y)
    return clampf(m * (0.07 if compact else 0.10), 4.0, 14.0)

func _draw():
    if ART.has(style):
        draw_art(self, style, Rect2(Vector2.ZERO, size))
        return
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
    var hc := halo_color()
    for i in 3:
        draw_rect(rect.grow(2.0 + i * 3.0), Color(hc.r, hc.g, hc.b, (0.16 - i * 0.045) * (0.5 + 0.5 * pulse)), false, 3.0)
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
        Art.diamond(self, o, ds * 0.5, Color("1b150e") if style == "fundador" else (GEMS[style][1] if GEMS.has(style) else Color("c99a45")))
        Art.diamond(self, o, ds * (0.32 if GEMS.has(style) else 0.22), gem_color())
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
        draw_circle(cc, cs * 0.45, Color(hc.r, hc.g, hc.b, 0.08 + 0.12 * pulse))
        if style == "fundador":
            draw_texture_rect(FOUNDER_SEAL, Rect2(cc - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), false)
        else:
            Art.icon(self, "crown", Rect2(cc - Vector2(cs, cs) * 0.36, Vector2(cs, cs) * 0.72), gem_color() if GEMS.has(style) else Color("ffe6a0"))
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
    var hc := halo_color()
    for i in 3:
        draw_arc(c, r + 2.0 + i * 3.0, 0, TAU, 72, Color(hc.r, hc.g, hc.b, (0.16 - i * 0.045) * (0.5 + 0.5 * pulse)), 3.0)
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
        Art.diamond(self, o, ds * 0.4, gem_color())
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
