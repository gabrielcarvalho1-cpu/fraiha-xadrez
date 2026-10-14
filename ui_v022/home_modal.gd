extends CanvasLayer
## R96 · base dos painéis abertos pelos botões do topo da Home (RANKING e CHAT GLOBAL): fundo escurecido,
## painel verde-escuro com moldura dourada, título e FECHAR. Tocar fora do painel fecha. PC e celular.
const GOLD := Color("f4ce7f")
const CREAM := Color("efe3c4")
const DIM := Color("b9ad8e")
const BG := Color(0.03, 0.09, 0.06, 0.97)
const FONT := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")
const Mobile = preload("res://ui_v022/mobile_layout.gd")

signal closed
var hub
var account
var shade: ColorRect
var panel: PanelContainer
var body: VBoxContainer
var title_label: Label
var close_button: Button
var opened_ms := 0

func build(p_hub, p_title: String):
	hub = p_hub
	layer = 96
	visible = false
	shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(_shade_input)
	add_child(shade)
	panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = BG
	st.border_color = Color("c99a45")
	st.set_border_width_all(3)
	st.set_corner_radius_all(10)
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 14
	for side in ["left", "right", "top", "bottom"]: st.set("content_margin_" + side, 14)
	panel.add_theme_stylebox_override("panel", st)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)
	title_label = label(p_title, 26, GOLD)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	head.add_child(title_label)
	close_button = button("FECHAR", 16)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	var line := ColorRect.new()
	line.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	body.add_child(line)

func _ready():
	if not get_viewport().size_changed.is_connected(_layout): get_viewport().size_changed.connect(_layout)

func label(t: String, fs: int, col: Color, semi := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", FONT_SEMI if semi else FONT)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("0b150f"))
	l.add_theme_constant_override("outline_size", 3)
	return l

func button(t: String, fs: int, on := false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", fs)
	style_button(b, on)
	return b

func style_button(b: Button, on: bool):
	for pair in [["normal", 0.0], ["hover", 0.08], ["pressed", -0.04], ["disabled", 0.0]]:
		var s := StyleBoxFlat.new()
		s.bg_color = (Color("e9b23a") if on else Color(0.07, 0.17, 0.11)).lightened(maxf(0.0, pair[1])).darkened(maxf(0.0, -pair[1]))
		s.border_color = Color("7a5512") if on else Color("c99a45")
		s.set_border_width_all(2)
		s.set_corner_radius_all(6)
		for side in ["left", "right"]: s.set("content_margin_" + side, 12)
		for side in ["top", "bottom"]: s.set("content_margin_" + side, 6)
		b.add_theme_stylebox_override(pair[0], s)
	var fg := Color("2a1a04") if on else CREAM
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fg)

var _target := Vector2.ZERO
var _scale := 1.0

## Textos com quebra de linha medem alto demais no primeiro quadro (largura ainda 0) e o painel cresce;
## enquanto aberto, ele volta sempre ao tamanho e à posição certos.
func _process(_d):
	if not visible or panel == null or _target == Vector2.ZERO: return
	if panel.size != _target:
		panel.size = _target
		panel.position = ((get_viewport().get_visible_rect().size - _target * _scale) / 2.0).floor()

func is_open() -> bool:
	return visible

func open():
	visible = true
	panel.visible = true   # (o campo HTML do celular segue a visibilidade do painel)
	opened_ms = Time.get_ticks_msec()
	_layout()
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.14)

func close():
	if not visible: return
	visible = false
	panel.visible = false
	closed.emit()

func _shade_input(e: InputEvent):
	var down: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
	# o mesmo toque que abriu chega duas vezes no celular (toque + clique emulado): não fecha na hora
	if down and Time.get_ticks_msec() - opened_ms > 400: close()

func portrait() -> bool:
	var vs := get_viewport().get_visible_rect().size
	return vs.y > vs.x * 1.15

func _layout():
	if panel == null: return
	var vs := get_viewport().get_visible_rect().size
	# PC / telas grandes: o painel cresce junto (texto legível); celular fica em escala 1.
	var sc := 1.0 if (portrait() or vs.y < 600.0) else clampf(minf(vs.x / 1150.0, vs.y / 780.0), 1.0, 1.6)
	var w := minf(vs.x / sc - 16.0, 820.0)
	var h := minf(vs.y / sc - (24.0 if portrait() else 20.0), 660.0)
	_target = Vector2(w, h)
	_scale = sc
	panel.scale = Vector2(sc, sc)
	panel.custom_minimum_size = _target
	panel.size = _target
	panel.position = ((vs - _target * sc) / 2.0).floor()
	title_label.add_theme_font_size_override("font_size", 22 if vs.x < 520 else 26)
