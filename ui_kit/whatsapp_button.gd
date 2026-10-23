extends Button
## R180 · BETA: botão "DÚVIDAS OU BUGS? FALE NO WHATSAPP" embaixo do PASSE (PC, celular deitado e em pé).
## Abre o WhatsApp do dono (wa.me) numa aba nova com uma mensagem pronta. Desenhado no estilo das placas da Home
## (fundo azul-noite, borda dourada) com um selo verde de conversa. Sem logo de marca: bolha de conversa genérica.

const NUMBER := "5543999384442"
const MESSAGE := "Olá! Vim pelo FRAIHA Xadrez (beta) e quero falar sobre: "
const F_TITLE := preload("res://account/fonts/Cinzel-Bold.woff")
const F_INFO := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const GOLD := Color8(232, 190, 92)
const CREAM := Color8(246, 236, 207)
const GREEN := Color8(37, 190, 90)

var _hover := false

static func url() -> String:
	return "https://wa.me/%s?text=%s" % [NUMBER, MESSAGE.uri_encode()]

func _ready():
	name = "WhatsAppButton"
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = ""
	text = ""
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	pressed.connect(func(): OS.shell_open(url()))
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	resized.connect(queue_redraw)

func _draw():
	var h := size.y
	var r := Rect2(Vector2.ZERO, size)
	var rad := int(h * 0.22)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("0d1a38") if not _hover else Color("142650")
	bg.set_corner_radius_all(rad)
	bg.set_border_width_all(maxi(2, int(h * 0.05)))
	bg.border_color = GOLD if not button_pressed else Color("fff1b0")
	bg.shadow_color = Color(0, 0, 0, 0.45)
	bg.shadow_size = maxi(2, int(h * 0.08))
	bg.shadow_offset = Vector2(0, h * 0.04)
	draw_style_box(bg, r)
	# filete dourado interno
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.set_corner_radius_all(maxi(1, rad - int(h * 0.08)))
	inner.set_border_width_all(1)
	inner.border_color = Color(GOLD, 0.35)
	draw_style_box(inner, r.grow(-h * 0.11))
	# selo verde com bolha de conversa
	var c := Vector2(h * 0.62, h * 0.5)
	var cr := h * 0.34
	draw_circle(c + Vector2(0, h * 0.03), cr, Color(0, 0, 0, 0.35))
	draw_circle(c, cr, GREEN)
	draw_arc(c, cr, 0.0, TAU, 40, Color(1, 1, 1, 0.25), maxf(1.0, h * 0.025), true)
	var br := cr * 0.58
	var bc := c + Vector2(0, -cr * 0.04)
	draw_circle(bc, br, Color.WHITE)
	draw_colored_polygon(PackedVector2Array([bc + Vector2(-br * 0.75, br * 0.45), bc + Vector2(-br * 1.05, br * 1.15), bc + Vector2(-br * 0.15, br * 0.9)]), Color.WHITE)
	draw_circle(bc, br * 0.72, GREEN)
	for i in 3:
		draw_circle(bc + Vector2((i - 1) * br * 0.42, 0), br * 0.13, Color.WHITE)
	# textos
	var x0 := h * 1.1
	var w := size.x - x0 - h * 0.55
	var t1 := "DÚVIDAS OU BUGS?"
	var t2 := "FALE NO WHATSAPP"
	var s1 := _fit(F_INFO, t1, int(h * 0.30), w)
	var s2 := _fit(F_TITLE, t2, int(h * 0.34), w)
	draw_string(F_INFO, Vector2(x0, h * 0.42), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, s1, CREAM)
	draw_string_outline(F_TITLE, Vector2(x0, h * 0.80), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, s2, maxi(2, int(h * 0.05)), Color("06240f"))
	draw_string(F_TITLE, Vector2(x0, h * 0.80), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, s2, Color8(120, 236, 150))
	# seta
	var a := Vector2(size.x - h * 0.36, h * 0.5)
	var aw := h * 0.12
	draw_polyline(PackedVector2Array([a + Vector2(-aw, -aw * 1.6), a, a + Vector2(-aw, aw * 1.6)]), GOLD, maxf(2.0, h * 0.06), true)

func _fit(f: Font, s: String, fs: int, w: float) -> int:
	while fs > 8 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w: fs -= 1
	return fs
