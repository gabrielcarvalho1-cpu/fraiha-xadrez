extends Control
## Tabuleiro de REVISÃO/TREINO: desenha uma posição (FEN) com as peças do FRAIHA, animação
## suave entre posições, setas (melhor lance), casas destacadas e, opcionalmente, interação
## para o jogador tentar um lance (Tentar Novamente / Treine Meus Erros).
## Independente do tabuleiro da partida: nunca altera a partida original.
signal move_tried(move: Dictionary)   # {from,to,promotion} legal na posição atual

const Rules := preload("res://chess/rules.gd")
const Notation := preload("res://analysis/notation.gd")

var pos = null                 # Rules
var flipped := false
var interactive := false
var selected := Vector2i(-1, -1)
var legal: Array = []
var highlight := {}            # Vector2i -> Color
var arrows: Array = []         # [{from,to,color}]
var anim := {}                 # code -> {from:Vector2, to:Vector2}
var anim_t := 1.0
var textures := {}
var last_from := Vector2i(-1, -1)
var last_to := Vector2i(-1, -1)
var mark_class := ""           # classe do lance (desenha o selo na casa de chegada)
var mark_glyph := ""
var mark_color := Color.WHITE
var pulse := 0.0

func _ready():
    mouse_filter = Control.MOUSE_FILTER_STOP
    for code in ["wP","wR","wN","wB","wQ","wK","bP","bR","bN","bB","bQ","bK"]:
        textures[code] = load("res://visual_v018/pieces/" + code + ".tres")
    resized.connect(queue_redraw)
    set_process(true)

func _process(delta):
    pulse += delta
    if anim_t < 1.0:
        anim_t = minf(1.0, anim_t + delta * 4.5)
        queue_redraw()
    elif not arrows.is_empty() or mark_class != "":
        queue_redraw()

func tile() -> float:
    return minf(size.x, size.y) / 8.0

func origin() -> Vector2:
    var t := tile() * 8.0
    return (size - Vector2(t, t)) / 2.0

func display(cell: Vector2i) -> Vector2i:
    return Vector2i(7 - cell.x, 7 - cell.y) if flipped else cell

func center(cell: Vector2i) -> Vector2:
    var d := display(cell)
    return origin() + (Vector2(d) + Vector2(0.5, 0.5)) * tile()

func cell_at(point: Vector2) -> Vector2i:
    var local := (point - origin()) / tile()
    var c := Vector2i(int(floor(local.x)), int(floor(local.y)))
    if c.x < 0 or c.y < 0 or c.x > 7 or c.y > 7: return Vector2i(-1, -1)
    return display(c)

## Mostra uma posição. Se `animate`, as peças que mudaram deslizam.
func show_fen(fen: String, animate := true, p_last_from := Vector2i(-1, -1), p_last_to := Vector2i(-1, -1)):
    var new_pos = Notation.from_fen(fen)
    if new_pos == null: return
    anim.clear()
    if animate and pos != null:
        var old: Dictionary = pos.board
        for sq in new_pos.board:
            var code: String = new_pos.board[sq]
            if old.get(sq, "") == code: continue
            # procura de onde a peça veio (mesmo código que sumiu)
            for osq in old:
                if old[osq] == code and not new_pos.board.has(osq):
                    anim[sq] = {"from": center(osq), "to": center(sq)}
                    break
        anim_t = 0.0 if not anim.is_empty() else 1.0
    else:
        anim_t = 1.0
    pos = new_pos
    last_from = p_last_from
    last_to = p_last_to
    selected = Vector2i(-1, -1)
    legal.clear()
    queue_redraw()

func set_arrows(list: Array):
    arrows = list
    queue_redraw()

func set_mark(cls: String, glyph: String, color: Color):
    mark_class = cls
    mark_glyph = glyph
    mark_color = color
    queue_redraw()

func clear_marks():
    arrows.clear()
    highlight.clear()
    mark_class = ""
    queue_redraw()

func _draw():
    var t := tile()
    var o := origin()
    # moldura
    draw_rect(Rect2(o - Vector2(6, 6), Vector2(t * 8 + 12, t * 8 + 12)), Color("3a2a12"))
    draw_rect(Rect2(o - Vector2(6, 6), Vector2(t * 8 + 12, t * 8 + 12)), Color("c99a45"), false, 2.0)
    for y in 8:
        for x in 8:
            var c := Vector2i(x, y)
            var d := display(c)
            var r := Rect2(o + Vector2(d) * t, Vector2(t, t))
            draw_rect(r, Color("cbb273") if (x + y) % 2 == 0 else Color("557a3e"))
            if c == last_from or c == last_to: draw_rect(r.grow(-2), Color(1.0, 0.78, 0.2, 0.28))
            if highlight.has(c): draw_rect(r.grow(-2), highlight[c])
            if c == selected: draw_rect(r.grow(-3), Color("f3d25c"), false, 3.0)
            if c in legal:
                if pos != null and not pos.piece(c).is_empty(): draw_rect(r.grow(-4), Color("d94f3d"), false, 3.0)
                else: draw_circle(r.get_center(), t * 0.11, Color(0.95, 0.83, 0.35, 0.8))
    # coordenadas
    var f := get_theme_default_font()
    var fs := maxi(9, int(t * 0.18))
    for i in 8:
        var file := "abcdefgh"[7 - i if flipped else i]
        var rank := str(i + 1 if flipped else 8 - i)
        draw_string(f, o + Vector2(i * t + 3, t * 8 - 3), file, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45))
        draw_string(f, o + Vector2(t * 8 - fs * 0.8, i * t + fs + 2), rank, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45))
    if pos == null: return
    for sq in pos.board:
        var code: String = pos.board[sq]
        var cpos := center(sq)
        if anim.has(sq) and anim_t < 1.0:
            var a: Dictionary = anim[sq]
            var e := 1.0 - pow(1.0 - anim_t, 3.0)
            cpos = a.from.lerp(a.to, e)
        _piece(cpos, code, t)
    # setas
    for ar in arrows:
        _arrow(center(ar.from), center(ar.to), ar.get("color", Color(0.3, 0.75, 1.0, 0.85)), t)
    # selo da classificação na casa de chegada
    if mark_class != "" and last_to != Vector2i(-1, -1):
        var c := center(last_to) + Vector2(t * 0.34, -t * 0.34)
        var rad := t * 0.19 + sin(pulse * 4.0) * 1.0
        draw_circle(c, rad + 2.0, Color(0, 0, 0, 0.55))
        draw_circle(c, rad, mark_color)
        var gf := maxi(10, int(t * 0.22))
        var w := f.get_string_size(mark_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gf).x
        draw_string(f, c + Vector2(-w / 2.0, gf * 0.36), mark_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gf, Color(0.05, 0.05, 0.05))

func _piece(c: Vector2, code: String, t: float):
    var tex: Texture2D = textures.get(code)
    if tex == null: return
    var heights := {"P": 46.0, "R": 54.0, "N": 57.0, "B": 60.0, "Q": 64.0, "K": 66.0}
    var k := t / 75.0
    var h: float = heights[code.substr(1, 1)] * k
    var w: float = (39.0 if code.ends_with("P") else 47.0) * k
    draw_texture_rect(tex, Rect2(Vector2(c.x - w / 2.0, c.y + 27.0 * k - h), Vector2(w, h)), false)

func _arrow(a: Vector2, b: Vector2, col: Color, t: float):
    var dir := (b - a).normalized()
    var head := t * 0.32
    var end := b - dir * t * 0.18
    draw_line(a + dir * t * 0.25, end - dir * head * 0.6, col, t * 0.14)
    var n := Vector2(-dir.y, dir.x)
    draw_colored_polygon(PackedVector2Array([end, end - dir * head + n * head * 0.6, end - dir * head - n * head * 0.6]), col)

# ---------------------------------------------------------------- interação (treino)
func _gui_input(event):
    if not interactive or pos == null: return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _click(cell_at(event.position))
        accept_event()
    elif event is InputEventScreenTouch and event.pressed:
        _click(cell_at(event.position))
        accept_event()

func _click(cell: Vector2i):
    if cell == Vector2i(-1, -1): return
    if selected != Vector2i(-1, -1) and cell in legal:
        var code: String = pos.piece(selected)
        var promo := "Q"
        var mv := {"from": selected, "to": cell, "promotion": promo}
        selected = Vector2i(-1, -1)
        legal.clear()
        queue_redraw()
        move_tried.emit(mv)
        return
    var code: String = pos.piece(cell)
    if not code.is_empty() and code[0] == pos.turn:
        selected = cell
        legal = pos.legal_from(cell)
    else:
        selected = Vector2i(-1, -1)
        legal.clear()
    queue_redraw()
