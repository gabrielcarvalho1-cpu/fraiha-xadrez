extends RefCounted
## Pele da tela de conta: componentes recortados da arte de referência (account/art/*.png).
## Coordenadas em "pixels da referência" (1122 x 1402); account_ui escala o painel inteiro.
## Cada componente pode ser `baked` (a arte completa já traz o fundo: só desenha texto/ícone
## e recebe o clique) ou desenhar o próprio recorte (páginas secundárias).
const Art := preload("res://account/login_art.gd")
const TEX_FIELD := preload("res://account/art/field.png")
const TEX_BUTTON := preload("res://account/art/button_primary.png")
const TEX_GOOGLE := preload("res://account/art/button_google.png")
const TEX_DIVIDER := preload("res://account/art/divider.png")
const TEX_ROW := preload("res://account/art/link_row.png")
const GOLD := Color("f3d58c")
const GOLD_DEEP := Color("8a5a16")
const CREAM := Color("f2e6c6")
const PLACEHOLDER := Color("b9ad8e")

# ---------------------------------------------------------------- campo
class Field extends Control:
    var line: LineEdit
    var eye: Button
    var icon_kind := ""
    var baked := false
    var secret := false
    const LEFT := 134.0      # início do texto (coords do recorte 738 x 120)
    const RIGHT := 60.0
    func _init():
        custom_minimum_size = Vector2(738, 120)
        mouse_filter = Control.MOUSE_FILTER_PASS
    func setup(kind: String, p_secret: bool):
        icon_kind = kind
        secret = p_secret
        line = LineEdit.new()
        line.secret = secret
        line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        line.offset_left = LEFT
        line.offset_right = -RIGHT - (60.0 if secret else 0.0)
        line.offset_top = 22
        line.offset_bottom = -22
        var flat := StyleBoxEmpty.new()
        for s in ["normal", "focus", "read_only"]: line.add_theme_stylebox_override(s, flat)
        line.add_theme_font_size_override("font_size", 32)
        line.add_theme_font_override("font", preload("res://account/fonts/Cinzel-SemiBold.woff"))
        line.add_theme_color_override("font_color", CREAM)
        line.add_theme_color_override("font_placeholder_color", PLACEHOLDER)
        line.add_theme_color_override("caret_color", GOLD)
        line.add_theme_color_override("selection_color", Color(0.79, 0.6, 0.27, 0.35))
        line.focus_entered.connect(queue_redraw)
        line.focus_exited.connect(queue_redraw)
        add_child(line)
        if secret:
            eye = Button.new()
            eye.name = "ShowPassword"
            eye.tooltip_text = "Mostrar senha"
            eye.focus_mode = Control.FOCUS_NONE
            eye.flat = true
            eye.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
            eye.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
            eye.position = Vector2(738 - 60 - 56, 24)
            eye.size = Vector2(72, 72)
            eye.draw.connect(func(): Art.icon(eye, "eye" if line.secret else "eye_off", Rect2(Vector2(10, 10), Vector2(52, 52)), Color("e6dcc0")))
            eye.pressed.connect(func():
                line.secret = not line.secret
                eye.tooltip_text = "Mostrar senha" if line.secret else "Ocultar senha"
                eye.queue_redraw())
            add_child(eye)
    func _draw():
        if not baked: draw_style_box(LoginSkinRef.nine_field(), Rect2(Vector2.ZERO, size))
        if not baked or icon_kind != "":
            if not baked: Art.icon(self, icon_kind, Rect2(Vector2(50, 32), Vector2(56, 56)), GOLD)
        if line != null and line.has_focus():
            draw_rect(Rect2(Vector2(40, 18), Vector2(size.x - 80, size.y - 36)), Color(1.0, 0.86, 0.45, 0.07))
            draw_rect(Rect2(Vector2(14, 8), Vector2(size.x - 28, size.y - 16)), Color(1.0, 0.86, 0.45, 0.35), false, 2.0)

# ---------------------------------------------------------------- botão
class SkinButton extends Button:
    var primary := true
    var baked := false
    var icon_kind := ""
    var font_size := 64
    func _init():
        focus_mode = Control.FOCUS_NONE
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
        for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color", "font_outline_color", "icon_normal_color"]:
            add_theme_color_override(c, Color(0, 0, 0, 0))
        add_theme_constant_override("outline_size", 0)
    func _notification(what):
        if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT]: queue_redraw()
    func _draw():
        var lit := is_hovered() and not disabled
        var down := button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
        var r := Rect2(Vector2.ZERO, size)
        if not baked:
            draw_style_box(LoginSkinRef.nine_button() if primary else LoginSkinRef.nine_google(), r)
            var f: Font = Art.FONT_BOLD
            var fs := font_size
            var icon_w := size.y * 0.5 if icon_kind != "" else 0.0
            var gap := 22.0 if icon_w > 0.0 else 0.0
            while fs > 14 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 260.0 - icon_w - gap: fs -= 1
            var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
            var x0 := (size.x - tw - icon_w - gap) / 2.0
            if icon_w > 0.0:
                var ib := Rect2(Vector2(x0, (size.y - icon_w) / 2.0), Vector2(icon_w, icon_w))
                draw_circle(ib.get_center(), icon_w * 0.52, Color(1, 1, 1, 0.97))
                Art.icon(self, icon_kind, ib.grow(-icon_w * 0.14), Color.WHITE)
            var base := Vector2(x0 + icon_w + gap, size.y / 2.0 + f.get_ascent(fs) * 0.36)
            LoginSkinRef.gold_text(self, f, base, text, fs, lit)
        # realce ao passar o mouse / pressionar, por cima da arte (recortada ou já na pintura)
        var inset := Rect2(Vector2(56, 14), Vector2(size.x - 112, size.y - 28)) if primary else Rect2(Vector2(50, 10), Vector2(size.x - 100, size.y - 20))
        if down: draw_rect(inset, Color(0, 0, 0, 0.22))
        elif lit: draw_rect(inset, Color(1.0, 0.92, 0.6, 0.10))
        if disabled: draw_rect(r, Color(0.02, 0.05, 0.03, 0.45))

# ---------------------------------------------------------------- link (linha com ícone, texto e seta)
class SkinLink extends Button:
    var icon_kind := ""
    var baked := false
    func _init():
        focus_mode = Control.FOCUS_NONE
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        custom_minimum_size = Vector2(550, 72)
        for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
        for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color", "font_outline_color"]:
            add_theme_color_override(c, Color(0, 0, 0, 0))
        add_theme_constant_override("outline_size", 0)
    func _notification(what):
        if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT]: queue_redraw()
    func _draw():
        var lit := is_hovered()
        if not baked: draw_style_box(LoginSkinRef.nine_row(), Rect2(Vector2.ZERO, size))
        var ic := Rect2(Vector2(50, 6), Vector2(46, 46))
        var col := Color("ffe9b0") if lit else GOLD
        match icon_kind:
            "": pass
            "person": LoginSkinRef.person_icon(self, ic, col)
            _: Art.icon(self, icon_kind, ic, col)
        var f: Font = Art.FONT_SEMI
        var fs := 37
        while fs > 16 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 130.0 - 60.0: fs -= 1
        var base := Vector2(125, 31 + f.get_ascent(fs) * 0.36)
        draw_string(f, base + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
        draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("fff0c8") if lit else CREAM)
        if lit: draw_rect(Rect2(Vector2(30, 0), Vector2(size.x - 40, 56)), Color(1.0, 0.9, 0.6, 0.06))

# ---------------------------------------------------------------- divisor
class Divider extends Control:
    func _init():
        custom_minimum_size = Vector2(678, 42)
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _draw():
        var tw := float(TEX_DIVIDER.get_width())
        var th := float(TEX_DIVIDER.get_height())
        var k := minf(size.x / tw, 1.0)
        draw_texture_rect(TEX_DIVIDER, Rect2(Vector2((size.x - tw * k) / 2.0, (size.y - th * k) / 2.0), Vector2(tw * k, th * k)), false)

# referência estática às styleboxes (criadas uma vez)
class LoginSkinRef:
    static var _f: StyleBoxTexture
    static var _b: StyleBoxTexture
    static var _g: StyleBoxTexture
    static var _r: StyleBoxTexture
    static func nine_field() -> StyleBoxTexture:
        if _f == null: _f = nine(TEX_FIELD, 80, 20)
        return _f
    static func nine_button() -> StyleBoxTexture:
        if _b == null: _b = nine(TEX_BUTTON, 110, 24)
        return _b
    static func nine_google() -> StyleBoxTexture:
        if _g == null: _g = nine(TEX_GOOGLE, 90, 20)
        return _g
    static func nine_row() -> StyleBoxTexture:
        if _r == null: _r = nine(TEX_ROW, 60, 10)
        return _r
    static func nine(tex: Texture2D, mx: float, my: float) -> StyleBoxTexture:
        var sb := StyleBoxTexture.new()
        sb.texture = tex
        sb.texture_margin_left = mx
        sb.texture_margin_right = mx
        sb.texture_margin_top = my
        sb.texture_margin_bottom = my
        return sb
    static func gold_text(ci: CanvasItem, font: Font, pos: Vector2, text: String, fs: int, lit := false):
        ci.draw_string(font, pos + Vector2(0, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.55))
        ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.22, 0.12, 0.02, 0.9))
        ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffe9b0") if lit else Color("f3d58c"))
        ci.draw_string(font, pos - Vector2(0, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.97, 0.85, 0.35))
    static func person_icon(ci: CanvasItem, r: Rect2, c: Color):
        var s := minf(r.size.x, r.size.y)
        var o := r.get_center()
        ci.draw_circle(o + Vector2(0, -s * 0.2), s * 0.19, c)
        ci.draw_colored_polygon(Art._shoulders(o + Vector2(0, s * 0.36), s * 0.38, s * 0.3), c)
