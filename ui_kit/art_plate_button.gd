extends Button
## R196 · botão que é só a ARTE do dono (placa pronta, com o texto na própria imagem), nítida em qualquer
## tamanho (mipmaps) e um pouco mais clara ao passar o mouse ou tocar. Ex.: COMUNIDADE da Home do PC.
var tex: Texture2D

static func make(path: String, node_name: String, sz: Vector2) -> Button:
	var b: Button = load("res://ui_kit/art_plate_button.gd").new()
	b.tex = load(path)
	b.name = node_name
	b.size = sz
	b.custom_minimum_size = sz
	return b

func _ready():
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for s in [mouse_entered, mouse_exited, button_down, button_up, resized]: s.connect(queue_redraw)

func _draw():
	if tex == null: return
	var ts := tex.get_size()
	var k := minf(size.x / ts.x, size.y / ts.y)
	var r := Rect2((size - ts * k) / 2.0, ts * k)
	var lit := is_hovered() or button_pressed or get_draw_mode() == DRAW_PRESSED
	draw_texture_rect(tex, r, false, Color(1.12, 1.1, 1.05) if lit else Color.WHITE)
