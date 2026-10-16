extends RefCounted
## R135 · LIGAS na partida com o LAYOUT DA MADEIRA: só mudam as casas e as peças (pixel art da arte do dono) e os
## enfeites dourados dos cantos da moldura vão POR CIMA das casas. Artes: tools/art/ligas_pixel_r135.py.
const DIR := "res://cosmetics/ligas_pixel/"
const Data := preload("res://cosmetics/league_pixel_data.gd")
const IDS := ["iron", "bronze", "silver", "gold", "platina", "esmeralda", "diamante", "mestre", "grande_mestre", "challenger"]
static var _pieces := {}
static var _corners := []

static func has(theme_id: String) -> bool:
	return theme_id in IDS and ResourceLoader.exists(DIR + theme_id + "_casas.png")

static func tiles(theme_id: String) -> Texture2D:
	return load(DIR + theme_id + "_casas.png") if has(theme_id) else null

## code ("wP"…) -> [Texture2D, Rect2] no formato do piece_override do tabuleiro
static func pieces(theme_id: String) -> Dictionary:
	if not has(theme_id): return {}
	if _pieces.has(theme_id): return _pieces[theme_id]
	var tex: Texture2D = load(DIR + theme_id + "_pecas.png")
	var data = Data.PECAS.get(theme_id)
	var out := {}
	if data is Dictionary:
		for code in data:
			var r: Array = data[code]
			out[code] = [tex, Rect2(r[0], r[1], r[2], r[3])]
	_pieces = {theme_id: out}   # só a liga atual fica na memória
	return out

## enfeites dos cantos: [Texture2D, Rect2 da região no atlas, Rect2 no tabuleiro (unidades do mundo)]
static func corners(origin: Vector2, board: float) -> Array:
	if _corners.is_empty():
		_corners = [load(DIR + "cantos.png"), Data.CANTOS]
	var tex: Texture2D = _corners[0]
	var d: Dictionary = _corners[1]
	var b: Array = d.board
	var k: float = board / float(b[2])
	var sz := float(d.size)
	var out := []
	for i in (d.at as Array).size():
		var at: Array = d.at[i]
		var pos := origin + (Vector2(at[0], at[1]) - Vector2(b[0], b[1])) * k
		out.append([tex, Rect2(i * sz, 0, sz, sz), Rect2(pos, Vector2(sz, sz) * k)])
	return out
