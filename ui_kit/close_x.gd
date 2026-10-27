extends Button
## R199 · botão FECHAR (X) das telas com a arte do dono (Chat global, Ranking, Coroas): selo vermelho com borda
## dourada no canto de cima à direita. No celular deitado o painel ocupa a tela toda e não sobra "fora" para tocar.
const GOLD := Color("f2c75c")

static func make(on_press: Callable, side: float) -> Button:
	var b: Button = load("res://ui_kit/close_x.gd").new()
	b.name = "ArtCloseX"
	b.size = Vector2(side, side)
	b.custom_minimum_size = b.size
	b.pressed.connect(on_press)
	return b

func _ready():
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Fechar"
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]: add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for s in [mouse_entered, mouse_exited, button_down, button_up, resized]: s.connect(queue_redraw)

func _draw():
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0
	var lit := is_hovered() or button_pressed
	draw_circle(c + Vector2(0, r * 0.08), r, Color(0, 0, 0, 0.45))
	draw_circle(c, r, Color("6b3d0c"))
	draw_circle(c, r * 0.9, GOLD)
	draw_circle(c, r * 0.76, Color("a3141c") if not lit else Color("c81e28"))
	draw_arc(c, r * 0.76, PI * 1.1, PI * 1.9, 24, Color(1, 1, 1, 0.25), r * 0.08, true)
	var a := r * 0.34
	var w := maxf(2.0, r * 0.17)
	draw_line(c + Vector2(-a, -a), c + Vector2(a, a), Color("fbe7b0"), w, true)
	draw_line(c + Vector2(a, -a), c + Vector2(-a, a), Color("fbe7b0"), w, true)
