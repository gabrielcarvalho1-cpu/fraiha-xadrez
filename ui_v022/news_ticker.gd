extends Button
## R161 · OUTDOOR da Home: a faixa "ESTRATÉGIA PARA IR MAIS LONGE" embaixo da logo vira a frase do dia (Admin →
## Novidades). Cobre o texto da arte com o mesmo fundo da faixa, escreve a frase (troca a cada 6 s quando há mais
## de uma; frase comprida corre devagar) e mostra o símbolo de toque à direita. Tocar abre NOVIDADES.
const FONT := preload("res://account/fonts/Cinzel-SemiBold.woff")
const GOLD := Color("f4ce7f")
const CREAM := Color("f3ead2")
const SWAP_S := 6.0

var feed                       # news_feed.gd
var fill_top := Color("011712")
var fill_bottom := Color("022219")
var font_px := 20
var _texts: Array = []
var _i := 0
var _t := 0.0
var _alpha := 1.0
var _scroll := 0.0
var _pulse := 0.0

func setup(p_feed, p_font_px: int, top_col: Color, bottom_col: Color):
	feed = p_feed
	font_px = p_font_px
	fill_top = top_col
	fill_bottom = bottom_col
	name = "NewsTicker"
	flat = true
	clip_contents = true   # frase comprida corre por dentro da faixa
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Novidades: atualizações, notícias, campeonatos e eventos"
	for st in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(st, StyleBoxEmpty.new())
	if feed != null: feed.changed.connect(_reload)
	_reload()

func _reload():
	_texts = feed.banner_texts() if feed != null else ["ESTRATÉGIA PARA IR MAIS LONGE"]
	_i = clampi(_i, 0, maxi(0, _texts.size() - 1))
	_scroll = 0.0
	queue_redraw()

func current() -> String:
	return String(_texts[_i]) if not _texts.is_empty() else ""

func _process(d: float):
	if not is_visible_in_tree(): return
	_pulse = fmod(_pulse + d, 1.6)
	var room := _text_room()
	var w := FONT.get_string_size(current(), HORIZONTAL_ALIGNMENT_LEFT, -1, _px()).x
	if w > room: _scroll += d * 34.0
	_t += d
	var hold := SWAP_S if w <= room else maxf(SWAP_S, (w - room) / 34.0 + 2.5)
	if _texts.size() > 1 and _t > hold:
		_alpha -= d * 3.0
		if _alpha <= 0.0:
			_alpha = 0.0
			_i = (_i + 1) % _texts.size()
			_t = 0.0
			_scroll = 0.0
	elif _alpha < 1.0:
		_alpha = minf(1.0, _alpha + d * 3.0)
	queue_redraw()

func _px() -> int:
	return maxi(9, int(round(font_px * minf(1.0, size.y / 36.0) if size.y > 0.0 else font_px)))

func _icon_rect() -> Rect2:
	var s := size.y * 0.78
	return Rect2(Vector2(size.x - s - size.y * 0.16, (size.y - s) / 2.0), Vector2(s, s))

func _text_room() -> float:
	return _icon_rect().position.x - size.y * 0.5

func _draw():
	var r := Rect2(Vector2.ZERO, size)
	# fundo da faixa (cobre o texto da arte)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([fill_top, fill_top, fill_bottom, fill_bottom]))
	if is_hovered(): draw_rect(r, Color(1, 0.9, 0.6, 0.06))
	var t := current()
	var px := _px()
	var room := _text_room()
	var w := FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var base_y := size.y / 2.0 + px * 0.36
	var col := Color(CREAM, _alpha)
	var x0 := size.y * 0.4
	if w <= room:
		x0 = x0 + (room - x0 - w) / 2.0 + size.y * 0.1
		draw_string_outline(FONT, Vector2(x0, base_y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 3, Color(0, 0, 0, 0.5 * _alpha))
		draw_string(FONT, Vector2(x0, base_y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	else:
		# frase comprida: corre da direita para a esquerda dentro da faixa (corte suave nas pontas)
		var off := minf(_scroll, w - room + x0)
		var clip_l := x0
		var x := x0 - off
		draw_string(FONT, Vector2(x, base_y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
		# esconde o que passou das pontas com o próprio fundo
		_mask(Rect2(0, 0, clip_l, size.y))
		_mask(Rect2(room, 0, size.x - room, size.y))
	# símbolo de toque: círculo dourado com a seta, pulsando de leve
	var ir := _icon_rect()
	var c := ir.get_center()
	var rad := ir.size.x / 2.0
	var p := 0.5 + 0.5 * sin(_pulse / 1.6 * TAU)
	draw_circle(c, rad * (1.0 + 0.18 * p), Color(GOLD, 0.16 * (1.0 - p)))
	draw_circle(c, rad, Color("0d1626"))
	draw_arc(c, rad - 1.0, 0, TAU, 32, GOLD, 2.0, true)
	var a := rad * 0.36
	draw_polyline(PackedVector2Array([c + Vector2(-a * 0.5, -a), c + Vector2(a * 0.6, 0), c + Vector2(-a * 0.5, a)]), GOLD, maxf(2.0, rad * 0.16), true)

func _mask(m: Rect2):
	if m.size.x <= 0.0: return
	var a := m.position.y / maxf(1.0, size.y)
	var b := m.end.y / maxf(1.0, size.y)
	draw_polygon(PackedVector2Array([m.position, Vector2(m.end.x, m.position.y), m.end, Vector2(m.position.x, m.end.y)]),
		PackedColorArray([fill_top.lerp(fill_bottom, a), fill_top.lerp(fill_bottom, a), fill_top.lerp(fill_bottom, b), fill_top.lerp(fill_bottom, b)]))
