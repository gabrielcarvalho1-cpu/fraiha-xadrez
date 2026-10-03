extends Control
## R38.3 · Pontos e peças capturadas nas partidas de xadrez (bot, online casual, ranqueada e local).
## A fonte da verdade é o próprio tabuleiro (game.pieces): o que falta de cada cor em relação ao conjunto
## inicial foi capturado (peão promovido conta como peão que saiu, e a peça nova entra no material).
## Valores das peças como no Chess.com: peão 1, cavalo 3, bispo 3, torre 5, dama 9 (rei não conta).
## Duas faixas: a do ADVERSÁRIO (peças suas que ele capturou) e a SUA (peças dele que você capturou);
## quem está na frente mostra "+N".

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
    return {"material": material, "captured_by": captured_by, "diff": int(material.w) - int(material.b)}

## Cor do jogador (embaixo do tabuleiro).
func my_color() -> String:
    if game == null: return "w"
    return "b" if game.board_flipped() else "w"

func _process(_delta):
    if not visible or game == null: return
    var key := "%d|%d|%s|%s" % [int(game.move_count), game.pieces.size(), str(top_rect), str(bottom_rect)]
    if key != _key:
        _key = key
        queue_redraw()

func _draw():
    if game == null: return
    var sm := summarize(game.pieces)
    var me := my_color()
    var them := "b" if me == "w" else "w"
    var diff: int = int(sm.diff) if me == "w" else -int(sm.diff)
    _row(top_rect, sm.captured_by[them], -diff, "ADVERSÁRIO")
    _row(bottom_rect, sm.captured_by[me], diff, "VOCÊ")

## Uma faixa: ícones das peças capturadas (agrupadas por tipo, levemente sobrepostas) e "+N" se na frente.
func _row(r: Rect2, codes: Array, adv: int, who: String):
    if r.size.x <= 0.0 or r.size.y <= 0.0: return
    if compact and codes.is_empty() and adv <= 0: return       # celular: sem faixa vazia
    if true:
        var bg := StyleBoxFlat.new()
        bg.bg_color = Color(0.04, 0.10, 0.07, 0.78)
        bg.border_color = Color("8a7442")
        bg.set_border_width_all(1)
        bg.set_corner_radius_all(8)
        draw_style_box(bg, r)
    var ic := r.size.y * (0.84 if compact else 0.82)
    var x := r.position.x + (4.0 if compact else 10.0)
    var cy := r.get_center().y
    var font := get_theme_default_font()
    var fs := int(r.size.y * (0.56 if compact else 0.5))
    var tag_w := 0.0
    if not compact:
        # quem é quem (o adversário em cima, você embaixo), discreto na ponta direita
        var tfs := int(fs * 0.55)
        tag_w = font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x + 14.0
        draw_string(font, Vector2(r.end.x - tag_w + 4.0, cy + tfs * 0.36), who, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(CREAM, 0.5))
    if codes.is_empty() and adv <= 0:
        if not compact: draw_string(font, Vector2(x, cy + fs * 0.36), "Nenhuma captura", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), Color(CREAM, 0.55))
        return
    var last := ""
    var room := r.end.x - 8.0 - tag_w - (fs * 2.2 if adv > 0 else 0.0)
    for code in codes:
        var step := ic * (0.42 if String(code) == last else 0.78)
        if last == "": step = 0.0
        x += step
        if x + ic > room: break
        last = String(code)
        var tex: Texture2D = game.piece_textures.get(code)
        if tex != null:
            var ts := tex.get_size()
            var sc := ic / maxf(ts.x, ts.y)
            var sz := ts * sc
            var pr := Rect2(Vector2(x + (ic - sz.x) / 2.0, cy - sz.y / 2.0), sz)
            # disco suave atrás (claro nas peças escuras, escuro nas claras) para ler sobre qualquer fundo
            var dark_piece := String(code).begins_with("b")
            draw_circle(pr.get_center() + Vector2(0, ic * 0.04), ic * 0.44, Color(0.93, 0.86, 0.68, 0.55) if dark_piece else Color(0.02, 0.05, 0.03, 0.55))
            draw_texture_rect(tex, pr, false)
    if adv > 0:
        var tx := x + (ic + 6.0 if not codes.is_empty() else 0.0)
        draw_string(font, Vector2(tx + 1, cy + fs * 0.36 + 1), "+%d" % adv, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
        draw_string(font, Vector2(tx, cy + fs * 0.36), "+%d" % adv, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GOLD)

## Total exibido para a cor (testes / acessibilidade).
func advantage_for(color: String) -> int:
    if game == null: return 0
    var d := int(summarize(game.pieces).diff)
    return d if color == "w" else -d
