extends RefCounted
## R130 · ANÁLISE com a cara do jogo: anel de PRECISÃO (ouro), retrato em moldura dourada e barra de AVALIAÇÃO
## ao lado do tabuleiro. Só desenho; os dados vêm do relatório (analyzer.gd).
const Art := preload("res://monetization/premium_art.gd")
const Config := preload("res://analysis/analysis_config.gd")
## Letras pequenas legíveis (o Cinzel de traço fino desmancha abaixo de ~16 px): Alegreya Bold.
const FONT_SMALL := preload("res://ui_kit/fonts/Alegreya-Bold.woff")

## Painel LIMPO (no lugar das molduras ornamentadas): fundo escuro quente, filete dourado fino, cantos suaves.
static func panel(pad := 20) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.045, 0.038, 0.03, 0.94)
	st.border_color = Color("d9b25f", 0.55)
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 6
	for side in ["left", "right", "top", "bottom"]: st.set("content_margin_" + side, pad)
	p.add_theme_stylebox_override("panel", st)
	return p

## Rótulo pequeno em caixa alta, legível e espaçado.
static func caps(parent: Node, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Art.label(parent, text, size, color, FONT_SMALL, align)
	var fv := FontVariation.new()
	fv.base_font = FONT_SMALL
	fv.spacing_glyph = maxi(1, int(size * 0.12))
	l.add_theme_font_override("font", fv)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

## Número grande nítido: Cinzel com contorno escuro fino (dá corpo ao traço e some o serrilhado).
static func big(parent: Node, text: String, size: int, color: Color, outline := Color(0.05, 0.03, 0.01, 0.85), align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Art.label(parent, text, size, color, Art.FONT_BOLD, align)
	l.add_theme_constant_override("outline_size", maxi(2, int(size * 0.07)))
	l.add_theme_color_override("font_outline_color", outline)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

## Anel de precisão: trilho fino + arco de cor viva (anima ao abrir) + número no meio. Sem moldura pesada.
class Ring extends Control:
	var value := 0.0          # 0..100
	var shown := 0.0
	var accent := Color("f5c451")
	var label: Label
	var cap: Label
	func _init(v: float, side: float, acc: Color):
		value = clampf(v, 0.0, 100.0)
		accent = acc
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		label = load("res://analysis/analysis_art.gd").big(self, ("%.1f%%" % value).replace(".", ","), int(side * 0.21), Color("fff6dc"), Color(0, 0, 0, 0.55))
		cap = load("res://analysis/analysis_art.gd").caps(self, "PRECISÃO", maxi(12, int(side * 0.085)), acc, HORIZONTAL_ALIGNMENT_CENTER)
		resized.connect(_place)
	func _ready():
		_place()
	func _place():
		label.size = Vector2(size.x, label.get_minimum_size().y)
		label.position = Vector2(0, size.y * 0.5 - label.size.y * 0.64)
		cap.size = Vector2(size.x, cap.get_minimum_size().y)
		cap.position = Vector2(0, size.y * 0.5 + label.size.y * 0.30)
	func _process(delta):
		if shown < value:
			shown = minf(value, shown + delta * 90.0)
			queue_redraw()
	func _draw():
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.5 - 5.0
		var w := maxf(5.0, r * 0.075)
		draw_circle(c, r + w, Color(0.02, 0.015, 0.01, 0.62))
		draw_arc(c, r, 0.0, TAU, 128, Color(1, 1, 1, 0.12), w, true)
		var a0 := -PI / 2.0
		var a1 := a0 + TAU * shown / 100.0
		draw_arc(c, r, a0, a1, 128, Color(accent, 0.28), w + 6.0, true)
		draw_arc(c, r, a0, a1, 128, accent, w, true)

## Retrato redondo: a arte é RECORTADA no círculo (polígono com UV), com um aro dourado fino.
## zoom > 1 corta a moldura que já vem desenhada em alguns avatares.
class Portrait extends Control:
	var tex: Texture2D
	var zoom := 1.18
	func _init(t: Texture2D, side: float, p_zoom := 1.18):
		tex = t
		zoom = p_zoom
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw():
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c + Vector2(0, 2), r + 1.0, Color(0, 0, 0, 0.45))
		draw_circle(c, r, Color(0.04, 0.03, 0.02))
		if tex != null:
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			var ri := r - 2.5
			var half := 0.5 / zoom
			for i in 64:
				var ang := TAU * i / 64.0
				var d := Vector2(cos(ang), sin(ang))
				pts.append(c + d * ri)
				uvs.append(Vector2(0.5, 0.5) + d * half)
			draw_colored_polygon(pts, Color.WHITE, uvs, tex)
		draw_arc(c, r - 1.0, 0.0, TAU, 72, Color("f3cf72"), 2.0, true)

## Fundo do painel do duelo: a arte (rei e dama dourados) cobrindo o painel, escurecida nas laterais (onde ficam
## os jogadores) e embaixo (onde fica o resultado), com um filete dourado fino em volta.
class Backdrop extends Control:
	var tex: Texture2D
	func _init(t: Texture2D):
		tex = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
	func _draw():
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.02, 0.01))
		if tex != null:
			var ts := tex.get_size()
			var k := maxf(size.x / ts.x, size.y / ts.y)
			var d := ts * k
			draw_texture_rect(tex, Rect2((size - d) / 2.0, d), false)
		# laterais e base escurecidas (gradiente em faixas)
		var n := 24
		for i in n:
			var t := float(i) / n
			var a := 0.72 * pow(1.0 - t, 1.6)
			var wcol := size.x * 0.36 / n
			draw_rect(Rect2(i * wcol, 0, wcol + 1, size.y), Color(0, 0, 0, a))
			draw_rect(Rect2(size.x - (i + 1) * wcol, 0, wcol + 1, size.y), Color(0, 0, 0, a))
			var hrow := size.y * 0.42 / n
			draw_rect(Rect2(0, size.y - (i + 1) * hrow, size.x, hrow + 1), Color(0, 0, 0, 0.55 * pow(1.0 - t, 1.4)))
		draw_rect(r, Color("d9b25f", 0.85), false, 1.5)
		draw_rect(r.grow(-5), Color("d9b25f", 0.25), false, 1.0)

## Faixa escura discreta atrás do resultado do duelo (lê bem por cima da arte), com filetes dourados nas pontas.
class ResultPlate extends Control:
	func _init():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw():
		var w := size.x
		var h := size.y
		var n := 16
		for i in n:
			var t := float(i) / (n - 1)
			var a := 0.78 * (1.0 - pow(absf(t - 0.5) * 2.0, 2.2))
			draw_rect(Rect2(w * float(i) / n, 0, w / n + 1, h), Color(0.02, 0.012, 0.006, a))
		draw_line(Vector2(w * 0.12, 0), Vector2(w * 0.88, 0), Color("d9b25f", 0.6), 1.0)
		draw_line(Vector2(w * 0.12, h), Vector2(w * 0.88, h), Color("d9b25f", 0.6), 1.0)

## Barra de avaliação vertical (Brancas = claro). Anima entre os lances.
class EvalBar extends Control:
	var target := 0.5       # fração das Brancas 0..1
	var cur := 0.5
	var flipped := false
	var text := ""
	func _init():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(26, 0)
	func set_eval(signed_pawns: float, p_text: String):
		var cp := int(clampf(signed_pawns, -99.0, 99.0) * 100.0)
		target = Config.win_percent(cp, 0) / 100.0
		text = p_text
		queue_redraw()
	func _process(delta):
		if absf(cur - target) > 0.001:
			cur = lerpf(cur, target, minf(1.0, delta * 8.0))
			queue_redraw()
	func _draw():
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(2), Color("6e4b18"))
		draw_rect(r, Color(0.07, 0.08, 0.1))
		var wh := size.y * cur
		var white_rect := Rect2(0, size.y - wh, size.x, wh) if not flipped else Rect2(0, 0, size.x, wh)
		draw_rect(white_rect, Color("efe6cf"))
		draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), Color("c99a45", 0.8), 1.0)
		draw_rect(r.grow(2), Color("c99a45"), false, 2.0)
		if text != "":
			var f: Font = load("res://ui_kit/fonts/Alegreya-Bold.woff")
			var fs := int(clampf(size.x * 0.46, 10, 14))
			var white_side := cur >= 0.5
			var at_bottom := white_side != flipped
			var y := size.y - 6.0 if at_bottom else fs + 4.0
			var col := Color(0.1, 0.08, 0.05) if white_side else Color("efe6cf")
			draw_string(f, Vector2(0, y), text.replace("+", ""), HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, col)
