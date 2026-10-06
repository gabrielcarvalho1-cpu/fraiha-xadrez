extends Control
## Tela de escolha de ritmo (JOGAR ONLINE / JOGAR RANQUEADO) no desktop, com a arte da
## referência. Os textos são desenhados por cima; os cliques repassam para os botões reais
## da ranked_ui (mesmas ações, mesmas regras). Coordenadas em pixels da arte.
const ART := preload("res://ui_v022/assets/online_panel.png")
const TITLE_FONT := preload("res://account/fonts/Cinzel-Bold.woff")
const BG_TAB := Color("001b0f")
const TAB_ART := preload("res://ui_v022/assets/online_tab.png")
const ICON_CASUAL := preload("res://ui_v022/assets/online_tab_icon_casual.png")
const ICON_RANKED := preload("res://ui_v022/assets/online_tab_icon_ranked.png")
const TAB_L := Rect2(127, 257, 430, 75)
const TAB_R := Rect2(562, 257, 435, 75)
const BACK := Rect2(352, 882, 420, 85)
const INVITE := Rect2(402, 344, 320, 42)    # R35.1: CONVIDAR AMIGO (só na aba CASUAL)
const CARD_DX := 512.0
const CARD_DY := 230.0
# Ritmos fechados pelo Admin: os cartões ABERTOS são redesenhados (recortes da própria arte) em posições
# sem buracos; a área dos cartões é coberta com a faixa lisa logo acima deles (sem asset novo).
const CARD_SRC := Rect2(56, 398, 508, 226)          # cartão 0 na arte (os outros: + DX/DY)
const AREA := Rect2(44, 392, 1036, 474)             # área dos 4 cartões
const AREA_FILL_SRC := Rect2(44, 352, 1036, 36)     # faixa lisa (sem desenho) acima dos cartões
var ui   # ranked_ui dona deste painel
var queue_hits: Array = []
var hover := ""
var invite_hit: Button

func setup(owner):
    ui = owner
    mouse_filter = Control.MOUSE_FILTER_STOP
    size = ART.get_size()
    for i in 4:
        var r := _card_button(i)
        queue_hits.append(_hit(r, "q%d" % i, func(): _queue(i)))
    _hit(TAB_L, "tab_l", func(): _tab("casual"))
    _hit(TAB_R, "tab_r", func(): _tab("ranked"))
    invite_hit = _hit(INVITE, "invite", func(): if not ui.rated(): ui.invite_requested.emit())
    _hit(BACK, "back", func():
        var b = ui.footer.find_child("BackButton", true, false)
        if b != null: b.pressed.emit())
    hide()

## Deslocamento do i-ésimo cartão VISÍVEL quando há n visíveis (4 = grade 2x2 original).
func _slot(i: int, n: int) -> Vector2:
    match n:
        3: return Vector2(i * CARD_DX, 0.0) if i < 2 else Vector2(CARD_DX / 2.0, CARD_DY)
        2: return Vector2(i * CARD_DX, CARD_DY / 2.0)
        1: return Vector2(CARD_DX / 2.0, CARD_DY / 2.0)
    return Vector2((i % 2) * CARD_DX, (i / 2) * CARD_DY)

func _card_button(i: int) -> Rect2:
    var o := _slot(i, _modes().size())
    return Rect2(82 + o.x, 552 + o.y, 450, 55)

## Índice original (posição/ícone na arte) do ritmo: Relâmpago 0, Rápida 1, Normal 2, Convencional 3.
func _art_index(id: String) -> int:
    var all: Array = ui.all_modes()
    for j in all.size():
        if String(all[j][0]) == id: return j
    return 0

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
    var n := _modes().size()
    for i in 4:
        var b := _real_button(i)
        queue_hits[i].visible = i < n
        queue_hits[i].disabled = b == null or b.disabled
        var r := _card_button(i)
        queue_hits[i].position = r.position
    invite_hit.visible = not ui.rated()
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
    # Abas CASUAL e RANQUEADA com o mesmo visual (verde e ouro com louros); hover = mais brilho.
    var font0 := get_theme_default_font()
    # Apaga a aba "Ranqueada" escura da arte original antes de desenhar as duas abas iguais.
    draw_rect(Rect2(566, 254, 438, 82), BG_TAB)
    for pair in [[TAB_L, ICON_CASUAL, "CASUAL", "tab_l"], [TAB_R, ICON_RANKED, "RANQUEADA", "tab_r"]]:
        var r: Rect2 = pair[0]
        var slot := Rect2(118 if pair[3] == "tab_l" else 556, 252, 450, 86)
        var lit: bool = hover == pair[3]
        draw_texture_rect(TAB_ART, slot, false, Color(1.18, 1.14, 1.0) if lit else Color.WHITE)
        var label: String = pair[2]
        var fs := 25
        var lw := font0.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
        var icon: Texture2D = pair[1]
        var isz := icon.get_size() * 0.82
        var total := isz.x + 16.0 + lw
        var x0 := slot.get_center().x - total / 2.0
        draw_texture_rect(icon, Rect2(Vector2(x0, slot.get_center().y - isz.y / 2.0 - 1), isz), false)
        var tp := Vector2(x0 + isz.x + 16.0, slot.get_center().y + fs * 0.36)
        draw_string_outline(font0, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.1, 0.06, 0.0, 0.8))
        draw_string(font0, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffe6a0") if lit else Color("f6d27a"))
        draw_string(font0, tp + Vector2(0.7, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffe6a0") if lit else Color("f6d27a"))
    var font := get_theme_default_font()
    # Título e subtítulo no estandarte.
    var title := "JOGAR RANQUEADO" if rated else "JOGAR ONLINE"
    _center(TITLE_FONT, title, 564, 176, 66, 470, Color("f6c85a"), 10, Color(0.16, 0.08, 0.0, 0.95))
    var sub := "RANQUEADA  ·  CADA RITMO TEM LIGA E PL PRÓPRIOS" if rated else "PARTIDA CASUAL  ·  ESCOLHA O RITMO E ENTRE NA FILA"
    _center(font, sub, 564, 224, 19, 520, Color("f1e6c8"))
    # Descrição (+ aviso de conexão/erro da própria ranked_ui).
    var desc := "Cada ritmo tem liga, PL e estatísticas próprios. Cores sorteadas pelo servidor." if rated else "Partida casual: escolha o ritmo e entre na fila — ou chame um amigo. Não vale PL."
    var lines := desc.split("\n")
    var notice_text: String = ui.notice.text if is_instance_valid(ui.notice) else ""
    if notice_text.is_empty() and not rated and not ui.account.online_ready(): notice_text = "Conectando ao servidor…"
    var y := 352.0 if lines.size() + (1 if not notice_text.is_empty() else 0) > 2 else (360.0 if lines.size() > 1 or not notice_text.is_empty() else 372.0)
    if not rated:
        # casual: no lugar da descrição fica o botão CONVIDAR AMIGO; o aviso (conexão/erro) vai para
        # a faixa livre entre os cartões e o VOLTAR
        if not notice_text.is_empty():
            _center(font, notice_text, 564, 866, 16, 700, Color("ffb08f") if ui.notice.text != "" else Color("f1d58a"))
        lines = PackedStringArray()
        notice_text = ""
    for line in lines:
        _center(font, line, 564, y, 19, 640, Color("f4ecd8"))
        y += 23
    if not notice_text.is_empty():
        _center(font, notice_text, 564, y, 15, 640, Color("ffb08f") if ui.notice.text != "" else Color("f1d58a"))
    # Cartões (só os ritmos abertos; sem buracos).
    var modes := _modes()
    var n := mini(4, modes.size())
    var reflow: bool = n != ui.all_modes().size()
    if reflow:
        draw_texture_rect_region(ART, AREA, AREA_FILL_SRC)
        for i in n:
            var j := _art_index(String(modes[i][0]))
            var src := Rect2(CARD_SRC.position + Vector2((j % 2) * CARD_DX, (j / 2) * CARD_DY), CARD_SRC.size)
            draw_texture_rect_region(ART, Rect2(CARD_SRC.position + _slot(i, n), CARD_SRC.size), src)
        if n == 0:
            _center(TITLE_FONT, "RANQUEADA TEMPORARIAMENTE INDISPONÍVEL", 564, 600, 38, 900, Color("f6d27a"), 7, Color(0.12, 0.06, 0.0, 0.9))
            _center(font, "Novas filas serão abertas em breve.", 564, 650, 22, 800, Color("efe6cf"))
    for i in n:
        var item: Array = modes[i]
        var o := _slot(i, n)
        var ox := o.x
        var oy := o.y
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
    if not rated:
        # R35.1 · CONVIDAR AMIGO (casual): botão verde e ouro no mesmo estilo dos cartões
        var ir := INVITE
        draw_rect(ir, Color("0d2a1a") if hover != "invite" else Color("174a2c"))
        draw_rect(ir, Color("d9a441"), false, 2.0)
        draw_rect(ir.grow(-4), Color(0.85, 0.64, 0.25, 0.35), false, 1.0)
        _center(TITLE_FONT, "CONVIDAR AMIGO", ir.get_center().x, ir.get_center().y + 8, 24, ir.size.x - 20, Color("f6d27a"), 4, Color(0.1, 0.05, 0.0, 0.8))
