extends RefCounted
## R186 · placa dos botões grandes do celular (microfone, fone e CHAT da MARCHA REAL / XEQUE): a MESMA moldura de
## ouro das placas de perfil da mesa (marcha/art/r57/placa_vazia.png = placa_perfil_1 sem o retrato), com o roxo
## escuro delas por dentro e um brilho roxo em cima, como o botão JOGAR CARTA. Antes era uma caixa roxa lisa.
## Desenhada em 9 partes: os cantos com as volutas ficam na proporção certa em qualquer tamanho de botão.

## R195 · carregada só na hora de desenhar: no site a arte vem no CONTEÚDO EXTRA (baixado depois da Home); o preload
## quebrava a compilação deste script (e do chat e da stage) na abertura do jogo, antes do conteúdo chegar.
const PLATE_PATH := "res://marcha/art/r57/placa_vazia.png"
static var _plate: Texture2D
static func plate() -> Texture2D:
	if _plate == null and ResourceLoader.exists(PLATE_PATH): _plate = load(PLATE_PATH)
	return _plate
const SRC := Vector2(240, 108)
const M := 24.0                      # margem da moldura na arte (cantos com volutas)

static func draw(ci: CanvasItem, r: Rect2, _tone := "marcha", on := true, pressed := false) -> void:
	var PLATE := plate()
	if PLATE == null:   # conteúdo extra ainda não chegou: só o veludo roxo com borda dourada
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.08, 0.28, 0.92)
		sb.border_color = Color("c9a048")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.18))
		ci.draw_style_box(sb, r)
		return
	var k: float = clampf(minf(r.size.x / SRC.x, r.size.y / SRC.y) * 1.25, 0.6, 3.0)
	var md: float = minf(M * k, minf(r.size.x, r.size.y) * 0.32)
	var mod := Color.WHITE if on else Color(0.62, 0.6, 0.62)
	if pressed: mod = mod.darkened(0.2)
	var sx := [0.0, M, SRC.x - M, SRC.x]
	var sy := [0.0, M, SRC.y - M, SRC.y]
	var dx := [r.position.x, r.position.x + md, r.end.x - md, r.end.x]
	var dy := [r.position.y, r.position.y + md, r.end.y - md, r.end.y]
	for i in 3:
		for j in 3:
			var src := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
			var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			if dst.size.x > 0.5 and dst.size.y > 0.5: ci.draw_texture_rect_region(PLATE, dst, src, mod)
	# brilho roxo suave no alto do miolo (o tom do JOGAR CARTA), sumindo para baixo
	var inner := r.grow(-md * 0.62)
	var top := Color(0.36, 0.13, 0.48, 0.55 if on else 0.25)
	var bot := Color(0.36, 0.13, 0.48, 0.0)
	ci.draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]),
		PackedColorArray([top, top, bot, bot]))

## Balão de conversa dourado (ícone do CHAT), dentro do quadrado r.
static func chat_glyph(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var b := Rect2(c - Vector2(s * 0.42, s * 0.32), Vector2(s * 0.84, s * 0.54))
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(s * 0.16))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, b)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(b.position.x + s * 0.18, b.end.y - 1), Vector2(b.position.x + s * 0.40, b.end.y - 1), Vector2(b.position.x + s * 0.12, b.end.y + s * 0.20)]), col)
	for i in 3:
		ci.draw_circle(Vector2(b.position.x + b.size.x * (0.28 + 0.22 * i), b.get_center().y), s * 0.055, Color("2a1606"))
