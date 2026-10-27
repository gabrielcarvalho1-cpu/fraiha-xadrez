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
    ## O painel de login é desenhado em escala (arte de 738 px ocupa ~430 px na tela). Fonte comum é
    ## rasterizada no tamanho nominal e reduzida sem mipmaps: traços finos somem ("SENHA" → "SLNIIA").
    ## Cópia em MSDF (campo de distância) fica nítida em qualquer escala. Não altera o .import.
    static var _msdf: FontFile
    static func field_font() -> FontFile:
        if _msdf == null:
            _msdf = (preload("res://account/fonts/Cinzel-SemiBold.woff") as FontFile).duplicate()
            _msdf.multichannel_signed_distance_field = true
            _msdf.msdf_pixel_range = 8
            _msdf.msdf_size = 48
        return _msdf
    func _init():
        custom_minimum_size = Vector2(738, 120)
        mouse_filter = Control.MOUSE_FILTER_PASS
    var big := false   # R181 · só no celular (PC congelado)
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
        line.add_theme_font_size_override("font_size", 38 if big else 32)   # R181 · celular: letra maior; PC congelado (32)
        line.add_theme_font_override("font", field_font())
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
    var side := 260.0   # espaço das pontas da placa (o texto cabe no resto)
    var glow := false   # R181 · botão PRINCIPAL (Jogar como convidado): brilho dourado pulsando em volta da placa
    var entrar_style := false   # R181 · texto no MESMO dourado em degradê do ENTRAR da arte (claro em cima, escuro embaixo)
    var veil := false   # R181 · véu azul suave no meio da placa (a textura tem uma mancha clara ali)
    var _bands: Array = []
    var _t := 0.0
    func _process(delta):
        if glow:
            _t += delta
            queue_redraw()
    func _init():
        focus_mode = Control.FOCUS_NONE
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
        for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color", "font_outline_color", "icon_normal_color"]:
            add_theme_color_override(c, Color(0, 0, 0, 0))
        add_theme_constant_override("outline_size", 0)
    func _notification(what):
        if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT]: queue_redraw()
    ## R176.1 · textura da placa (o destaque dos botões de saída recolore só o miolo dela)
    func plate_texture() -> Texture2D:
        return null if baked else (LoginSkinRef.nine_button() if primary else LoginSkinRef.nine_google()).texture
    func _draw():
        var lit := is_hovered() and not disabled
        var down := button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
        var r := Rect2(Vector2.ZERO, size)
        if glow:
            var a := 0.30 + 0.18 * sin(_t * 3.2)
            var g := StyleBoxFlat.new()
            g.bg_color = Color(0, 0, 0, 0)
            g.set_corner_radius_all(int(size.y * 0.22))
            g.shadow_color = Color(1.0, 0.80, 0.30, a)
            g.shadow_size = int(size.y * 0.16)
            draw_style_box(g, r.grow(-size.y * 0.10))
        if not baked:
            draw_style_box(LoginSkinRef.nine_button() if primary else LoginSkinRef.nine_google(), r)
            if veil:
                var v := StyleBoxFlat.new()
                v.bg_color = Color8(22, 52, 122, 150)
                v.set_corner_radius_all(int(size.y * 0.3))
                v.shadow_color = Color8(22, 52, 122, 110)
                v.shadow_size = int(size.y * 0.14)
                draw_style_box(v, Rect2(Vector2(size.x * 0.24, size.y * 0.27), Vector2(size.x * 0.52, size.y * 0.46)))
            var f: Font = Art.FONT_BOLD
            var fs := font_size
            var icon_w := size.y * 0.5 if icon_kind != "" else 0.0
            var gap := 22.0 if icon_w > 0.0 else 0.0
            while fs > 14 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - side - icon_w - gap: fs -= 1
            var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
            var x0 := (size.x - tw - icon_w - gap) / 2.0
            if icon_w > 0.0:
                var ib := Rect2(Vector2(x0, (size.y - icon_w) / 2.0), Vector2(icon_w, icon_w))
                draw_circle(ib.get_center(), icon_w * 0.52, Color(1, 1, 1, 0.97))
                Art.icon(self, icon_kind, ib.grow(-icon_w * 0.14), Color.WHITE)
            var base := Vector2(x0 + icon_w + gap, size.y / 2.0 + f.get_ascent(fs) * 0.36)
            if entrar_style: _entrar_text(f, base, fs, lit)
            else: LoginSkinRef.gold_text(self, f, base, text, fs, lit)
        # realce ao passar o mouse / pressionar, por cima da arte (recortada ou já na pintura)
        var inset := Rect2(Vector2(56, 14), Vector2(size.x - 112, size.y - 28)) if primary else Rect2(Vector2(50, 10), Vector2(size.x - 100, size.y - 20))
        if down: draw_rect(inset, Color(0, 0, 0, 0.22))
        elif lit: draw_rect(inset, Color(1.0, 0.92, 0.6, 0.10))
        if disabled: draw_rect(r, Color(0.029, 0.043, 0.071, 0.45))

    ## dourado do ENTRAR: sombra + contorno marrom + 3 faixas (escuro embaixo → claro em cima), cada faixa recortada
    func _entrar_text(f: Font, base: Vector2, fs: int, lit: bool) -> void:
        draw_string(f, base + Vector2(0, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
        draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color8(58, 30, 6, 235))
        draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(206, 158, 72) if not lit else Color8(226, 182, 96))
        var top := base.y - f.get_ascent(fs) * 0.72   # topo das maiúsculas
        var cap := f.get_ascent(fs) * 0.72
        var specs := [[top + cap * 0.62, Color8(241, 196, 104)], [top + cap * 0.34, Color8(250, 226, 136)]]
        while _bands.size() < specs.size():
            var b := TextBand.new()
            add_child(b)
            _bands.append(b)
        for i in specs.size():
            var band: Control = _bands[i]
            band.position = Vector2.ZERO
            band.size = Vector2(size.x, maxf(1.0, specs[i][0]))
            band.setup(f, base, text, fs, specs[i][1].lightened(0.08) if lit else specs[i][1])

class TextBand extends Control:
    var f: Font
    var base := Vector2.ZERO
    var t := ""
    var fs := 16
    var col := Color.WHITE
    func _init():
        clip_contents = true
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func setup(p_f: Font, p_base: Vector2, p_t: String, p_fs: int, p_col: Color) -> void:
        if p_f == f and p_base == base and p_t == t and p_fs == fs and p_col == col: return
        f = p_f; base = p_base; t = p_t; fs = p_fs; col = p_col
        queue_redraw()
    func _draw():
        if f != null: draw_string(f, base, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

# ---------------------------------------------------------------- link (linha com ícone, texto e seta)
class SkinLink extends Button:
    const TEXT_X := 78.0       # onde o texto começa (antes 125)
    const CHEVRON_W := 100.0    # espaço da seta pintada na arte, à direita (seta em x≈795–810 da arte)
    var icon_kind := ""
    var baked := false
    var small := false   # R181 · links secundários (Criar conta / Esqueci minha senha): sem ícone, centralizados
    var halo := false    # R181 · luz dourada leve em volta do texto (Criar conta)
    var big := false     # R181 · celular: ícone mais à esquerda e texto maior. PC (false) = desenho original
    var fixed_fs := 0    # R181 · celular, telas de lista: mesmo tamanho para todos os links da tela (0 = automático)
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
        if small:
            var sf: Font = Art.FONT_SEMI
            var sfs := 30
            while sfs > 14 and sf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x > size.x - 12.0: sfs -= 1
            var sk: float = maxf(0.05, get_global_transform().get_scale().x)
            # R196 · o tamanho final em pixels também precisa caber (celular estreito: o mínimo de 9 px fazia
            # "Criar conta" e "Esqueci minha senha" encostarem um no outro)
            var ps := maxi(9, int(round(sfs * sk)))
            while ps > 7 and sf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x > (size.x - 12.0) * sk: ps -= 1
            var swp := sf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x
            var sb := Vector2((size.x * sk - swp) / 2.0, (size.y / 2.0 + sf.get_ascent(sfs) * 0.36) * sk)
            draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / sk)
            if halo:
                for w in [14, 9, 5]:
                    draw_string_outline(sf, sb, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, int(round(w * sk)), Color(1.0, 0.82, 0.38, 0.10))
            draw_string_outline(sf, sb, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, 2, Color(0.071, 0.085, 0.113, 0.7))
            draw_string(sf, sb, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, Color("fff0c8") if lit else CREAM)
            draw_set_transform(Vector2.ZERO)
            if lit: draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color(1.0, 0.9, 0.6, 0.06))
            return
        if not baked: draw_style_box(LoginSkinRef.nine_row(), Rect2(Vector2.ZERO, size))
        # R181 · celular: ícone mais à esquerda e texto MAIOR (mesmo tamanho nos três), sem mexer na arte. PC: original
        var ic := Rect2(Vector2(10, 4), Vector2(52, 52)) if big else Rect2(Vector2(50, 6), Vector2(46, 46))
        var col := Color("ffe9b0") if lit else GOLD
        match icon_kind:
            "": pass
            "person": LoginSkinRef.person_icon(self, ic, col)
            _: Art.icon(self, icon_kind, ic, col)
        var f: Font = Art.FONT_SEMI
        var fs := LoginSkinRef.link_font_size(f, size.x) if big else (fixed_fs if fixed_fs > 0 else 33)
        var room := size.x - TEXT_X - CHEVRON_W if big else size.x - 130.0 - 60.0
        while fs > 16 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room: fs -= 1
        var base := Vector2(TEXT_X, 30 + f.get_ascent(fs) * 0.36) if big else Vector2(125, 31 + f.get_ascent(fs) * 0.36)
        # O painel inteiro é reduzido (scale k): o texto é rasterizado no tamanho FINAL em pixels
        # (fonte fs*k desenhada com transform 1/k) para ficar nítido, sem bordas grossas/serrilhadas.
        var gk: float = maxf(0.05, get_global_transform().get_scale().x)
        var pfs := maxi(9, int(round(fs * gk)))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / gk)
        var pb := base * gk
        draw_string_outline(f, pb, text, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, 2, Color(0.071, 0.085, 0.113, 0.7))
        draw_string(f, pb, text, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, Color("fff0c8") if lit else CREAM)
        draw_set_transform(Vector2.ZERO)
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
    ## R181 · tamanho único dos links da tela de entrar: o maior em que o texto mais longo cabe (até 42; antes 33)
    const LINK_TEXTS := ["Criar conta", "Esqueci minha senha", "Jogar como convidado"]
    static func link_font_size(f: Font, w: float) -> int:
        var fs := 42
        for t in LINK_TEXTS:
            while fs > 16 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - SkinLink.TEXT_X - SkinLink.CHEVRON_W: fs -= 1
        return fs
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
