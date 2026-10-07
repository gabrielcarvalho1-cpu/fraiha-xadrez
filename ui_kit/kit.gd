extends RefCounted
## R51 · Kit visual tirado das imagens de referência do dono (ui_kit/art/*.png, gerado por tools/ui_kit_build.py).
## Molduras 9-slice (cantos e bordas originais da arte) para botões, caixas e campos; ícones recortados.
const FONT_BOLD := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")
## Alegreya (OFL). Os algarismos alinhados (lnum) já estão embutidos no arquivo (o padrão dela é o estilo antigo).
const SERIF_BOLD := preload("res://ui_kit/fonts/Alegreya-Bold.woff")      # nomes, títulos de seção, botões
const SERIF := preload("res://ui_kit/fonts/Alegreya-Medium.woff")          # textos corridos
const GOLD := Color("f2c66d")
const CREAM := Color("f1e6c8")
const DIM := Color("9aa39a")
const GREEN := Color("6fd36f")

## [arquivo, margem esquerda, direita, cima, baixo] em px da arte (fonte do 9-slice).
const FRAMES := {
    "btn_verde": ["btn_verde", 40, 40, 30, 30],
    "btn_azul": ["btn_azul", 34, 40, 30, 30],
    "btn_vermelho": ["btn_vermelho", 28, 44, 28, 28],
    "caixa_linha": ["caixa_linha", 18, 18, 20, 20],
    "caixa_vazia": ["caixa_vazia", 56, 56, 30, 30],
    "campo": ["campo", 26, 26, 30, 30],
    "painel_amigos": ["painel_amigos", 90, 230, 178, 75],
}
static var _cache := {}

static func tex(name: String) -> Texture2D:
    if not _cache.has(name):
        var path := "res://ui_kit/art/%s.png" % name
        _cache[name] = load(path) if ResourceLoader.exists(path) else null
    return _cache[name]

## StyleBox 9-slice da arte. `k` = escala da arte na tela (bordas ficam proporcionais); pad = margem do conteúdo.
static func box(kind: String, k := 0.5, pad := Vector2(-1, -1), modulate := Color.WHITE) -> StyleBox:
    var f: Array = FRAMES[kind]
    var t := tex(f[0])
    if t == null: return StyleBoxEmpty.new()
    var s := StyleBoxTexture.new()
    s.texture = t
    s.texture_margin_left = f[1]; s.texture_margin_right = f[2]
    s.texture_margin_top = f[3]; s.texture_margin_bottom = f[4]
    # a arte é desenhada em escala k: as margens na tela ficam k vezes menores
    s.expand_margin_left = 0
    s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
    s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
    s.modulate_color = modulate
    var px := pad if pad.x >= 0 else Vector2(f[1] * k + 6, f[3] * k * 0.5)
    s.content_margin_left = px.x; s.content_margin_right = px.x
    s.content_margin_top = px.y; s.content_margin_bottom = px.y
    return _scaled(s, k)

## StyleBoxTexture não tem escala própria: usamos uma cópia da textura reduzida (nearest, arte pixel) quando k < 1.
static func _scaled(s: StyleBoxTexture, k: float) -> StyleBoxTexture:
    if is_equal_approx(k, 1.0): return s
    var key := "%s@%.3f" % [s.texture.resource_path, k]
    if not _cache.has(key):
        var img: Image = s.texture.get_image()
        img.resize(maxi(1, int(round(img.get_width() * k))), maxi(1, int(round(img.get_height() * k))), Image.INTERPOLATE_LANCZOS)
        _cache[key] = ImageTexture.create_from_image(img)
    var o: StyleBoxTexture = s.duplicate()
    o.texture = _cache[key]
    o.texture_margin_left = round(s.texture_margin_left * k); o.texture_margin_right = round(s.texture_margin_right * k)
    o.texture_margin_top = round(s.texture_margin_top * k); o.texture_margin_bottom = round(s.texture_margin_bottom * k)
    return o

## Botão no estilo da referência: moldura da arte + texto Cinzel + ícone opcional à esquerda.
static func button(b: Button, kind: String, k: float, font_px: int, icon_name := "") -> void:
    var normal := box(kind, k)
    b.add_theme_stylebox_override("normal", normal)
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    var hover := box(kind, k, Vector2(-1, -1), Color(1.18, 1.14, 1.05))
    b.add_theme_stylebox_override("hover", hover)
    b.add_theme_stylebox_override("pressed", box(kind, k, Vector2(-1, -1), Color(0.88, 0.88, 0.88)))
    b.add_theme_stylebox_override("disabled", box(kind, k, Vector2(-1, -1), Color(0.55, 0.55, 0.55)))
    b.add_theme_font_override("font", SERIF_BOLD)
    b.add_theme_font_size_override("font_size", font_px)
    for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        b.add_theme_color_override(c, CREAM)
    b.add_theme_color_override("font_disabled_color", Color("8b8b80"))
    b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
    b.add_theme_constant_override("outline_size", 3)
    if not icon_name.is_empty() and tex(icon_name) != null:
        b.icon = tex(icon_name)
        b.expand_icon = false
        b.add_theme_constant_override("icon_max_width", int(round(font_px * 1.7)))
        b.add_theme_constant_override("h_separation", int(round(font_px * 0.6)))

static func label(l: Label, px: int, color := CREAM, bold := true) -> void:
    l.add_theme_font_override("font", SERIF_BOLD if bold else SERIF)
    l.add_theme_font_size_override("font_size", px)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
    l.add_theme_constant_override("outline_size", 2)

## Ícone pequeno (TextureRect) do kit, no tamanho px de altura.
static func icon(name: String, px: float) -> TextureRect:
    var t := TextureRect.new()
    t.texture = tex(name)
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    var ts: Vector2 = t.texture.get_size() if t.texture != null else Vector2.ONE
    t.custom_minimum_size = Vector2(px * ts.x / ts.y, px)
    t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    t.mouse_filter = Control.MOUSE_FILTER_IGNORE
    t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    return t

## Placa/fita com cantos fixos e miolo esticado (NinePatchRect), para títulos com largura própria.
static func plate(name: String, w: float, h: float, side: int) -> NinePatchRect:
    var n := NinePatchRect.new()
    var t := tex(name)
    var k := h / t.get_size().y
    var key := "%s@h%.1f" % [name, h]
    if not _cache.has(key):
        var img: Image = t.get_image()
        img.resize(maxi(1, int(round(img.get_width() * k))), int(round(h)), Image.INTERPOLATE_LANCZOS)
        _cache[key] = ImageTexture.create_from_image(img)
    n.texture = _cache[key]
    side = int(round(side * k))
    n.patch_margin_left = side; n.patch_margin_right = side
    n.patch_margin_top = 0; n.patch_margin_bottom = 0
    n.custom_minimum_size = Vector2(w, h)
    n.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    n.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return n
