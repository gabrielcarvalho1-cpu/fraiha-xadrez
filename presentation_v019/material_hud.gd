extends Control
## R38.3 · Pontos e peças capturadas nas partidas de xadrez (bot, online casual, ranqueada e local).
## A fonte da verdade é o próprio tabuleiro (game.pieces): o que falta de cada cor em relação ao conjunto
## inicial foi capturado (peão promovido conta como peão que saiu, e a peça nova entra no material).
## Valores das peças como no Chess.com: peão 1, cavalo 3, bispo 3, torre 5, dama 9 (rei não conta).
## Duas faixas: a do ADVERSÁRIO (peças suas que ele capturou) e a SUA (peças dele que você capturou),
## cada uma com o total de pontos capturados; quem está na frente mostra "+N" (diferença dos dois totais).

const VALUES := {"P": 1, "N": 3, "B": 3, "R": 5, "Q": 9, "K": 0}
const START := {"P": 8, "N": 2, "B": 2, "R": 2, "Q": 1}
const ORDER := ["P", "N", "B", "R", "Q"]     # ordem de exibição (como no Chess.com)
const CREAM := Color("efe3c4")
const GOLD := Color("f0c96a")

var game = null                 # world.gd
var top_rect := Rect2()         # faixa do adversário (coordenadas da tela)
var bottom_rect := Rect2()      # faixa do jogador
var compact := false            # celular: ícones menores, sem moldura
var _key := ""

func _init():
    name = "MaterialHud"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)

## Material de cada cor e peças capturadas por cada cor, calculados só a partir do tabuleiro.
## Devolve {"material": {"w": int, "b": int}, "captured_by": {"w": [códigos pretos], "b": [códigos brancos]},
##          "diff": material branco - material preto}.
static func summarize(pieces: Dictionary) -> Dictionary:
    var count := {"w": {}, "b": {}}
    var material := {"w": 0, "b": 0}
    for cell in pieces:
        var code := String(pieces[cell])
        if code.length() < 2: continue
        var c := code.substr(0, 1)
        var kind := code.substr(1, 1)
        if not count.has(c): continue
        count[c][kind] = int(count[c].get(kind, 0)) + 1
        material[c] += int(VALUES.get(kind, 0))
    var captured_by := {"w": [], "b": []}
    for c in ["w", "b"]:
        var extras := 0
        for kind in ["N", "B", "R", "Q"]: extras += maxi(0, int(count[c].get(kind, 0)) - int(START[kind]))
        var other := "b" if c == "w" else "w"
        for kind in ORDER:
            var missing: int
            if kind == "P": missing = maxi(0, 8 - int(count[c].get("P", 0)) - extras)
            else: missing = maxi(0, int(START[kind]) - int(count[c].get(kind, 0)))
            for k in missing: captured_by[other].append(c + kind)
    var points := {"w": 0, "b": 0}
    for c in ["w", "b"]:
        for code in captured_by[c]: points[c] += int(VALUES.get(String(code).substr(1, 1), 0))
    return {"material": material, "captured_by": captured_by, "points": points, "diff": int(material.w) - int(material.b)}

## Cor do jogador (embaixo do tabuleiro).
func my_color() -> String:
    if game == null: return "w"
    return "b" if game.board_flipped() else "w"

func _process(_delta):
    if not visible or game == null: return
    var key := "%d|%d|%s|%s|%s" % [int(game.move_count), str(game.pieces).hash(), str(top_rect), str(bottom_rect), my_color()]
    if key != _key:
        _key = key
        queue_redraw()

func _draw():
    if game == null: return
    var sm := summarize(game.pieces)
    var me := my_color()
    var them := "b" if me == "w" else "w"
    var mine: int = int(sm.points[me])
    var theirs: int = int(sm.points[them])
    _row(top_rect, sm.captured_by[them], theirs, theirs - mine, "ADVERSÁRIO")
    _row(bottom_rect, sm.captured_by[me], mine, mine - theirs, "VOCÊ")

## Uma faixa: ícones das peças que aquele jogador capturou (agrupadas por tipo; encolhem para caber todas),
## o total de pontos dele ("13 pts") e, para quem está na frente, "+N" (diferença entre os dois totais).
func _row(r: Rect2, codes: Array, pts: int, adv: int, who: String):
    if r.size.x <= 0.0 or r.size.y <= 0.0: return
    if compact and codes.is_empty(): return       # celular: sem faixa vazia
    var bg := StyleBoxFlat.new()
    bg.bg_color = Color(0.04, 0.10, 0.07, 0.8)
    bg.border_color = Color("8a7442")
    bg.set_border_width_all(1)
    bg.set_corner_radius_all(8)
    draw_style_box(bg, r)
    var font := get_theme_default_font()
    var cy := r.get_center().y
    var fs := int(r.size.y * (0.5 if compact else 0.42))
    var pad := 6.0 if compact else 10.0
    # texto da direita: "VOCÊ · 13 pts" (no celular só "13 pts") e o "+N" dourado de quem está na frente
    var ptxt := "%d %s" % [pts, "pt" if pts == 1 else "pts"]
    var lw := font.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
    var lx := r.end.x - pad - lw
    draw_string(font, Vector2(lx, cy + fs * 0.36), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(CREAM, 0.95))
    var right := lx - 8.0
    if not compact:
        var tfs := int(fs * 0.62)
        var tw := font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
        draw_string(font, Vector2(lx - 8.0 - tw, cy + tfs * 0.36), who, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(CREAM, 0.5))
        right = lx - 16.0 - tw
    if adv > 0:
        var at := "+%d" % adv
        var aw := font.get_string_size(at, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0
        var pill := Rect2(Vector2(right - aw, cy - fs * 0.62), Vector2(aw, fs * 1.24))
        var pb := StyleBoxFlat.new()
        pb.bg_color = Color("caa04a")
        pb.set_corner_radius_all(6)
        draw_style_box(pb, pill)
        draw_string(font, Vector2(pill.position.x + 7.0, cy + fs * 0.36), at, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("1c1405"))
        right = pill.position.x - 8.0
    if codes.is_empty():
        if not compact: draw_string(font, Vector2(r.position.x + pad, cy + fs * 0.36), "Nenhuma captura", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.85), Color(CREAM, 0.5))
        return
    # ícones: o mesmo tipo fica encostado (0,42), tipos diferentes separados (0,8); tudo encolhe para caber
    var ic := r.size.y * (0.84 if compact else 0.8)
    var need := ic
    for k in range(1, codes.size()): need += ic * (0.42 if codes[k] == codes[k - 1] else 0.8)
    var avail := right - (r.position.x + pad)
    if need > avail and need > 0.0: ic *= avail / need
    var x := r.position.x + pad
    for k in codes.size():
        var code := String(codes[k])
        if k > 0: x += ic * (0.42 if code == String(codes[k - 1]) else 0.8)
        var tex: Texture2D = game.piece_textures.get(code)
        if tex == null: continue
        var ts := tex.get_size()
        var sz := ts * (ic / maxf(ts.x, ts.y))
        var pr := Rect2(Vector2(x + (ic - sz.x) / 2.0, cy - sz.y / 2.0), sz)
        # disco suave atrás (claro nas peças escuras, escuro nas claras) para ler sobre qualquer fundo
        var dark_piece := code.begins_with("b")
        draw_circle(pr.get_center() + Vector2(0, ic * 0.04), ic * 0.44, Color(0.93, 0.86, 0.68, 0.55) if dark_piece else Color(0.02, 0.05, 0.03, 0.55))
        draw_texture_rect(tex, pr, false)

## Vantagem exibida para a cor = pontos que ela capturou − pontos que o outro capturou (testes).
func advantage_for(color: String) -> int:
    if game == null: return 0
    var pts: Dictionary = summarize(game.pieces).points
    var other := "b" if color == "w" else "w"
    return int(pts[color]) - int(pts[other])

## Pontos capturados exibidos para a cor (testes).
func points_for(color: String) -> int:
    if game == null: return 0
    return int(summarize(game.pieces).points[color])
