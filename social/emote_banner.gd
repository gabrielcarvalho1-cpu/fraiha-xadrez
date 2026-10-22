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
	var nw := _label(who.to_upper(), NAME_C * u, 230.0 * u, 23.0 * u, Color("e6eefc"), 2)
	# filetes dourados dos dois lados do nome (com losango na ponta) + losango pequeno em cima, como na referência
	var orn := Control.new()
	orn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orn.size = size
	orn.draw.connect(func():
		var y := NAME_C.y * u
		var gap := 10.0 * u
		var gold := Color("f0c35a")
		var th := maxf(1.0, 1.9 * u)
		var l1 := NAME_C.x * u - nw / 2.0 - gap
		var r0 := NAME_C.x * u + nw / 2.0 + gap
		if l1 - LINE_X.x * u > 8.0 * u:
			orn.draw_line(Vector2(LINE_X.x * u, y), Vector2(l1, y), gold, th, true)
			_diamond(orn, Vector2(l1, y), 3.6 * u, gold, gold)
		if LINE_X.y * u - r0 > 8.0 * u:
			orn.draw_line(Vector2(r0, y), Vector2(LINE_X.y * u, y), gold, th, true)
			_diamond(orn, Vector2(r0, y), 3.6 * u, gold, gold)
		_diamond(orn, Vector2(NAME_C.x * u, 61.0 * u), 5.0 * u, gold, Color("2a5fd6")))
	add_child(orn)
	_label(text.to_upper(), TEXT_C * u, TEXT_W * u, 50.0 * u, Color("f6d27a"), maxi(2, int(round(5.0 * u))))

static func _diamond(ci: CanvasItem, c: Vector2, r: float, edge: Color, fill: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), edge)
	if fill != edge:
		var q := r * 0.55
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -q), c + Vector2(q, 0), c + Vector2(0, q), c + Vector2(-q, 0)]), fill)

## Texto centrado (a fonte encolhe até caber em w). Devolve a largura do texto.
func _label(t: String, center: Vector2, w: float, fs: float, col: Color, outline: int) -> float:
	var px := maxi(8, int(round(fs)))
	while px > 8 and FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > w: px -= 1
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	var lh := FONT.get_height(px)
	l.position = Vector2(center.x - w / 2.0, center.y - lh / 2.0 - 2.0)
	l.size = Vector2(w, lh + 4.0)
	add_child(l)
	return FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
