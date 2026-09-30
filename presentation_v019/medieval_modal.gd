extends Control
## Confirmação de sair/abandonar no desktop, com a arte da referência (moldura dourada,
## brasão, cavalos, botões vermelho e verde). Espelha o ConfirmationDialog do stage, que
## continua sendo a fonte das ações/textos (fica escondido fora da tela enquanto isto aparece).
const ART := preload("res://ui_v022/assets/modal_abandon.png")
const TITLE_FONT := preload("res://account/fonts/Cinzel-Bold.woff")
const RED := Rect2(48, 288, 307, 70)
const GREEN := Rect2(374, 288, 311, 70)
var dialog: ConfirmationDialog
var mode_of: Callable
var ok_btn: Button
var cancel_btn: Button
var hover := ""

func setup(d: ConfirmationDialog, mode_fn: Callable):
    dialog = d
    mode_of = mode_fn
    mouse_filter = Control.MOUSE_FILTER_STOP
    ok_btn = _hit(RED, func(): dialog.confirmed.emit(); dialog.hide())
    cancel_btn = _hit(GREEN, func(): dialog.canceled.emit(); dialog.hide())
    hide()

func _hit(r: Rect2, action: Callable) -> Button:
    var b := Button.new()
    b.flat = true
    b.focus_mode = Control.FOCUS_NONE
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    for s in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
    b.position = r.position
    b.size = r.size
    b.pressed.connect(action)
    b.mouse_entered.connect(func(): hover = "ok" if r == RED else "cancel"; queue_redraw())
    b.mouse_exited.connect(func(): hover = ""; queue_redraw())
    add_child(b)
    return b

func sync(active: bool, viewport_size: Vector2):
    var want: bool = active and dialog.visible
    if want:
        # O diálogo nativo continua aberto (teclas e testes), mas fora da vista.
        dialog.position = Vector2i(-20000, -20000)
        size = ART.get_size()
        var k := minf(1.15, (viewport_size.x - 40.0) / size.x)
        scale = Vector2.ONE * k
        position = (viewport_size - size * k) / 2.0
    if visible != want:
        visible = want
        queue_redraw()
    elif want:
        queue_redraw()

func _title() -> String:
    var m := String(mode_of.call())
    var t := dialog.dialog_text
    if m in ["ranked", "casual"]: return "DESISTIR DA PARTIDA?"
    if m == "bot": return "ABANDONAR PARTIDA?"
    if m == "local": return "ENCERRAR PARTIDA?"
    if m == "online": return "SAIR DA SALA?"
    if "Sair do FRAIHA" in t: return "SAIR DO JOGO?"
    return "CONFIRMAR"

func _body() -> String:
    var t := dialog.dialog_text
    if t == "Deseja abandonar a partida?":
        return "Deseja realmente abandonar a partida?\nSeu progresso nesta partida será perdido."
    return t

func _fit(font: Font, text: String, size: int, width: float) -> int:
    while size > 10 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width: size -= 1
    return size

func _draw():
    draw_texture(ART, Vector2.ZERO)
    var w := size.x
    # Título dourado com contorno escuro.
    var title := _title()
    var ts := _fit(TITLE_FONT, title, 36, 470)
    var tw := TITLE_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
    var tp := Vector2((w - tw) / 2.0, 152)
    draw_string_outline(TITLE_FONT, tp + Vector2(0, 2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, 8, Color(0.1, 0.05, 0.0, 0.9))
    draw_string(TITLE_FONT, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color("f6d27a"))
    # Texto.
    var font := get_theme_default_font()
    var lines := _body().split("\n")
    var y := 225.0 if lines.size() > 1 else 238.0
    for line in lines:
        var fs := _fit(font, line, 21, 520)
        var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
        draw_string(font, Vector2((w - lw) / 2.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("efe6cf"))
        y += 30
    # Botões: rótulos vivos, brilho no hover.
    for pair in [[RED, dialog.ok_button_text.to_upper(), Color("f7ead0"), "ok"], [GREEN, dialog.cancel_button_text.to_upper(), Color("f1d58a"), "cancel"]]:
        var r: Rect2 = pair[0]
        if hover == pair[3]:
            draw_rect(r.grow(-6), Color(1.0, 0.85, 0.45, 0.10))
        var label: String = pair[1]
        var room := r.size.x - 110.0
        var fs := _fit(font, label, 22, room)
        var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
        var p := Vector2(r.position.x + 88.0 + (room - lw) / 2.0, r.get_center().y + fs * 0.36)
        draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.6))
        draw_string(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pair[2])
        draw_string(font, p + Vector2(0.6, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pair[2])
