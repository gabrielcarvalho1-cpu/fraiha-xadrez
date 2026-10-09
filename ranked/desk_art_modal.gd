extends Control
## R54 · Modal do PC (Web desktop) na arte de referência aprovada (tools/ui_ref/desk/, recortes em
## ranked/art/desk_*.png gerados por tools/desk_result_art.py). A arte traz moldura, títulos e botões de
## texto fixo; o que muda (modo/motivo, PL, liga, barra, nome, retrato, textos por modo) é desenhado por
## cima nas posições da referência, com as fontes do jogo. Os botões são áreas de clique sobre as placas
## da arte (realce suave no hover). Quem abre decide as ações: este nó não conhece regra nem servidor.
## Só no PC: no celular as telas seguem o layout próprio.
const FONT_TITLE := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_BODY := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const FONT_MED := preload("res://ui_kit/fonts/Alegreya-Medium.woff")
const BAR_FILL := preload("res://ranked/art/desk_bar_fill.png")
const CREAM := Color("f4ead2")
const GOLD := Color("f7d27a")
const MUTED := Color("c3c9bb")
const RED := Color("ff9a82")
const EMERALD := Color("8fe6a6")

var art: TextureRect
var dim: ColorRect
var ref := Vector2.ONE
var frac := 0.9                 # altura máxima da tela ocupada pela arte
var _items: Array = []          # [Control, Rect2 na referência, tamanho de fonte na referência (0 = não é texto)]
var _bar: Control
var _bar_fill: NinePatchRect
var _bar_from := 0.0
var _bar_to := 0.0
var _bar_t := 1.0
var kind := ""

func _init():
	name = "DeskArtModal"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _ready():
	get_viewport().size_changed.connect(_layout)

## Começa uma tela nova: arte + tamanho da referência (as posições abaixo são em pixels da referência).
func begin(tex: Texture2D, ref_size: Vector2, which: String, with_dim := false):
	clear()
	kind = which
	ref = ref_size
	if with_dim:
		dim = ColorRect.new()
		dim.color = Color(0.02, 0.04, 0.03, 0.8)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	art = TextureRect.new()
	art.name = "Art"
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

func clear():
	for c in get_children():   # tira já da árvore: a tela nova reusa os mesmos nomes
		remove_child(c)
		c.queue_free()
	_items.clear()
	art = null
	dim = null
	_bar = null
	_bar_fill = null
	kind = ""

func show_modal():
	visible = true
	_layout()
	if art == null: return
	art.pivot_offset = art.size / 2.0
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)

func close():
	visible = false
	clear()

func is_open() -> bool:
	return visible and art != null

# ---------------------------------------------------------------- peças vivas
func label(text: String, r: Rect2, px: float, color := CREAM, font: Font = FONT_BODY, align := HORIZONTAL_ALIGNMENT_CENTER, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.01, 0.92))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.clip_text = not wrap
	add_child(l)
	_items.append([l, r, px])
	if visible: _layout()
	return l

## circle: recorta em círculo; zoom < 1 aproxima o centro (avatares que trazem borda própria).
func image(tex: Texture2D, r: Rect2, circle := false, zoom := 1.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if circle else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if circle:
		var mat := ShaderMaterial.new()
		mat.shader = _circle_shader()
		mat.set_shader_parameter("zoom", zoom)
		t.material = mat
	add_child(t)
	_items.append([t, r, 0.0])
	return t

## Área de clique sobre a placa da arte. O realce é um brilho claro e discreto (hover) / escuro (pressionado).
func button(r: Rect2, action: Callable, id: String, radius := 18.0) -> Button:
	var b := Button.new()
	b.name = id
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = {"hover": Color(1, 0.95, 0.75, 0.10), "pressed": Color(0, 0, 0, 0.18), "disabled": Color(0, 0, 0, 0.45)}.get(st, Color(0, 0, 0, 0))
		s.set_corner_radius_all(int(radius))
		s.set_meta("radius", radius)
		b.add_theme_stylebox_override(st, s)
	b.pressed.connect(action)
	add_child(b)
	_items.append([b, r, 0.0])
	return b

## Barra de PL viva sobre o trilho vazio da arte; anima de `from` até `to` (0–100).
func bar(r: Rect2, from: float, to: float):
	_bar = Control.new()
	_bar.name = "PlBar"
	_bar.clip_contents = true
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_bar_fill = NinePatchRect.new()   # pedaço dourado da referência repetido na horizontal, esticado na vertical
	_bar_fill.texture = BAR_FILL
	_bar_fill.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	_bar_fill.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	_bar_fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_bar_fill)
	_items.append([_bar, r, -1.0])
	_bar_from = clampf(from, 0.0, 100.0)
	_bar_to = clampf(to, 0.0, 100.0)
	_bar_t = 0.0
	set_process(true)

func bar_value() -> float:
	return lerpf(_bar_from, _bar_to, _ease(_bar_t))

func _process(delta):
	if _bar == null or _bar_t >= 1.0:
		set_process(false)
		return
	_bar_t = minf(1.0, _bar_t + delta / 0.9)
	_layout_bar()

func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

# ---------------------------------------------------------------- layout
func scale_k() -> float:
	var vp := get_viewport_rect().size
	return minf(vp.y * frac / ref.y, vp.x * 0.94 / ref.x)

func art_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var k := scale_k()
	var sz := ref * k
	return Rect2((vp - sz) / 2.0, sz)

func _layout():
	if art == null: return
	var vp := get_viewport_rect().size
	if dim != null:
		dim.position = Vector2.ZERO
		dim.size = vp
	var ar := art_rect()
	var k := scale_k()
	art.position = ar.position
	art.size = ar.size
	for it in _items:
		var c: Control = it[0]
		if not is_instance_valid(c): continue
		var r: Rect2 = it[1]
		var px: float = it[2]
		if px > 0.0 and c is Label:
			# texto: largura fixa da caixa; com quebra, a altura fica a da caixa (linhas centralizadas nela)
			c.custom_minimum_size = Vector2(r.size.x * k, 0)
			c.size = r.size * k
			_fit(c, px * k)
			c.size = r.size * k
		c.position = ar.position + r.position * k
		c.size = r.size * k
		if c is Button:
			for st in ["normal", "hover", "pressed", "focus", "disabled"]:
				var s: StyleBoxFlat = c.get_theme_stylebox(st)
				s.set_corner_radius_all(int(float(s.get_meta("radius", 18.0)) * k))
	_layout_bar()

func _layout_bar():
	if _bar == null or _bar_fill == null: return
	_bar_fill.position = Vector2.ZERO
	var h := _bar.size.y
	_bar_fill.size = Vector2(_bar.size.x * bar_value() / 100.0, h)
	_bar_fill.visible = _bar_fill.size.x >= 1.0

func _fit(l: Label, px: float):
	var size := int(round(px))
	var font: Font = l.get_theme_font("font")
	if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
		while size > 8 and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > l.size.x: size -= 1
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(2, int(round(size * 0.12))))

static var _circle: Shader
static func _circle_shader() -> Shader:
	if _circle == null:
		_circle = Shader.new()
		_circle.code = "shader_type canvas_item;\nuniform float zoom = 1.0;\nvoid fragment(){ vec2 uv = (UV - vec2(0.5)) * zoom + vec2(0.5); vec4 c = texture(TEXTURE, uv); float d = distance(UV, vec2(0.5)); c.a *= smoothstep(0.5, 0.485, d); COLOR = c; }"
	return _circle
