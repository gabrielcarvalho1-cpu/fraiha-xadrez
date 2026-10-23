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
uniform sampler2D plate_mask : filter_nearest;   // miolo da placa na textura do botão (o resto não muda)
uniform vec2 mask_size = vec2(0.0);
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
	bool masked = mask_size.x > 0.0 && abs(float(textureSize(TEXTURE, 0).x) - mask_size.x) < 0.5 && abs(float(textureSize(TEXTURE, 0).y) - mask_size.y) < 0.5;
	bool inside = !masked || texture(plate_mask, UV).a > 0.5;
	bool goldish = hsv.x > 0.05 && hsv.x < 0.19 && hsv.y > 0.38 && hsv.z > 0.38;
	if (recolor > 0.5 && inside) {
		if (hsv.y > 0.16 && hsv.x > 0.24 && hsv.x < 0.80 && hsv.z >= 0.24) {
			o = hsv2rgb(vec3(0.992, min(1.0, hsv.y * 1.02), hsv.z * 0.95));   // azul-marinho -> vinho
			wine = true;
		} else if (hsv.z < 0.30 || (hsv.y < 0.25 && hsv.z < 0.55) || (hsv.x > 0.24 && hsv.x < 0.80 && hsv.z < 0.24)) {
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
	if (inside || goldish) o += vec3(1.0, 0.88, 0.62) * band * 0.36 * shine;
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
	if c.s > 0.16 and c.h > 0.24 and c.h < 0.80 and c.v >= 0.24 and c.v < 0.62:
		var o := Color.from_hsv(0.992, minf(1.0, c.s * 1.02), c.v * 0.95)
		o.a = c.a
		return o
	if c.v < 0.30 or (c.s < 0.25 and c.v < 0.55) or (c.h > 0.24 and c.h < 0.80 and c.v < 0.24):
		var w := Color(0.36, 0.06, 0.07) * (0.72 + c.v * 2.0)
		var o2 := c.lerp(w, 0.85)
		o2.a = c.a
		return o2
	return c

## o que segura o preenchimento: a moldura dourada; na textura de botão (sem texto) também o brilho claro da moldura
static func _wall(c: Color, bright_too: bool) -> bool:
	if c.h > 0.03 and c.h < 0.2 and c.s > 0.3 and c.v > 0.18: return true   # dourado, inclusive o escuro da moldura
	return bright_too and c.v > 0.8 and c.s < 0.45

## R176.8 · miolo de placa pintada: TODO pixel do miolo (menos texto claro) vira o mesmo vinho, só pelo brilho —
## antes azul e escuro iam por contas diferentes e a placa ficava manchada (SAIR do lobby).
static func recolor_plate_px(c: Color) -> Color:
	if c.v > 0.72 and c.s < 0.35: return c          # letra/realce claro
	if _gold(c): return c
	var lum := 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
	var f := clampf(0.42 + lum * 2.1, 0.42, 1.25)
	var o := Color(0.50, 0.075, 0.09) * f
	o.a = c.a
	return o

static func _gold(c: Color) -> bool:
	return c.h > 0.05 and c.h < 0.19 and c.s > 0.38 and c.v > 0.38

var _mode := ""            # "material" | "patch" | "none"
var _patch: Texture2D
var _t := 0.0   # (testes antigos mexiam nisso; o tempo agora é o TIME do shader)

func _ready():
	# só monta quando o botão aparece de verdade (arte carregada sob demanda continua sob demanda)
	var b := get_parent() as Control
	if b != null and not b.is_visible_in_tree():
		b.visibility_changed.connect(_first_show)
		return
	(func(): _setup()).call_deferred()

func _first_show():
	var b := get_parent() as Control
	if b == null or not b.is_visible_in_tree() or _mode != "": return
	(func(): if _mode == "": _setup()).call_deferred()

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
				# R176.8b · escrita e porta no padrão do VOLTAR de COROAS (iguais em todos os botões de saída)
				if pair.size() >= 4:
					var lb := BackLabel.new()
					lb.name = "BackLabel"
					lb.text = label_for(b)
					lb.inner_frac = Rect2(pair[2].position / pair[3], pair[2].size / pair[3])
					lb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
					add_child(lb)
					_hide_child_labels(b)
		_mode = "patch" if _patch != null else "none"
		queue_redraw()
		return
	if b.material == null:
		var bm := recolor_material()
		bm.set_shader_parameter("phase", ph)
		bm.set_shader_parameter("box", b.size)
		var pt := _plate_texture(b)
		if pt != null:
			var mk := _mask_of(pt)
			if mk != null:
				bm.set_shader_parameter("plate_mask", mk)
				bm.set_shader_parameter("mask_size", pt.get_size())
		b.resized.connect(func(): if b.material == bm: bm.set_shader_parameter("box", b.size))
		b.material = bm
		for ch in b.get_children():
			if ch is CanvasItem and not (ch is Label) and not (ch is RichTextLabel) and ch != self and (ch as CanvasItem).material == null:
				(ch as CanvasItem).use_parent_material = true
		_mode = "material"
		_style_text(b)   # R176.8b · mesma escrita (Cinzel dourada) dos botões de placa
		get_tree().create_timer(0.3).timeout.connect(func(): if is_instance_valid(b): _style_text(b))   # quem cria o botão às vezes pinta o texto depois
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
		var empty_box: bool = bt.flat or sb == null or sb is StyleBoxEmpty or (sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color.a < 0.05 and (sb as StyleBoxFlat).border_width_left == 0)
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
		var m = b.get_meta("art_src")
		var a: Array = m.call() if m is Callable else m
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

## textura da placa de um botão desenhado (para recolorir só o miolo, mesmo quando a textura traz fundo junto)
static func _plate_texture(b: Control) -> Texture2D:
	if b.has_method("plate_texture"): return b.plate_texture()
	if b is TextureButton: return (b as TextureButton).texture_normal
	var sb = b.get_theme_stylebox("normal")
	if sb is StyleBoxTexture: return (sb as StyleBoxTexture).texture
	return null

## máscara do miolo (preenchimento do centro até a moldura dourada); nula se a textura já não tem fundo
static var _mask_cache := {}
static func _mask_of(t: Texture2D) -> Texture2D:
	var key := t.get_rid().get_id()
	if _mask_cache.has(key): return _mask_cache[key]
	var res: Texture2D = null
	var ts := t.get_size()
	var img := _image_of(t) if ts.x * ts.y <= 260000.0 else null   # placas de botão são pequenas; arte grande não
	if img != null:
		var pair := _make_patch(t, Rect2(Vector2.ZERO, img.get_size()), true)
		if not pair.is_empty(): res = pair[0]
	_mask_cache[key] = res
	return res

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

## recorte da arte com SÓ a placa recolorida (fundo transparente).
## R176.8 · PLACA LIMPA: o miolo inteiro (dentro da moldura dourada, inclusive o "buraco" das letras) vira um vinho
## liso com degradê; as letras/ícones da arte são separados por brilho (só manchas grandes o bastante: pingos e
## risquinhos da textura somem) e recompostos nítidos com sombra suave. A seta ">" só vira "<" quando é mesmo uma
## seta solta no fim da placa (nunca uma letra).
static func _make_patch(t: Texture2D, region: Rect2, mask_only := false) -> Array:
	var img := _image_of(t)
	if img == null: return []
	var r := Rect2i(region.position.round(), region.size.round()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x < 6 or r.size.y < 6: return []
	var sub := img.get_region(r)
	var w := r.size.x
	var h := r.size.y
	if mask_only: return _outer_mask(sub, w, h)
	var seen := PackedByteArray()
	for wv in [0.5, 0.3, 0.18]:
		seen = _flood_center(sub, w, h, wv)
		if not seen.is_empty(): break
	if seen.is_empty(): return []
	var m := _fill_holes(seen, w, h)
	_clip_rows(sub, m, w, h)
	return _clean_plate(sub, m, w, h)

## R176.8c · a placa termina na 1ª linha dourada acima/abaixo do meio: o vão escuro entre a placa e a moldura
## da página (embaixo do VOLTAR do DESAFIO DAS LIGAS) não vira vinho. Mediana de várias colunas (letras não contam).
static func _clip_rows(sub: Image, m: PackedByteArray, w: int, h: int) -> void:
	var gold := func(c: Color) -> bool: return c.h > 0.05 and c.h < 0.19 and c.s > 0.45 and c.v > 0.5
	var half := maxi(4, int(w * 0.04))
	# linha da moldura = faixa HORIZONTAL dourada (letras e a porta pintadas não formam uma faixa contínua)
	var line := func(x: int, y: int) -> bool:
		var ok := 0
		for xx in range(maxi(0, x - half), mini(w, x + half + 1)):
			if gold.call(sub.get_pixel(xx, y)): ok += 1
		return ok >= int((half * 2 + 1) * 0.85)
	var tops: Array = []
	var bots: Array = []
	for fx in [0.3, 0.42, 0.55, 0.68, 0.8, 0.9]:
		var x := int(w * fx)
		var y := h / 2
		while y > 0 and not line.call(x, y): y -= 1
		tops.append(y)
		y = h / 2
		while y < h - 1 and not line.call(x, y): y += 1
		bots.append(y)
	tops.sort()
	bots.sort()
	var top: int = tops[tops.size() / 2]
	var bot: int = bots[bots.size() / 2]
	if bot - top < h * 0.35: return   # não achou a moldura: não mexe
	for y in h:
		if y >= top and y <= bot: continue
		for x in w: m[y * w + x] = 0

## miolo alcançado do centro sem atravessar a moldura (dourado com brilho >= wall_v); vazio se vazar
static func _flood_center(sub: Image, w: int, h: int, wall_v: float) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[int] = []
	var wall := func(c: Color) -> bool: return c.a < 0.5 or (c.h > 0.03 and c.h < 0.2 and c.s > 0.3 and c.v > wall_v)
	for fy in [0.5, 0.4, 0.6]:
		for fx in [0.5, 0.35, 0.65, 0.2, 0.8]:
			var x := int(w * fx)
			var y := int(h * fy)
			if not wall.call(sub.get_pixel(x, y)): stack.append(y * w + x)
	var edge_hits := 0
	var count := 0
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if seen[i] == 1: continue
		var x := i % w
		var y := i / w
		if wall.call(sub.get_pixel(x, y)): continue
		seen[i] = 1
		count += 1
		if x == 0 or y == 0 or x == w - 1 or y == h - 1: edge_hits += 1
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	if edge_hits > (w + h) * 2 * 0.35 or count < w * h * 0.2: return PackedByteArray()
	return seen

## miolo + tudo o que ele cerca (letras, ícones, o "buraco" do O): o que NÃO se alcança da borda do recorte
static func _fill_holes(seen: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var outside := PackedByteArray()
	outside.resize(w * h)
	var q: Array[int] = []
	for x in w:
		q.append(x)
		q.append((h - 1) * w + x)
	for y in h:
		q.append(y * w)
		q.append(y * w + w - 1)
	var qi := 0
	while qi < q.size():
		var i: int = q[qi]
		qi += 1
		if outside[i] == 1 or seen[i] == 1: continue
		outside[i] = 1
		var x := i % w
		if x > 0: q.append(i - 1)
		if x < w - 1: q.append(i + 1)
		if i >= w: q.append(i - w)
		if i < w * (h - 1): q.append(i + w)
	var m := PackedByteArray()
	m.resize(w * h)
	for i in w * h:
		if outside[i] == 0: m[i] = 1
	return m

## quanto um pixel é "tinta" (letra creme/dourada) — 0 = fundo
static func _ink(c: Color) -> float:
	var warm := c.s < 0.32 or c.h < 0.2 or c.h > 0.94
	if not warm: return 0.0
	return clampf((c.v - 0.40) / 0.22, 0.0, 1.0)

static func _clean_plate(sub: Image, m: PackedByteArray, w: int, h: int) -> Array:
	var n := w * h
	# costura: pixel escuro/azul colado no miolo (entre o miolo e a moldura) também vira placa
	# R176.8c · só costura o que está DENTRO da moldura: o que se alcança da borda do recorte sem cruzar dourado é fora
	var outside := PackedByteArray()
	outside.resize(n)
	var oq: Array[int] = []
	for x in w:
		oq.append(x)
		oq.append((h - 1) * w + x)
	for y in h:
		oq.append(y * w)
		oq.append(y * w + w - 1)
	var oi := 0
	while oi < oq.size():
		var k: int = oq[oi]
		oi += 1
		if outside[k] == 1 or m[k] == 1: continue
		var kc := sub.get_pixel(k % w, k / w)
		if _gold(kc) or (kc.h > 0.03 and kc.h < 0.2 and kc.s > 0.3 and kc.v > 0.18): continue
		outside[k] = 1
		var kx := k % w
		if kx > 0: oq.append(k - 1)
		if kx < w - 1: oq.append(k + 1)
		if k >= w: oq.append(k - w)
		if k < w * (h - 1): oq.append(k + w)
	var m2 := m.duplicate()
	var ys := []
	for i in n: if m[i] == 1: ys.append(i / w)
	var ytop: int = ys.min() if not ys.is_empty() else 0
	var ybot: int = ys.max() if not ys.is_empty() else h - 1
	for i in n:
		if m[i] == 1 or outside[i] == 1: continue
		if i / w < ytop - 1 or i / w > ybot + 1: continue
		var x := i % w
		var y := i / w
		var c := sub.get_pixel(x, y)
		if _gold(c) or c.a < 0.5: continue
		var touch := false
		for dy in [-2, -1, 0, 1, 2]:
			for dx in [-2, -1, 0, 1, 2]:
				var nx: int = x + dx
				var ny: int = y + dy
				if nx >= 0 and ny >= 0 and nx < w and ny < h and m[ny * w + nx] == 1: touch = true
		if touch: m2[i] = 1
	m = m2
	# 0) distância até a moldura (sombra interna; enfeite colado na moldura não é letra)
	var dist := PackedByteArray()
	dist.resize(n)
	for i in n: dist[i] = 0 if m[i] == 0 else 255
	for step in 5:
		for i in n:
			if dist[i] != 255: continue
			var x := i % w
			var y := i / w
			var near := (x > 0 and dist[i - 1] == step) or (x < w - 1 and dist[i + 1] == step) or (y > 0 and dist[i - w] == step) or (y < h - 1 and dist[i + w] == step)
			if near: dist[i] = step + 1
	# 1) tinta e componentes (8-vizinhos) do núcleo da tinta
	var ink := PackedFloat32Array()
	ink.resize(n)
	for i in n:
		if m[i] == 1: ink[i] = _ink(sub.get_pixel(i % w, i / w))
	var lab := PackedInt32Array()
	lab.resize(n)
	lab.fill(-1)
	var comps: Array = []   # {area, mn, mx, col}
	var min_area := maxi(4, int(h * h * 0.0006))
	for i0 in n:
		if lab[i0] != -1 or ink[i0] < 0.5: continue
		var id := comps.size()
		var st: Array[int] = [i0]
		lab[i0] = id
		var area := 0
		var mn := Vector2i(w, h)
		var mx := Vector2i(-1, -1)
		var acc := Color(0, 0, 0, 0)
		var near_frame := false
		while not st.is_empty():
			var i: int = st.pop_back()
			var x := i % w
			var y := i / w
			area += 1
			if dist[i] <= 3: near_frame = true
			mn = Vector2i(mini(mn.x, x), mini(mn.y, y))
			mx = Vector2i(maxi(mx.x, x), maxi(mx.y, y))
			if ink[i] > 0.85: acc += sub.get_pixel(x, y)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
					var j := ny * w + nx
					if lab[j] == -1 and ink[j] >= 0.5:
						lab[j] = id
						st.append(j)
		var col := Color(0.96, 0.84, 0.55)
		if acc.a > 0.5: col = Color(acc.r / acc.a, acc.g / acc.a, acc.b / acc.a)
		var thin: bool = (mx.y - mn.y + 1) <= maxi(3, int(h * 0.04)) and (mx.x - mn.x + 1) > 5 * (mx.y - mn.y + 1)   # risco da textura/moldura
		comps.append({"area": area, "mn": mn, "mx": mx, "col": col, "keep": area >= min_area and not thin and not (near_frame and area < h * h * 0.01)})
	# R176.8b · padrão único: TODA a escrita/ícone pintado sai (o jogo escreve por cima no mesmo estilo em todos)
	for cp in comps: cp.keep = false
	# 2) borda macia das letras: pixel de tinta fraca herda o componente vizinho (até 2 px); pingos somem
	var a_out := PackedFloat32Array()
	a_out.resize(n)
	var c_out: Array[Color] = []
	c_out.resize(n)
	for i in n:
		if m[i] == 0 or ink[i] <= 0.0: continue
		var id := lab[i]
		if id == -1:
			var x := i % w
			var y := i / w
			for dy in [-2, -1, 0, 1, 2]:
				for dx in [-2, -1, 0, 1, 2]:
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
					var l2 := lab[ny * w + nx]
					if l2 != -1 and comps[l2].keep:
						id = l2
						break
				if id != -1: break
		if id == -1 or not comps[id].keep: continue
		a_out[i] = ink[i]
		c_out[i] = sub.get_pixel(i % w, i / w) if ink[i] > 0.85 else comps[id].col
	# 3) seta ">" solta no fim da placa vira "<" (espelha só os pixels dela)
	for id in comps.size():
		var cp: Dictionary = comps[id]
		if not cp.keep: continue
		var bw: int = cp.mx.x - cp.mn.x + 1
		var bh: int = cp.mx.y - cp.mn.y + 1
		if (cp.mn.x + cp.mx.x) * 0.5 < w * 0.72 or bw > w * 0.12 or bh < h * 0.2 or bh > h * 0.75: continue
		var alone := true
		for id2 in comps.size():
			if id2 == id or not comps[id2].keep or comps[id2].area < cp.area * 0.25: continue
			var o: Dictionary = comps[id2]
			var vert: bool = o.mx.y >= cp.mn.y and o.mn.y <= cp.mx.y
			if vert and o.mx.x < cp.mn.x and cp.mn.x - o.mx.x < w * 0.05: alone = false
			if vert and o.mn.x > cp.mx.x and o.mn.x - cp.mx.x < w * 0.05: alone = false
		if not alone: continue
		var x0: int = maxi(0, cp.mn.x - 2)
		var x1: int = mini(w - 1, cp.mx.x + 2)
		var y0: int = maxi(0, cp.mn.y - 2)
		var y1: int = mini(h - 1, cp.mx.y + 2)
		for y in range(y0, y1 + 1):
			var row_a: Array = []
			var row_c: Array = []
			for x in range(x0, x1 + 1):
				row_a.append(a_out[y * w + x])
				row_c.append(c_out[y * w + x])
			for x in range(x0, x1 + 1):
				var k := x1 - x
				a_out[y * w + x] = row_a[k]
				c_out[y * w + x] = row_c[k]
	# 4) montagem
	var sh := maxi(1, int(round(h / 60.0)))   # sombra das letras
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var gold := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var fy := float(y) / float(maxi(1, h - 1))
		var base := Color(0.58, 0.10, 0.12).lerp(Color(0.33, 0.05, 0.07), fy)
		for x in w:
			var i := y * w + x
			if m[i] == 0:
				var c := sub.get_pixel(x, y)
				if _gold(c): gold.set_pixel(x, y, c)
				continue
			var d: int = mini(dist[i], 5)
			var bg := base * (0.72 + 0.28 * float(d - 1) / 4.0)
			var sx := x - sh
			var sy := y - sh
			if sx >= 0 and sy >= 0:
				var sa: float = a_out[sy * w + sx]
				if sa > 0.0: bg = bg.lerp(Color(0.12, 0.02, 0.03), sa * 0.55)
			var a: float = a_out[i]
			var o := bg.lerp(c_out[i], a) if a > 0.0 else bg
			o.a = 1.0
			out.set_pixel(x, y, o)
	var mn := Vector2i(w, h)
	var mx := Vector2i(-1, -1)
	for i in n:
		if m[i] == 1:
			mn = Vector2i(mini(mn.x, i % w), mini(mn.y, i / w))
			mx = Vector2i(maxi(mx.x, i % w), maxi(mx.y, i / w))
	var inner := Rect2(Vector2(mn), Vector2(mx - mn + Vector2i.ONE)) if mx.x >= 0 else Rect2(0, 0, w, h)
	return [ImageTexture.create_from_image(out), ImageTexture.create_from_image(gold), inner, Vector2(w, h)]

## Máscara da placa numa textura de botão: tudo o que fica DENTRO da moldura externa (o fundo que vem junto na
## textura é o que se alcança a partir das bordas sem atravessar o dourado). Moldura aberta: sem máscara.
static func _outer_mask(sub: Image, w: int, h: int) -> Array:
	var out_px := PackedByteArray()
	out_px.resize(w * h)
	var q: Array[int] = []
	for x in w:
		q.append(x)
		q.append((h - 1) * w + x)
	for y in h:
		q.append(y * w)
		q.append(y * w + w - 1)
	var qi := 0
	while qi < q.size():
		var i: int = q[qi]
		qi += 1
		if out_px[i] == 1: continue
		var x: int = i % w
		var y: int = i / w
		var c := sub.get_pixel(x, y)
		if c.a >= 0.5 and _wall(c, true): continue
		out_px[i] = 1
		if x > 0: q.append(i - 1)
		if x < w - 1: q.append(i + 1)
		if y > 0: q.append(i - w)
		if y < h - 1: q.append(i + w)
	if out_px[(h / 2) * w + w / 2] == 1: return []   # o "fora" chegou ao centro: não há moldura fechada
	var mimg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for i in w * h:
		if out_px[i] == 0: mimg.set_pixel(i % w, i / w, Color.WHITE)
	return [ImageTexture.create_from_image(mimg)]

## Seta ">" pintada no fim da placa: um bloco dourado solto (cercado pelo miolo), estreito, no último quarto.
## Devolve o retângulo (com folga) para espelhar; vazio se não houver seta.
static func _chevron_rect(sub: Image, seen: PackedByteArray, w: int, h: int) -> Rect2:
	var visited := PackedByteArray()
	visited.resize(w * h)
	var best := Rect2()
	for y0 in range(2, h - 2):
		for x0 in range(int(w * 0.72), w - 2):
			var i0 := y0 * w + x0
			if visited[i0] == 1 or seen[i0] == 1 or not _gold(sub.get_pixel(x0, y0)): continue
			var stack: Array[int] = [i0]
			var mn := Vector2i(x0, y0)
			var mxv := Vector2i(x0, y0)
			var touches := false
			var count := 0
			while not stack.is_empty():
				var i: int = stack.pop_back()
				if visited[i] == 1: continue
				var x := i % w
				var y := i / w
				if seen[i] == 1 or not _gold(sub.get_pixel(x, y)): continue
				visited[i] = 1
				count += 1
				mn = Vector2i(mini(mn.x, x), mini(mn.y, y))
				mxv = Vector2i(maxi(mxv.x, x), maxi(mxv.y, y))
				if x <= 1 or y <= 1 or x >= w - 2 or y >= h - 2:
					touches = true
					continue
				stack.append_array([i - 1, i + 1, i - w, i + w])
			var bw := mxv.x - mn.x + 1
			var bh := mxv.y - mn.y + 1
			if touches or count < 12: continue
			if bw > w * 0.12 or bh < h * 0.2 or bh > h * 0.75: continue
			var r := Rect2(mn.x - 3, mn.y - 3, bw + 6, bh + 6)
			if r.position.x < 0 or r.end.x > w or r.position.y < 0 or r.end.y > h: continue
			# a folga em volta tem que ser miolo (nada da moldura entra no espelho)
			var ok := true
			for yy in range(int(r.position.y), int(r.end.y)):
				for xx in [int(r.position.x), int(r.end.x) - 1]:
					if seen[yy * w + xx] != 1 and _gold(sub.get_pixel(xx, yy)): ok = false
			if ok and r.get_center().x > best.get_center().x: best = r
	return best

## texto do botão no padrão único: INÍCIO / SAIR / DESISTIR / VOLTAR
static func label_for(b: Control) -> String:
	if b.has_meta("back_label"): return String(b.get_meta("back_label"))
	var nm := String(b.name)
	if nm in ["HomeButton", "home"]: return "INÍCIO"
	if nm.ends_with("Resign"): return "DESISTIR"
	var texts: Array = []
	if b is Button: texts.append(String((b as Button).text))
	for c in b.find_children("*", "Label", true, false): texts.append(String((c as Label).text))
	for raw in texts:
		var t := String(raw).strip_edges().to_lower()
		if t.begins_with("sair"): return "SAIR"
		if t.begins_with("início") or t.begins_with("inicio"): return "INÍCIO"
		if t.begins_with("desistir"): return "DESISTIR"
	if nm.ends_with("Leave") or nm.ends_with("Exit"): return "SAIR"
	return "VOLTAR"

## botões desenhados (com texto próprio): a escrita vira a mesma das placas — Cinzel dourada com contorno escuro
static func _style_text(b: Control) -> void:
	b.set_meta("back_style", true)   # botões que desenham o próprio texto (OrnateButton…) leem isso
	b.queue_redraw()
	var targets: Array = []
	if b is Button and not (b as Button).text.is_empty(): targets.append(b)
	for c in b.find_children("*", "Label", true, false): targets.append(c)
	for t in targets:
		var c := t as Control
		c.add_theme_font_override("font", LABEL_FONT)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: c.add_theme_color_override(k, Color("f8dc8e"))
		c.add_theme_color_override("font_outline_color", Color("2a1206"))
		c.add_theme_constant_override("outline_size", maxi(4, int(c.get_theme_font_size("font_size") * 0.16)))

## os textos que o próprio botão já mostra somem (a escrita nova fica por cima, no lugar)
static func _hide_child_labels(b: Control) -> void:
	for c in b.find_children("*", "Label", true, false):
		if c.get_parent() != null and c.get_parent().name == "BackPulse": continue
		(c as CanvasItem).self_modulate.a = 0.0
	if b is Button and not (b as Button).text.is_empty():
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: (b as Button).add_theme_color_override(k, Color(0, 0, 0, 0))
		(b as Button).add_theme_constant_override("outline_size", 0)

const DOOR := preload("res://ui_kit/art/back_door.png")
const LABEL_FONT := preload("res://account/fonts/Cinzel-Bold.woff")
class BackLabel extends Control:
	var text := "VOLTAR"
	var inner_frac := Rect2(0, 0, 1, 1)
	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw():
		var par := get_parent().get_parent() as BaseButton
		if par != null and par.disabled: return
		var ir := Rect2(inner_frac.position * size, inner_frac.size * size)
		var h := ir.size.y
		# porta à esquerda
		var dh := h * 0.66
		var ds := Vector2(dh * DOOR.get_width() / float(DOOR.get_height()), dh)
		var dp := Vector2(ir.position.x + maxf(h * 0.32, ir.size.x * 0.06), ir.position.y + (h - dh) / 2.0)
		draw_texture_rect(DOOR, Rect2(dp + Vector2(1, 2), ds), false, Color(0, 0, 0, 0.45))
		draw_texture_rect(DOOR, Rect2(dp, ds), false)
		# texto: Cinzel dourado com contorno escuro, centrado no espaço depois da porta
		var x0 := dp.x + ds.x + h * 0.2
		var x1 := ir.end.x - h * 0.3
		var fs := int(h * 0.5)
		while fs > 8 and LABEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > x1 - x0: fs -= 1
		var tw := LABEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := (ir.position.x + ir.end.x) / 2.0 + ds.x * 0.5
		var tx := clampf(cx - tw / 2.0, x0, x1 - tw)
		var ty := ir.position.y + h / 2.0 + fs * 0.36
		var ol := maxi(2, int(fs * 0.16))
		draw_string_outline(LABEL_FONT, Vector2(tx + 1, ty + 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, Color(0, 0, 0, 0.35))
		draw_string_outline(LABEL_FONT, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, Color("2a1206"))
		draw_string(LABEL_FONT, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f8dc8e"))

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
	for nn in ["Glint", "BackLabel"]:
		var gl = get_node_or_null(nn)
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
