extends Control
## R181 · SELO DO RIVAL DE IA (só no CELULAR; no PC o nome continua com " · IA" em texto).
## Ícone pequeno (cabeça de robô dourada, desenhada aqui, sem arte nova) logo depois do nome do adversário.
## Tocar/clicar mostra "IA" num balãozinho por 2 s.

const GOLD := Color8(232, 190, 92)
const INK := Color("10141e")
var _tip := 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "IA"
	set_process(false)

func _gui_input(e: InputEvent):
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		_tip = 2.0
		set_process(true)
		queue_redraw()
		accept_event()

func _process(delta):
	_tip -= delta
	if _tip <= 0.0:
		set_process(false)
	queue_redraw()

func _draw():
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) / 2.0
	var head := Rect2(o + Vector2(s * 0.12, s * 0.30), Vector2(s * 0.76, s * 0.58))
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD
	sb.set_corner_radius_all(int(s * 0.14))
	sb.border_color = INK
	sb.set_border_width_all(maxi(1, int(s * 0.06)))
	draw_style_box(sb, head)
	# antena
	draw_line(o + Vector2(s * 0.5, s * 0.30), o + Vector2(s * 0.5, s * 0.12), INK, maxf(1.0, s * 0.07))
	draw_circle(o + Vector2(s * 0.5, s * 0.10), s * 0.08, GOLD)
	# olhos
	draw_circle(head.position + Vector2(head.size.x * 0.30, head.size.y * 0.45), s * 0.08, INK)
	draw_circle(head.position + Vector2(head.size.x * 0.70, head.size.y * 0.45), s * 0.08, INK)
	draw_line(head.position + Vector2(head.size.x * 0.30, head.size.y * 0.75), head.position + Vector2(head.size.x * 0.70, head.size.y * 0.75), INK, maxf(1.0, s * 0.06))
	if _tip > 0.0:
		var f := get_theme_default_font()
		var fs := int(maxf(12.0, s * 0.7))
		var tw := f.get_string_size("IA", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(Vector2(size.x + 4.0, (size.y - fs * 1.3) / 2.0), Vector2(tw + 12.0, fs * 1.3))
		var bb := StyleBoxFlat.new()
		bb.bg_color = Color(0.06, 0.08, 0.12, 0.95)
		bb.border_color = GOLD
		bb.set_border_width_all(1)
		bb.set_corner_radius_all(6)
		draw_style_box(bb, r)
		draw_string(f, r.position + Vector2(6, fs * 1.0), "IA", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GOLD)
