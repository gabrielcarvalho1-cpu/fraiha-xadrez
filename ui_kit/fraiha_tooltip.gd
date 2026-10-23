extends Control
## R176.8c (PRÉVIA) · DICA DE BOTÃO no visual do jogo: placa azul-noite com moldura dourada dupla, losangos nos
## cantos, título em Cinzel e explicação curta; uma setinha aponta para o botão. Abre sempre FORA do botão
## (embaixo; sem espaço, em cima) e dentro da tela — nunca por cima de outro controle.
const FONT_T := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_B := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const NAVY_TOP := Color("16284a")
const NAVY_BOT := Color("0a1428")
const GOLD := Color("e8b242")
const GOLD_LT := Color("ffe2a0")
const CREAM := Color("efe6d2")

var title := ""
var body := ""
var arrow_x := -1.0      # x da ponta da seta (local); <0 = sem seta
var arrow_up := true     # seta em cima (dica embaixo do botão)
var pad := Vector2(16, 10)
var tfs := 17
var bfs := 15
var max_w := 360.0

static func make(t: String, b: String, k := 1.0) -> Control:
	var n = load("res://ui_kit/fraiha_tooltip.gd").new()
	n.title = t
	n.body = b
	n.tfs = int(round(17 * k))
	n.bfs = int(round(15 * k))
	n.pad = Vector2(16, 10) * k
	n.max_w = 360.0 * k
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n._measure()
	return n

func _lines() -> PackedStringArray:
	if body.is_empty(): return PackedStringArray()
	var out := PackedStringArray()
	var cur := ""
	for w in body.split(" "):
		var t := (cur + " " + w) if cur != "" else w
		if FONT_B.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x > max_w - pad.x * 2 and cur != "":
			out.append(cur)
			cur = w
		else: cur = t
	if cur != "": out.append(cur)
	return out

func _measure():
	var w := FONT_T.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	for l in _lines(): w = maxf(w, FONT_B.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x)
	var h := FONT_T.get_height(tfs) if title != "" else 0.0
	var n := _lines().size()
	if n > 0: h += (6.0 if title != "" else 0.0) + n * FONT_B.get_height(bfs)
	size = Vector2(w + pad.x * 2, h + pad.y * 2) + Vector2(0, 8)
	custom_minimum_size = size

## coloca a dica junto do retângulo do botão `r` (coordenadas da tela), dentro de `screen`
func place_near(r: Rect2, screen: Rect2, gap := 8.0):
	var below := r.end.y + gap + size.y <= screen.end.y
	arrow_up = below
	var x := clampf(r.get_center().x - size.x / 2.0, screen.position.x + 6, screen.end.x - size.x - 6)
	var y := (r.end.y + gap) if below else (r.position.y - gap - size.y)
	position = Vector2(x, y)
	arrow_x = clampf(r.get_center().x - x, 18.0, size.x - 18.0)
	queue_redraw()

## sem espaço livre em cima/embaixo: ao LADO do botão (esquerda; sem espaço, direita), centrada na altura
func place_side(r: Rect2, screen: Rect2, gap := 10.0):
	arrow_x = -1.0
	var x := r.position.x - gap - size.x
	if x < screen.position.x + 6: x = r.end.x + gap
	var y := clampf(r.get_center().y - size.y / 2.0, screen.position.y + 6, screen.end.y - size.y - 6)
	position = Vector2(x, y)
	queue_redraw()

func _draw():
	var box := Rect2(Vector2(0, 8 if arrow_up else 0), size - Vector2(0, 8))
	# sombra
	draw_rect(Rect2(box.position + Vector2(3, 4), box.size), Color(0, 0, 0, 0.45))
	# fundo em degradê
	var n := 12
	for i in n:
		var t0 := float(i) / n
		draw_rect(Rect2(box.position.x, box.position.y + box.size.y * t0, box.size.x, box.size.y / n + 1), NAVY_TOP.lerp(NAVY_BOT, t0))
	# seta
	if arrow_x >= 0:
		var ax := arrow_x
		var tip := Vector2(ax, 0) if arrow_up else Vector2(ax, size.y)
		var base_y := box.position.y if arrow_up else box.end.y
		var tri := PackedVector2Array([tip, Vector2(ax - 11, base_y + (1 if arrow_up else -1)), Vector2(ax + 11, base_y + (1 if arrow_up else -1))])
		draw_colored_polygon(tri, NAVY_TOP if arrow_up else NAVY_BOT)
		draw_polyline(PackedVector2Array([Vector2(ax - 11, base_y), tip, Vector2(ax + 11, base_y)]), GOLD, 2.0, true)
	# moldura dourada dupla
	draw_rect(box, GOLD, false, 2.0)
	draw_rect(box.grow(-4), Color(GOLD_LT.r, GOLD_LT.g, GOLD_LT.b, 0.35), false, 1.0)
	if arrow_x >= 0:   # abre a moldura onde a seta encosta
		var by := box.position.y if arrow_up else box.end.y
		draw_line(Vector2(arrow_x - 10, by), Vector2(arrow_x + 10, by), NAVY_TOP if arrow_up else NAVY_BOT, 3.0)
	for c in [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]:
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), GOLD)
	# textos
	var y := box.position.y + pad.y
	if title != "":
		y += FONT_T.get_ascent(tfs)
		draw_string_outline(FONT_T, Vector2(pad.x, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 3, Color(0.03, 0.02, 0.0, 0.8))
		draw_string(FONT_T, Vector2(pad.x, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color("f6d27a"))
		y += FONT_T.get_descent(tfs) + 6.0
	for l in _lines():
		y += FONT_B.get_ascent(bfs)
		draw_string(FONT_B, Vector2(pad.x, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, CREAM)
		y += FONT_B.get_descent(bfs)
