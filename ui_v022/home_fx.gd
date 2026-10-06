extends Control
## R44 · Animações da Home (arte oficial v7): tochas e lanterna tremulando, água da cachoeira e do rio
## correndo, passarinhos atravessando o céu e a barriguinha da gatinha YUMI subindo e descendo
## (só a barriga: cabeça, orelhas, patas e contorno ficam parados).
## Tudo em coordenadas do canvas 1672 x 941, por cima da arte e por baixo dos painéis/botões.
## Só recortes da PRÓPRIA arte animados por shader (nada redesenhado) + luz aditiva discreta.
const FOREST := preload("res://ui_v022/assets/home_forest_v7.png")

## [centro da chama, tamanho do recorte, raio da luz]
const TORCHES := [
    [Vector2(590, 532), Vector2(36, 52), 48.0],     # pilar esquerdo do menu (R44: moldura nova)
    [Vector2(1052, 532), Vector2(36, 52), 48.0],    # pilar direito do menu (R44: moldura nova)
    [Vector2(1266, 494), Vector2(24, 34), 34.0],    # tocha da ponte
    [Vector2(1471, 490), Vector2(24, 34), 34.0],    # tocha da direita
    [Vector2(392, 327), Vector2(52, 50), 40.0],     # lanterna da árvore
]
const WATER_RECT := Rect2(1150, 400, 312, 420)
const BELLY_RECT := Rect2(40, 704, 150, 92)        # corpo da gatinha (a barriga fica no meio)
const BELLY_C := Vector2(108, 748)                 # centro da barriga
const BELLY_R := Vector2(52, 30)                   # raio da área que respira (dentro do contorno)
const SKY := Rect2(1185, 228, 440, 92)            # céu visível entre a placa do perfil e as montanhas

const FLAME_SHADER := """
shader_type canvas_item;
uniform float seed = 0.0;
float fm(vec4 c) { return smoothstep(0.55, 0.85, max(c.r, c.g)) * step(c.b, c.r + 0.05); }
void fragment() {
    vec4 o = texture(TEXTURE, UV);
    float k = 1.0 - UV.y;
    float sway = sin(TIME * 6.0 + seed) * 0.07 + sin(TIME * 13.0 + seed * 2.3) * 0.035;
    float st = 1.0 + 0.16 * sin(TIME * 8.0 + seed) + 0.07 * sin(TIME * 17.0 + seed * 1.7);
    vec2 suv = vec2(UV.x - sway * k * k, 1.0 - (1.0 - UV.y) / st);
    vec4 s = texture(TEXTURE, suv);
    float m = max(fm(o), fm(s));
    vec4 c = mix(o, s, m);
    c.rgb *= 1.0 + m * (0.18 * sin(TIME * 11.0 + seed) + 0.08 * sin(TIME * 23.0 + seed));
    COLOR = vec4(c.rgb, m);
}
"""

const WATER_SHADER := """
shader_type canvas_item;
float wm(vec3 c) { return smoothstep(0.06, 0.22, c.b - c.r) * smoothstep(0.32, 0.6, c.b); }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
    vec4 o = texture(TEXTURE, UV);
    float m = wm(o.rgb);
    vec2 d = vec2(sin(UV.y * 140.0 + TIME * 5.0) * 0.004, 0.0);
    vec4 c = texture(TEXTURE, UV + d * m);
    float m2 = m * wm(c.rgb);
    vec3 col = mix(o.rgb, c.rgb, m2);
    float streak = smoothstep(0.62, 0.92, n(vec2(UV.x * 70.0, UV.y * 9.0 - TIME * 2.4)));
    col += vec3(0.55, 0.85, 1.0) * streak * m * 0.55;
    float tw = step(0.992, h(floor(UV * vec2(156.0, 210.0)) + floor(TIME * 5.0)));
    col += vec3(0.8, 0.95, 1.0) * tw * m * 0.6;
    COLOR = vec4(col, m);
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
var _add := CanvasItemMaterial.new()
var _glow_tex: GradientTexture2D

func _init():
    name = "HomeFx"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size = Vector2(1672, 941)

func _ready():
    _src = FOREST.get_image()
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
    # água
    _piece(WATER_RECT, WATER_SHADER)
    # tochas: luz por baixo (aditiva) + chama recortada da arte balançando
    for i in TORCHES.size():
        var c: Vector2 = TORCHES[i][0]
        var sz: Vector2 = TORCHES[i][1]
        var glow := TextureRect.new()
        glow.texture = _glow_tex
        glow.material = _add
        glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
        glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        var r: float = TORCHES[i][2]
        glow.size = Vector2(r, r) * 2.0
        glow.position = c - Vector2(r, r)
        add_child(glow)
        _glows.append([glow, randf() * TAU])
        var m := _piece(Rect2(c - Vector2(sz.x / 2.0, sz.y * 0.62), sz), FLAME_SHADER)
        m.set_shader_parameter("seed", float(i) * 1.7)
    # barriguinha da gatinha
    _cat_mat = _piece(BELLY_RECT, CAT_SHADER)
    _cat_mat.set_shader_parameter("c", (BELLY_C - BELLY_RECT.position) / BELLY_RECT.size)
    _cat_mat.set_shader_parameter("r", BELLY_R / BELLY_RECT.size)

func _piece(r: Rect2, code: String) -> ShaderMaterial:
    var rr := Rect2i(r)
    var tr := TextureRect.new()
    tr.texture = ImageTexture.create_from_image(_src.get_region(rr))
    tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    tr.stretch_mode = TextureRect.STRETCH_SCALE
    tr.position = Vector2(rr.position)
    tr.size = Vector2(rr.size)
    tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
    tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    var sh := Shader.new()
    sh.code = code
    var mat := ShaderMaterial.new()
    mat.shader = sh
    tr.material = mat
    add_child(tr)
    return mat

func _process(delta):
    if not is_visible_in_tree(): return
    t += delta
    for gl in _glows:
        var s: float = gl[1]
        gl[0].modulate.a = 0.60 + 0.30 * sin(t * 8.0 + s) + 0.14 * sin(t * 19.0 + s * 2.0) + randf_range(-0.08, 0.08)
    # barriga sobe e desce devagar (gato dormindo, ~3,5 s por ciclo)
    _cat_mat.set_shader_parameter("breath", 0.5 + 0.5 * sin(t * 1.8))
    # passarinhos
    _next_flock -= delta
    if _next_flock <= 0.0:
        _next_flock = randf_range(6.0, 11.0)
        var dir := 1.0 if randf() < 0.5 else -1.0
        var y0 := randf_range(SKY.position.y + 14.0, SKY.end.y - 24.0)
        var speed := randf_range(38.0, 55.0)
        for k in randi_range(2, 5):
            _birds.append({"x": (SKY.position.x - 20.0 - k * 16.0) if dir > 0.0 else (SKY.end.x + 20.0 + k * 16.0),
                "y": y0 + randf_range(-10.0, 10.0) + k * 3.0, "dir": dir, "v": speed * randf_range(0.92, 1.08),
                "ph": randf() * TAU, "s": randf_range(0.8, 1.15)})
    for b in _birds:
        b.x += b.dir * b.v * delta
    _birds = _birds.filter(func(b): return b.x > SKY.position.x - 120.0 and b.x < SKY.end.x + 120.0)
    queue_redraw()

func _draw():
    for b in _birds:
        if b.x < SKY.position.x or b.x > SKY.end.x: continue
        var flap := sin(t * 11.0 + b.ph)
        var c := Vector2(b.x, b.y + sin(t * 2.0 + b.ph) * 2.0)
        var w: float = 7.0 * b.s
        var tip := Vector2(w, -3.5 * flap * b.s - 0.5)
        var col := Color(0.09, 0.06, 0.12, 0.85)
        draw_polyline(PackedVector2Array([c + Vector2(-tip.x, tip.y), c + Vector2(-w * 0.35, -0.6), c, c + Vector2(w * 0.35, -0.6), c + tip]), col, 1.8)
