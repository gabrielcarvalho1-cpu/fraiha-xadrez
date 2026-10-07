extends Control
## R49 · VOCÊ SUBIU DE LIGA! — a arte de referência do dono (ranked/art/promo_modal.png, recorte da tela
## 1672 x 941) com os dados VIVOS do resultado por cima: nome da nova liga, "De X para Y", a linha do resultado,
## o "+N PL", "Progresso na Liga …", "N / 100 PL" e a barra. O título, o lema e os dois botões são da arte;
## os botões de verdade (mesmas ações de antes) ficam por cima, invisíveis, com brilho no hover.
## Escudo: o da arte é o de FERRO; outra liga recebe o brasão dela por cima (ThemeCatalog.badge_texture).
signal play_again
signal back_to_ranked
signal analyze

const ART := preload("res://ranked/art/promo_modal.png")
const ORIGIN := Vector2(430, 14)          # canto do recorte na tela de referência
const SCENE := Vector2(1672, 941)
const FONT_BOLD := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")
const ThemeCatalog := preload("res://cosmetics/theme_catalog.gd")
const Catalog := preload("res://league/catalog.gd")
const LEAGUES := ["Madeira", "Ferro", "Bronze", "Prata", "Ouro", "Platina", "Esmeralda", "Diamante", "Mestre", "Grande Mestre", "Challenger"]
# medidas na referência (px da tela 1672 x 941)
const SHIELD := Rect2(735, 250, 200, 252)
const BTN_AGAIN := Rect2(540, 788, 295, 64)
const BTN_BACK := Rect2(852, 788, 280, 64)
const BAR := Rect2(568, 739, 535, 20)

var data := {}
var k := 1.0
var off := Vector2.ZERO
var bar_now := 0.0
var bar_target := 0.0
var again: Button
var back: Button
var analyze_button: Button
var dim := true

func _init():
    name = "PromotionModal"
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    again = _hit("PromoPlayAgain", func(): play_again.emit())
    back = _hit("PromoBack", func(): back_to_ranked.emit())
    analyze_button = Button.new()
    analyze_button.name = "PromoAnalyze"
    analyze_button.text = "ANALISAR PARTIDA"
    analyze_button.focus_mode = Control.FOCUS_NONE
    analyze_button.flat = true
    analyze_button.add_theme_font_override("font", FONT_BOLD)
    analyze_button.add_theme_color_override("font_color", Color("f4ce7f"))
    analyze_button.add_theme_color_override("font_hover_color", Color("ffe6a0"))
    analyze_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    analyze_button.pressed.connect(func(): analyze.emit())
    analyze_button.hide()
    add_child(analyze_button)
    hide()

func _hit(nm: String, action: Callable) -> Button:
    var b := Button.new()
    b.name = nm
    b.focus_mode = Control.FOCUS_NONE
    for st in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    b.pressed.connect(action)
    b.mouse_entered.connect(queue_redraw)
    b.mouse_exited.connect(queue_redraw)
    add_child(b)
    return b

## r = ranked_result do servidor (promoted = true). can_analyze: a análise está liberada para esta partida.
func open(r: Dictionary, can_analyze: bool):
    data = r.duplicate()
    bar_now = 0.0
    bar_target = clampf(float(r.get("pl_after", 0)), 0.0, 100.0)
    analyze_button.visible = can_analyze
    show()
    _layout()
    queue_redraw()

func _notification(what):
    if what == NOTIFICATION_RESIZED and visible: _layout()

func _layout():
    var vs := get_viewport_rect().size
    var art := ART.get_size()
    # PC: mesma escala da cena de referência (a moldura ocupa a altura da tela); celular em pé: cabe na largura.
    k = minf(vs.x / SCENE.x, vs.y / SCENE.y)
    if vs.x < vs.y: k = minf((vs.x - 8.0) / art.x, (vs.y - 60.0) / art.y)
    off = (vs - art * k) / 2.0 - ORIGIN * k
    if vs.x < vs.y: off.y -= 20.0
    _place(again, BTN_AGAIN)
    _place(back, BTN_BACK)
    var fs := int(round(16.0 * k)) if vs.x > vs.y else maxi(13, int(round(16.0 * k * 1.3)))
    analyze_button.add_theme_font_size_override("font_size", fs)
    analyze_button.reset_size()
    var bottom := P(Vector2(0, ORIGIN.y + art.y)).y
    analyze_button.position = Vector2((vs.x - analyze_button.size.x) / 2.0, minf(bottom + 2.0, vs.y - analyze_button.size.y - 4.0))

func P(p: Vector2) -> Vector2:
    return off + p * k

func R(r: Rect2) -> Rect2:
    return Rect2(P(r.position), r.size * k)

func _place(b: Control, r: Rect2):
    b.position = R(r).position
    b.size = R(r).size

func _process(delta):
    if not visible: return
    if bar_now != bar_target:
        bar_now = move_toward(bar_now, bar_target, 40.0 * delta)
        queue_redraw()

func _text_center(font: Font, txt: String, cx: float, base: float, fs: float, color: Color, outline := 0, out_col := Color(0, 0, 0, 0.7), max_w := 0.0):
    var px := int(round(fs * k))
    if max_w > 0.0:
        while px > 8 and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_w * k: px -= 1
    var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
    var p := P(Vector2(cx, base)) - Vector2(w / 2.0, 0)
    if outline > 0: draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, int(round(outline * k)), out_col)
    draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _text(font: Font, txt: String, x: float, base: float, fs: float, color: Color, align_right := false):
    var px := int(round(fs * k))
    var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
    var p := P(Vector2(x, base)) - Vector2(w if align_right else 0.0, 0)
    draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, int(maxf(2.0, 3.0 * k)), Color(0, 0, 0, 0.68))
    draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _draw():
    if not visible: return
    if dim: draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.68))
    var art := ART.get_size()
    draw_texture_rect(ART, Rect2(P(ORIGIN), art * k), false)
    var before := clampi(int(data.get("league_before", 0)), 0, LEAGUES.size() - 1)
    var after := clampi(int(data.get("league_after", 0)), 0, LEAGUES.size() - 1)
    # brasão da nova liga (a arte traz o de Ferro)
    if after != 1:
        var badge: Texture2D = ThemeCatalog.badge_texture(Catalog.IDS[after])
        if badge != null:
            var sr := R(SHIELD)
            draw_circle(sr.get_center(), sr.size.x * 0.52, Color(0.03, 0.08, 0.05, 0.85))
            var ts := badge.get_size()
            var sc := minf(sr.size.x / ts.x, sr.size.y / ts.y)
            draw_texture_rect(badge, Rect2(sr.get_center() - ts * sc / 2.0, ts * sc), false)
    var font := get_theme_default_font()
    # NOME DA LIGA (grande, dourado, contorno escuro)
    _text_center(FONT_BOLD, LEAGUES[after].to_upper(), 835, 546, 64, Color("f7d77f"), 8, Color(0.16, 0.08, 0.0, 0.95), 420)
    _text_center(FONT_SEMI, "De %s para %s" % [LEAGUES[before], LEAGUES[after]], 835, 575, 22, Color("f1ece0"), 3, Color(0, 0, 0, 0.6), 420)
    # linha do resultado + PL ganho
    var outcome: String = {"win": "Vitória", "loss": "Derrota", "draw": "Empate"}.get(String(data.get("outcome", "win")), "Vitória")
    var parts := [outcome]
    for key in ["mode_name", "reason_text"]:
        var v := String(data.get(key, ""))
        if not v.is_empty(): parts.append(v)
    _text(font, "  ·  ".join(parts), 567, 668, 20, Color("efe8d8"))
    var ch := int(data.get("pl_change", 0))
    _text_center(FONT_BOLD, ("%+d PL" % ch) if ch != 0 else "0 PL", 1043, 673, 31, Color("f7d77f"), 4, Color(0.12, 0.06, 0.0, 0.9), 130)
    # progresso na liga nova
    _text(font, "Progresso na Liga %s" % LEAGUES[after], 564, 722, 17, Color("ece6d6"))
    _text(font, "%d / 100 PL" % int(data.get("pl_after", 0)), 1105, 722, 17, Color("ece6d6"), true)
    var br := R(BAR)
    if bar_now > 0.0:
        var fr := Rect2(br.position, Vector2(br.size.x * bar_now / 100.0, br.size.y)).grow(-2.0 * k)
        draw_rect(fr, Color("c99a3c"))
        draw_rect(Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.45)), Color(1.0, 0.92, 0.6, 0.35))
    # brilho dos botões no hover
    for b in [again, back]:
        if b.is_hovered(): draw_rect(Rect2(b.position, b.size).grow(-6.0 * k), Color(1.0, 0.88, 0.5, 0.12))
