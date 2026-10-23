extends Control
## R176 · Faixa do emote no padrão da referência (placa azul, moldura dourada com gemas e medalhão redondo):
## o emote animado vai no medalhão, o nome em cima (VOCÊ / apelido) e a frase grande em dourado.
## Aparece pequena, AO LADO DA FOTO de quem mandou — nunca no meio do tabuleiro.
## Medidas em px da arte social/art/emote_banner.png (640 x 208).

const TEX := preload("res://social/art/emote_banner.png")
const FONT := preload("res://account/fonts/Cinzel-Bold.woff")
const REF := Vector2(640, 208)
const MEDAL := Vector2(129, 119)     # centro do medalhão
const MEDAL_R := 69.0
const NAME_C := Vector2(388, 87)     # centro do nome (entre os dois filetes dourados)
const LINE_X := Vector2(228, 548)    # onde os filetes começam/terminam
const TEXT_C := Vector2(402, 137)    # centro da frase
const TEXT_W := 360.0                # largura útil da frase
const TEXT_MID := Vector2(398, 114)  # R178l · centro da frase sem o nome

## Monta a faixa com altura h (px de tela).
static func make(text: String, who: String, emote_id: String, h: float) -> Control:
	var b = load("res://social/emote_banner.gd").new()
	b._build(text, who, emote_id, h)
	return b

func _build(text: String, who: String, emote_id: String, h: float) -> void:
	name = "EmoteBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var u := h / REF.y
	size = REF * u
	custom_minimum_size = size
	var bg := TextureRect.new()
	bg.texture = TEX
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.size = size
	add_child(bg)
	if not emote_id.is_empty():
		var side := MEDAL_R * 1.62 * u
		var fx: Control = preload("res://social/emote_fx.gd").make(emote_id, side)
		fx.position = MEDAL * u - Vector2(side, side) / 2.0
		add_child(fx)
	# R178l · sem o nome de quem mandou (a faixa já fica no cartão dele): só a frase, maior e no meio da placa
	# R180 · desenhada direto com a mesma fonte que mede (o Label crescia para a direita em faixa pequena e a frase
	# saía da placa / descentralizada); escolhe 1 ou 2 linhas, o que deixar a letra maior, sempre dentro da placa azul
	_phrase(text.to_upper(), u)

const PLATE := Rect2(224, 64, 344, 100)   # R180 · área azul livre para a frase (entre o medalhão e a borda direita)
var _lines: PackedStringArray = []
var _px := 12
var _ol := 2

func _phrase(t: String, u: float) -> void:
	_ol = maxi(1, int(round(4.0 * u)))
	var room := Vector2(PLATE.size.x * u - 2.0 * _ol, PLATE.size.y * u)
	var cap := maxi(6, int(62.0 * u))
	var one := _best([t], room, cap)
	var two_lines := _split(t)
	var two := _best(two_lines, room, cap) if two_lines.size() == 2 else 0
	if two > 0 and (float(two) > float(one) * 1.5 or (one < 10 and two > one)):   # uma linha, salvo se a letra ficaria bem menor ou miúda
		_lines = PackedStringArray(two_lines)
		_px = two
	else:
		_lines = PackedStringArray([t])
		_px = one
	var layer := Control.new()
	layer.name = "Phrase"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = size
	layer.draw.connect(func(): _draw_phrase(layer, u))
	add_child(layer)

static func _split(t: String) -> Array:
	if not t.contains(" "): return [t]
	var mid := t.length() / 2
	var best := -1
	for i in t.length():
		if t[i] == " " and (best < 0 or absi(i - mid) < absi(best - mid)): best = i
	return [t.substr(0, best), t.substr(best + 1)]

## maior fonte (px inteiro, até cap) em que todas as linhas cabem na largura e na altura
static func _best(lines: Array, room: Vector2, cap: int) -> int:
	var px := cap
	while px > 6:
		var w := 0.0
		for l in lines: w = maxf(w, FONT.get_string_size(String(l), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
		var hh := FONT.get_height(px) * lines.size() * (0.92 if lines.size() > 1 else 1.0)
		if w <= room.x and hh <= room.y: break
		px -= 1
	return px

func _draw_phrase(ci: Control, u: float) -> void:
	var c := (PLATE.position + PLATE.size / 2.0) * u
	var lh := FONT.get_height(_px) * (0.92 if _lines.size() > 1 else 1.0)
	var top := c.y - lh * _lines.size() / 2.0
	for i in _lines.size():
		var s := _lines[i]
		var w := FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, _px).x
		var pos := Vector2(round(c.x - w / 2.0), round(top + lh * i + FONT.get_ascent(_px) - (FONT.get_height(_px) - lh) * 0.5))
		ci.draw_string_outline(FONT, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, _px, _ol * 2, Color(0.08, 0.04, 0.0, 0.9))
		ci.draw_string(FONT, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, _px, Color("f6d27a"))

## R180 · usado pelo teste: retângulos de cada linha da frase (px da faixa)
func phrase_rects() -> Array:
	var u := size.y / REF.y
	var c := (PLATE.position + PLATE.size / 2.0) * u
	var lh := FONT.get_height(_px) * (0.92 if _lines.size() > 1 else 1.0)
	var top := c.y - lh * _lines.size() / 2.0
	var out := []
	for i in _lines.size():
		var w := FONT.get_string_size(_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _px).x
		out.append(Rect2(c.x - w / 2.0 - _ol, top + lh * i, w + 2.0 * _ol, lh))
	return out

static func _diamond(ci: CanvasItem, c: Vector2, r: float, edge: Color, fill: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), edge)
	if fill != edge:
		var q := r * 0.55
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -q), c + Vector2(q, 0), c + Vector2(0, q), c + Vector2(-q, 0)]), fill)

## Texto centrado (a fonte encolhe até caber em w). Devolve a largura do texto.
## R176.8c · frase longa (XEQUE-MATE CHEGANDO…, JOGAMOS DE NOVO!) numa faixa pequena: se nem com a fonte
## bem menor cabe numa linha, quebra em DUAS linhas no espaço do meio — nunca passa da placa.
func _label(t: String, center: Vector2, w: float, fs: float, col: Color, outline: int, wrap := true) -> float:
	var room := w - outline * 2.0
	var px := maxi(6, int(round(fs)))
	var lo := maxi(6 if not wrap else 8, int(round(fs * (0.4 if not wrap else 0.5))))   # R178i · frase curta numa faixa pequena: uma linha só
	while px > lo and FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room: px -= 1
	var shown := t
	var lines := 1
	if wrap and FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room and t.contains(" "):
		var mid := t.length() / 2
		var best := -1
		for i in t.length():
			if t[i] == " " and (best < 0 or absi(i - mid) < absi(best - mid)): best = i
		shown = t.substr(0, best) + "\n" + t.substr(best + 1)
		lines = 2
		px = maxi(8, int(round(fs * 0.62)))
		var widest := func(q: int) -> float:
			var m := 0.0
			for part in shown.split("\n"): m = maxf(m, FONT.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, q).x)
			return m
		while px > 7 and widest.call(px) > room: px -= 1
	while px > 6 and lines == 1 and FONT.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room: px -= 1
	var l := Label.new()
	l.text = shown
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_constant_override("line_spacing", -int(px * 0.15))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	var lh := FONT.get_height(px) * lines - (px * 0.15) * (lines - 1)
	l.position = Vector2(center.x - w / 2.0, center.y - lh / 2.0 - 2.0)
	l.size = Vector2(w, lh + 4.0)
	add_child(l)
	var ms := l.get_minimum_size()
	l.size = Vector2(w, ms.y)
	l.position.y = center.y - ms.y / 2.0 - 1.0
	var tw := 0.0
	for part in shown.split("\n"): tw = maxf(tw, FONT.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return tw
