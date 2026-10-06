extends RefCounted
## FRAIHA Voice · ícone do microfone desenhado em pixel (mesmo estilo dos botões do HUD), usado no
## Xadrez (HudButton), na Marcha Real e no XEQUE (barras desenhadas à mão).
const RED := Color("e07a5f")
const LIVE := Color("7fd17a")

static func draw_mic(ci: CanvasItem, r: Rect2, state: String, col: Color, talking := false) -> void:
    var c := r.get_center()
    var s := minf(r.size.x, r.size.y)
    var w := maxf(2.0, s / 16.0)
    var body := Rect2(c + Vector2(-s * 0.13, -s * 0.36), Vector2(s * 0.26, s * 0.44))
    var main := col
    if state == "DISCONNECTED": main = col.darkened(0.15)
    # cápsula
    var sb := StyleBoxFlat.new()
    sb.bg_color = main if state in ["CONNECTED", "MUTED"] else Color(0, 0, 0, 0)
    sb.border_color = main
    sb.set_border_width_all(int(round(w)))
    sb.set_corner_radius_all(int(s * 0.13))
    ci.draw_style_box(sb, body)
    # suporte em U + haste + base
    ci.draw_arc(c + Vector2(0, -s * 0.06), s * 0.24, deg_to_rad(10), deg_to_rad(170), 16, main, w)
    ci.draw_line(c + Vector2(0, s * 0.18), c + Vector2(0, s * 0.32), main, w)
    ci.draw_line(c + Vector2(-s * 0.14, s * 0.33), c + Vector2(s * 0.14, s * 0.33), main, w)
    match state:
        "MUTED":
            ci.draw_line(c + Vector2(-s * 0.30, -s * 0.36), c + Vector2(s * 0.30, s * 0.30), RED, w * 1.3)
        "CONNECTED":
            ci.draw_circle(c + Vector2(s * 0.30, -s * 0.30), s * (0.085 if not talking else 0.11), LIVE)
            if talking:
                for k in [0.34, 0.44]:
                    ci.draw_arc(c + Vector2(0, -s * 0.12), s * k, deg_to_rad(-40), deg_to_rad(40), 8, LIVE, w * 0.8)
        "REQUESTING_PERMISSION", "CONNECTING", "RECONNECTING":
            var t := Time.get_ticks_msec() / 1000.0
            for i in 3:
                var a := 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 5.0 - i * 0.9))
                ci.draw_circle(c + Vector2(s * (0.22 + i * 0.1), s * 0.36), s * 0.04, Color(col, a))
        "ERROR":
            var p := c + Vector2(s * 0.30, -s * 0.28)
            ci.draw_circle(p, s * 0.12, RED)
            ci.draw_line(p + Vector2(0, -s * 0.06), p + Vector2(0, s * 0.02), Color("0b150f"), w * 0.9)
            ci.draw_circle(p + Vector2(0, s * 0.065), w * 0.45, Color("0b150f"))

## Fone de ouvido = ÁUDIO RECEBIDO da voz (diferente do alto-falante de música/efeitos do jogo).
## muted: risco vermelho (não estou ouvindo ninguém, mas continuo na sala).
static func draw_headphones(ci: CanvasItem, r: Rect2, muted: bool, col: Color) -> void:
    var c := r.get_center()
    var s := minf(r.size.x, r.size.y)
    var w := maxf(2.5, s / 12.0)
    var main := col if not muted else col.darkened(0.25)
    ci.draw_arc(c + Vector2(0, s * 0.06), s * 0.30, PI, TAU, 18, main, w)          # arco da cabeça
    for side in [-1.0, 1.0]:
        var cup := Rect2(c + Vector2(side * s * 0.30 - s * 0.11, s * 0.0), Vector2(s * 0.22, s * 0.32))
        ci.draw_rect(cup, main)                                                        # conchas
        ci.draw_line(c + Vector2(side * s * 0.30, s * 0.06), c + Vector2(side * s * 0.30, s * 0.02), main, w)
    if muted:
        ci.draw_line(c + Vector2(-s * 0.36, -s * 0.30), c + Vector2(s * 0.36, s * 0.36), RED, w * 1.3)

## R46 · Indicador de voz sobre o RETRATO de um assento da mesa (Marcha/XEQUE online). Só leitura do
## FraihaVoice; desenha nada fora da voz. seat = assento como o jogador vê (0 = eu); a sala usa o assento
## absoluto + 1 (o servidor gira a mesa para cada jogador: absoluto = (meu absoluto + seat) % 4).
static func draw_seat_voice(ci: CanvasItem, avatar: Rect2, voice, seat: int) -> void:
    if voice == null or not voice.active() or int(voice.my_uid) <= 0: return
    var uid := ((int(voice.my_uid) - 1 + seat) % 4) + 1
    var me := seat == 0
    if not me and not voice.remote.has(uid): return
    var talking: bool = voice.is_speaking(uid)
    if talking:
        for i in 3: ci.draw_rect(avatar.grow(4 + i * 2.0), Color(0.5, 0.95, 0.5, 0.6 - i * 0.18), false, 2.5)
    var side := clampf(avatar.size.x * 0.34, 18.0, 34.0)
    var b := Rect2(avatar.position + Vector2(-side * 0.3, avatar.size.y - side * 0.7), Vector2(side, side))
    ci.draw_circle(b.get_center(), side * 0.56, Color("0b150f"))
    ci.draw_arc(b.get_center(), side * 0.56, 0, TAU, 18, Color("d9b45e"), 1.5)
    var deaf: bool = (not me) and voice.is_participant_muted(uid)
    draw_headphones(ci, b.grow(-side * 0.12), deaf, LIVE if talking else Color("f4ce7f"))

## Badge "×" (sair da voz) no canto do botão; devolve o retângulo de toque.
static func draw_leave_badge(ci: CanvasItem, r: Rect2) -> Rect2:
    var rr := minf(r.size.x, r.size.y) * 0.2
    var c := Vector2(r.end.x - rr * 0.4, r.position.y + rr * 0.4)
    ci.draw_circle(c, rr, Color("0b150f"))
    ci.draw_arc(c, rr, 0, TAU, 16, Color("b99555"), 1.5)
    var a := rr * 0.45
    ci.draw_line(c + Vector2(-a, -a), c + Vector2(a, a), Color("f1e4c2"), 2.0)
    ci.draw_line(c + Vector2(-a, a), c + Vector2(a, -a), Color("f1e4c2"), 2.0)
    return Rect2(c - Vector2(rr, rr) * 1.3, Vector2(rr, rr) * 2.6)

## Texto curto de estado ao lado do botão (Marcha/XEQUE desenham à mão).
static func draw_status(ci: CanvasItem, right_x: float, center_y: float, width: float, txt: String, fs: int, col: Color) -> void:
    var font := ThemeDB.fallback_font
    var lines := [txt]
    if font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
        var cut := txt.find(" · ")
        lines = [txt.substr(0, cut), txt.substr(cut + 3)] if cut > 0 else [txt]
    var y := center_y - (lines.size() - 1) * fs * 0.6 + fs * 0.35
    for ln in lines:
        ci.draw_string_outline(font, Vector2(right_x - width, y), String(ln), HORIZONTAL_ALIGNMENT_RIGHT, width, fs, 4, Color("0b150f"))
        ci.draw_string(font, Vector2(right_x - width, y), String(ln), HORIZONTAL_ALIGNMENT_RIGHT, width, fs, col)
        y += fs * 1.2
