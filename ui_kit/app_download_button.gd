extends Button
## R183/R184 · "BAIXAR O APP": no site (celular e PC; não no iPhone nem dentro do app). Abre a página de download
## https://jogar.fraihaxadrez.com/app/ (Android + Windows, com o passo a passo).
## Mesmo estilo do botão do WhatsApp (placa azul-noite com borda dourada), com selo dourado de download.

const URL := "https://jogar.fraihaxadrez.com/app/"
const F_TITLE := preload("res://account/fonts/Cinzel-Bold.woff")
const F_INFO := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const GOLD := Color8(232, 190, 92)
## R196 · celular: a ARTE do dono (placa pronta, 1000x270) no lugar do desenho; o PC continua com o desenho
const ART_PATH := "res://ui_kit/art/app_plate.png"
const ART_ASPECT := 1000.0 / 270.0
var art := false
var _art_tex: Texture2D
const CREAM := Color8(246, 236, 207)

static var _show_cache := -1

## R184 · aparece no SITE para todo mundo (celular e PC), menos iPhone/iPad (ainda sem app) e menos dentro do
## próprio app/executável. Teste: --app-banner-test
static func should_show() -> bool:
	if "--app-banner-test" in OS.get_cmdline_user_args(): return true
	if not OS.has_feature("web"): return false
	if _show_cache < 0:
		var r = JavaScriptBridge.eval("/iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1) ? 1 : 0")
		var ios: bool = (r is bool and r) or ((r is int or r is float) and int(r) == 1)
		_show_cache = 0 if ios else 1
	return _show_cache == 1

func _ready():
	name = "AppDownloadButton"
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	pressed.connect(func(): OS.shell_open(URL))
	resized.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _draw():
	if art:
		if _art_tex == null:
			_art_tex = load(ART_PATH)
			texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var aw := minf(size.x, size.y * ART_ASPECT)
		var ar := Rect2((size - Vector2(aw, aw / ART_ASPECT)) / 2.0, Vector2(aw, aw / ART_ASPECT))
		var lit := is_hovered() or button_pressed or (get_draw_mode() == DRAW_PRESSED)
		draw_texture_rect(_art_tex, ar, false, Color(1.12, 1.1, 1.05) if lit else Color.WHITE)
		return
	var h := size.y
	var r := Rect2(Vector2.ZERO, size)
	var rad := int(h * 0.22)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("0d1a38")
	bg.set_corner_radius_all(rad)
	bg.set_border_width_all(maxi(2, int(h * 0.05)))
	bg.border_color = GOLD if not button_pressed else Color("fff1b0")
	bg.shadow_color = Color(0, 0, 0, 0.45)
	bg.shadow_size = maxi(2, int(h * 0.08))
	bg.shadow_offset = Vector2(0, h * 0.04)
	draw_style_box(bg, r)
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.set_corner_radius_all(maxi(1, rad - int(h * 0.08)))
	inner.set_border_width_all(1)
	inner.border_color = Color(GOLD, 0.35)
	draw_style_box(inner, r.grow(-h * 0.11))
	# selo dourado com seta de download
	var c := Vector2(h * 0.62, h * 0.5)
	var cr := h * 0.34
	draw_circle(c + Vector2(0, h * 0.03), cr, Color(0, 0, 0, 0.35))
	draw_circle(c, cr, Color8(214, 160, 58))
	draw_circle(c, cr * 0.86, Color8(244, 206, 127))
	var lw := maxf(2.0, h * 0.07)
	var dark := Color("2a1702")
	draw_line(c + Vector2(0, -cr * 0.5), c + Vector2(0, cr * 0.22), dark, lw, true)
	draw_polyline(PackedVector2Array([c + Vector2(-cr * 0.32, -cr * 0.06), c + Vector2(0, cr * 0.26), c + Vector2(cr * 0.32, -cr * 0.06)]), dark, lw, true)
	draw_line(c + Vector2(-cr * 0.42, cr * 0.5), c + Vector2(cr * 0.42, cr * 0.5), dark, lw, true)
	var x0 := h * 1.1
	var w := size.x - x0 - h * 0.55
	var t1 := "NOVO: APP PARA CELULAR E PC"
	var t2 := "BAIXAR O APP"
	var s1 := _fit(F_INFO, t1, int(h * 0.30), w)
	var s2 := _fit(F_TITLE, t2, int(h * 0.34), w)
	draw_string(F_INFO, Vector2(x0, h * 0.42), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, s1, CREAM)
	draw_string_outline(F_TITLE, Vector2(x0, h * 0.80), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, s2, maxi(2, int(h * 0.05)), Color("2a1702"))
	draw_string(F_TITLE, Vector2(x0, h * 0.80), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, s2, Color8(255, 222, 140))
	var a := Vector2(size.x - h * 0.36, h * 0.5)
	var aw := h * 0.12
	draw_polyline(PackedVector2Array([a + Vector2(-aw, -aw * 1.6), a, a + Vector2(-aw, aw * 1.6)]), GOLD, maxf(2.0, h * 0.06), true)

func _fit(f: Font, s: String, fs: int, w: float) -> int:
	while fs > 8 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w: fs -= 1
	return fs
