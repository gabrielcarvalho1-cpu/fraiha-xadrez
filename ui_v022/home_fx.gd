extends Control
## R44 · Animações da Home (R44.1: todas lentas e sutis; fumacinha nos cavalos) (arte oficial v7): tochas e lanterna tremulando, água da cachoeira e do rio
## correndo, passarinhos atravessando o céu e a barriguinha da gatinha YUMI subindo e descendo
## (só a barriga: cabeça, orelhas, patas e contorno ficam parados).
## Tudo em coordenadas do canvas 1672 x 941, por cima da arte e por baixo dos painéis/botões.
## Só recortes da PRÓPRIA arte animados por shader (nada redesenhado) + luz aditiva discreta.
const FOREST_PATH := "res://ui_v022/assets/home_forest_v9.png"   # R64: arte v9 · R89: carregada só para montar os efeitos

## [centro da chama, tamanho do recorte, raio da luz]
const TORCHES := [
    [Vector2(579, 540), Vector2(36, 52), 48.0],     # pilar esquerdo do menu (R47: arte v8)
    [Vector2(1069, 540), Vector2(36, 52), 48.0],    # pilar direito do menu (R47: arte v8)
    [Vector2(1266, 494), Vector2(24, 34), 34.0],    # tocha da ponte
    [Vector2(1471, 490), Vector2(24, 34), 34.0],    # tocha da direita
    [Vector2(392, 327), Vector2(52, 50), 40.0],     # lanterna da árvore
]
const WATER_RECT := Rect2(1150, 400, 312, 420)
const BELLY_RECT := Rect2(40, 704, 150, 92)        # corpo da gatinha (a barriga fica no meio)
const BELLY_C := Vector2(108, 748)                 # centro da barriga
const BELLY_R := Vector2(52, 30)                   # raio da área que respira (dentro do contorno)
const SKY := Rect2(1185, 228, 440, 92)
## R44.1 · fumacinha das narinas dos cavalos do logo: [narina, direção do focinho]
const NOSES := [[Vector2(586, 172), 1.0], [Vector2(1060, 172), -1.0]]            # céu visível entre a placa do perfil e as montanhas

## R44.1 · tudo SUTIL e LENTO (pedido do dono): nada de esticar a chama nem brilhos piscando.
## R197 · chama mais viva e mais SUAVE (pedido do dono): recorte com filtro linear (sem "degrau" de pixel),
## balanço com 2 ruídos lentos, a ponta "lambendo" para cima e a luz respirando.
const FLAME_SHADER := """
shader_type canvas_item;
uniform float seed = 0.0;
float fm(vec4 c) { return smoothstep(0.50, 0.82, max(c.r, c.g)) * step(c.b, c.r + 0.05); }
float h(float x) { return fract(sin(x * 91.7) * 43758.5453); }
float sn(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h(i), h(i + 1.0), f); }
void fragment() {
    vec4 o = texture(TEXTURE, UV);
    float k = clamp(1.0 - UV.y, 0.0, 1.0);
    float sway = (sn(TIME * 1.3 + seed) - 0.5) * 0.06 + (sn(TIME * 3.1 + seed * 2.3) - 0.5) * 0.025;
    float lick = (sn(TIME * 2.2 + seed * 1.7) - 0.5) * 0.07;
    vec2 suv = vec2(UV.x - sway * k * k, UV.y + lick * k * k);
    vec4 s = texture(TEXTURE, suv);
    float m = max(fm(o), fm(s));
    vec4 c = mix(o, s, fm(s));
    c.rgb *= 1.0 + m * ((sn(TIME * 1.9 + seed * 3.0) - 0.5) * 0.18 + (sn(TIME * 6.0 + seed) - 0.5) * 0.06);
    COLOR = vec4(c.rgb, m);
}
"""

const WATER_SHADER := """
shader_type canvas_item;
// só água de verdade: azul claro e saturado (céu, árvores e pedras azuladas ficam de fora)
float wm(vec3 c) { return smoothstep(0.22, 0.37, c.b - c.r) * smoothstep(0.62, 0.82, c.b) * smoothstep(0.30, 0.50, c.g); }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
uniform vec2 px_size = vec2(312.0, 420.0);
void fragment() {
    vec4 o = texture(TEXTURE, UV);
    float m = wm(o.rgb);
    vec2 p = UV * px_size;
    // correnteza: variação lenta de brilho descendo (±8 %)
    float flow = n(vec2(p.x * 0.12, p.y * 0.034 - TIME * 0.6)) - 0.5;
    // R197 · reflexos bem leves descendo pela queda (riscos claros, sem piscar)
    float glint = pow(n(vec2(p.x * 0.35, p.y * 0.05 - TIME * 1.5)), 6.0) * 0.55;
    vec3 col = o.rgb * (1.0 + flow * 0.16) + vec3(0.85, 0.95, 1.0) * glint * 0.35;
    COLOR = vec4(col, m * 0.92);
}
"""

## R197 · folhas: o miolo das folhas "respira" ~1 px com o vento (as bordas ficam onde estão) e a luz varia de leve
const LEAF_SHADER := """
shader_type canvas_item;
uniform float seed = 0.0;
float lm(vec3 c) { return smoothstep(0.02, 0.10, c.g - max(c.r * 0.92, c.b)) * smoothstep(0.16, 0.32, c.g); }
void fragment() {
    vec2 px = TEXTURE_PIXEL_SIZE;
    vec2 q = UV / px;
    float ph = TIME * 0.85 + seed + q.y * 0.045 + q.x * 0.02;
    float gust = 0.55 + 0.45 * sin(TIME * 0.31 + seed + q.y * 0.004);
    vec2 d = vec2(sin(ph), 0.45 * cos(ph * 0.8)) * px * 1.3 * gust;
    vec4 o = texture(TEXTURE, UV);
    vec4 s = texture(TEXTURE, UV + d);
    float m = lm(o.rgb) * lm(s.rgb);
    COLOR = vec4(s.rgb * (1.0 + 0.06 * sin(ph * 1.3 + 1.0) * gust), m);
}
"""

const CAT_SHADER := """
shader_type canvas_item;
uniform vec2 c;            // centro da barriga (UV)
uniform vec2 r;            // raio (UV)
uniform float breath = 0.0;
void fragment() {
    vec2 d = (UV - c) / r;
    float w = 1.0 - smoothstep(0.35, 1.0, length(d));
    float k = 1.0 + 0.06 * breath * w;
    vec2 suv = c + (UV - c) / k;
    vec4 s = texture(TEXTURE, suv);
    COLOR = vec4(s.rgb, w > 0.0 ? 1.0 : 0.0);
}
"""

var t := 0.0
var _src: Image
var _cat_mat: ShaderMaterial
var _glows: Array = []
var _birds: Array = []
var _next_flock := 3.0
var _puffs: Array = []
var _next_puff := 4.0
var _add := CanvasItemMaterial.new()
var _glow_tex: GradientTexture2D
## R52e · fumacinha: discos desenhados uma vez e animados (escala/posição/opacidade) em vez de draw_circle
## por quadro, que na Web criava buffers novos de GPU a cada quadro.
const Disc := preload("res://ui_v022/static_disc.gd")
const PUFF_POOL := 20
var _puff_discs: Array = []
var _drew_birds := false

## R197 · a mesma animação serve a Home do PC (padrão) e a Home do celular em pé (mobile_home_ref.gd troca a
## arte e as posições antes de montar). Tudo em coordenadas da arte.
var forest_path := FOREST_PATH
var torches: Array = TORCHES
var lantern_last := true          # o último da lista é a lanterna (vidro fechado: só a luz respira)
var water_rects: Array = [WATER_RECT]
var leaf_rects: Array = []        # R197 · folhas que balançam
var belly := [BELLY_RECT, BELLY_C, BELLY_R]
var sky := SKY
var noses: Array = NOSES
var mists: Array = []             # R197 · névoa subindo da base das quedas: [centro, largura]
var art_size := Vector2(1672, 941)
## R197 · fagulhas subindo das tochas e névoa da cachoeira (discos prontos, só animados)
const EMBER_POOL := 24
const MIST_POOL := 14
var _embers: Array = []
var _ember_discs: Array = []
var _mist: Array = []
var _mist_discs: Array = []
## R197 · passarinhos ao fundo (laço de 24 s, bem baixo, no bus dos efeitos: o mudo dos efeitos desliga)
const AMBIENCE := "res://audio_v025/passarinhos.ogg"
const AMBIENCE_DB := -21.0
var _amb: AudioStreamPlayer
var _awake := true

func _init():
    name = "HomeFx"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size = Vector2(1672, 941)

var _built := false
## R89 · no celular a Home do PC só existe deitada: os efeitos são montados na 1ª vez que ela aparece
## (antes: no _ready, também no celular em pé — leitura da GPU + 6 MB de imagem guardados para sempre).
var auto_build := true
func _ready():
    if auto_build and not preload("res://ui_v022/mobile_layout.gd").active(get_viewport()): _build()

func set_awake(on: bool):
    _awake = on
    if on and not _built: _build()
    _sync_amb()

func _notification(what):
    if what == NOTIFICATION_VISIBILITY_CHANGED: _sync_amb()

func _sync_amb():
    if _amb == null: return
    var on := _awake and is_visible_in_tree()
    if on and not _amb.playing: _amb.play()
    elif not on and _amb.playing: _amb.stop()

func _build():
    if _built: return
    _built = true
    size = art_size
    _src = (load(forest_path) as Texture2D).get_image()
    if _src.is_compressed(): _src.decompress()
    _add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    var g := Gradient.new()
    g.set_color(0, Color(1.0, 0.72, 0.32, 0.55))
    g.set_color(1, Color(1.0, 0.45, 0.10, 0.0))
    _glow_tex = GradientTexture2D.new()
    _glow_tex.gradient = g
    _glow_tex.fill = GradientTexture2D.FILL_RADIAL
    _glow_tex.fill_from = Vector2(0.5, 0.5)
    _glow_tex.fill_to = Vector2(1.0, 0.5)
    _glow_tex.width = 64
    _glow_tex.height = 64
    # folhas (por baixo de tudo)
    for i in leaf_rects.size():
        _piece(leaf_rects[i], LEAF_SHADER, true).set_shader_parameter("seed", float(i) * 2.3)
    # água
    for wr in water_rects:
        _piece(wr, WATER_SHADER).set_shader_parameter("px_size", (wr as Rect2).size)
    # névoa da cachoeira
    var sg := Gradient.new()
    sg.set_color(0, Color(1, 1, 1, 1))
    sg.set_color(1, Color(1, 1, 1, 0))
    _soft = GradientTexture2D.new()
    _soft.gradient = sg
    _soft.fill = GradientTexture2D.FILL_RADIAL
    _soft.fill_from = Vector2(0.5, 0.5)
    _soft.fill_to = Vector2(1.0, 0.5)
    _soft.width = 32
    _soft.height = 32
    for i in MIST_POOL:
        _mist_discs.append(_soft_sprite(Color(0.88, 0.95, 1.0), false))
    # tochas: luz por baixo (aditiva) + chama recortada da arte balançando
    for i in torches.size():
        var c: Vector2 = torches[i][0]
        var sz: Vector2 = torches[i][1]
        var glow := TextureRect.new()
        glow.texture = _glow_tex
        glow.material = _add
        glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
        glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        var r: float = torches[i][2]
        glow.size = Vector2(r, r) * 2.0
        glow.position = c - Vector2(r, r)
        add_child(glow)
        _glows.append([glow, randf() * TAU])
        if lantern_last and i == torches.size() - 1: continue   # lanterna: vidro fechado, só a luz respira
        var m := _piece(Rect2(c - Vector2(sz.x / 2.0, sz.y * 0.62), sz), FLAME_SHADER, true)
        m.set_shader_parameter("seed", float(i) * 1.7)
    for i in EMBER_POOL:
        _ember_discs.append(_soft_sprite(Color(1.0, 0.75, 0.32), true))
    # barriguinha da gatinha
    if not belly.is_empty():
        var br: Rect2 = belly[0]
        _cat_mat = _piece(br, CAT_SHADER)
        _cat_mat.set_shader_parameter("c", (belly[1] - br.position) / br.size)
        _cat_mat.set_shader_parameter("r", belly[2] / br.size)
    for i in PUFF_POOL:
        var d = Disc.new(1.0, Color(0.93, 0.93, 0.95, 1.0))
        d.modulate.a = 0.0   # R52f · escondido por alfa: visible redesenharia o disco ao reaparecer (buffers novos na Web)
        add_child(d)
        _puff_discs.append(d)
    _src = null   # R89 · os recortes já viraram texturas; a imagem inteira não fica na memória
    if ResourceLoader.exists(AMBIENCE):
        _amb = AudioStreamPlayer.new()
        _amb.name = "BirdsAmbience"
        var st = load(AMBIENCE)
        if st is AudioStreamOggVorbis: st.loop = true
        _amb.stream = st
        _amb.bus = "Effects"
        _amb.volume_db = AMBIENCE_DB
        if OS.has_feature("web"): _amb.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
        add_child(_amb)
        _sync_amb.call_deferred()

## R197 · ponto de luz suave (textura radial pronta; só posição/escala/alfa mudam: nada é redesenhado)
var _soft: GradientTexture2D
func _soft_sprite(col: Color, additive: bool) -> Sprite2D:
    var sp := Sprite2D.new()
    sp.texture = _soft
    sp.self_modulate = col
    sp.modulate.a = 0.0
    if additive: sp.material = _add
    add_child(sp)
    return sp

func _piece(r: Rect2, code: String, smooth := false) -> ShaderMaterial:
    var rr := Rect2i(r)
    var tr := TextureRect.new()
    tr.texture = ImageTexture.create_from_image(_src.get_region(rr))
    tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    tr.stretch_mode = TextureRect.STRETCH_SCALE
    tr.position = Vector2(rr.position)
    tr.size = Vector2(rr.size)
    tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
    tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if smooth else CanvasItem.TEXTURE_FILTER_NEAREST
    var sh := Shader.new()
    sh.code = code
    var mat := ShaderMaterial.new()
    mat.shader = sh
    tr.material = mat
    add_child(tr)
    return mat

func _process(delta):
    if not _built or not is_visible_in_tree(): return
    t += delta
    for gl in _glows:
        var s: float = gl[1]
        # R197 · luz em volta: respira e tremula de leve (soma de senos, sem saltos)
        gl[0].modulate.a = 0.44 + 0.06 * sin(t * 1.3 + s) + 0.035 * sin(t * 3.7 + s * 2.0) + 0.02 * sin(t * 7.3 + s * 3.0)
    # barriga sobe e desce devagar (gato dormindo, ~3,5 s por ciclo)
    if _cat_mat != null: _cat_mat.set_shader_parameter("breath", 0.5 + 0.5 * sin(t * 1.6))
    _life(delta)
    # fumacinha dos cavalos: de vez em quando um deles solta 2 bufadas curtas, bem discretas
    _next_puff -= delta
    if _next_puff <= 0.0 and not noses.is_empty():
        _next_puff = randf_range(7.0, 13.0)
        var nose: Array = noses[randi() % noses.size()]
        for k in 2:
            for j in 5:
                _puffs.append({"p": nose[0] + Vector2(nose[1] * randf_range(0.0, 2.0), randf_range(-1.0, 1.5)),
                    "v": Vector2(nose[1] * randf_range(15.0, 23.0), randf_range(-3.0, 3.0)), "age": -k * 0.55 - j * 0.04,
                    "life": randf_range(1.3, 1.8), "r0": randf_range(1.6, 2.6)})
    for pf in _puffs:
        pf.age += delta
        if pf.age > 0.0:
            pf.p += pf.v * delta
            pf.v *= 1.0 - 0.9 * delta
            pf.v.y -= 2.5 * delta
    _puffs = _puffs.filter(func(pf): return pf.age < pf.life)
    # passarinhos
    _next_flock -= delta
    if _next_flock <= 0.0 and sky.size.x > 0.0:
        _next_flock = randf_range(10.0, 18.0)
        var dir := 1.0 if randf() < 0.5 else -1.0
        var y0 := randf_range(sky.position.y + 14.0, sky.end.y - 24.0)
        var speed := randf_range(26.0, 36.0)
        for k in randi_range(2, 5):
            _birds.append({"x": (sky.position.x - 20.0 - k * 16.0) if dir > 0.0 else (sky.end.x + 20.0 + k * 16.0),
                "y": y0 + randf_range(-10.0, 10.0) + k * 3.0, "dir": dir, "v": speed * randf_range(0.92, 1.08),
                "ph": randf() * TAU, "s": randf_range(0.8, 1.15)})
    for b in _birds:
        b.x += b.dir * b.v * delta
    _birds = _birds.filter(func(b): return b.x > sky.position.x - 120.0 and b.x < sky.end.x + 120.0)
    _update_puffs()
    # passarinhos: linhas (sem buffers), e só redesenha enquanto há bando no céu
    if not _birds.is_empty() or _drew_birds:
        _drew_birds = not _birds.is_empty()
        queue_redraw()

## R197 · fagulhas das tochas (sobem e somem) e névoa das quedas (sobe devagar, bem transparente)
var _next_ember := 0.3
var _next_mist := 0.2
func _life(delta: float) -> void:
    _next_ember -= delta
    var flames: int = torches.size() - (1 if lantern_last else 0)
    if _next_ember <= 0.0 and flames > 0:
        _next_ember = randf_range(0.12, 0.3)
        var tc: Array = torches[randi() % flames]
        var c: Vector2 = tc[0]
        var sz: Vector2 = tc[1]
        _embers.append({"p": c + Vector2(randf_range(-0.2, 0.2) * sz.x, -sz.y * 0.35), "v": Vector2(randf_range(-4.0, 4.0), -randf_range(14.0, 24.0) * sz.y / 50.0),
            "age": 0.0, "life": randf_range(0.8, 1.5), "r": randf_range(0.7, 1.2) * clampf(sz.x / 30.0, 0.6, 1.4), "ph": randf() * TAU})
    _next_mist -= delta
    if _next_mist <= 0.0 and not mists.is_empty():
        _next_mist = randf_range(0.35, 0.7)
        var mp: Array = mists[randi() % mists.size()]
        _mist.append({"p": mp[0] + Vector2(randf_range(-0.5, 0.5) * mp[1], randf_range(-2.0, 2.0)), "v": Vector2(randf_range(-3.0, 3.0), -randf_range(5.0, 9.0)),
            "age": 0.0, "life": randf_range(2.6, 3.8), "r": randf_range(0.18, 0.3) * mp[1]})
    var shown := 0
    for e in _embers:
        e.age += delta
        e.p += (e.v + Vector2(sin(t * 3.0 + e.ph) * 5.0, 0.0)) * delta
        if e.age >= e.life or shown >= EMBER_POOL: continue
        var k: float = e.age / e.life
        var d = _ember_discs[shown]
        shown += 1
        d.position = e.p
        d.scale = Vector2.ONE * e.r * 2.2 * (1.0 - 0.5 * k) / 16.0
        d.modulate.a = 0.85 * sin(PI * minf(1.0, k * 1.6 + 0.08)) * (1.0 - k)
    for i in range(shown, EMBER_POOL): _ember_discs[i].modulate.a = 0.0
    _embers = _embers.filter(func(e): return e.age < e.life)
    shown = 0
    for m in _mist:
        m.age += delta
        m.p += m.v * delta
        if m.age >= m.life or shown >= MIST_POOL: continue
        var k: float = m.age / m.life
        var d = _mist_discs[shown]
        shown += 1
        d.position = m.p
        d.scale = Vector2.ONE * m.r * (0.8 + 0.9 * k) / 16.0
        d.modulate.a = 0.22 * sin(PI * k)
    for i in range(shown, MIST_POOL): _mist_discs[i].modulate.a = 0.0
    _mist = _mist.filter(func(m): return m.age < m.life)

func _update_puffs():
    var shown := 0
    for pf in _puffs:
        if pf.age <= 0.0 or shown >= PUFF_POOL: continue
        var k: float = pf.age / pf.life
        var d = _puff_discs[shown]
        shown += 1
        d.position = pf.p
        # R52f · raio r0 + 10k = escala do disco de raio 1 (mesma geometria; nunca redesenha, mesmo trocando de fumaça)
        d.scale = Vector2.ONE * (pf.r0 + 10.0 * k)
        d.modulate.a = 0.26 * sin(PI * minf(1.0, k * 1.15)) * (1.0 - k)
    for i in range(shown, PUFF_POOL):
        _puff_discs[i].modulate.a = 0.0

func _draw():
    # (fumacinha: discos em _puff_discs, animados em _update_puffs)
    for b in _birds:
        if b.x < sky.position.x or b.x > sky.end.x: continue
        var flap := sin(t * 7.0 + b.ph)
        var c := Vector2(b.x, b.y + sin(t * 2.0 + b.ph) * 2.0)
        var w: float = 7.0 * b.s
        var tip := Vector2(w, -3.5 * flap * b.s - 0.5)
        var col := Color(0.09, 0.06, 0.12, 0.7)
        # mesmo traço de antes, em segmentos (draw_polyline vira polígono com buffers novos a cada quadro)
        var pts := [c + Vector2(-tip.x, tip.y), c + Vector2(-w * 0.35, -0.6), c, c + Vector2(w * 0.35, -0.6), c + tip]
        for j in 4: draw_line(pts[j], pts[j + 1], col, 1.8)
