extends CanvasLayer
## R96 · base dos painéis abertos pelos botões do topo da Home (RANKING e CHAT GLOBAL).
## R96.1 · na temática do jogo: a MESMA moldura das outras páginas (ui_kit/modal/moldura_*.png, tiradas das artes
## do Histórico no PC e do Conheça o FRAIHA no celular, sem o título escrito). O título vai na placa da arte e
## o botão VOLTAR / VOLTAR À HOME da arte fecha. Tocar fora da moldura também fecha.
const GOLD := Color("f4ce7f")
const CREAM := Color("efe3c4")
const DIM := Color("b9ad8e")
const FONT := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")
const FRAME_PC := preload("res://ui_kit/modal/moldura_pc.png")     # 1672 x 941
const FRAME_CEL := preload("res://ui_kit/modal/moldura_cel.png")   # 900 x 1116 (meio repete na vertical)
# retângulos na arte (pixels da textura)
const PC_TITLE := Rect2(500, 96, 676, 70)
const PC_CLOSE := Rect2(84, 812, 424, 70)
const PC_BODY := Rect2(78, 196, 1514, 604)
const CEL_TITLE := Rect2(118, 306, 664, 96)
const CEL_CLOSE := Rect2(88, 488, 724, 116)
const CEL_TOP := 700.0          # cabeçalho fixo (título + VOLTAR + borda de cima da caixa)
const CEL_BOTTOM := 188.0       # rodapé fixo
const CEL_BODY_X := Vector2(122, 778)

signal closed
var hub
var account
var shade: ColorRect
var frame: NinePatchRect
var body: VBoxContainer
var title_label: Label
var close_button: Button
var opened_ms := 0
var _body_rect := Rect2()
var _frame_rect := Rect2()

func build(p_hub, p_title: String):
	hub = p_hub
	layer = 96
	visible = false
	add_to_group("fraiha_modal")   # R142 · rolagem por toque das telas de trás ignora o dedo enquanto este painel está aberto
	preload("res://ui_v022/esc_stack.gd").register(self)   # R129 · ESC fecha (= X do painel)
	shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(_shade_input)
	add_child(shade)
	frame = NinePatchRect.new()
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(frame)
	title_label = label(p_title, 30, GOLD)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.clip_text = true   # sem largura mínima: o título fica sempre centrado na placa
	title_label.add_theme_constant_override("outline_size", 6)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_label)
	close_button = Button.new()   # área de toque sobre o VOLTAR da arte
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color(1.0, 0.86, 0.45, 0.10)
	glow.set_corner_radius_all(8)
	for st in ["normal", "focus", "disabled"]: close_button.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	close_button.add_theme_stylebox_override("hover", glow)
	close_button.add_theme_stylebox_override("pressed", glow)
	close_button.pressed.connect(close)
	add_child(close_button)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.clip_contents = true
	add_child(body)

func _ready():
	if not get_viewport().size_changed.is_connected(_layout): get_viewport().size_changed.connect(_layout)

## tamanho do texto: maior no PC (a moldura ocupa a tela toda), normal no celular.
func ts(fs: int) -> int:
	var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	return int(round(fs * (1.4 if (vs.x >= 1000.0 and vs.y >= 600.0) else 1.0)))

func label(t: String, fs: int, col: Color, semi := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", FONT_SEMI if semi else FONT)
	l.add_theme_font_size_override("font_size", ts(fs))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("10141e"))
	l.add_theme_constant_override("outline_size", 3)
	return l

func button(t: String, fs: int, on := false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", ts(fs))
	style_button(b, on)
	return b

## Abas e botões no estilo das placas do jogo: verde-escuro com moldura dourada; o ativo em ouro.
func style_button(b: Button, on: bool):
	for pair in [["normal", 0.0], ["hover", 0.08], ["pressed", -0.04], ["disabled", 0.0]]:
		var s := StyleBoxFlat.new()
		s.bg_color = (Color("d9a33a") if on else Color("15213a")).lightened(maxf(0.0, pair[1])).darkened(maxf(0.0, -pair[1]))
		s.border_color = Color("fff0b8") if on else Color("c99a45")
		s.set_border_width_all(2)
		s.set_corner_radius_all(3)
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = 3
		s.shadow_offset = Vector2(0, 2)
		for side in ["left", "right"]: s.set("content_margin_" + side, 6 if narrow() else 12)   # R123 · celular: mais espaço para o texto
		for side in ["top", "bottom"]: s.set("content_margin_" + side, 6)
		b.add_theme_stylebox_override(pair[0], s)
	var fg := Color("2a1a04") if on else CREAM
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fg)
	b.add_theme_color_override("font_outline_color", Color("10141e"))
	b.add_theme_constant_override("outline_size", 0 if on else 3)

func is_open() -> bool:
	return visible

func open():
	visible = true
	preload("res://ui_v022/web_text_field.gd").set_covered(self, true)   # R152 · campos HTML de baixo somem
	for n in [frame, body, title_label, close_button]: n.visible = true   # (o campo HTML do celular segue a visibilidade)
	opened_ms = Time.get_ticks_msec()
	_layout()
	for n in [frame, body, title_label]:
		n.modulate.a = 0.0
		create_tween().tween_property(n, "modulate:a", 1.0, 0.14)

func close():
	preload("res://ui_v022/web_text_field.gd").set_covered(self, false)
	if not visible: return
	visible = false
	for n in [frame, body, title_label, close_button]: n.visible = false
	closed.emit()

func _shade_input(e: InputEvent):
	var down: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	# o mesmo toque que abriu chega duas vezes no celular (toque + clique emulado): não fecha na hora
	if down and Time.get_ticks_msec() - opened_ms > 400: close()

func portrait() -> bool:
	var vs := get_viewport().get_visible_rect().size
	return vs.y > vs.x * 1.15

func narrow() -> bool:
	return get_viewport().get_visible_rect().size.x < 520.0

## Textos com quebra de linha medem alto demais no primeiro quadro e o corpo cresce; enquanto aberto,
## ele volta sempre ao lugar certo.
func _process(_d):
	if not visible or body == null or _body_rect.size == Vector2.ZERO: return
	if body.size != _body_rect.size or body.position != _body_rect.position:
		body.position = _body_rect.position
		body.size = _body_rect.size

## título longo (ex.: TERMOS E PRIVACIDADE) diminui até caber na placa
func _fit_title(fs: int, max_w: float) -> int:
	var f: Font = title_label.get_theme_font("font") if title_label.has_theme_font_override("font") else FONT
	while fs > 12 and f.get_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w * 0.94: fs -= 1
	return fs

func _place(n: Control, tex_rect: Rect2, s: float, origin: Vector2):
	n.position = origin + tex_rect.position * s
	n.size = tex_rect.size * s

func _layout():
	if frame == null: return
	var vs := get_viewport().get_visible_rect().size
	if portrait():
		# celular em pé: largura da tela; altura livre (o meio da moldura repete)
		frame.texture = FRAME_CEL
		frame.patch_margin_top = int(CEL_TOP)
		frame.patch_margin_bottom = int(CEL_BOTTOM)
		frame.patch_margin_left = 0
		frame.patch_margin_right = 0
		frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
		var w := minf(vs.x - 8.0, 560.0)
		var s := w / 900.0
		var h_tex := maxf(CEL_TOP + CEL_BOTTOM + 38.0 * 4.0, (vs.y - 16.0) / s)
		var origin := Vector2(floor((vs.x - w) / 2.0), floor((vs.y - h_tex * s) / 2.0))
		frame.scale = Vector2(s, s)
		frame.size = Vector2(900.0, h_tex)
		frame.position = origin
		_frame_rect = Rect2(origin, Vector2(w, h_tex * s))
		title_label.add_theme_font_size_override("font_size", _fit_title(int(clampf(CEL_TITLE.size.y * s * 0.62, 18.0, 40.0)), CEL_TITLE.size.x * s * 0.92))
		_place(title_label, CEL_TITLE, s, origin)
		_place(close_button, CEL_CLOSE, s, origin)
		_body_rect = Rect2(origin + Vector2(CEL_BODY_X.x, CEL_TOP + 6.0) * s,
			Vector2((CEL_BODY_X.y - CEL_BODY_X.x) * s, (h_tex - CEL_TOP - CEL_BOTTOM + 24.0) * s))
	else:
		# PC / deitado: a moldura inteira, proporcional
		frame.texture = FRAME_PC
		frame.patch_margin_top = 0
		frame.patch_margin_bottom = 0
		frame.patch_margin_left = 0
		frame.patch_margin_right = 0
		frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		var s := minf((vs.x - 16.0) / 1672.0, (vs.y - 8.0) / 941.0)
		s = minf(s, 1.0)
		var origin := ((vs - Vector2(1672, 941) * s) / 2.0).floor()
		frame.scale = Vector2(s, s)
		frame.size = Vector2(1672, 941)
		frame.position = origin
		_frame_rect = Rect2(origin, Vector2(1672, 941) * s)
		title_label.add_theme_font_size_override("font_size", _fit_title(int(clampf(PC_TITLE.size.y * s * 0.55, 16.0, 40.0)), PC_TITLE.size.x * s * 0.92))
		_place(title_label, PC_TITLE, s, origin)
		_place(close_button, PC_CLOSE, s, origin)
		_body_rect = Rect2(origin + PC_BODY.position * s, PC_BODY.size * s)
	body.position = _body_rect.position
	body.size = _body_rect.size
