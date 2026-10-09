extends RefCounted
## R55.2 · XEQUE no PC: painéis, molduras, cantoneiras e a placa de aço do botão XEQUE PRÉ-COMPOSTOS.
## Antes (R55/R55.1) cada painel era refeito a cada quadro com ~15–25 operações de desenho (borda escura,
## moldura, brilho, miolo em degradê, faixa vinho, 4 cantoneiras com 3 polígonos cada); a placa do XEQUE
## tinha ~90 (filete pontilhado + rebites). Aqui as MESMAS operações, com as mesmas cores e medidas, são
## pintadas UMA vez numa imagem no tamanho real da tela (px) e guardadas: cada painel vira 1 desenho de
## textura por quadro. A imagem é refeita só quando muda o tamanho/escala ou o estado visual (cor da borda,
## brilho, faixa, cores do miolo, estado do botão). Nada aqui decide regra ou estado do jogo.

const MARGIN := 4.0           # px de referência fora do painel (borda escura + cantoneiras)
const MARGIN_GLOW := 19.0     # com o halo (5 contornos de 3 px até grow 16)
static var _cache := {}
static var _k := -1.0            # escala atual: mudou (janela redimensionada) → as imagens antigas saem
static var builds := 0        # quantas imagens foram montadas (testes: não pode crescer a cada quadro)

static func _key(parts: Array) -> String:
	var out := PackedStringArray()
	for p in parts:
		if p is Color: out.append(p.to_html(true))
		elif p is float: out.append("%.3f" % p)
		elif p is Vector2: out.append("%.2fx%.2f" % [p.x, p.y])
		else: out.append(str(p))
	return "|".join(out)

static func _store(key: String, img: Image, origin: Vector2, k: float) -> Dictionary:
	if _cache.size() > 48: _cache.clear()
	builds += 1
	var d := {"tex": ImageTexture.create_from_image(img), "offset": origin, "size": Vector2(img.get_width(), img.get_height()) / k}
	_cache[key] = d
	return d

static func _rescale(k: float):
	if absf(k - _k) > 0.0005:
		_cache.clear()
		_k = k

# ---------------------------------------------------------------- pintor (coordenadas de referência → px)
class Painter:
	var img: Image
	var o: Vector2          # canto da imagem em px de referência
	var k: float
	func _init(origin: Vector2, size_ref: Vector2, scale: float):
		o = origin
		k = scale
		img = Image.create(maxi(1, int(ceil(size_ref.x * k))), maxi(1, int(ceil(size_ref.y * k))), false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
	func _px(r: Rect2) -> Rect2i:
		var a := ((r.position - o) * k).round()
		var b := ((r.end - o) * k).round()
		return Rect2i(Vector2i(a), Vector2i(b - a)).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	func fill(r: Rect2, c: Color):
		var p := _px(r)
		if p.size.x <= 0 or p.size.y <= 0: return
		if c.a >= 0.999:
			img.fill_rect(p, c)
		else:
			var src := Image.create(p.size.x, p.size.y, false, Image.FORMAT_RGBA8)
			src.fill(c)
			img.blend_rect(src, Rect2i(Vector2i.ZERO, p.size), p.position)
	## contorno como o draw_rect(filled = false, width): linha centrada na borda do retângulo
	func outline(r: Rect2, w: float, c: Color):
		var h := w / 2.0
		fill(Rect2(r.position.x - h, r.position.y - h, r.size.x + w, w), c)
		fill(Rect2(r.position.x - h, r.end.y - h, r.size.x + w, w), c)
		fill(Rect2(r.position.x - h, r.position.y + h, w, r.size.y - w), c)
		fill(Rect2(r.end.x - h, r.position.y + h, w, r.size.y - w), c)
	## degradê vertical (o polígono de 4 cores do desenho imediato), linha a linha
	func grad(r: Rect2, top: Color, bot: Color):
		var p := _px(r)
		for y in p.size.y:
			var t := (y + 0.5) / float(maxi(1, p.size.y))
			img.fill_rect(Rect2i(p.position.x, p.position.y + y, p.size.x, 1), top.lerp(bot, t))
	## losango de meias-medidas (hx, hy) centrado em c
	func diamond(c: Vector2, hx: float, hy: float, col: Color):
		var cy := (c.y - o.y) * k
		var cx := (c.x - o.x) * k
		var y0 := int(floor(cy - hy * k))
		var y1 := int(ceil(cy + hy * k))
		for y in range(y0, y1):
			var dy := absf(y + 0.5 - cy) / (hy * k)
			if dy >= 1.0: continue
			var half := (1.0 - dy) * hx * k
			var x0 := int(round(cx - half))
			var x1 := int(round(cx + half))
			if x1 > x0 and y >= 0 and y < img.get_height():
				img.fill_rect(Rect2i(x0, y, x1 - x0, 1).intersection(Rect2i(0, 0, img.get_width(), img.get_height())), col)

# ---------------------------------------------------------------- painel da referência
## Mesmo desenho do npanel() da R55: halo (glow), borda escura, moldura dourada com brilho, miolo azul (ou
## vinho→azul), faixa vinho do título e cantoneiras (L escuro + L dourado + losango claro).
static func panel(r: Rect2, k: float, header: float, border: Color, glow: bool, wine_full: bool, fill_t: Color, fill_b: Color, wine_t: Color, wine_b: Color, hi: Color) -> Dictionary:
	_rescale(k)
	var key := _key(["p", r.size, k, header, border, glow, wine_full, fill_t, fill_b])
	var m := MARGIN_GLOW if glow else MARGIN
	if _cache.has(key):
		var c: Dictionary = _cache[key]
		return {"tex": c.tex, "rect": Rect2(r.position - Vector2(m, m), c.size)}
	var lr := Rect2(Vector2(m, m), r.size)          # o painel na imagem (px de referência)
	var p := Painter.new(Vector2.ZERO, r.size + Vector2(2 * m, 2 * m), k)
	if glow:
		for i in 5: p.outline(lr.grow(4 + i * 3), 3.0, Color(border.r, border.g, border.b, 0.16 - i * 0.03))
	p.fill(lr.grow(3), Color("0b0703"))
	p.fill(lr, border.darkened(0.25))
	p.fill(Rect2(lr.position, Vector2(lr.size.x, 1.5)), border.lightened(0.45))
	p.fill(lr.grow(-1.5), border)
	var inner := lr.grow(-3.5)
	p.fill(inner, Color("0d0904"))
	var f := inner.grow(-1.0)
	if wine_full:
		p.grad(Rect2(f.position, Vector2(f.size.x, f.size.y * 0.45)), wine_t, wine_b.lerp(fill_t, 0.4))
		p.grad(Rect2(f.position + Vector2(0, f.size.y * 0.45), Vector2(f.size.x, f.size.y * 0.55)), wine_b.lerp(fill_t, 0.4), fill_b)
	else:
		p.grad(f, fill_t, fill_b)
	if header > 0.0:
		var hb := Rect2(f.position, Vector2(f.size.x, header))
		p.grad(hb, wine_t, wine_b)
		p.fill(Rect2(hb.position.x, hb.end.y - 2, hb.size.x, 2), Color(0.02, 0.01, 0.01, 0.8))
		p.fill(Rect2(hb.position.x, hb.position.y, hb.size.x, 1), Color(1, 0.6, 0.5, 0.18))
	_corners(p, lr, border, hi)
	var d := _store(key, p.img, Vector2.ZERO, k)
	return {"tex": d.tex, "rect": Rect2(r.position - Vector2(m, m), d.size)}

static func _corners(p: Painter, r: Rect2, col: Color, hi: Color, s := 11.0):
	for c in [[r.position, 1, 1], [Vector2(r.end.x, r.position.y), -1, 1], [Vector2(r.position.x, r.end.y), 1, -1], [r.end, -1, -1]]:
		var q: Vector2 = c[0]
		var dx: float = c[1]
		var dy: float = c[2]
		# L escuro: [-2, s+1] x [-2, 2] ∪ [-2, 2] x [-2, s+1]
		p.fill(_span(q, dx, dy, -2.0, s + 1.0, -2.0, 2.0), Color("0b0703"))
		p.fill(_span(q, dx, dy, -2.0, 2.0, -2.0, s + 1.0), Color("0b0703"))
		# L dourado: [-0,5, s] x [-0,5, 1,2] ∪ [-0,5, 1,2] x [-0,5, s]
		var gold := col.lightened(0.15)
		p.fill(_span(q, dx, dy, -0.5, s, -0.5, 1.2), gold)
		p.fill(_span(q, dx, dy, -0.5, 1.2, -0.5, s), gold)
		p.diamond(q + Vector2(4.5 * dx, 4.5 * dy), 2.2, 2.2, hi)

## Retângulo no canto q, com as medidas na direção (dx, dy) do canto.
static func _span(q: Vector2, dx: float, dy: float, ax: float, bx: float, ay: float, by: float) -> Rect2:
	var x0 := q.x + ax * dx
	var x1 := q.x + bx * dx
	var y0 := q.y + ay * dy
	var y1 := q.y + by * dy
	return Rect2(minf(x0, x1), minf(y0, y1), absf(x1 - x0), absf(y1 - y0))

# ---------------------------------------------------------------- placa de aço do XEQUE
## Mesmo desenho do corpo do botão da R55 (sem o texto e sem o halo pulsante, que continuam ao vivo).
static func steel(r: Rect2, k: float, lt: Color, dk: Color) -> Dictionary:
	_rescale(k)
	var key := _key(["s", r.size, k, lt, dk])
	var m := 5.0
	if _cache.has(key):
		var c: Dictionary = _cache[key]
		return {"tex": c.tex, "rect": Rect2(r.position - Vector2(m, m), c.size)}
	var rr := Rect2(Vector2(m, m), r.size)
	var p := Painter.new(Vector2.ZERO, r.size + Vector2(2 * m, 2 * m), k)
	p.fill(rr.grow(4), Color("0b0703"))
	p.fill(rr.grow(2), Color("2b2f35"))
	p.grad(rr, lt, dk)
	p.fill(Rect2(rr.position.x, rr.position.y, rr.size.x, 3), Color(1, 1, 1, 0.35))
	p.fill(Rect2(rr.position.x, rr.end.y - 3, rr.size.x, 3), Color(0, 0, 0, 0.35))
	var inner := rr.grow(-12)
	# o filete pontilhado usa as mesmas posições de antes (x inteiros a partir da borda do botão na tela)
	var sx := int(r.position.x + 12.0) + 4
	var ex := int(r.position.x + r.size.x - 12.0) - 4
	for x in range(sx, ex, 9):
		var lx: float = x - r.position.x + m
		p.fill(Rect2(lx, inner.position.y, 3, 1.5), Color(0, 0, 0, 0.3))
		p.fill(Rect2(lx, inner.end.y, 3, 1.5), Color(0, 0, 0, 0.3))
	for q in [Vector2(rr.position.x + 22, rr.position.y + 22), Vector2(rr.end.x - 22, rr.position.y + 22), Vector2(rr.position.x + 22, rr.end.y - 22), Vector2(rr.end.x - 22, rr.end.y - 22)]:
		p.diamond(q, 10, 10, Color("c99a3a"))
		p.diamond(q, 7, 7, Color("27354d"))
	for q in [Vector2(rr.position.x + 22, rr.get_center().y), Vector2(rr.end.x - 22, rr.get_center().y)]:
		p.diamond(q, 4, 7, Color("e7b64c"))
	var d := _store(key, p.img, Vector2.ZERO, k)
	return {"tex": d.tex, "rect": Rect2(r.position - Vector2(m, m), d.size)}
