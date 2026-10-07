extends RefCounted
## R51 · Páginas do PC no visual das imagens de referência do dono.
## A referência limpa (ui_kit/pages/<id>_bg.png, gerada por tools/ref_pages_build.py) é o fundo da página;
## o jogo desenha por cima, nas posições medidas na referência, só o que é vivo (nomes, estado, números, botões).
const Kit = preload("res://ui_kit/kit.gd")
const CREAM := Color("f1e6c8")
const GOLD := Color("f5cf72")
const MUTED := Color("a9a594")
const GREEN := Color("7fe08a")

static func tex(name: String) -> Texture2D:
    var p := "res://ui_kit/pages/%s.png" % name
    return load(p) if ResourceLoader.exists(p) else null

## Página na arte da referência (1672 x 941) — R51b: só a moldura e o miolo (fora dela a arte é transparente
## e a Home aparece em volta). Reduzida em `k` e centrada dentro da área segura do canvas, para nada ser
## cortado quando a janela não é 16:9; uma camada invisível atrás segura os cliques da tela toda.
## dim > 0: a Home atrás fica escurecida (a camada passa das bordas do canvas, para a janela inteira escurecer igual).
static func full_page(canvas: Control, bg_name: String, size: Vector2, k := 0.92, dim := 0.0) -> Control:
    var page := Control.new()
    page.size = size
    page.scale = Vector2.ONE * k
    page.position = (size - size * k) / 2.0
    page.mouse_filter = Control.MOUSE_FILTER_STOP
    canvas.add_child(page)
    var block := ColorRect.new()
    block.name = "ClickBlock"
    block.color = Color(0.02, 0.03, 0.02, dim)
    block.position = -page.position / k - size * 2.0 / k
    block.size = size * 5.0 / k
    block.mouse_filter = Control.MOUSE_FILTER_STOP
    page.add_child(block)
    var bg := TextureRect.new()
    bg.name = "RefBg"
    bg.texture = tex(bg_name)
    bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    bg.stretch_mode = TextureRect.STRETCH_SCALE
    bg.size = size
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    page.add_child(bg)
    return page

## R52 · Painel/modal próprio (padrão aprovado nas Ligas): a página fica nas coordenadas da referência
## (ref_size, fundo transparente fora da moldura), reduzida para caber em `frac` da tela e centralizada;
## atrás, uma camada escurece a Home inteira e segura os cliques. show_page faz o fade de entrada.
static func modal(canvas: Control, bg_name: String, ref_size: Vector2, design: Vector2, dim := 0.72, frac := 0.92) -> Control:
    var k := minf(design.x * frac / ref_size.x, design.y * frac / ref_size.y)
    var page := Control.new()
    page.size = ref_size
    page.scale = Vector2.ONE * k
    page.position = ((design - ref_size * k) / 2.0).round()
    page.mouse_filter = Control.MOUSE_FILTER_STOP
    page.set_meta("ref_full", true)
    page.set_meta("modal", true)
    canvas.add_child(page)
    var block := ColorRect.new()
    block.name = "ClickBlock"
    block.color = Color(0.02, 0.03, 0.02, dim)
    block.position = -page.position / k - design * 2.0 / k
    block.size = design * 5.0 / k
    block.mouse_filter = Control.MOUSE_FILTER_STOP
    page.add_child(block)
    var bg := TextureRect.new()
    bg.name = "RefBg"
    bg.texture = tex(bg_name)
    bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    bg.stretch_mode = TextureRect.STRETCH_SCALE
    bg.size = ref_size
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    page.add_child(bg)
    return page

## Texto centralizado (ou alinhado) numa caixa; serif = Alegreya (títulos), senão a fonte padrão (textos).
static func text(parent: Control, t: String, rect: Rect2, px: int, color: Color, serif := false, align := HORIZONTAL_ALIGNMENT_CENTER, bold := true) -> Label:
    var l := Label.new()
    l.text = t
    l.position = rect.position
    l.size = rect.size
    l.horizontal_alignment = align
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.clip_text = true
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if serif: l.add_theme_font_override("font", Kit.SERIF_BOLD if bold else Kit.SERIF)
    l.add_theme_font_size_override("font_size", px)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
    l.add_theme_constant_override("outline_size", 3)
    parent.add_child(l)
    return l

## Imagem (ícone/brasão) na caixa, mantendo a proporção.
static func image(parent: Control, t: Texture2D, rect: Rect2, linear := true) -> TextureRect:
    var r := TextureRect.new()
    r.texture = t
    r.position = rect.position
    r.size = rect.size
    r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if linear: r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    parent.add_child(r)
    return r

## Botão com a arte recortada da referência (cantos fixos, miolo esticado) + texto; clique de verdade por cima.
static func art_button(parent: Control, art: String, label: String, rect: Rect2, px: int, color: Color, action: Callable, side := 26) -> Button:
    var n := NinePatchRect.new()
    n.texture = tex(art)
    n.patch_margin_left = side; n.patch_margin_right = side
    n.patch_margin_top = 12; n.patch_margin_bottom = 12
    n.position = rect.position
    n.size = rect.size
    n.mouse_filter = Control.MOUSE_FILTER_IGNORE
    n.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    parent.add_child(n)
    var b := Button.new()
    b.text = label
    b.position = rect.position
    b.size = rect.size
    b.focus_mode = Control.FOCUS_NONE
    var empty := StyleBoxEmpty.new()
    var lit := StyleBoxFlat.new()
    lit.bg_color = Color(1.0, 0.86, 0.45, 0.10)
    lit.set_corner_radius_all(4)
    for st in ["normal", "focus", "disabled"]: b.add_theme_stylebox_override(st, empty)
    for st in ["hover", "pressed"]: b.add_theme_stylebox_override(st, lit)
    b.add_theme_font_override("font", Kit.SERIF_BOLD)
    b.add_theme_font_size_override("font_size", px)
    for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
        b.add_theme_color_override(c, color)
    b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
    b.add_theme_constant_override("outline_size", 3)
    if action.is_valid(): b.pressed.connect(action)
    parent.add_child(b)
    b.set_meta("art", n)
    return b

## Área clicável invisível (botões que já estão desenhados na arte, ex.: VOLTAR À HOME).
static func hotspot(parent: Control, rect: Rect2, action: Callable, name := "") -> Button:
    var b := Button.new()
    if not name.is_empty(): b.name = name
    b.position = rect.position
    b.size = rect.size
    b.focus_mode = Control.FOCUS_NONE
    b.flat = true
    var lit := StyleBoxFlat.new()
    lit.bg_color = Color(1.0, 0.86, 0.45, 0.08)
    lit.set_corner_radius_all(6)
    for st in ["normal", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
    for st in ["hover", "pressed"]: b.add_theme_stylebox_override(st, lit)
    b.pressed.connect(action)
    parent.add_child(b)
    return b

## Linha "ícone + TEXTO" centralizada (estado dos cartões: ✓ DERROTADO, cadeado BLOQUEADO...).
static func icon_text(parent: Control, icon: Texture2D, t: String, center: Vector2, px: int, color: Color, icon_h: float) -> void:
    var font: Font = Kit.SERIF_BOLD
    var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
    var iw := 0.0
    if icon != null: iw = icon_h * icon.get_size().x / icon.get_size().y + 8.0
    var x := center.x - (tw + iw) / 2.0
    if icon != null: image(parent, icon, Rect2(x, center.y - icon_h / 2.0, iw - 8.0, icon_h))
    text(parent, t, Rect2(x + iw, center.y - px, tw + 8.0, px * 2.0), px, color, true, HORIZONTAL_ALIGNMENT_LEFT)
