extends Control
## R108 · EXPERIMENTAR: o tabuleiro de verdade do universo (Fundador ou Club) — arena, casas na cor do tabuleiro,
## moldura e as peças do conjunto na posição inicial — para a pessoa ver exatamente o que vai ganhar.
## Só desenho, nada muda na conta nem no jogo.
const Catalog := preload("res://cosmetics/theme_catalog.gd")
const BACK := ["R", "N", "B", "Q", "K", "B", "N", "R"]

var theme_id := "fundador"
var pieces := {}
var arena: Texture2D
var data := {}

func _init(id := "fundador"):
	theme_id = id
	name = "PreviewBoard_" + id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	data = Catalog.get_theme(id)
	arena = Catalog.texture(String(data.get("arena_path", "")))
	pieces = Catalog.piece_textures(id)

func _draw():
	var s := size
	if s.x < 8 or s.y < 8: return
	if arena != null:
		var ts := arena.get_size()
		var sc := maxf(s.x / ts.x, s.y / ts.y)
		var vis := s / sc
		draw_texture_rect_region(arena, Rect2(Vector2.ZERO, s), Rect2((ts - vis) * 0.5, vis))
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.25))
	var pal: Array = data.get("board_palette", [Color("ead6a4"), Color("2a2118")])
	var rim: Color = data.get("rim", Color("ffd36b"))
	var side := minf(s.x, s.y) * 0.86
	var o := (s - Vector2(side, side)) * 0.5
	var cell := side / 8.0
	# sombra e moldura
	draw_rect(Rect2(o + Vector2(6, 10), Vector2(side, side)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(o - Vector2(10, 10), Vector2(side + 20, side + 20)), rim.darkened(0.55))
	draw_rect(Rect2(o - Vector2(10, 10), Vector2(side + 20, side + 20)), rim, false, 3.0)
	for y in 8:
		for x in 8:
			draw_rect(Rect2(o + Vector2(x, y) * cell, Vector2(cell, cell)), pal[(x + y) % 2])
	for x in 8:
		_piece("b" + BACK[x], o + Vector2(x, 0) * cell, cell)
		_piece("bP", o + Vector2(x, 1) * cell, cell)
		_piece("wP", o + Vector2(x, 6) * cell, cell)
		_piece("w" + BACK[x], o + Vector2(x, 7) * cell, cell)

func _piece(code: String, at: Vector2, cell: float):
	var t: Texture2D = pieces.get(code)
	if t == null: return
	var ts := t.get_size()
	var h := cell * 0.98
	var w := h * ts.x / maxf(1.0, ts.y)
	draw_texture_rect(t, Rect2(at + Vector2((cell - w) * 0.5, cell - h - cell * 0.02), Vector2(w, h)), false)
