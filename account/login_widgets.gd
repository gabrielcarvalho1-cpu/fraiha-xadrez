extends RefCounted
## Peças da tela de conta no estilo da moldura: campo com ícone, botão ornamentado e link.
const Art := preload("res://account/login_art.gd")

## Botão com pontas em "V". primary = verde com ouro (ENTRAR); senão escuro elegante.
class OrnateButton extends Button:
    var primary := false
    var icon_kind := ""
    var label := ""
    var font_size := 22
    func _init():
        focus_mode = Control.FOCUS_NONE
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
        # O texto do próprio Button fica invisível (desenhamos com a fonte da moldura),
        # mas continua em `text` para leitores e testes.
        for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
            add_theme_color_override(c, Color(0, 0, 0, 0))
    func _notification(what):
        if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT]: queue_redraw()
    func _draw():
        var r := Rect2(Vector2.ZERO, size)
        var lit := is_hovered() and not disabled
        var down := button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
        var notch := size.y * (0.42 if primary else 0.32)
        var outer := Art.pointed(r, notch)
        Art.vertical_gradient(self, outer, Art.GOLD if primary else Art.GOLD_MID, Art.GOLD_DARK)
        var inner_r := r.grow(-(3.0 if primary else 2.0))
        var inner := Art.pointed(inner_r, notch - 1.5)
        if primary:
            var top := Color("2f7d43") if not down else Color("1d5a2c")
            var bottom := Color("0f3d1d")
            if lit: top = top.lightened(0.12)
            Art.vertical_gradient(self, inner, top, bottom)
        else:
            Art.vertical_gradient(self, inner, Color("16211b").lightened(0.06 if lit else 0.0), Color("070d0a"))
        var line := Art.pointed(r.grow(-7.0), notch - 4.0)
        line.append(line[0])
        draw_polyline(line, Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.35 if primary else 0.22), 1.0)
        if primary:
            # Brilho superior e estrelinhas perto das pontas.
            draw_line(Vector2(notch + 6.0, 6.0), Vector2(size.x - notch - 6.0, 6.0), Color(1, 1, 1, 0.12), 2.0)
            if size.x >= 320.0:
                for x in [notch + 24.0, size.x - notch - 24.0]:
                    Art.star4(self, Vector2(x, size.y / 2.0), 7.0, Art.GOLD)
        else:
            for x in [notch * 0.55 + 8.0, size.x - notch * 0.55 - 8.0]:
                Art.diamond(self, Vector2(x, size.y / 2.0), 4.0, Art.GOLD_MID)
        var f: Font = Art.FONT_BOLD if primary else Art.FONT_SEMI
        var icon_w := size.y * 0.62 if not icon_kind.is_empty() else 0.0
        var gap := 14.0 if icon_w > 0.0 else 0.0
        # Ajusta a fonte para caber entre as pontas (telas estreitas).
        var fs := font_size
        var room := size.x - notch * 2.0 - 16.0 - icon_w - gap
        while fs > 10 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room: fs -= 1
        var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
        var x0 := (size.x - tw - icon_w - gap) / 2.0
        if icon_w > 0.0:
            var ib := Rect2(Vector2(x0, (size.y - icon_w) / 2.0), Vector2(icon_w, icon_w))
            if icon_kind == "google":
                draw_circle(ib.get_center(), icon_w * 0.5, Color(1, 1, 1, 0.95))
                Art.icon(self, "google", ib.grow(-icon_w * 0.12), Color.WHITE)
            else:
                Art.icon(self, icon_kind, ib, Art.GOLD)
        var base := Vector2(x0 + icon_w + gap, size.y / 2.0 + f.get_ascent(fs) * 0.36)
        var col := Art.CREAM if primary else Color("eef0ea")
        if disabled: col = Color("8b8f86")
        draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.55))
        draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Art.GOLD if (primary and lit) else col)

## Campo com moldura dourada fina, ícone à esquerda e (senha) botão de mostrar.
class Field extends MarginContainer:
    var line: LineEdit
    var icon_kind := ""
    var eye: Button
    func _init():
        add_theme_constant_override("margin_left", 58)
        add_theme_constant_override("margin_right", 14)
        add_theme_constant_override("margin_top", 4)
        add_theme_constant_override("margin_bottom", 4)
        mouse_filter = Control.MOUSE_FILTER_PASS
    func setup(kind: String, secret: bool):
        icon_kind = kind
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        add_child(row)
        line = LineEdit.new()
        line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        line.secret = secret
        var flat := StyleBoxEmpty.new()
        for s in ["normal", "focus", "read_only"]: line.add_theme_stylebox_override(s, flat)
        line.add_theme_font_size_override("font_size", 20)
        line.add_theme_color_override("font_color", Art.CREAM)
        line.add_theme_color_override("font_placeholder_color", Color("8c8f80"))
        line.add_theme_color_override("caret_color", Art.GOLD)
        line.add_theme_color_override("selection_color", Color(0.79, 0.6, 0.27, 0.35))
        line.focus_entered.connect(queue_redraw)
        line.focus_exited.connect(queue_redraw)
        row.add_child(line)
        if secret:
            eye = Button.new()
            eye.name = "ShowPassword"
            eye.tooltip_text = "Mostrar senha"
            eye.focus_mode = Control.FOCUS_NONE
            eye.flat = true
            eye.custom_minimum_size = Vector2(44, 0)
            eye.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
            eye.draw.connect(func(): Art.icon(eye, "eye" if line.secret else "eye_off", Rect2(Vector2(6, (eye.size.y - 30) / 2.0), Vector2(30, 30)), Color("b9b7a8")))
            eye.pressed.connect(func():
                line.secret = not line.secret
                eye.tooltip_text = "Mostrar senha" if line.secret else "Ocultar senha"
                eye.queue_redraw())
            row.add_child(eye)
    func _draw():
        var r := Rect2(Vector2.ZERO, size)
        var focused := line != null and line.has_focus()
        draw_rect(r, Color(0.02, 0.05, 0.035, 0.9))
        draw_rect(r, Art.GOLD_MID if focused else Color(0.62, 0.48, 0.24, 0.9), false, 1.6)
        draw_rect(r.grow(-4.0), Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.14 if focused else 0.07), false, 1.0)
        # Pequenas pontas nos cantos (como nos campos da referência).
        for c in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
            Art.diamond(self, c, 3.0, Art.GOLD_MID)
        Art.icon(self, icon_kind, Rect2(Vector2(16, (size.y - 28) / 2.0), Vector2(28, 28)), Art.GOLD_MID)
        draw_line(Vector2(52, 10), Vector2(52, size.y - 10), Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.18), 1.0)

## Link com ícone e sublinhado dourado.
class Link extends Button:
    var icon_kind := ""
    func _init():
        flat = true
        focus_mode = Control.FOCUS_NONE
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        add_theme_font_override("font", Art.FONT_SEMI)
        add_theme_color_override("font_color", Color("e9d29a"))
        add_theme_color_override("font_hover_color", Art.GOLD)
        add_theme_color_override("font_pressed_color", Art.GOLD_MID)
        alignment = HORIZONTAL_ALIGNMENT_LEFT
        for s in ["normal", "hover", "pressed", "focus"]:
            var st := StyleBoxEmpty.new()
            st.content_margin_left = 42
            st.content_margin_right = 4
            add_theme_stylebox_override(s, st)
    func _notification(what):
        if what in [NOTIFICATION_MOUSE_ENTER, NOTIFICATION_MOUSE_EXIT]: queue_redraw()
    func _draw():
        var fs := get_theme_font_size("font_size")
        var tw := Art.FONT_SEMI.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
        var y := size.y / 2.0 + fs * 0.62
        var col := Art.GOLD if is_hovered() else Color(0.79, 0.6, 0.27, 0.7)
        draw_line(Vector2(42, y), Vector2(42 + tw, y), col, 1.2)
        if not icon_kind.is_empty():
            Art.icon(self, icon_kind, Rect2(Vector2(2, (size.y - 28) / 2.0), Vector2(28, 28)), Art.GOLD_MID)
