extends Control
## R103 · Vitrine: arena do produto (salão do Fundador / biblioteca do Club) com as peças do conjunto
## em destaque. Só desenho — os textos ficam por cima, num VBox filho (overlay).
## Peças: fundador_pieces.png / club_pieces.png = 2 linhas (claras, escuras) × 6 colunas
## (peão, torre, cavalo, bispo, rainha, rei), células de 362 px.

const ARENAS := {
    "founder": preload("res://cosmetics/v031/fundador_arena.png"),
    "club": preload("res://cosmetics/v031/club_arena.png"),
}
const PIECES := {
    "founder": preload("res://cosmetics/v031/fundador_pieces.png"),
    "club": preload("res://cosmetics/v031/club_pieces.png"),
}
## R103 · Fundador: o Rei e a Rainha dourados da tela de carregamento (arte principal do FRAIHA).
const SPLASH := preload("res://branding/fraiha_loading_splash_r63.png")
const SPLASH_BAND := Rect2(0, 178, 1672, 547)   # faixa sem o logo e sem a barra de carregamento
const SPLASH_PIECES_X := 825.0                  # centro do par Rei + Rainha na arte
const CELL := 362.0
const PAWN := 0
const ROOK := 1
const KNIGHT := 2
const BISHOP := 3
const QUEEN := 4
const KING := 5

var kind := "founder"
var pieces_right := true      # peças à direita (texto à esquerda); no celular ficam embaixo
var overlay: VBoxContainer

func _init(k := "founder"):
    kind = k
    name = "Showcase_" + k
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay = VBoxContainer.new()
    overlay.name = "ShowcaseText"
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(overlay)
    resized.connect(_place)
    overlay.minimum_size_changed.connect(func(): _place.call_deferred())

func _place():
    # o VBox não encolhe sozinho (filho de Control comum): zera e recoloca pela altura mínima real
    var w := size.x * (0.5 if pieces_right else 0.9)
    overlay.size = Vector2(w, 0)
    var h := overlay.get_combined_minimum_size().y
    if pieces_right:
        overlay.position = Vector2(size.x * 0.045, maxf(8.0, (size.y - h) * 0.5))
    elif kind == "founder":
        # a arte ocupa a metade de cima; se o texto não couber embaixo, a vitrine cresce
        var art_h := minf(size.y * 0.5, size.x * 0.62)
        var need := ceilf(size.x * 0.62 * 0.92 + h + 16.0)
        if w > 120.0 and need > size.y + 1.0 and need > custom_minimum_size.y and need < size.x * 2.6:
            custom_minimum_size.y = need
        overlay.position = Vector2(size.x * 0.05, maxf(art_h * 0.92, size.y - h - 14.0))
    else:
        overlay.position = Vector2(size.x * 0.05, size.y * 0.04)
    overlay.size = Vector2(w, h)
    queue_redraw()

func _piece(col: int, dark: bool, center_bottom: Vector2, h: float, alpha := 1.0):
    var tex: Texture2D = PIECES[kind]
    var src := Rect2(col * CELL, (CELL if dark else 0.0), CELL, CELL)
    var dst := Rect2(center_bottom.x - h * 0.5, center_bottom.y - h, h, h)
    # sombra no chão
    draw_set_transform(Vector2(center_bottom.x, center_bottom.y - h * 0.035), 0.0, Vector2(1.0, 0.22))
    draw_circle(Vector2.ZERO, h * 0.3, Color(0, 0, 0, 0.45 * alpha))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, alpha))

func _draw_splash(s: Vector2):
    draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.02, 0.01))
    var band := SPLASH_BAND
    var sc := (s.y * 0.96 if pieces_right else minf(s.y * 0.5, s.x * 0.62)) / band.size.y
    var cx := s.x * (0.74 if pieces_right else 0.5)
    var x0 := cx - (SPLASH_PIECES_X - band.position.x) * sc
    var y0 := 0.0 if not pieces_right else (s.y - band.size.y * sc) * 0.62
    draw_texture_rect_region(SPLASH, Rect2(x0, y0, band.size.x * sc, band.size.y * sc), band)
    var ink := Color(0.03, 0.02, 0.01)
    if pieces_right:
        # funde a borda esquerda da arte no escuro onde fica o texto
        var steps := 28
        var w := maxf(x0 + s.x * 0.18, s.x * 0.5)
        for i in steps:
            var a := 1.0 - float(i) / steps
            draw_rect(Rect2(w * i / steps, 0, w / steps + 1, s.y), Color(ink.r, ink.g, ink.b, minf(1.0, a * 1.15)))
    else:
        # celular: arte no alto, texto embaixo — funde a base da arte no escuro
        var steps2 := 16
        var top := band.size.y * sc * 0.82
        var h := band.size.y * sc - top
        for i in steps2:
            var a2 := float(i + 1) / steps2
            draw_rect(Rect2(0, top + h * i / steps2, s.x, h / steps2 + 1), Color(ink.r, ink.g, ink.b, a2))
    draw_rect(Rect2(Vector2(1, 1), s - Vector2(2, 2)), Color(0.79, 0.6, 0.27, 0.85), false, 2.0)

func _draw():
    var s := size
    if s.x < 4 or s.y < 4: return
    if kind == "founder":
        _draw_splash(s)
        return
    var tex: Texture2D = ARENAS[kind]
    var ts := tex.get_size()
    # cobre a área mostrando o alto da arena (trono/janelas)
    var sc := maxf(s.x / ts.x, s.y / ts.y)
    var vis := s / sc
    var src := Rect2((ts.x - vis.x) * 0.5, clampf((ts.y - vis.y) * 0.3, 0.0, ts.y - vis.y), vis.x, vis.y)
    draw_texture_rect_region(tex, Rect2(Vector2.ZERO, s), src)
    # escurece o lado do texto e a base, para leitura
    var ink := Color(0.029, 0.036, 0.050)
    if pieces_right:
        var steps := 24
        for i in steps:
            var x0 := s.x * 0.62 * i / steps
            var a := 0.86 * (1.0 - float(i) / steps)
            draw_rect(Rect2(x0, 0, s.x * 0.62 / steps + 1, s.y), Color(ink.r, ink.g, ink.b, a))
    else:
        var steps2 := 20
        for i in steps2:
            var y0 := s.y * 0.6 * i / steps2
            var a2 := 0.82 * (1.0 - float(i) / steps2)
            draw_rect(Rect2(0, y0, s.x, s.y * 0.6 / steps2 + 1), Color(ink.r, ink.g, ink.b, a2))
    for i in 10:
        var a3 := 0.06 * i
        draw_rect(Rect2(0, s.y * (0.85 + i * 0.015), s.x, s.y * 0.016), Color(ink.r, ink.g, ink.b, a3))
    # peças: rei ao centro, rainha e cavalo ao lado, peças escuras atrás
    var floor_y := s.y * (0.93 if pieces_right else 0.95)
    var cx := s.x * (0.75 if pieces_right else 0.5)
    var h := minf(s.y * (0.74 if pieces_right else 0.5), s.x * (0.2 if pieces_right else 0.36))
    var gap := h * 0.48
    _piece(ROOK, true, Vector2(cx - gap * 2.05, floor_y - h * 0.1), h * 0.62, 0.95)
    _piece(KNIGHT, true, Vector2(cx + gap * 2.05, floor_y - h * 0.1), h * 0.66, 0.95)
    _piece(QUEEN, false, Vector2(cx - gap * 0.95, floor_y - h * 0.03), h * 0.84)
    _piece(KNIGHT, false, Vector2(cx + gap * 1.0, floor_y - h * 0.03), h * 0.8)
    _piece(KING, false, Vector2(cx, floor_y), h)
    # moldura fina dourada
    draw_rect(Rect2(Vector2(1, 1), s - Vector2(2, 2)), Color(0.79, 0.6, 0.27, 0.85), false, 2.0)
