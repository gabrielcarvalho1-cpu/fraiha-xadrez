extends Button
## Botão do HUD da partida no estilo FRAIHA: fundo verde-escuro, moldura dourada, cravos nos
## cantos e ícone desenhado em pixel (sem depender de fonte com símbolos).
## glyph: "fullscreen", "exit_fullscreen", "home", "gear", "restart", "sound_on", "sound_off". hint: tecla (ex.: "ESC").
const GOLD := Color("f4ce7f")
const GOLD_DIM := Color("b99555")
const INK := Color("0b150f")
var glyph := ""
var hint := ""
var icon_only := false
var icon_box := 54.0   # largura reservada ao ícone à esquerda (botões com texto)

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
    normal.bg_color = Color(0.07, 0.14, 0.10, 0.93)
    normal.border_color = GOLD_DIM
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(8)
    normal.shadow_color = Color(0, 0, 0, 0.45)
    normal.shadow_size = 6
    normal.shadow_offset = Vector2(0, 2)
    var hover := normal.duplicate()
    hover.bg_color = Color(0.11, 0.22, 0.15, 0.96)
    hover.border_color = GOLD
    var pressed := normal.duplicate()
    pressed.bg_color = Color(0.05, 0.10, 0.07, 0.96)
    pressed.border_color = GOLD
    var disabled := normal.duplicate()
    disabled.bg_color = Color(0.06, 0.09, 0.08, 0.8)
    disabled.border_color = Color("4b4a3a")
    for pair in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled], ["focus", StyleBoxEmpty.new()]]:
        add_theme_stylebox_override(pair[0], pair[1])
    _margins()

func _margins():
    for s in ["normal", "hover", "pressed", "disabled"]:
        var st: StyleBoxFlat = get_theme_stylebox(s)
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
    for c in ([] if glyph.is_empty() else [Vector2(6, 6), Vector2(size.x - 6, 6), Vector2(6, size.y - 6), Vector2(size.x - 6, size.y - 6)]):
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
