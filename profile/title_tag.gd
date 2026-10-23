extends Control
## R176.9 · TÍTULO com cor própria e BRILHO suave (halo da mesma cor que "respira"), sob o nome do jogador.
## Usado no cartão do adversário no início da partida, no cartão do lobby e na aba TÍTULOS do Perfil.
const Cosmetics = preload("res://profile/premium_cosmetics.gd")
const FONT := preload("res://account/fonts/Cinzel-Bold.woff")

var text := ""
var color := Color("f6d27a")
var px := 16
var align := HORIZONTAL_ALIGNMENT_CENTER
var glow := true
var t := 0.0
var natural_w := 0.0

static func make(id: String, p_px := 16, p_align := HORIZONTAL_ALIGNMENT_CENTER) -> Control:
	var n = load("res://profile/title_tag.gd").new()
	n.set_title(id, p_px)
	n.align = p_align
	return n

func set_title(id: String, p_px := -1):
	text = Cosmetics.title_text(id).to_upper()
	color = Cosmetics.title_color(id)
	if p_px > 0: px = p_px
	natural_w = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + px * 1.2
	custom_minimum_size = Vector2(0, FONT.get_height(px) + px * 0.6)   # largura: quem coloca decide (o texto encolhe para caber)
	visible = not text.is_empty()
	queue_redraw()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(d):
	if not glow or not is_visible_in_tree(): return
	t += d
	queue_redraw()

func _draw():
	if text.is_empty(): return
	var f := FONT
	var p := px
	while p > 8 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, p).x > size.x - 4: p -= 1
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, p).x
	var x := 2.0
	if align == HORIZONTAL_ALIGNMENT_CENTER: x = (size.x - tw) / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT: x = size.x - tw - 2.0
	var y := size.y / 2.0 + f.get_ascent(p) * 0.38
	var pos := Vector2(x, y)
	if glow:
		var k := 0.75 + 0.25 * sin(t * 2.4)
		for i in 3:
			var c := Color(color.r, color.g, color.b, (0.16 - i * 0.045) * k)
			f.draw_string_outline(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, p, 4 + i * 4, c)
	f.draw_string_outline(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, p, maxi(3, int(p * 0.2)), Color(0.05, 0.03, 0.01, 0.9))
	f.draw_string(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, p, color.lightened(0.08))
