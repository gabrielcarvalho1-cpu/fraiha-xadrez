extends Control
## Gráfico da avaliação ao longo da partida: horizontal = lances, vertical = vantagem relativa
## (Brancas acima, Pretas abaixo, escala comprimida pela expectativa de vitória). Marca os
## pontos críticos (erros/erros graves/oportunidades perdidas), mate e o lance selecionado.
## Anima ao entrar (a linha "cresce" da esquerda para a direita). Funciona em celular (toque).
signal ply_selected(ply: int)

const Config := preload("res://analysis/analysis_config.gd")

var moves: Array = []
var selected := -1
var reveal := 0.0           # 0..1 (animação de entrada)
var hover := -1
var revealing := false

func _ready():
    mouse_filter = Control.MOUSE_FILTER_STOP
    resized.connect(queue_redraw)

func set_moves(list: Array, animate := true):
    moves = list
    reveal = 0.0 if animate else 1.0
    revealing = animate
    queue_redraw()

func set_selected(ply: int):
    selected = ply
    queue_redraw()

func _process(delta):
    if revealing:
        reveal = minf(1.0, reveal + delta * 1.1)
        if reveal >= 1.0: revealing = false
        queue_redraw()

## Avaliação assinada (Brancas +) → posição vertical 0..1 (0 = topo). Escala por win% para
## que +1 e +8 não fiquem "colados" e a área decisiva fique visível.
static func _y_of(signed_pawns: float) -> float:
    var cp := int(clampf(signed_pawns, -99.0, 99.0) * 100.0)
    var w := Config.win_percent(cp, 0) / 100.0   # 0..1
    return 1.0 - w

func _draw():
    var w := size.x
    var h := size.y
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.06, 0.04, 0.9))
    draw_rect(Rect2(Vector2.ZERO, size), Color("c99a45"), false, 1.5)
    if moves.is_empty(): return
    var n := moves.size()
    var step := w / float(n)
    var pts := PackedVector2Array()
    pts.append(Vector2(0, h * 0.5))
    var shown := int(ceil(n * reveal))
    for i in shown:
        var y := _y_of(float(moves[i].signed_after)) * h
        pts.append(Vector2((i + 1) * step, y))
    # áreas: Brancas (claro) acima da linha, Pretas (escuro) abaixo
    var white_poly := pts.duplicate()
    white_poly.append(Vector2(pts[pts.size() - 1].x, h * 0.5))
    white_poly.append(Vector2(0, h * 0.5))
    var black_poly := PackedVector2Array()
    for p in pts: black_poly.append(p)
    black_poly.append(Vector2(pts[pts.size() - 1].x, h * 0.5))
    black_poly.append(Vector2(0, h * 0.5))
    # clip: só a parte acima do meio é "branca" e abaixo é "preta" — desenhamos duas áreas em relação à linha do meio
    var up := PackedVector2Array()
    var down := PackedVector2Array()
    for p in pts:
        up.append(Vector2(p.x, minf(p.y, h * 0.5)))
        down.append(Vector2(p.x, maxf(p.y, h * 0.5)))
    up.append(Vector2(pts[pts.size() - 1].x, h * 0.5))
    up.append(Vector2(0, h * 0.5))
    down.append(Vector2(pts[pts.size() - 1].x, h * 0.5))
    down.append(Vector2(0, h * 0.5))
    if up.size() >= 3: draw_colored_polygon(up, Color(0.93, 0.88, 0.72, 0.85))
    if down.size() >= 3: draw_colored_polygon(down, Color(0.08, 0.12, 0.10, 0.95))
    draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), Color(0.79, 0.6, 0.27, 0.6), 1.0)
    draw_polyline(pts, Color("f1d58a"), 2.0, true)
    # marcadores de pontos críticos
    for i in shown:
        var m: Dictionary = moves[i]
        var cls := String(m.class)
        if cls in ["blunder", "mistake", "missed", "brilliant", "legendary"] or int(m.mate_in) != 0 and i == n - 1:
            var p := Vector2((i + 1) * step, _y_of(float(m.signed_after)) * h)
            var col: Color = Config.COLORS.get(cls, Color.WHITE)
            draw_circle(p, 5.0, Color(0, 0, 0, 0.7))
            draw_circle(p, 3.5, col)
    # seleção
    if selected >= 0 and selected < shown:
        var x := (selected + 1) * step
        draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 1, 1, 0.55), 1.5)
        var p := Vector2(x, _y_of(float(moves[selected].signed_after)) * h)
        draw_circle(p, 6.0, Color("ffe6a0"))
        draw_circle(p, 3.0, Color(0.1, 0.1, 0.1))
    # rótulos
    var f := get_theme_default_font()
    draw_string(f, Vector2(6, 14), "BRANCAS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.15, 0.15, 0.1, 0.8))
    draw_string(f, Vector2(6, h - 5), "PRETAS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.85, 0.75, 0.8))

func _gui_input(event):
    var p := Vector2.ZERO
    var press := false
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        p = event.position
        press = true
    elif event is InputEventScreenTouch and event.pressed:
        p = event.position
        press = true
    elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
        p = event.position
        press = true
    if press and not moves.is_empty():
        var idx := clampi(int(floor(p.x / (size.x / float(moves.size())))), 0, moves.size() - 1)
        if idx != selected:
            selected = idx
            queue_redraw()
            ply_selected.emit(idx)
        accept_event()
