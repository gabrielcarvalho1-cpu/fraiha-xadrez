extends Button
## Botão do HUD da partida no estilo FRAIHA: fundo verde-escuro, moldura dourada, cravos nos
## cantos e ícone desenhado em pixel (sem depender de fonte com símbolos).
## glyph: "fullscreen", "exit_fullscreen", "home", "gear", "restart", "sound_on", "sound_off", "trophy", "chat", "crown". hint: tecla (ex.: "ESC").
const GOLD := Color("f4ce7f")
const GOLD_DIM := Color("b99555")
const INK := Color("10141e")
var glyph := ""
var hint := ""
var icon_only := false
var icon_box := 54.0   # largura reservada ao ícone à esquerda (botões com texto)

## R36 · Home v7: o quadrado (moldura dourada e fundo) já está na arte; o botão só desenha o ícone
## e uma luz suave no hover/clique.
func set_over_art(on: bool):
    if not on:
        _style()
        queue_redraw()
        return
    var clear := StyleBoxFlat.new()
    clear.bg_color = Color(0, 0, 0, 0)
    var glow := StyleBoxFlat.new()
    glow.bg_color = Color(1.0, 0.86, 0.45, 0.10)
    glow.set_corner_radius_all(4)
    var press := glow.duplicate()
    press.bg_color = Color(0, 0, 0, 0.18)
    for pair in [["normal", clear], ["hover", glow], ["pressed", press], ["disabled", clear]]:
        add_theme_stylebox_override(pair[0], pair[1])
    queue_redraw()

## R113 · a mesma moldura da arte da Home (dourada, fundo escuro), recortada dos botões de som / tela cheia.
## Em 9 partes: estica sem deformar os cantos (serve também para o botão largo das Coroas).
var framed := false
func set_frame(tex: Texture2D, margin := 14.0):
    framed = true
    for pair in [["normal", Color(1, 1, 1)], ["hover", Color(1.22, 1.16, 1.05)], ["pressed", Color(0.82, 0.82, 0.82)], ["disabled", Color(0.6, 0.6, 0.6)]]:
        var st := StyleBoxTexture.new()
        st.texture = tex
        st.texture_margin_left = margin
        st.texture_margin_right = margin
        st.texture_margin_top = margin
        st.texture_margin_bottom = margin
        st.modulate_color = pair[1]
        add_theme_stylebox_override(pair[0], st)
    add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    _margins()
    queue_redraw()

static func make(glyph_id: String, caption := "", key_hint := "") -> Button:
    var b = load("res://ui_v022/hud_button.gd").new()
    b.glyph = glyph_id
    b.hint = key_hint
    b.text = caption
    b.icon_only = caption.is_empty()
    b._style()
    return b

func _style():
    focus_mode = Control.FOCUS_NONE
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    alignment = HORIZONTAL_ALIGNMENT_LEFT
    add_theme_font_size_override("font_size", 18)
    add_theme_color_override("font_color", Color("f1e4c2"))
    add_theme_color_override("font_hover_color", GOLD)
    add_theme_color_override("font_pressed_color", GOLD)
    add_theme_color_override("font_disabled_color", Color("7d8479"))
    add_theme_color_override("font_outline_color", INK)
    add_theme_constant_override("outline_size", 4)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.097, 0.129, 0.194, 0.93)
    normal.border_color = GOLD_DIM
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(8)
    normal.shadow_color = Color(0, 0, 0, 0.45)
    normal.shadow_size = 6
    normal.shadow_offset = Vector2(0, 2)
    var hover := normal.duplicate()
    hover.bg_color = Color(0.149, 0.198, 0.297, 0.96)
    hover.border_color = GOLD
    var pressed := normal.duplicate()
    pressed.bg_color = Color(0.070, 0.094, 0.141, 0.96)
    pressed.border_color = GOLD
    var disabled := normal.duplicate()
    disabled.bg_color = Color(0.085, 0.099, 0.127, 0.8)
    disabled.border_color = Color("4b4a3a")
    for pair in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled], ["focus", StyleBoxEmpty.new()]]:
        add_theme_stylebox_override(pair[0], pair[1])
    _margins()

func _margins():
    for s in ["normal", "hover", "pressed", "disabled"]:
        var st: StyleBox = get_theme_stylebox(s)
        st.content_margin_left = (icon_box - 4.0) if not icon_only else 0.0
        st.content_margin_right = (_hint_width() + 22.0) if not hint.is_empty() else 16.0

func _hint_width() -> float:
    return get_theme_default_font().get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0

func _notification(what):
    if what == NOTIFICATION_RESIZED: _margins()
    if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT: queue_redraw()

func _draw():
    var lit := is_hovered() or button_pressed
    var col := GOLD if (lit and not disabled) else (Color("7d8479") if disabled else Color("e9cf8f"))
    # Cravos dourados nos cantos da moldura.
    for c in ([] if glyph.is_empty() or framed else [Vector2(6, 6), Vector2(size.x - 6, 6), Vector2(6, size.y - 6), Vector2(size.x - 6, size.y - 6)]):
        draw_colored_polygon(PackedVector2Array([c + Vector2(0, -2.5), c + Vector2(2.5, 0), c + Vector2(0, 2.5), c + Vector2(-2.5, 0)]), GOLD_DIM if not lit else GOLD)
    var box := minf(size.y, icon_box)
    var center := Vector2(icon_box / 2.0 + 2.0, size.y / 2.0) if not icon_only else size / 2.0
    var r := box * 0.22
    var w := maxf(2.0, box / 18.0)
    match glyph:
        "fullscreen", "exit_fullscreen":
            var inward := glyph == "exit_fullscreen"
            for dx in [-1, 1]:
                for dy in [-1, 1]:
                    var corner := center + Vector2(dx, dy) * r
                    var tip := corner if not inward else center + Vector2(dx, dy) * r * 0.35
                    var arm := r * 0.6
                    var sx: float = -dx if not inward else dx
                    var sy: float = -dy if not inward else dy
                    draw_line(tip, tip + Vector2(sx * arm, 0), col, w)
                    draw_line(tip, tip + Vector2(0, sy * arm), col, w)
        "home":
            var base := center + Vector2(0, r * 0.25)
            draw_polyline(PackedVector2Array([base + Vector2(-r * 1.05, -r * 0.2), base + Vector2(0, -r * 1.25), base + Vector2(r * 1.05, -r * 0.2)]), col, w)
            draw_polyline(PackedVector2Array([base + Vector2(-r * 0.75, -r * 0.45), base + Vector2(-r * 0.75, r * 0.85), base + Vector2(r * 0.75, r * 0.85), base + Vector2(r * 0.75, -r * 0.45)]), col, w)
            draw_rect(Rect2(base + Vector2(-r * 0.22, r * 0.2), Vector2(r * 0.44, r * 0.65)), col)
        "gear":
            draw_circle(center, r * 0.72, col, false, w)
            draw_circle(center, r * 0.22, col)
            for i in 8:
                var a := TAU * float(i) / 8.0
                var d := Vector2(cos(a), sin(a))
                draw_line(center + d * r * 0.78, center + d * r * 1.12, col, w * 1.3)
        "bookmark":
            # Marcador de página: MARCAR PARA REVISAR (sem engine).
            var top := center + Vector2(-r * 0.6, -r * 1.0)
            draw_colored_polygon(PackedVector2Array([top, top + Vector2(r * 1.2, 0), top + Vector2(r * 1.2, r * 2.0), center + Vector2(0, r * 0.55), top + Vector2(0, r * 2.0)]), col)
        "magnifier":
            # Lupa: ANALISAR PARTIDA (só depois do fim).
            draw_arc(center + Vector2(-r * 0.2, -r * 0.2), r * 0.62, 0, TAU, 24, col, w * 1.2)
            draw_line(center + Vector2(r * 0.3, r * 0.3), center + Vector2(r * 0.95, r * 0.95), col, w * 1.8)
        "sound_on", "sound_off":
            # Alto-falante (corpo + cone); ligado: ondas; desligado: X vermelho-ferrugem.
            var o := center + Vector2(-r * 0.55, 0)
            draw_rect(Rect2(o + Vector2(-r * 0.55, -r * 0.38), Vector2(r * 0.5, r * 0.76)), col)
            draw_colored_polygon(PackedVector2Array([o + Vector2(-0.1 * r, -r * 0.38), o + Vector2(r * 0.55, -r * 0.95), o + Vector2(r * 0.55, r * 0.95), o + Vector2(-0.1 * r, r * 0.38)]), col)
            if glyph == "sound_on":
                for k in [0.55, 0.95]:
                    draw_arc(o + Vector2(r * 0.6, 0), r * k, deg_to_rad(-45), deg_to_rad(45), 10, col, w)
            else:
                var x := o + Vector2(r * 1.15, 0)
                var xc := Color("e07a5f") if not disabled else col
                draw_line(x + Vector2(-r * 0.38, -r * 0.38), x + Vector2(r * 0.38, r * 0.38), xc, w * 1.2)
                draw_line(x + Vector2(-r * 0.38, r * 0.38), x + Vector2(r * 0.38, -r * 0.38), xc, w * 1.2)
        "trophy":
            # R96 · RANKING: taça com alças, haste e base.
            var t := center + Vector2(0, -r * 0.15)
            draw_colored_polygon(PackedVector2Array([t + Vector2(-r * 0.78, -r * 0.85), t + Vector2(r * 0.78, -r * 0.85),
                t + Vector2(r * 0.62, -r * 0.05), t + Vector2(r * 0.25, r * 0.38), t + Vector2(-r * 0.25, r * 0.38), t + Vector2(-r * 0.62, -r * 0.05)]), col)
            draw_arc(t + Vector2(-r * 0.72, -r * 0.42), r * 0.34, deg_to_rad(90), deg_to_rad(270), 12, col, w)
            draw_arc(t + Vector2(r * 0.72, -r * 0.42), r * 0.34, deg_to_rad(-90), deg_to_rad(90), 12, col, w)
            draw_rect(Rect2(t + Vector2(-r * 0.12, r * 0.36), Vector2(r * 0.24, r * 0.42)), col)
            draw_rect(Rect2(t + Vector2(-r * 0.55, r * 0.76), Vector2(r * 1.1, r * 0.3)), col)
            draw_colored_polygon(PackedVector2Array([t + Vector2(0, -r * 0.62), t + Vector2(r * 0.14, -r * 0.34), t + Vector2(0, -r * 0.06), t + Vector2(-r * 0.14, -r * 0.34)]), INK)
        "chat":
            # R96 · CHAT GLOBAL: balão com três pontinhos.
            var b := Rect2(center + Vector2(-r * 1.05, -r * 0.8), Vector2(r * 2.1, r * 1.35))
            var st := StyleBoxFlat.new()
            st.bg_color = col
            st.set_corner_radius_all(int(r * 0.35))
            draw_style_box(st, b)
            draw_colored_polygon(PackedVector2Array([b.position + Vector2(r * 0.35, b.size.y - 1), b.position + Vector2(r * 0.95, b.size.y - 1), b.position + Vector2(r * 0.25, b.size.y + r * 0.55)]), col)
            for i in 3:
                draw_circle(b.get_center() + Vector2((i - 1) * r * 0.55, 0), r * 0.15, INK)
        "crown":
            # R112 · COROAS: coroa de 3 pontas com joias e faixa.
            var c0 := center + Vector2(0, r * 0.1)
            draw_colored_polygon(PackedVector2Array([c0 + Vector2(-r * 1.0, r * 0.55), c0 + Vector2(-r * 1.05, -r * 0.65), c0 + Vector2(-r * 0.5, -r * 0.1),
                c0 + Vector2(0, -r * 0.95), c0 + Vector2(r * 0.5, -r * 0.1), c0 + Vector2(r * 1.05, -r * 0.65), c0 + Vector2(r * 1.0, r * 0.55)]), col)
            draw_rect(Rect2(c0 + Vector2(-r * 1.0, r * 0.62), Vector2(r * 2.0, r * 0.3)), col)
            for p in [Vector2(-r * 1.05, -r * 0.65), Vector2(0, -r * 0.95), Vector2(r * 1.05, -r * 0.65)]: draw_circle(c0 + p, r * 0.17, col)
            for k in [-0.5, 0.0, 0.5]: draw_circle(c0 + Vector2(r * k, r * 0.25), r * 0.11, INK)
        "restart":
            draw_arc(center, r * 0.85, deg_to_rad(-70), deg_to_rad(220), 20, col, w)
            var end := center + Vector2(cos(deg_to_rad(-70)), sin(deg_to_rad(-70))) * r * 0.85
            draw_colored_polygon(PackedVector2Array([end + Vector2(-r * 0.45, -r * 0.15), end + Vector2(r * 0.15, -r * 0.45), end + Vector2(r * 0.1, r * 0.25)]), col)
    if not hint.is_empty():
        # Tecla como uma pequena "plaquinha".
        var font := get_theme_default_font()
        var hw := _hint_width()
        var rect := Rect2(size.x - hw - 12.0, size.y / 2.0 - 11.0, hw, 22.0)
        var st := StyleBoxFlat.new()
        st.bg_color = Color(0, 0, 0, 0.35)
        st.border_color = GOLD_DIM
        st.set_border_width_all(1)
        st.set_corner_radius_all(4)
        draw_style_box(st, rect)
        draw_string(font, rect.position + Vector2(6, 16), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("d8c79c"))
