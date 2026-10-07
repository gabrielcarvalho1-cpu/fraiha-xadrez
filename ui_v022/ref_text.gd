extends Control
## R47 · texto VIVO por cima da arte de referência, no mesmo lugar e na mesma medida do texto que foi
## apagado da arte (tools/home_ref_v8.py). A caixa da referência é (x, y do topo das letras, largura da
## tinta); o tamanho da fonte sai da LARGURA medida na referência, sem passar da altura de letra dada.
## Desenha com a fonte do jogo (nítida em qualquer escala) — nada de texto rasterizado na arte.
const CAP := {"default": 0.715, "oswald": 0.80, "squeeze": 0.715}   # altura das maiúsculas / tamanho da fonte (medido)
const DROP := {"default": 0.0, "oswald": 2.0, "squeeze": 0.0}     # ajuste fino da linha de base (medido nas capturas)
const OSWALD := preload("res://marcha/art/fonts/oswald-latin-600-normal.woff")

var text := ""
var font_kind := "default"
var target_width := 0.0      # largura da tinta na referência (px da arte)
var cap_height := 0.0        # altura das maiúsculas na referência (teto do tamanho)
var color := Color("f4edda")
var outline := Color(0.03, 0.02, 0.0, 0.85)
var outline_size := 3
var align_center := false
var bold := 0                # traço extra da própria cor (letra mais encorpada, como na referência)
var _size := 16
var _sx := 1.0               # "squeeze": a fonte do jogo na altura da referência, estreitada até a largura dela

static func make(t: String, rect: Rect2, kind := "default", col := Color("f4edda"), center := false) -> Control:
    var c = load("res://ui_v022/ref_text.gd").new()
    c.name = "RefText"
    c.text = t
    c.font_kind = kind
    c.color = col
    c.align_center = center
    c.target_width = rect.size.x
    c.cap_height = rect.size.y
    c.position = rect.position
    c.size = rect.size
    c.mouse_filter = Control.MOUSE_FILTER_IGNORE
    c.fit()
    return c

func the_font() -> Font:
    return OSWALD if font_kind == "oswald" else get_theme_default_font()

func ink_width() -> float:
    var f := the_font()
    return 0.0 if f == null else f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x * _sx

func set_text(t: String):
    text = t
    fit()

func fit():
    var f := the_font()
    if f == null: return
    var s := 40
    var cap_max := int(floor(cap_height / CAP[font_kind])) if cap_height > 0.0 else 64
    s = mini(s, maxi(cap_max, 8))
    _sx = 1.0
    if font_kind == "squeeze":
        var w0 := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
        if w0 > 0.0 and target_width > 0.0: _sx = clampf((target_width * 1.03 + 2.0) / w0, 0.55, 1.0)
    else:
        while s > 8 and target_width > 0.0 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > target_width * 1.03 + 2.0:   # avanço ≈ tinta + respiros
            s -= 1
    _size = s
    queue_redraw()

func font_size() -> int:
    return _size

func _draw():
    var f := the_font()
    if f == null or text.is_empty(): return
    var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size).x * _sx
    var x := (size.x - w) / 2.0 if align_center else 0.0
    if _sx < 1.0: draw_set_transform(Vector2(x, 0), 0.0, Vector2(_sx, 1.0))
    var base := Vector2(0.0 if _sx < 1.0 else x, CAP[font_kind] * _size + DROP[font_kind])   # topo das maiúsculas em y = 0
    if outline_size > 0:
        draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, outline_size, outline)
    draw_string(f, base + Vector2(0, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, Color(0, 0, 0, 0.55))
    if bold > 0:
        draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, bold, color)
    draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, color)
