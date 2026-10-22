extends Control
## R176 · BOTÕES DE VOLTAR / SAIR / DESISTIR / FECHAR / CANCELAR / INÍCIO em TODO o jogo: o miolo vira o vinho do
## botão vermelho do jogo e "respira" devagar (nada brusco), para quem não conhece o jogo achar a saída rápido.
## Não muda a arte nem o clique: é uma camada por cima do botão (ignora o mouse), também nos botões "fantasma"
## que ficam sobre a arte pintada (INÍCIO do tabuleiro, VOLTAR À HOME das Configurações…).
## Ligado uma vez no stage (watch): todo botão que entra na árvore é conferido pelo texto e pelo nome.


## textos de saída (começo do texto, sem acento/maiúscula)
const WORDS := ["voltar", "sair", "desistir", "fechar", "cancelar", "inicio", "não", "nao", "← voltar", "‹ voltar", "< voltar"]
## nomes de nó de botões de saída (fim do nome)
const NAME_ENDS := ["Back", "Cancel", "Close", "Resign", "Leave", "Exit", "BackText", "ResignText"]
const NAME_EXACT := ["HomeButton", "home", "MenuResign", "VoiceLeave", "PaymentCancelOpen", "PaymentCancelRetry"]
const SKIP_META := "no_back_pulse"   # botão que NÃO deve piscar (set_meta(SKIP_META, true))


static func watch(tree: SceneTree) -> void:
	if tree.has_meta("back_pulse_watch"): return
	tree.set_meta("back_pulse_watch", true)
	tree.node_added.connect(func(n: Node):
		if n is BaseButton:
			# o texto costuma ser preenchido logo depois do add_child: confere no fim do quadro e de novo depois
			(func(): _check(n)).call_deferred()
			tree.create_timer(0.25).timeout.connect(func(): _check(n)))
	# o que já estava na árvore antes de ligar (cena principal, Home)
	(func(): _sweep(tree.root)).call_deferred()
	tree.create_timer(1.0).timeout.connect(func(): _sweep(tree.root))

static func _sweep(n: Node) -> void:
	if not is_instance_valid(n): return
	for b in n.find_children("*", "BaseButton", true, false): _check(b)

static func is_exit(b: BaseButton) -> bool:
	if b.has_meta(SKIP_META): return false
	var nm := String(b.name)
	if nm.begins_with("RefNav_"): return false   # abas da barra de baixo do celular (INÍCIO = a própria Home)
	if nm in NAME_EXACT: return true
	for e in NAME_ENDS:
		if nm.ends_with(e) and not nm.ends_with("Backdrop"): return true
	var texts: Array = []
	if b is Button: texts.append(String((b as Button).text))
	if b.has_meta("title"): texts.append(String(b.get_meta("title")))
	# botões de arte com o texto num Label filho (barra de baixo do celular, cartões de página…)
	for c in b.get_children():
		if c is Label: texts.append(String(c.text))
		for cc in c.get_children():
			if cc is Label: texts.append(String(cc.text))
	for raw in texts:
		var t := String(raw).strip_edges().to_lower().replace("í", "i").replace("à", "a").replace("Í", "i")
		if t.is_empty(): continue
		if t == "✕" or t == "x" or t == "×": return true
		for w in WORDS:
			if t.begins_with(w): return true
	return false

static func _check(n: Node) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree(): return
	var b := n as BaseButton
	if b == null or b.has_node("BackPulse") or not is_exit(b): return
	attach(b)

static func attach(c: Control) -> Control:
	if c.has_node("BackPulse"): return c.get_node("BackPulse")
	var p = load("res://ui_kit/back_pulse.gd").new()
	p.name = "BackPulse"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(p)
	return p

# ------------------------------------------------------------------ R176.1 · cor e forma do próprio jogo
# Antes: um retângulo vermelho por cima (cortava os cantos das placas e o vermelho não era o do jogo).
# Agora: o MIOLO azul/escuro do próprio botão vira o VINHO do botão vermelho do jogo (ui_kit/art/btn_vermelho.png),
# a moldura dourada, o texto e os ícones continuam iguais, a forma é exatamente a do botão, e o vinho "respira"
# devagar (brilho ±8 % a cada 2,6 s). Dois casos:
#  · botão desenhado (Cta, NinePatch, StyleBox, textura): o próprio botão recebe o shader de recolor;
#  · botão "fantasma" sobre a arte pintada (placas VOLTAR À HOME, INÍCIO do tabuleiro, MAIS do celular): o pedaço
#    da arte embaixo dele é recolorido uma vez (só a placa: preenchimento a partir do centro até a moldura dourada)
#    e desenhado por cima, alinhado pixel a pixel.

const BREATH := 2.6
const RECOLOR := """
shader_type canvas_item;
// R176.1 · vinho do botão vermelho do jogo + respiração suave + um BRILHO de luz que atravessa o botão
// de vez em quando (como luz passando no metal), sempre dentro da forma do botão.
uniform float breath = 2.6;
uniform float recolor = 1.0;     // 1 = azul/escuro vira vinho (botão desenhado); 0 = já vem recolorido (arte)
uniform float breathe = 1.0;     // 1 = respira; 0 = não (camada só da moldura dourada)
uniform float shine = 1.0;       // força do brilho
uniform bool use_uv = false;     // arte recortada: UV cobre o botão inteiro
uniform vec2 box = vec2(200.0, 60.0);
uniform float phase = 0.0;       // cada botão passa o brilho num momento diferente
varying vec2 lp;
void vertex() { lp = VERTEX; }
vec3 rgb2hsv(vec3 c) { vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0); vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r)); float d = q.x - min(q.w, q.y); float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x); }
vec3 hsv2rgb(vec3 c) { vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0); vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y); }
void fragment() {
	vec3 hsv = rgb2hsv(COLOR.rgb);
	float k = 1.0 + 0.08 * sin(TIME * 6.2831853 / breath) * breathe;
	vec3 o = COLOR.rgb;
	bool wine = false;
	if (recolor > 0.5) {
		if (hsv.y > 0.16 && hsv.x > 0.50 && hsv.x < 0.80) {
			o = hsv2rgb(vec3(0.992, min(1.0, hsv.y * 1.02), hsv.z * 0.95));   // azul-marinho -> vinho
			wine = true;
		} else if (hsv.z < 0.30) {
			o = mix(COLOR.rgb, vec3(0.36, 0.06, 0.07) * (0.72 + hsv.z * 2.0), 0.85);   // preto/marrom -> vinho
			wine = true;
		}
	} else { wine = breathe > 0.5; }
	if (wine) o *= k;
	// brilho: faixa diagonal de luz quente que cruza o botão em ~1 s, a cada 5 s
	vec2 p = use_uv ? UV : lp / max(box, vec2(1.0));
	float t = fract((TIME + phase) / 5.0);
	float run = clamp(t / 0.2, 0.0, 1.0);
	float pos = mix(-0.35, 1.35, run);
	float d = (p.x + (p.y - 0.5) * 0.5) - pos;
	float band = smoothstep(0.12, 0.0, abs(d)) * (1.0 - step(1.0, run));
	o += vec3(1.0, 0.88, 0.62) * band * 0.36 * shine;
	COLOR.rgb = o;
}
"""
static var _shader: Shader
static func recolor_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = RECOLOR
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m

## mesma conta do shader, para recolorir a arte pintada uma vez (CPU)
static func recolor_px(c: Color) -> Color:
	if c.s > 0.16 and c.h > 0.50 and c.h < 0.80:
		var o := Color.from_hsv(0.992, minf(1.0, c.s * 1.02), c.v * 0.95)
		o.a = c.a
		return o
	if c.v < 0.30:
		var w := Color(0.36, 0.06, 0.07) * (0.72 + c.v * 2.0)
		var o2 := c.lerp(w, 0.85)
		o2.a = c.a
		return o2
	return c

static func _gold(c: Color) -> bool:
	return c.h > 0.05 and c.h < 0.19 and c.s > 0.38 and c.v > 0.38

var _mode := ""            # "material" | "patch" | "none"
var _patch: Texture2D
var _t := 0.0   # (testes antigos mexiam nisso; o tempo agora é o TIME do shader)

func _ready():
	(func(): _setup()).call_deferred()

func _setup():
	var b := get_parent() as Control
	if b == null: return
	var ph := randf() * 5.0
	if _painted(b):
		var src := _art_source(b)
		if not src.is_empty() and src.tex != null:
			var pair: Array = _make_patch(src.tex, src.region)
			if not pair.is_empty():
				_patch = pair[0]
				var m := recolor_material()
				m.set_shader_parameter("recolor", 0.0)
				m.set_shader_parameter("use_uv", true)
				m.set_shader_parameter("phase", ph)
				material = m
				# camada da moldura dourada (igual à arte): só recebe o brilho, não respira
				var gl := TextureRect.new()
				gl.name = "Glint"
				gl.texture = pair[1]
				gl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				gl.stretch_mode = TextureRect.STRETCH_SCALE
				gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				gl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				var gm := recolor_material()
				gm.set_shader_parameter("recolor", 0.0)
				gm.set_shader_parameter("breathe", 0.0)
				gm.set_shader_parameter("use_uv", true)
				gm.set_shader_parameter("phase", ph)
				gl.material = gm
				add_child(gl)
		_mode = "patch" if _patch != null else "none"
		queue_redraw()
		return
	if b.material == null:
		var bm := recolor_material()
		bm.set_shader_parameter("phase", ph)
		bm.set_shader_parameter("box", b.size)
		b.resized.connect(func(): if b.material == bm: bm.set_shader_parameter("box", b.size))
		b.material = bm
		for ch in b.get_children():
			if ch is CanvasItem and not (ch is Label) and not (ch is RichTextLabel) and ch != self and (ch as CanvasItem).material == null:
				(ch as CanvasItem).use_parent_material = true
		_mode = "material"
	else:
		_mode = "none"

## botão sem desenho próprio (o desenho é da arte por baixo)
static func _painted(b: Control) -> bool:
	if b.self_modulate.a < 0.05 or b.has_meta("art_src"): return true
	if b.get_script() != null and b.has_method("_draw"): return false   # desenha a si mesmo (Cta, botões do HUD…)
	if b is TextureButton: return (b as TextureButton).texture_normal == null and not _has_art_child(b)
	if b is Button:
		var bt := b as Button
		var sb := bt.get_theme_stylebox("normal")
		var empty_box: bool = bt.flat or sb == null or sb is StyleBoxEmpty
		var text_hidden: bool = bt.text.is_empty() or bt.get_theme_color("font_color").a < 0.05
		return empty_box and text_hidden and not _has_art_child(b)
	return false

static func _has_art_child(b: Node) -> bool:
	for ch in b.get_children():
		if ch.name == "RefHover" or ch.name == "BackPulse": continue
		if (ch is TextureRect or ch is NinePatchRect) and (ch as CanvasItem).visible: return true
	return false

## de onde vem a arte embaixo do botão: meta "art_src" [textura, Rect2 em px da textura], o recorte do brilho
## (RefHover) ou a TextureRect de fundo mais próxima que cobre o botão.
static func _art_source(b: Control) -> Dictionary:
	if b.has_meta("art_src"):
		var a: Array = b.get_meta("art_src")
		return {"tex": a[0], "region": a[1]}
	var hv = b.get_node_or_null("RefHover")
	if hv is TextureRect and hv.texture is AtlasTexture:
		return {"tex": hv.texture.atlas, "region": hv.texture.region}
	var center := b.get_global_rect().get_center()
	var node: Node = b
	while node.get_parent() != null and node.get_parent() is Control:
		var par: Node = node.get_parent()
		var best: TextureRect = null
		for ch in par.get_children():
			if ch == node: break   # só o que é desenhado ANTES (embaixo) do botão
			if ch is TextureRect and ch.visible and ch.texture != null and (ch as TextureRect).get_global_rect().has_point(center):
				best = ch
		if best != null and best.stretch_mode == TextureRect.STRETCH_SCALE:
			var gr := best.get_global_rect()
			var ts := best.texture.get_size()
			var br := b.get_global_rect()
			var k := ts / gr.size
			return {"tex": best.texture, "region": Rect2((br.position - gr.position) * k, br.size * k)}
		node = par
	return {}

static var _img_cache := {}
static func _image_of(t: Texture2D) -> Image:
	if t == null: return null
	var key := t.get_rid().get_id()
	if _img_cache.has(key): return _img_cache[key]
	var img := t.get_image()
	if img == null: return null
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	_img_cache[key] = img
	return img

## recorte da arte com SÓ a placa recolorida (fundo transparente): preenche a partir do miolo até bater na
## moldura dourada; se vazar (moldura aberta), usa só o miolo azul do recorte.
static func _make_patch(t: Texture2D, region: Rect2) -> Array:
	var img := _image_of(t)
	if img == null: return []
	var r := Rect2i(region.position.round(), region.size.round()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x < 6 or r.size.y < 6: return []
	var sub := img.get_region(r)
	var w := r.size.x
	var h := r.size.y
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[int] = []
	# sementes: pontos do miolo (faixa central) que não são dourados
	for fy in [0.5, 0.4, 0.6]:
		for fx in [0.5, 0.35, 0.65, 0.2, 0.8]:
			var x := int(w * fx)
			var y := int(h * fy)
			if not _gold(sub.get_pixel(x, y)): stack.append(y * w + x)
	var edge_hits := 0
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if seen[i] == 1: continue
		var x := i % w
		var y := i / w
		var c := sub.get_pixel(x, y)
		if _gold(c) or c.a < 0.5: continue
		seen[i] = 1
		if x == 0 or y == 0 or x == w - 1 or y == h - 1: edge_hits += 1
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	var leaked := edge_hits > (w + h) * 2 * 0.35
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var gold := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := sub.get_pixel(x, y)
			var inside: bool = seen[y * w + x] == 1
			if leaked:
				inside = x > 4 and y > 4 and x < w - 5 and y < h - 5 and c.s > 0.16 and c.h > 0.5 and c.h < 0.8
			if not inside:
				if _gold(c): gold.set_pixel(x, y, c)   # moldura: cópia exata (só para o brilho passar por ela)
				continue
			var o := recolor_px(c)
			if o.is_equal_approx(c): continue
			out.set_pixel(x, y, o)
	return [ImageTexture.create_from_image(out), ImageTexture.create_from_image(gold)]

## a arte embaixo mudou (pele do tabuleiro ligou/desligou): refaz o destaque
func refresh():
	var b := get_parent() as Control
	if _mode == "material" and b != null and b.material is ShaderMaterial and (b.material as ShaderMaterial).shader == _shader:
		b.material = null
		for ch in b.get_children():
			if ch is CanvasItem and not (ch is Label): (ch as CanvasItem).use_parent_material = false
	_mode = ""
	_patch = null
	material = null
	var gl = get_node_or_null("Glint")
	if gl != null:
		remove_child(gl)
		gl.queue_free()
	_setup()
	queue_redraw()

func _draw():
	if _mode != "patch" or _patch == null: return
	var par := get_parent() as Control
	if par is BaseButton and (par as BaseButton).disabled: return
	draw_texture_rect(_patch, Rect2(Vector2.ZERO, size), false)
