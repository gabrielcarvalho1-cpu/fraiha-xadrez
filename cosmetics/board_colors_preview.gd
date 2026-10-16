extends Control
## R139 · prévia do tabuleiro padrão (Madeira) com as cores de casas e peças dadas — posição inicial.
## Usada em TABULEIRO E PEÇAS e na vitrine do Fundador / Club. Quadrada: ocupa o maior quadrado que cabe.
const BoardColors := preload("res://cosmetics/board_colors.gd")
const SkinRef := preload("res://ranked/board_skin.gd")

var board_id := "madeira"
var piece_id := "original"
var classic_pieces := {}   # para "classicas" (o conjunto original do jogo)
var _casas: TextureRect
var _pieces: Control

func _init(p_board := "madeira", p_pieces := "original"):
	board_id = p_board
	piece_id = p_pieces
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_casas = TextureRect.new()
	_casas.texture = BoardColors.casas()
	_casas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_casas.stretch_mode = TextureRect.STRETCH_SCALE
	_casas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_casas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_casas)
	_pieces = Control.new()
	_pieces.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_pieces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pieces.draw.connect(_draw_pieces)
	add_child(_pieces)
	resized.connect(_fit)

func set_colors(p_board: String, p_pieces: String):
	board_id = p_board
	piece_id = p_pieces
	_casas.material = BoardColors.board_material(board_id)
	_pieces.queue_redraw()

func _ready():
	set_colors(board_id, piece_id)
	_fit()

func _fit():
	var side := minf(size.x, size.y)
	var r := Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	for n in [_casas, _pieces]:
		n.position = r.position
		n.size = r.size
	queue_redraw()
	_pieces.queue_redraw()

func _draw():
	var side := minf(size.x, size.y)
	draw_rect(Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)).grow(2.0), Color("c99a45"), false, 3.0)

func _dict() -> Dictionary:
	if piece_id == BoardColors.CLASSICAS:
		var out := {}
		for code in classic_pieces: out[code] = [classic_pieces[code], Rect2()]
		return out
	return BoardColors.pieces(piece_id, SkinRef.PECAS)

func _draw_pieces():
	var d := _dict()
	var cs := _pieces.size.x / 8.0
	var back := ["R", "N", "B", "Q", "K", "B", "N", "R"]
	for x in 8:
		for row in [[0, "b" + back[x]], [1, "bP"], [6, "wP"], [7, "w" + back[x]]]:
			draw_piece(_pieces, d, row[1], Rect2(Vector2(x, row[0]) * cs, Vector2(cs, cs)))

## Mesma conta da partida (world.gd _piece): uma escala só para todas as peças (0,84 unidade por pixel numa casa
## de 75) e todas apoiadas na mesma linha de base (28 abaixo do centro). Assim nada fica torto nem de outro tamanho.
static func draw_piece(c: CanvasItem, d: Dictionary, code: String, cell: Rect2):
	if not d.has(code): return
	var tex: Texture2D = d[code][0]
	var src: Rect2 = d[code][1]
	if tex == null: return
	var k := cell.size.x / 75.0
	var center := cell.get_center()
	if src.size == Vector2.ZERO:
		# peças clássicas: os tamanhos fixos que a partida usa
		var heights := {"P": 46.0, "R": 54.0, "N": 57.0, "B": 60.0, "Q": 64.0, "K": 66.0}
		var sz0 := Vector2(39.0 if code.ends_with("P") else 47.0, float(heights[code.substr(1, 1)])) * k
		c.draw_texture_rect(tex, Rect2(Vector2(center.x - sz0.x / 2.0, center.y + 27.0 * k - sz0.y), sz0), false)
		return
	var sz := src.size * 0.84 * k
	c.draw_texture_rect_region(tex, Rect2(Vector2(center.x - sz.x / 2.0, center.y + 28.0 * k - sz.y), sz), src)
