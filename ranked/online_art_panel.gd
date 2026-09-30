extends Control
## Tela de escolha de ritmo (JOGAR ONLINE / JOGAR RANQUEADO) no desktop, com a arte da
## referência. Os textos são desenhados por cima; os cliques repassam para os botões reais
## da ranked_ui (mesmas ações, mesmas regras). Coordenadas em pixels da arte.
const ART := preload("res://ui_v022/assets/online_panel.png")
const TITLE_FONT := preload("res://account/fonts/Cinzel-Bold.woff")
const TAB_L := Rect2(127, 257, 430, 75)
const TAB_R := Rect2(562, 257, 435, 75)
const BACK := Rect2(352, 882, 420, 85)
const CARD_DX := 512.0
const CARD_DY := 230.0
var ui   # ranked_ui dona deste painel
var queue_hits: Array = []
var hover := ""

func setup(owner):
    ui = owner
    mouse_filter = Control.MOUSE_FILTER_STOP
    size = ART.get_size()
    for i in 4:
        var r := _card_button(i)
        queue_hits.append(_hit(r, "q%d" % i, func(): _queue(i)))
    _hit(TAB_L, "tab_l", func(): _tab("casual"))
    _hit(TAB_R, "tab_r", func(): _tab("ranked"))
    _hit(BACK, "back", func():
        var b = ui.footer.find_child("BackButton", true, false)
        if b != null: b.pressed.emit())
    hide()

func _card_button(i: int) -> Rect2:
    return Rect2(82 + (i % 2) * CARD_DX, 552 + (i / 2) * CARD_DY, 450, 55)

func _hit(r: Rect2, id: String, action: Callable) -> Button:
    var b := Button.new()
    b.flat = true
    b.focus_mode = Control.FOCUS_NONE
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    for s in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
    b.position = r.position
    b.size = r.size
    b.pressed.connect(action)
    b.mouse_entered.connect(func(): hover = id; queue_redraw())
    b.mouse_exited.connect(func(): if hover == id: hover = ""; queue_redraw())
    add_child(b)
    return b

func _modes() -> Array:
    return ui.mode_list()

func _real_button(i: int) -> Button:
    var modes := _modes()
    if i >= modes.size(): return null
    return ui.box.find_child("Queue_" + String(modes[i][0]), true, false)

func _queue(i: int):
    var b := _real_button(i)
    if b != null and not b.disabled: b.pressed.emit()

func _tab(kind: String):
    if kind == ui.kind: return
    ui.switch_requested.emit(kind)

func layout(viewport_size: Vector2):
    var k := minf(1.0, minf((viewport_size.x - 40.0) / size.x, (viewport_size.y - 20.0) / size.y))
    scale = Vector2.ONE * k
    position = (viewport_size - size * k) / 2.0
    for i in 4:
        var b := _real_button(i)
        queue_hits[i].disabled = b == null or b.disabled
    queue_redraw()

func _fit(font: Font, text: String, fs: int, width: float) -> int:
    while fs > 9 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width: fs -= 1
    return fs

func _center(font: Font, text: String, cx: float, baseline: float, fs: int, width: float, col: Color, outline := 0, ocol := Color(0, 0, 0, 0.7)):
    fs = _fit(font, text, fs, width)
    var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
    var p := Vector2(cx - w / 2.0, baseline)
    if outline > 0: draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, ocol)
    draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw():
    var rated: bool = ui.rated()
    draw_texture(ART, Vector2.ZERO)
    # Aba ativa: a arte já destaca "Casual"; no Ranked, a esquerda escurece e a direita ganha brilho.
    if rated:
        draw_rect(TAB_L.grow(-8), Color(0, 0, 0, 0.45))
        draw_rect(TAB_R.grow(-10), Color(1.0, 0.85, 0.4, 0.13))
        draw_rect(TAB_R.grow(-10), Color("f1d58a"), false, 2.0)
    for id in ["tab_l", "tab_r"]:
        if hover == id and not ((id == "tab_l") != rated): draw_rect((TAB_L if id == "tab_l" else TAB_R).grow(-10), Color(1, 0.9, 0.6, 0.08))
    var font := get_theme_default_font()
    # Título e subtítulo no estandarte.
    var title := "JOGAR RANQUEADO" if rated else "JOGAR ONLINE"
    _center(TITLE_FONT, title, 564, 176, 66, 470, Color("f6c85a"), 10, Color(0.16, 0.08, 0.0, 0.95))
    var sub := "RANQUEADA  ◆  CADA RITMO TEM LIGA E PL PRÓPRIOS" if rated else "PARTIDA CASUAL  ◆  ESCOLHA O RITMO E ENTRE NA FILA"
    _center(font, sub, 564, 224, 19, 520, Color("f1e6c8"))
    # Descrição (+ aviso de conexão/erro da própria ranked_ui).
    var desc := "Cada ritmo tem liga, PL e estatísticas próprios. Cores sorteadas pelo servidor." if rated else "Partida casual contra outro jogador: escolha o ritmo e entre na fila.\nNão vale PL e não altera o Ranked."
    var lines := desc.split("\n")
    var notice_text: String = ui.notice.text if is_instance_valid(ui.notice) else ""
    if notice_text.is_empty() and not rated and not ui.account.online_ready(): notice_text = "Conectando ao servidor…"
    var y := 352.0 if lines.size() + (1 if not notice_text.is_empty() else 0) > 2 else (360.0 if lines.size() > 1 or not notice_text.is_empty() else 372.0)
    for line in lines:
        _center(font, line, 564, y, 19, 640, Color("f4ecd8"))
        y += 23
    if not notice_text.is_empty():
        _center(font, notice_text, 564, y, 15, 640, Color("ffb08f") if ui.notice.text != "" else Color("f1d58a"))
    # Cartões.
    var modes := _modes()
    for i in mini(4, modes.size()):
        var item: Array = modes[i]
        var ox := (i % 2) * CARD_DX
        var oy := (i / 2) * CARD_DY
        var name := String(item[1])
        var nf := _fit(TITLE_FONT, name, 34, 290)
        var np := Vector2(237 + ox, 459 + oy)
        draw_string_outline(TITLE_FONT, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, nf, 7, Color(0.12, 0.06, 0.0, 0.9))
        draw_string(TITLE_FONT, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, nf, Color("f6d27a"))
        draw_string(font, Vector2(285 + ox, 499 + oy), "%d min por jogador" % int(item[2]), HORIZONTAL_ALIGNMENT_LEFT, 250, 19, Color("efe6cf"))
        var second := "sem PL"
        if rated:
            var stats: Dictionary = ui.account.ranked.get(String(item[0]), {})
            second = ui.league_line(int(stats.get("league", 0)), int(stats.get("pl", 0)))
        draw_string(font, Vector2(285 + ox, 530 + oy), second, HORIZONTAL_ALIGNMENT_LEFT, 250, 19, Color("efe6cf"))
        var r := _card_button(i)
        if queue_hits[i].disabled:
            draw_rect(r.grow(-4), Color(0, 0, 0, 0.45))
        elif hover == "q%d" % i:
            draw_rect(r.grow(-6), Color(1.0, 0.88, 0.5, 0.10))
    if hover == "back": draw_rect(BACK.grow(-12), Color(1.0, 0.88, 0.5, 0.08))
