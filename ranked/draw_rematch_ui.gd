extends Control
## R98 · EMPATE e REVANCHE na partida online (Casual e Ranqueada), por cima do HUD da partida.
##   · botão EMPATE (placa verde, irmã do DESISTIR) — no celular a ação fica no painel AÇÕES;
##   · faixa "FULANO OFERECE EMPATE" com ACEITAR / RECUSAR, centrada no tabuleiro;
##   · aviso curto ("Empate oferecido", "O adversário recusou o empate").
## A revanche fica nas telas de resultado (ranked_ui), usando art_button() daqui.
const FONT_TITLE := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_BODY := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const GOLD := Color("f7d27a")
const CREAM := Color("f4ead2")
const TEX := {"green": "res://ranked/art/desk_draw_btn.png", "red": "res://ranked/art/desk_red_btn.png"}
const ASPECT := 632.0 / 185.0

var ui            # ranked_ui dono (kind, controller, src())
var controller
var draw_button: Button
var banner: PanelContainer
var banner_title: Label
var banner_sub: Label
var accept_button: Button
var decline_button: Button
var toast: Label
var toast_until := 0
var board := Rect2()
var mobile := false

static func art_button(color: String, text: String, px: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var t := StyleBoxTexture.new()
		t.texture = load(TEX[color])
		t.modulate_color = {"hover": Color(1.12, 1.1, 1.06), "pressed": Color(0.82, 0.8, 0.78), "disabled": Color(0.55, 0.55, 0.55)}.get(st, Color.WHITE)
		b.add_theme_stylebox_override(st, t)
	var l := Label.new()
	l.name = "Caption"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_override("font", FONT_TITLE)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.01, 0.95))
	l.add_theme_constant_override("outline_size", maxi(3, px / 5))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 2)
	b.add_child(l)
	return b

static func set_caption(b: Button, text: String, px := 0):
	var l: Label = b.get_node("Caption")
	l.text = text
	if px > 0:
		l.add_theme_font_size_override("font_size", px)
		l.add_theme_constant_override("outline_size", maxi(3, px / 5))

func setup(p_ui, p_controller):
	ui = p_ui
	controller = p_controller
	name = "DrawRematch"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_button = art_button("green", "EMPATE", 22)
	draw_button.name = "DrawButton"
	draw_button.tooltip_text = "Oferecer empate ao adversário"
	draw_button.pressed.connect(func(): controller.offer_draw())
	add_child(draw_button)
	banner = PanelContainer.new()
	banner.name = "DrawOfferBanner"
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.12, 0.08, 0.96)
	st.border_color = Color("d9a94a")
	st.set_border_width_all(3)
	st.set_corner_radius_all(10)
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 18
	for side in ["left", "right"]: st.set("content_margin_" + side, 22)
	for side in ["top", "bottom"]: st.set("content_margin_" + side, 16)
	banner.add_theme_stylebox_override("panel", st)
	add_child(banner)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	banner.add_child(col)
	banner_title = _label("", 26, GOLD, FONT_TITLE)
	col.add_child(banner_title)
	banner_sub = _label("Aceitar termina a partida empatada (½ – ½).", 17, CREAM, FONT_BODY)
	col.add_child(banner_sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	accept_button = art_button("green", "ACEITAR", 22)
	accept_button.name = "DrawAccept"
	accept_button.pressed.connect(func(): controller.answer_draw(true))
	row.add_child(accept_button)
	decline_button = art_button("red", "RECUSAR", 22)
	decline_button.name = "DrawDecline"
	decline_button.pressed.connect(func(): controller.answer_draw(false))
	row.add_child(decline_button)
	toast = _label("", 20, GOLD, FONT_BODY)
	toast.name = "DrawToast"
	toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	var tst := StyleBoxFlat.new()
	tst.bg_color = Color(0.03, 0.08, 0.05, 0.92)
	tst.border_color = Color("84754b")
	tst.set_border_width_all(2)
	tst.set_corner_radius_all(8)
	for side in ["left", "right"]: tst.set("content_margin_" + side, 18)
	for side in ["top", "bottom"]: tst.set("content_margin_" + side, 8)
	toast.add_theme_stylebox_override("normal", tst)
	add_child(toast)
	controller.draw_declined.connect(func(): say("O adversário recusou o empate."))
	controller.draw_changed.connect(func():
		if controller.draw_offer == controller.human_color: say("Empate oferecido. Aguardando o adversário…"))
	_sync()

func _label(text: String, px: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l

func say(text: String, ms := 3500):
	toast.text = text
	toast_until = Time.get_ticks_msec() + ms
	_sync()

func layout(p_board: Rect2, p_mobile: bool, resign: Button):
	board = p_board
	mobile = p_mobile
	_sync()

func _process(_d):
	if mobile: _board_from_game()
	_sync()

## celular: o HUD do celular arruma o tabuleiro por conta própria → mede o tabuleiro de verdade na tela
func _board_from_game():
	var st = ui.get_parent()
	var g = st.get("game") if st != null else null
	if g == null or not (g is Node2D): return
	var t: Transform2D = g.get_global_transform_with_canvas()
	var a: Vector2 = t * g.ORIGIN
	var b: Vector2 = t * (g.ORIGIN + Vector2(8, 8) * g.TILE)
	board = Rect2(a, b - a).abs()

func _sync():
	if controller == null: return
	var online: bool = ui.src() == controller and controller.in_match()
	var playing: bool = online and controller.status == "playing"
	draw_button.visible = playing and not mobile and ui.hud.visible
	if draw_button.visible:
		# PC: à esquerda do DESISTIR, mesma altura da placa (segue o DESISTIR, que o HUD reposiciona)
		var rb: Button = ui.resign_button
		draw_button.size = rb.size
		draw_button.position = Vector2(rb.position.x - rb.size.x - 12.0, rb.position.y)
		var mine: bool = controller.draw_offer == controller.human_color
		draw_button.disabled = not controller.can_offer_draw()
		var want := "EMPATE OFERECIDO" if mine else "EMPATE"
		var cap: Label = draw_button.get_node("Caption")
		if cap.text != want: set_caption(draw_button, want, 15 if mine else 22)
		draw_button.tooltip_text = ("No Ranked, o empate só pode ser oferecido depois de 10 lances de cada lado." if controller.rules.ply < controller.draw_min_ply and controller.kind == "ranked"
			else "Oferecer empate ao adversário")
	banner.visible = playing and controller.draw_from_opponent()
	if banner.visible:
		var opp := String(controller.opponent.get("nickname", "O adversário"))
		banner_title.text = "%s OFERECE EMPATE" % opp.to_upper()
		var w := minf(board.size.x * (0.94 if mobile else 0.78), 640.0)
		var bw := minf(260.0, (w - 44.0 - 14.0) / 2.0)
		for b in [accept_button, decline_button]:
			b.custom_minimum_size = Vector2(bw, bw / ASPECT)
			set_caption(b, b.get_node("Caption").text, int(clampf(bw / ASPECT * 0.3, 13.0, 22.0)))
		banner_title.add_theme_font_size_override("font_size", 18 if mobile else 26)
		banner_sub.add_theme_font_size_override("font_size", 14 if mobile else 17)
		banner.size = Vector2(w, 0)
		banner.reset_size()
		banner.size.x = w
		banner.position = Vector2(board.get_center().x - w / 2.0, board.position.y + board.size.y * 0.30 - banner.size.y / 2.0)
	toast.visible = online and Time.get_ticks_msec() < toast_until and not banner.visible
	if toast.visible:
		toast.add_theme_font_size_override("font_size", 15 if mobile else 20)
		toast.reset_size()
		toast.position = Vector2(board.get_center().x - toast.size.x / 2.0, board.position.y + board.size.y * 0.12)
