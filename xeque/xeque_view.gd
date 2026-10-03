extends Control
## XEQUE — desenho das telas. Tudo é desenhado em coordenadas da tela de referência do formato
## (PC 1920x1080, celular retrato 1080x1920, celular paisagem 1950x900) e escalado para a janela.
## As posições abaixo foram medidas nas telas de referência aprovadas (telas_referencia/*.jpg):
## a cena da mesa casa com o tabuleiro do JSON; relógio e cartas da mão foram ajustados pixel a pixel.
const Rules := preload("res://xeque/rules.gd")

# ---------------------------------------------------------------- medidas por formato
const LAYOUTS := {
    "desktop": {
        "scene": [1.1832, Vector2(-29.2, -112.6)], "board": Rect2(650, 208, 620, 536),
        "title": [Vector2(20, 92), 96], "sub": [Vector2(20, 127), 23],
        "mesa": Rect2(42, 173, 356, 190), "como": Rect2(42, 393, 356, 333),
        "plates": {0: ["h", Rect2(48, 895, 344, 130)], 1: ["v", Vector2(506, 476), 190], 2: ["hc", Rect2(816, 10, 288, 112)], 3: ["v", Vector2(1414, 476), 190]},
        "turn": Rect2(1525, 36, 350, 68), "meter": Rect2(1522, 158, 356, 142),
        "xeque": [Vector2(1700, 640), 0.92], "play": Rect2(1525, 757, 350, 80),
        "hint": [Vector2(1700, 912), 24], "help": Rect2(1752, 993, 54, 54), "menu": Rect2(1813, 993, 54, 54),
        "music": Rect2(1630, 993, 54, 54), "fx": Rect2(1691, 993, 54, 54),
        "hand": [Vector2(960, 930), 0.212], "pile": [Vector2(960, 530), 0.128], "clock": [Vector2(960, 333), 0.22],
        "reveal": [Vector2(960, 528), 0.19], "mate_clock": [Vector2(960, 262), 0.36], "mate_title": [Vector2(960, 862), 196],
        "mate_line": [Vector2(960, 958), 33],
    },
    "portrait": {
        "scene": [1.7176, Vector2(-895.9, 55.5)], "board": Rect2(90, 521, 900, 778),
        "title": [Vector2(86, 86), 84], "sub": [Vector2(86, 117), 22],
        "mesa": Rect2(700, 5, 320, 157), "como": null,
        "plates": {0: ["h", Rect2(62, 1444, 356, 136)], 1: ["v", Vector2(190, 330), 214], 2: ["v", Vector2(540, 330), 214], 3: ["v", Vector2(890, 330), 214]},
        "turn": Rect2(350, 1361, 380, 62), "meter": Rect2(708, 1452, 300, 120),
        "xeque": [Vector2(184, 1846), 0.768], "play": Rect2(405, 1805, 630, 82),
        "hint": null, "help": Rect2(470, 22, 60, 60), "menu": Rect2(540, 22, 60, 60),
        "music": Rect2(330, 22, 60, 60), "fx": Rect2(400, 22, 60, 60),
        "hand": [Vector2(540, 1664), 0.167], "pile": [Vector2(540, 988), 0.18], "clock": [Vector2(540, 703), 0.32],
        "reveal": [Vector2(540, 960), 0.25], "mate_clock": [Vector2(540, 690), 0.48], "mate_title": [Vector2(540, 1252), 128],
        "mate_line": [Vector2(540, 1326), 27],
    },
    "landscape": {
        "scene": [0.9924, Vector2(145.4, -125.9)], "board": Rect2(715, 143, 520, 450),
        "title": [Vector2(38, 76), 80], "sub": [Vector2(38, 102), 20],
        "mesa": Rect2(40, 130, 320, 170), "como": null,
        "plates": {0: ["h", Rect2(40, 460, 320, 120)], 1: ["v", Vector2(560, 368), 180], 2: ["hc", Rect2(857, 2, 236, 90)], 3: ["v", Vector2(1390, 368), 180]},
        "turn": Rect2(42, 342, 318, 62), "meter": Rect2(1590, 56, 320, 128),
        "xeque": [Vector2(1750, 360), 0.837], "play": Rect2(1581, 459, 326, 96),
        "hint": [Vector2(1750, 632), 22], "help": Rect2(1798, 2, 50, 48), "menu": Rect2(1856, 2, 50, 48),
        "music": Rect2(1682, 2, 50, 48), "fx": Rect2(1740, 2, 50, 48),
        "hand": [Vector2(975, 772), 0.183], "pile": [Vector2(975, 413), 0.122], "clock": [Vector2(975, 248), 0.185],
        "reveal": [Vector2(975, 400), 0.16], "mate_clock": [Vector2(975, 222), 0.31], "mate_title": [Vector2(975, 690), 124],
        "mate_line": [Vector2(975, 800), 26],
    },
}
const STATUS_COLOR := {"aguardando": Color("e8b242"), "sua_vez": Color("ffd257"), "pensando": Color("6fb4ee"), "declarou": Color("e8b242"),
    "em_risco": Color("e02a36"), "com_o_relogio": Color("b068ff"), "xeque_mate": Color("e02a36"), "eliminado": Color("6b6f72")}

var ui
var grey_avatars := {}
var vignette: ImageTexture = null
var vignette_layout := ""

## Escurecimento das bordas do salão medido nas telas de referência (razão referência/cena em blocos):
## ~0,93 sobre o tabuleiro, caindo para ~0,55 nas laterais e ~0,45 nos cantos de cima.
func _vignette() -> ImageTexture:
    if vignette != null and vignette_layout == ui.layout: return vignette
    var d: Vector2 = ui.design
    var b: Rect2 = L().board
    var w := int(d.x / 8.0)
    var h := int(d.y / 8.0)
    var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
    var c := b.get_center()
    for y in h:
        for x in w:
            var px := Vector2(x * 8.0 + 4.0, y * 8.0 + 4.0)
            var dx := (px.x - c.x) / (b.size.x * 1.55)
            var dy := (px.y - c.y) / (b.size.y * 1.12)
            var dist := sqrt(dx * dx + dy * dy)
            var tt := pow(clampf((dist - 0.35) / 0.6, 0.0, 1.0), 1.3)
            var f := 0.94 - 0.44 * tt
            img.set_pixel(x, y, Color(0.02, 0.012, 0.008, 1.0 - f))
    vignette = ImageTexture.create_from_image(img)
    vignette_layout = ui.layout
    return vignette

func _init():
    mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event):
    var pos := Vector2.INF
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed: pos = event.position
        else: ui.pressed_id = ""
    elif event is InputEventScreenTouch and event.pressed and not _emulated_mouse(): pos = event.position
    elif event is InputEventMouseMotion:
        ui.on_hover((event.position - ui.origin) / ui.k)
        return
    if pos == Vector2.INF: return
    accept_event()
    var p: Vector2 = (pos - ui.origin) / ui.k
    for h in range(ui.hits.size() - 1, -1, -1):
        if Rect2(ui.hits[h].rect).has_point(p):
            ui.pressed_id = String(ui.hits[h].id)
            break
    ui.on_press(p)

## No celular o toque também chega como clique emulado: tratar os dois = ação dupla.
static func _emulated_mouse() -> bool:
    return bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true))

# ---------------------------------------------------------------- primitivas
func L() -> Dictionary:
    return LAYOUTS[ui.layout]

func font(key: String) -> Font:
    return ui.fonts[key]

func text(s: String, pos: Vector2, key: String, fs: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 0, ocol := Color("120a06")):
    if outline > 0: draw_string_outline(font(key), pos, s, align, width, fs, outline, ocol)
    draw_string(font(key), pos, s, align, width, fs, col)

func tw(s: String, key: String, fs: int) -> float:
    return font(key).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

func fit(s: String, key: String, fs: int, room: float) -> int:
    var f := fs
    while f > 9 and tw(s, key, f) > room: f -= 1
    return f

## Texto com trechos destacados entre *asteriscos* (cor de destaque).
func rich(s: String, center: Vector2, key: String, fs: int, col: Color, hi: Color):
    var parts := s.split("*")
    var total := 0.0
    for p in parts: total += tw(p, key, fs)
    var x := center.x - total / 2.0
    for i in parts.size():
        text(parts[i], Vector2(x, center.y), key, fs, hi if i % 2 == 1 else col)
        x += tw(parts[i], key, fs)

## Retângulo de cantos chanfrados em degraus de pixel (2 degraus), como os painéis da referência.
func stair(r: Rect2, d: float, col: Color):
    draw_rect(Rect2(r.position.x + 2 * d, r.position.y, r.size.x - 4 * d, r.size.y), col)
    draw_rect(Rect2(r.position.x + d, r.position.y + d, r.size.x - 2 * d, r.size.y - 2 * d), col)
    draw_rect(Rect2(r.position.x, r.position.y + 2 * d, r.size.x, r.size.y - 4 * d), col)

## Painel verde com moldura dourada (placas, A MESA PEDE, COMO JOGAR, medidor).
func panel(r: Rect2, border: Color = Color("e8b242"), glow := false, fill_top: Color = Color("154031"), fill_bot: Color = Color("0f2a1e")):
    if glow:
        for i in 5: stair(r.grow(4 + i * 3), 3, Color(border.r, border.g, border.b, 0.13 - i * 0.022))
    stair(r.grow(3), 3, Color("120a06"))
    stair(r, 3, border)
    var inner := r.grow(-3)
    stair(inner, 2, fill_bot)
    var g := inner.grow(-2)
    draw_polygon(PackedVector2Array([g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]),
        PackedColorArray([fill_top, fill_top, fill_bot, fill_bot]))
    # brilho do ouro no alto da moldura
    draw_rect(Rect2(r.position.x + 6, r.position.y, r.size.x - 12, 1), Color(1, 0.95, 0.7, 0.55))

func chip(r: Rect2, label: String, fill: Color, border: Color, col: Color, fs := 18):
    draw_rect(r.grow(1), Color("120a06"))
    draw_rect(r, border)
    draw_rect(r.grow(-2), fill)
    var f := fit(label, "ui_sp", fs, r.size.x - 10)
    text(label, Vector2(r.position.x, r.position.y + r.size.y / 2.0 + f * 0.36), "ui_sp", f, col, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)

func tex_center(tex: Texture2D, c: Vector2, sc: float, rot := 0.0, mod: Color = Color.WHITE):
    var sz := tex.get_size() * sc
    if rot == 0.0:
        draw_texture_rect(tex, Rect2(c - sz / 2.0, sz), false, mod)
        return
    draw_set_transform(ui.origin + c * ui.k, rot, Vector2(ui.k, ui.k))
    draw_texture_rect(tex, Rect2(-sz / 2.0, sz), false, mod)
    draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))

## 9 fatias: o botão aprovado esticado sem deformar cantos e bordas.
func nine(tex: Texture2D, r: Rect2, m: float, sm: float, mod: Color = Color.WHITE):
    var s := tex.get_size()
    var xs := [0.0, m, s.x - m, s.x]
    var ys := [0.0, m, s.y - m, s.y]
    var dx := [r.position.x, r.position.x + m * sm, r.end.x - m * sm, r.end.x]
    var dy := [r.position.y, r.position.y + m * sm, r.end.y - m * sm, r.end.y]
    for i in 3:
        for j in 3:
            draw_texture_rect_region(tex, Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j]), Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j]), mod)

func hit(r: Rect2, id: String):
    ui.hits.append({"rect": r, "id": id})

## r = parte visível do botão (o PNG tem 10 px de margem transparente em volta do corpo 380x100).
func button_gold(r: Rect2, label: String, id: String, enabled := true, fs := 44):
    var hov: bool = ui.hover_id == id and enabled
    var down: bool = ui.pressed_id == id and enabled
    var sm := r.size.y / 100.0
    if enabled:
        nine(ui.BTN_GOLD, r.grow(10 * sm + (2 if hov else 0)), 26, sm, Color(1.08, 1.06, 1.0) if hov else Color.WHITE)
        var f := fit(label, "ui_sp", fs, r.size.x - 40 * sm)
        text(label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + f * 0.36 + (2 if down else 0)), "ui_sp", f, Color("2a1505"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        hit(r, id)
    else:
        nine(ui.BTN_DARK, r.grow(10 * sm), 26, sm)
        var f2 := fit(label, "ui_sp", fs, r.size.x - 40 * sm)
        text(label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + f2 * 0.36), "ui_sp", f2, Color(0.96, 0.92, 0.82, 0.62), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)

func button_dark(r: Rect2, label: String, id: String, fs := 40):
    var hov: bool = ui.hover_id == id
    var sm := r.size.y / 100.0
    nine(ui.BTN_DARK, r.grow(10 * sm + (2 if hov else 0)), 26, sm, Color(1.15, 1.15, 1.1) if hov else Color.WHITE)
    var f := fit(label, "ui_sp", fs, r.size.x - 40 * sm)
    text(label, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + f * 0.36), "ui_sp", f, Color("f6ecd2"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
    hit(r, id)

## MÚSICA / EFEITOS: liga e desliga só a música ou só os efeitos sonoros.
func sound_button(r: Rect2, kind: String):
    var id := "mute_music" if kind == "music" else "mute_fx"
    var off: bool = ui.Sound.music_muted(ui.hub) if kind == "music" else ui.Sound.effects_muted(ui.hub)
    var hov: bool = ui.hover_id == id
    panel(r, Color("e8b242") if not hov else Color("ffeea5"), false, Color("12382a"), Color("0b2219"))
    ui.Sound.glyph(self, r.grow(-6), kind, off, Color("f6ecd2") if not off else Color("8d9092"))
    hit(r, id)

func square_button(r: Rect2, glyph: String, id: String):
    var hov: bool = ui.hover_id == id
    panel(r, Color("e8b242") if not hov else Color("ffeea5"), false, Color("12382a"), Color("0b2219"))
    if glyph == "menu":
        for i in 3: draw_rect(Rect2(r.position.x + r.size.x * 0.3, r.position.y + r.size.y * (0.36 + i * 0.13), r.size.x * 0.4, 3), Color("f6ecd2"))
    else:
        text(glyph, Vector2(r.position.x, r.position.y + r.size.y * 0.72), "ui", int(r.size.y * 0.62), Color("f6ecd2"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
    hit(r, id)

# ---------------------------------------------------------------- desenho principal
func _draw():
    if ui == null: return
    ui.hits.clear()
    var vs := size
    draw_rect(Rect2(Vector2.ZERO, vs), Color("070b0a"))
    # telas 16:9 (tutorial e resultado) usam o desenho do PC também no celular deitado
    var dsg: Vector2 = ui.design
    if ui.mode in ["tutorial", "over"] and ui.layout == "landscape": dsg = Vector2(1920, 1080)
    ui.k = minf(vs.x / dsg.x, vs.y / dsg.y)
    ui.origin = (vs - dsg * ui.k) / 2.0
    draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
    match ui.mode:
        "game": _draw_game()
        "tutorial": _draw_tutorial(dsg)
        "over": _draw_result(dsg)
    if ui.menu_open: _draw_menu()
    if ui.confirm_quit: _draw_confirm()
    if not ui.flash.is_empty(): _draw_flash()
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------- partida
func _draw_scene():
    var sc: Array = L().scene
    var s: float = sc[0]
    var o: Vector2 = sc[1]
    draw_texture_rect(ui.SCENE, Rect2(o, Vector2(1672, 941) * s), false)
    var d: Vector2 = ui.design
    draw_texture_rect(_vignette(), Rect2(Vector2.ZERO, d), false)
    var end_y: float = o.y + 941 * s
    # escurece até o fundo (como nas referências: a mão fica sobre a sombra do salão)
    var fade := 240.0
    draw_polygon(PackedVector2Array([Vector2(0, end_y - fade), Vector2(d.x, end_y - fade), Vector2(d.x, end_y), Vector2(0, end_y)]),
        PackedColorArray([Color(0.027, 0.043, 0.04, 0), Color(0.027, 0.043, 0.04, 0), Color("070b0a"), Color("070b0a")]))
    if end_y < d.y: draw_rect(Rect2(0, end_y, d.x, d.y - end_y), Color("070b0a"))
    if o.y > 0: draw_rect(Rect2(0, 0, d.x, o.y), Color("070b0a"))
    if o.x > 0:
        draw_rect(Rect2(0, 0, o.x, d.y), Color("070b0a"))
        draw_polygon(PackedVector2Array([Vector2(o.x, 0), Vector2(o.x + 90, 0), Vector2(o.x + 90, d.y), Vector2(o.x, d.y)]),
            PackedColorArray([Color("070b0a"), Color(0.027, 0.043, 0.04, 0), Color(0.027, 0.043, 0.04, 0), Color("070b0a")]))
    var right: float = o.x + 1672 * s
    if right < d.x:
        draw_rect(Rect2(right, 0, d.x - right, d.y), Color("070b0a"))
        draw_polygon(PackedVector2Array([Vector2(right - 90, 0), Vector2(right, 0), Vector2(right, d.y), Vector2(right - 90, d.y)]),
            PackedColorArray([Color(0.027, 0.043, 0.04, 0), Color("070b0a"), Color("070b0a"), Color(0.027, 0.043, 0.04, 0)]))

func _draw_game():
    var g = ui.g
    if g == null: return
    var lay := L()
    _draw_scene()
    _draw_title()
    _draw_mesa_pede()
    if lay.como != null: _draw_como_jogar(lay.como)
    var mate: bool = ui.phase in ["mate", "elim"]
    # relógio do centro (o de quem está em foco)
    if not mate: _draw_center_clock()
    _draw_pile()
    for s in 4:
        if mate and s == int(ui.result.loser): continue
        _draw_plate(s)
    _draw_bubble()
    _draw_turn_banner()
    _draw_meter()
    _draw_xeque_button(false)
    _draw_play_button()
    _draw_hint()
    square_button(lay.help, "?", "help")
    square_button(lay.menu, "menu", "menu")
    sound_button(lay.music, "music")
    sound_button(lay.fx, "fx")
    if not mate: _draw_hand()
    _draw_fly()
    if ui.phase in ["reveal", "clock", "safe"]: _draw_reveal(false)
    if ui.mesa_anim >= 0.0 and ui.phase == "": _draw_mesa_anim()
    if ui.phase == "safe": _draw_safe()
    if mate: _draw_mate()

## Rodada nova: a carta da MESA vira no centro da mesa e voa para o painel A MESA PEDE.
func _draw_mesa_anim():
    var g = ui.g
    var t: float = ui.mesa_anim
    var d: Vector2 = ui.design
    var tex: Texture2D = ui.cards[g.target]
    var center: Vector2 = Rect2(L().board).get_center()
    var big := minf(d.y * 0.42, 460.0) / 504.0
    var mr: Rect2 = L().mesa
    var shade := clampf(t / 0.25, 0.0, 1.0) * (1.0 - clampf((t - 1.2) / 0.4, 0.0, 1.0))
    draw_rect(Rect2(Vector2(-4000, -4000), Vector2(12000, 12000)), Color(0, 0, 0, 0.55 * shade))
    var pos := center
    var sc := big
    var flip := 1.0
    if t < 0.5:
        # entra virada para baixo e gira mostrando a peça
        var k := t / 0.5
        flip = absf(cos(k * PI))
        if k < 0.5: tex = ui.CARD_BACK
        sc = big * (0.6 + 0.4 * ease(k, 0.4))
    elif t > 1.2:
        var k := ease(clampf((t - 1.2) / 0.55, 0.0, 1.0), 2.2)
        pos = center.lerp(mr.get_center(), k)
        sc = lerpf(big, (mr.size.y * 0.8) / 504.0, k)
    var a := 1.0 - clampf((t - 1.7) / 0.2, 0.0, 1.0)
    var sz := tex.get_size() * sc
    draw_set_transform(ui.origin + pos * ui.k, 0.0, Vector2(ui.k * maxf(0.04, flip), ui.k))
    if t >= 0.5 and t < 1.2:
        for i in 5: draw_rect(Rect2(-sz / 2.0, sz).grow(6 + i * 6), Color(1, 0.84, 0.35, 0.13 - i * 0.022), false, 6.0)
    draw_rect(Rect2(-sz / 2.0, sz).grow(3), Color(0, 0, 0, 0.5 * a))
    draw_texture_rect(tex, Rect2(-sz / 2.0, sz), false, Color(1, 1, 1, a))
    draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
    if t >= 0.45 and t < 1.3:
        var ta := clampf((t - 0.45) / 0.2, 0.0, 1.0) * (1.0 - clampf((t - 1.1) / 0.2, 0.0, 1.0))
        var label := "A MESA PEDE"
        var nm: String = String(Rules.NAMES[g.target]).to_upper()
        var ty := pos.y - sz.y / 2.0 - 22
        text(label, Vector2(0, ty - 54), "ui_sp4", 34, Color(0.91, 0.7, 0.26, ta), d.x, HORIZONTAL_ALIGNMENT_CENTER, 6, Color(0.07, 0.04, 0.02, ta))
        text(nm, Vector2(0, ty), "title", 64, Color(1, 0.93, 0.7, ta), d.x, HORIZONTAL_ALIGNMENT_CENTER, 8, Color(0.16, 0.07, 0.02, ta))
        text("RODADA %d" % g.round_no, Vector2(0, pos.y + sz.y / 2.0 + 44), "ui_sp4", 26, Color(0.96, 0.92, 0.82, ta), d.x, HORIZONTAL_ALIGNMENT_CENTER, 5, Color(0.07, 0.04, 0.02, ta))

func _draw_title():
    var lay := L()
    var tp: Array = lay.title
    text("Xeque", tp[0], "title", tp[1], Color("f2c050"), -1, HORIZONTAL_ALIGNMENT_LEFT, 8, Color("2a1206"))
    draw_string(font("title"), tp[0] + Vector2(0, -2), "Xeque", HORIZONTAL_ALIGNMENT_LEFT, -1, tp[1], Color(1, 0.93, 0.62, 0.35))
    var sp: Array = lay.sub
    var sub := "RODADA %d · BLEFE DE CARTAS" % ui.g.round_no if ui.layout != "portrait" else "RODADA %d" % ui.g.round_no
    text(sub, sp[0], "ui_sp4", sp[1], Color("caa14a"), -1, HORIZONTAL_ALIGNMENT_LEFT, 2, Color(0.07, 0.04, 0.02, 0.85))

func _draw_mesa_pede():
    var r: Rect2 = L().mesa
    var g = ui.g
    # destaque permanente: brilho dourado pulsando em volta do painel
    var pulse := 0.5 + 0.5 * sin(ui.t * 3.2)
    for i in 6: stair(r.grow(5 + i * 4), 4, Color(1.0, 0.82, 0.3, (0.16 - i * 0.025) * (0.6 + 0.4 * pulse)))
    var landing: float = clampf((ui.mesa_anim - 1.45) / 0.45, 0.0, 1.0) if ui.mesa_anim >= 0.0 else 0.0
    panel(r, Color("ffd257").lerp(Color("fff3c0"), landing), true)
    var compact: bool = ui.layout == "portrait"
    var pad := 18.0 if compact else 20.0
    text("A MESA PEDE", r.position + Vector2(pad, 33 if compact else 35), "ui_sp4", 19 if compact else 21, Color("e8b242"))
    var name: String = Rules.NAMES[g.target]
    var plural: String = Rules.PLURAL[g.target]
    var icon: Texture2D = ui.pieces[g.target]
    var ih := (r.size.y - 66.0) if compact else (r.size.y - 82.0)
    var isz := icon.get_size() * (ih / icon.get_size().y)
    var ipos := r.position + Vector2(pad, (46 if compact else 57))
    draw_texture_rect(icon, Rect2(ipos, isz), false)
    var x := ipos.x + maxf(isz.x, ih * 0.6) + (14 if compact else 16)
    var big := fit(name.to_upper(), "ui", 66 if compact else 78, r.end.x - x - 12)
    text(name.to_upper(), Vector2(x, r.position.y + (101 if compact else 107)), "ui", big, Color("f6ecd2"), -1, HORIZONTAL_ALIGNMENT_LEFT, 5, Color("120a06"))
    if compact:
        text("Diga que são %s" % plural.to_lower(), Vector2(x, r.position.y + 131), "ui_sp", fit("Diga que são %s" % plural.to_lower(), "ui_sp", 21, r.end.x - x - 8), Color("e8dcc0"))
    else:
        text("Diga que suas cartas", Vector2(x, r.position.y + 137), "ui_sp", 21, Color("e8dcc0"))
        text("são %s" % plural.to_lower(), Vector2(x, r.position.y + 164), "ui_sp", fit("são %s" % plural.to_lower(), "ui_sp", 21, r.end.x - x - 8), Color("e8dcc0"))

func _draw_como_jogar(r: Rect2):
    panel(r)
    text("COMO JOGAR", r.position + Vector2(20, 36), "ui_sp4", 21, Color("e8b242"))
    var steps := [["A mesa pede uma peça."], ["Baixe de 1 a 3 cartas", "viradas e diga que são", "essa peça."], ["Duvidou de alguém? *XEQUE!*"], ["Quem errou aciona o seu", "Relógio. Se disparar, é", "xeque-mate: está fora."]]
    var y := r.position.y + 67
    for i in steps.size():
        var nb := Rect2(r.position.x + 20, y - 12, 28, 28)
        draw_rect(nb.grow(1), Color("120a06"))
        draw_rect(nb, Color("e8b242"))
        text(str(i + 1), Vector2(nb.position.x, nb.position.y + 22), "ui", 22, Color("2a1505"), nb.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        for line in steps[i]:
            var parts := String(line).split("*")
            var x := r.position.x + 60
            for j in parts.size():
                text(parts[j], Vector2(x, y + 9), "ui_sp", 22, Color("ff5a52") if j % 2 == 1 else Color("f6ecd2"))
                x += tw(parts[j], "ui_sp", 22)
            y += 29.5
        y += 9

func _draw_center_clock():
    var c: Array = L().clock
    var pos: Vector2 = c[0]
    var vis: String = ui.clock_visual(ui.clock_focus())
    var tex: Texture2D = ui.clock_tex[vis]
    var shake := Vector2.ZERO
    if ui.phase == "clock":
        shake = Vector2(sin(ui.t * 61.0), cos(ui.t * 47.0)) * 3.0
    elif vis == "quase":
        shake = Vector2(sin(ui.t * 40.0), 0) * 1.2
    var pulse := 1.0 + (0.02 * sin(ui.t * 9.0) if vis in ["pulsando", "quase"] or ui.phase == "clock" else 0.0)
    tex_center(tex, pos + shake, c[1] * 2.0 * pulse)      # versões do jogo têm metade do tamanho do arquivo aprovado

func _draw_pile():
    var g = ui.g
    var n := 0
    for p in g.plays: n += int(p.count)
    var showing: bool = ui.phase in ["reveal", "clock", "safe", "mate", "elim"]
    if showing: n -= int(ui.result.cards.size())
    for f in ui.fly: n -= int(f.count)
    n = clampi(n, 0, 6)
    var pl: Array = L().pile
    var rots := [-0.26, -0.08, 0.1, 0.24, -0.16, 0.18]
    var offs := [Vector2(-34, 8), Vector2(-10, -4), Vector2(14, 2), Vector2(32, 10), Vector2(-22, 14), Vector2(24, -8)]
    var sc: float = pl[1] * 2.0
    for i in n:
        tex_center(ui.CARD_BACK, pl[0] + offs[i] * (sc / 0.29), sc, rots[i])

func _seat_anchor(s: int) -> Vector2:
    var p: Array = L().plates[s]
    if p[0] == "v": return p[1]
    return Rect2(p[1]).get_center()

func _draw_fly():
    var pl: Array = L().pile
    for f in ui.fly:
        var from := _seat_anchor(int(f.from))
        if int(f.from) == 0: from = L().hand[0]
        var tt: float = ease(clampf(f.t, 0.0, 1.0), -2.0)
        for i in int(f.count):
            tex_center(ui.CARD_BACK, from.lerp(pl[0], tt) + Vector2(i * 12, i * -4), pl[1] * 2.0, -0.2 + i * 0.15)

# ---------------------------------------------------------------- placas
func _avatar(s: int, eliminated: bool) -> Texture2D:
    var a: Texture2D = ui.avatars[s]
    if not eliminated or a == null: return a
    if not grey_avatars.has(s):
        var img := a.get_image()
        if img.is_compressed(): img.decompress()
        img.resize(160, 160)
        for y in img.get_height():
            for x in img.get_width():
                var c := img.get_pixel(x, y)
                var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
                img.set_pixel(x, y, Color(l * 0.62, l * 0.62, l * 0.64, c.a))
        grey_avatars[s] = ImageTexture.create_from_image(img)
    return grey_avatars[s]

func _crowns(pos: Vector2, s: int, w: float, gap: float, eliminated := false):
    var g = ui.g
    var lives: int = g.lives[s]
    # durante o XEQUE-MATE a coroa perdida pisca antes de apagar
    var losing: bool = ui.phase in ["mate", "elim"] and int(ui.result.loser) == s
    var n: int = Rules.LIVES
    # o espaço é o das 3 coroas da arte; com 1 vida (regra da WePlay) a coroa fica centralizada
    pos.x += (3 - n) * (w + gap) / 2.0
    for i in n:
        var lost := i >= lives
        var tex: Texture2D = ui.CROWN_LOST if lost else ui.CROWN
        var mod := Color(0.55, 0.55, 0.55) if eliminated else Color.WHITE
        if losing and i == lives and ui.phase == "mate" and int(ui.t * 6.0) % 2 == 0: tex = ui.CROWN
        var h := w * 192.0 / 228.0
        draw_texture_rect(tex, Rect2(pos + Vector2(i * (w + gap), 0), Vector2(w, h)), false, mod)

func _cards_count(pos: Vector2, s: int, fs: int):
    var n: int = ui.g.hands[s].size()
    var h := fs * 1.05
    var w := h * 0.71
    draw_rect(Rect2(pos - Vector2(0, h * 0.82), Vector2(w, h)).grow(1), Color("120a06"))
    draw_texture_rect(ui.CARD_BACK, Rect2(pos - Vector2(0, h * 0.82), Vector2(w, h)), false)
    text("×%d" % n, pos + Vector2(w + 4, 0), "ui", fs, Color("f6ecd2"))

func _status_chip(r: Rect2, st: Dictionary, fs := 18):
    var id: String = st.id
    match id:
        "sua_vez": chip(r, st.text, Color("ffd257"), Color("ffd257"), Color("2a1505"), fs)
        "pensando": chip(r, st.text, Color("13314f"), Color("6fb4ee"), Color("9fd0ff"), fs)
        "em_risco": chip(r, st.text, Color("a3121f"), Color("e02a36"), Color("ffe3dc"), fs)
        "xeque_mate": chip(r, st.text, Color("d91f2d"), Color("ff5a52"), Color("fff3e8"), fs)
        "com_o_relogio": chip(r, st.text, Color("2a1544"), Color("b068ff"), Color("e6ccff"), fs)
        "eliminado": chip(r, st.text, Color("1c1d1d"), Color("4a4d4f"), Color("8d9092"), fs)
        _: chip(r, st.text, Color("0a1d15"), Color("3d5a4b"), Color("c9d6cf"), fs)

func _draw_plate(s: int):
    var g = ui.g
    var spec: Array = L().plates[s]
    var st: Dictionary = ui.seat_status(s)
    var elim: bool = st.id == "eliminado"
    var border: Color = STATUS_COLOR.get(st.id, Color("e8b242"))
    var glow: bool = st.id in ["xeque_mate", "com_o_relogio"]
    var fill_t := Color("1f2322") if elim else Color("154031")
    var fill_b := Color("141716") if elim else Color("0f2a1e")
    var name: String = g.names[s]
    var bot := s != 0
    var tag: String = ui.seat_tag(s)           # R35: "BOT" ou "AMIGO" (online)
    var namecol := Color("8d9092") if elim else Color("f6ecd2")
    match spec[0]:
        "h", "hc":
            var r: Rect2 = spec[1]
            var compact: bool = spec[0] == "hc"
            panel(r, border, glow, fill_t, fill_b)
            var av := r.size.y - (24.0 if compact else 30.0)
            var ar := Rect2(r.position + Vector2(11, (r.size.y - av) / 2.0), Vector2(av, av))
            draw_rect(ar.grow(3), Color("120a06"))
            draw_rect(ar.grow(2), Color("d8d0bf") if not elim else Color("555"))
            draw_texture_rect(_avatar(s, elim), ar, false)
            var x := ar.end.x + 9
            var nfs := 24 if compact else 30
            var top := r.position.y + (31 if compact else 40)
            nfs = fit(name, "ui", nfs, r.end.x - x - (52 if bot else 8))
            text(name, Vector2(x, top), "ui", nfs, namecol, -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
            if bot:
                var bx := x + tw(name, "ui", nfs) + 8
                chip(Rect2(bx, top - nfs * 0.78, (42 if compact else 48) * (1.45 if tag != "BOT" else 1.0), nfs * 0.92), tag, Color("9fd0ff") if not elim else Color("555"), Color("9fd0ff") if not elim else Color("555"), Color("13314f"), 15)
            var cw := 30.0 if compact else 36.0
            _crowns(Vector2(x + 2, top + (8 if compact else 12)), s, cw, cw * 0.27, elim)
            var ch := 24.0 if compact else 30.0
            var cy := r.end.y - ch - (12 if compact else 14)
            var label: String = st.text
            _status_chip(Rect2(x, cy, maxf(tw(label, "ui_sp", 17) + 22, 86), ch), st)
            if s != 0: _cards_count(Vector2(r.end.x - 52, r.end.y - 14), s, 20 if compact else 24)
        "v":
            # medidas da placa vertical tiradas da referência do celular em pé (placa de 214 px);
            # PC e paisagem usam as mesmas proporções (u = largura / 214)
            var c: Vector2 = spec[1]
            var w: float = spec[2]
            var u := w / 214.0
            var nfs := int(round(28 * u))
            nfs = fit(name, "ui", nfs, w - 16)
            var bw := 52.0 * u
            var bh := 22.0 * u
            var one_line := tw(name, "ui", nfs) + bw + 10 <= w - 16 or not bot
            var avs := 100.0 * u
            var h := (304.0 if not one_line else 278.0) * u
            var r := Rect2(c.x - w / 2.0, c.y - h / 2.0, w, h)
            ui.set_meta("plate_top_%d" % s, r.position.y)
            panel(r, border, glow, fill_t, fill_b)
            var ar := Rect2(c.x - avs / 2.0, r.position.y + 13 * u, avs, avs)
            draw_rect(ar.grow(4), Color("120a06"))
            draw_rect(ar.grow(3), Color("d8c08a") if not elim else Color("555"))
            draw_rect(ar.grow(1), Color("5a3a12") if not elim else Color("333"))
            draw_texture_rect(_avatar(s, elim), ar, false)
            var y := ar.end.y + 32 * u
            var bcol := Color("9fd0ff") if not elim else Color("555")
            if one_line:
                var total := tw(name, "ui", nfs) + (bw + 8 if bot else 0.0)
                var x0 := c.x - total / 2.0
                text(name, Vector2(x0, y), "ui", nfs, namecol, -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
                if bot: chip(Rect2(x0 + tw(name, "ui", nfs) + 8, y - nfs * 0.74, bw * (1.45 if tag != "BOT" else 1.0), bh), tag, bcol, bcol, Color("13314f"), int(18 * u))
                y += 21 * u
            else:
                text(name, Vector2(r.position.x, y), "ui", nfs, namecol, w, HORIZONTAL_ALIGNMENT_CENTER, 3)
                chip(Rect2(c.x - bw * (1.45 if tag != "BOT" else 1.0) / 2.0, y + 11 * u, bw * (1.45 if tag != "BOT" else 1.0), bh), tag, bcol, bcol, Color("13314f"), int(18 * u))
                y += 43 * u
            var cw := 36.0 * u
            _crowns(Vector2(c.x - (cw * 3 + cw * 0.36 * 2) / 2.0, y - 2 * u), s, cw, cw * 0.36, elim)
            y += 27 * u + 13 * u
            var label: String = st.text
            var chh := 30.0 * u
            var cfs := int(round(19 * u))
            var chw := minf(w - 18, maxf(tw(label, "ui_sp", cfs) + 28, 100 * u))
            _status_chip(Rect2(c.x - chw / 2.0, y, chw, chh), st, cfs)
            y += chh + 9 * u + 17 * u
            _cards_count(Vector2(c.x - 20 * u, y), s, int(round(22 * u)))

func _draw_bubble():
    var b: Dictionary = ui.bubble
    if b.is_empty() or ui.g == null or ui.phase in ["mate", "elim"]: return
    var s := int(b.seat)
    var spec: Array = L().plates[s]
    var label_n := str(int(b.count))
    var label_t: String = " × " + String(Rules.NAMES[String(b.target)]).to_upper()
    var fs := 26 if ui.layout != "portrait" else 28
    var w := tw(label_n, "ui", fs) + tw(label_t, "ui_sp", fs) + 28
    var h := 42.0
    var c: Vector2
    match spec[0]:
        "v": c = Vector2(spec[1].x, float(ui.get_meta("plate_top_%d" % s, spec[1].y - 140)) - h / 2.0 - 4)
        "hc": c = Vector2(Rect2(spec[1]).end.x + w / 2.0 + 10, Rect2(spec[1]).get_center().y)
        "h": c = Vector2(Rect2(spec[1]).end.x + w / 2.0 + 14, Rect2(spec[1]).position.y + h / 2.0 + 6)   # à direita: acima fica a faixa de turno
        _: c = Vector2(Rect2(spec[1]).get_center().x, Rect2(spec[1]).position.y - h / 2.0 - 6)
    var r := Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h))
    stair(r.grow(3), 3, Color("120a06"))
    stair(r, 3, Color("f6ecd2"))
    draw_rect(Rect2(r.position.x + 4, r.end.y - 4, r.size.x - 8, 2), Color("d6c7a1"))
    var x := r.position.x + 14
    text(label_n, Vector2(x, c.y + fs * 0.36), "ui", fs, Color("c8102e"))
    text(label_t, Vector2(x + tw(label_n, "ui", fs), c.y + fs * 0.36), "ui_sp", fs, Color("2a1505"))

func _draw_turn_banner():
    var r: Rect2 = L().turn
    var g = ui.g
    var col_a: Color
    var col_b: Color
    var label := ""
    var timer := ""
    var dark := Color("2a1505")
    if ui.phase != "":
        col_a = Color("ffb460"); col_b = Color("e07a2a"); label = "XEQUE!"
    elif g.state == Rules.TURN_WAITING and g.turn == 0:
        col_a = Color("ffe27a"); col_b = Color("f2b23a"); label = "SUA VEZ"
        var secs := int(ceil(ui.turn_left_ms / 1000.0))
        timer = "%d:%02d" % [secs / 60, secs % 60]
    elif g.state == Rules.TURN_WAITING:
        col_a = Color("9ed2ff"); col_b = Color("5d9fe0"); label = "VEZ DE " + String(g.names[g.turn]).to_upper(); dark = Color("0c2340")
    else:
        col_a = Color("ffe27a"); col_b = Color("f2b23a"); label = "RODADA %d" % g.round_no
    stair(r.grow(3), 3, Color("120a06"))
    stair(r, 3, col_b.darkened(0.25))
    var inner := r.grow(-3)
    draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]),
        PackedColorArray([col_a, col_a, col_b, col_b]))
    draw_rect(Rect2(inner.position.x + 4, inner.position.y + 3, inner.size.x - 8, 3), Color(1, 1, 1, 0.35))
    var fs := int(r.size.y * 0.62)
    var low: bool = timer != "" and ui.turn_left_ms <= ui.LOW_TIME_MS
    if timer == "":
        var f := fit(label, "ui_sp4", fs, r.size.x - 30)
        if ui.layout == "portrait":
            text(label, Vector2(r.position.x, r.get_center().y + f * 0.36), "ui_sp4", f, dark, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        else:
            text(label, Vector2(r.position.x + 20, r.get_center().y + f * 0.36), "ui_sp4", f, dark)
    else:
        text(label, Vector2(r.position.x + 20, r.get_center().y + fs * 0.36), "ui_sp4", fs, dark)
        var tcol := dark
        if low:
            # pouco tempo: o relógio da faixa pisca em vermelho
            tcol = Color("c8102e") if int(ui.t * 4.0) % 2 == 0 else dark
            draw_rect(r.grow(2), Color(0.88, 0.16, 0.2, 0.25 + 0.2 * sin(ui.t * 12.0)), false, 3.0)
        text(timer, Vector2(r.position.x, r.get_center().y + fs * 0.36), "ui_sp", fs, tcol, r.size.x - 20, HORIZONTAL_ALIGNMENT_RIGHT)

func _draw_meter():
    var r: Rect2 = L().meter
    var who: int = ui.clock_focus()
    var vis: String = ui.clock_visual(who)
    panel(r)
    var compact: bool = ui.layout != "desktop"
    text("RELÓGIO DE XEQUE", r.position + Vector2(18, 33 if not compact else 31), "ui_sp4", 21 if not compact else 19, Color("e8b242"))
    var total: int = Rules.CLOCK_SLOTS
    var used: int = total - ui.g.clock_left(who)
    if ui.phase in ["reveal", "clock"] and int(ui.result.loser) == who: used = total - int(ui.result.clock_left_before)
    var segs := total - 1                     # medidor de 5 casas da arte: apertos sobrevividos
    var lit := used
    if vis == "disparado": lit = segs
    var seg_col: Color = {"neutro": Color("e8b242"), "pulsando": Color("b068ff"), "perigo": Color("e02a36"), "quase": Color("e02a36"), "disparado": Color("e02a36")}[vis]
    var gap := 6.0
    var sx := r.position.x + 18
    var sw := (r.size.x - 36 - (segs - 1) * gap) / float(segs)
    var sy := r.position.y + (52 if not compact else 46)
    var shh := 26.0 if not compact else 22.0
    draw_rect(Rect2(sx - 3, sy - 3, r.size.x - 30, shh + 6), Color("0a1712"))
    for i in segs:
        var sr := Rect2(sx + i * (sw + gap), sy, sw, shh)
        draw_rect(sr, Color("10241b"))
        draw_rect(sr, Color("2d4a3c"), false, 2.0)
        if i < lit or (ui.phase == "clock" and int(ui.result.loser) == who and i == used and int(ui.t * 5) % 2 == 0):
            draw_rect(sr.grow(-2), seg_col)
            draw_rect(Rect2(sr.position.x + 2, sr.position.y + 2, sr.size.x - 4, 4), seg_col.lightened(0.35))
    var words: String = {"neutro": "NEUTRO", "pulsando": "PULSANDO", "perigo": "EM PERIGO", "quase": "QUASE DISPARANDO", "disparado": "DISPAROU!"}[vis]
    var wcol: Color = {"neutro": Color("e8b242"), "pulsando": Color("c58bff"), "perigo": Color("ff5a52"), "quase": Color("ff5a52"), "disparado": Color("ff5a52")}[vis]
    var fs := 30 if not compact else 26
    var ty := r.end.y - (22 if not compact else 18)
    text(words, Vector2(r.position.x + 18, ty), "ui_sp4", fit(words, "ui_sp4", fs, r.size.x * 0.62), wcol)
    var owner: String = ui.g.names[who]
    text(owner, Vector2(r.position.x, ty), "ui", fit(owner, "ui", 20, r.size.x * 0.34), Color("c9d6cf"), r.size.x - 18, HORIZONTAL_ALIGNMENT_RIGHT)

func _draw_xeque_button(active: bool):
    var x: Array = L().xeque
    var enabled: bool = ui.can_human_challenge()
    var state := "desabilitado"
    if active or ui.phase != "": state = "ativado"
    elif enabled:
        state = "normal"
        if ui.pressed_id == "xeque": state = "pressionado"
        elif ui.hover_id == "xeque": state = "hover"
    var tex: Texture2D = ui.xeque_tex[state]
    var sc: float = x[1]
    var pulse := 1.0
    if state == "ativado": pulse = 1.0 + 0.03 * sin(ui.t * 10.0)
    tex_center(tex, x[0], sc * pulse)
    if enabled and ui.phase == "": hit(Rect2(x[0] - Vector2(432, 202) * sc * 0.45, Vector2(432, 202) * sc * 0.9), "xeque")

func _draw_play_button():
    var r: Rect2 = L().play
    var g = ui.g
    var my_turn: bool = ui.phase == "" and g.state == Rules.TURN_WAITING and g.turn == 0 and not ui.input_locked
    if my_turn and not ui.can_human_play():
        # sua vez sem carta escolhida: o botão aparece dourado como na referência, mas o toque só
        # mostra o aviso (o motor só aceita 1 a 3 cartas)
        button_gold(r, "JOGAR CARTAS", "play_empty", true, int(r.size.y * 0.66))
        return
    button_gold(r, "JOGAR CARTAS", "play", ui.can_human_play(), int(r.size.y * 0.66))

func _draw_hint():
    var h = L().hint
    if h == null: return
    var lines: Array = ui.help_text()
    if String(lines[0]).is_empty(): return
    var fs: int = h[1]
    rich(lines[0], h[0], "ui_sp", fs, Color("f6ecd2"), Color("ffd257"))
    rich(lines[1], h[0] + Vector2(0, fs * 1.3), "ui_sp", fs, Color("f6ecd2"), Color("ffd257"))

# ---------------------------------------------------------------- mão
func hand_layout() -> Array:
    var g = ui.g
    var hd: Array = L().hand
    var sc: float = hd[1]
    var cw := 720.0 * sc
    var n: int = g.hands[0].size()
    var out := []
    var step := cw * 0.737
    var mid := (n - 1) / 2.0
    for i in n:
        var off := i - mid
        var rot := deg_to_rad(4.0 * off) if n > 1 else 0.0
        var c: Vector2 = hd[0] + Vector2(off * step, absf(off) * absf(off) * cw * 0.024 + absf(off) * cw * 0.026)
        if i in ui.selected: c.y -= cw * 0.15
        out.append({"c": c, "rot": rot, "sc": sc * 2.0})     # versões do jogo: metade do tamanho do arquivo aprovado
    return out

func _draw_hand():
    var g = ui.g
    var hand: Array = g.hands[0]
    var lay := hand_layout()
    var my_turn: bool = ui.phase == "" and g.turn == 0 and g.state == Rules.TURN_WAITING and not ui.input_locked
    for i in hand.size():
        var it: Dictionary = lay[i]
        var tex: Texture2D = ui.cards[hand[i]]
        var sz: Vector2 = tex.get_size() * it.sc
        if i in ui.selected:
            draw_set_transform(ui.origin + Vector2(it.c) * ui.k, it.rot, Vector2(ui.k, ui.k))
            var a := 0.55 + 0.25 * sin(ui.t * 6.0)
            for gi in 4: draw_rect(Rect2(-sz / 2.0, sz).grow(3 + gi * 3), Color(1, 0.85, 0.35, a * (0.5 - gi * 0.11)), false, 3.0)
            draw_rect(Rect2(-sz / 2.0, sz).grow(2), Color("ffd257"), false, 3.0)
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
        var mod := Color.WHITE if my_turn or g.turn != 0 else Color(0.9, 0.9, 0.9)
        tex_center(tex, it.c, it.sc, it.rot, mod)
        if my_turn:
            hit(Rect2(Vector2(it.c) - sz / 2.0, sz), "card_%d" % i)
        if ui.hover_id == "card_%d" % i and my_turn and not (i in ui.selected):
            draw_set_transform(ui.origin + Vector2(it.c) * ui.k, it.rot, Vector2(ui.k, ui.k))
            draw_rect(Rect2(-sz / 2.0, sz).grow(1), Color(1, 0.93, 0.6, 0.7), false, 2.0)
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))

# ---------------------------------------------------------------- XEQUE: revelação, seguro, xeque-mate
func _draw_reveal(big: bool):
    var r: Dictionary = ui.result
    var rv: Array = L().reveal
    var cards: Array = r.cards
    var n := cards.size()
    var sc: float = rv[1] * 2.0
    var cw := 360.0 * sc
    var base: Vector2 = rv[0]
    if big: base.y += 0.0
    var flip: float = clampf(ui.phase_t / 0.35, 0.0, 1.0) if ui.phase == "reveal" else 1.0
    for i in n:
        var off := i - (n - 1) / 2.0
        var c := base + Vector2(off * cw * 1.0, absf(off) * cw * 0.2)
        var rot := deg_to_rad(8.0 * off)
        var tex: Texture2D = ui.cards[cards[i]] if flip >= 0.5 else ui.CARD_BACK
        var wscale := absf(flip * 2.0 - 1.0)
        var sz := tex.get_size() * sc
        draw_set_transform(ui.origin + c * ui.k, rot, Vector2(ui.k * maxf(0.05, wscale), ui.k))
        draw_rect(Rect2(-sz / 2.0, sz).grow(3), Color(0, 0, 0, 0.45))
        var lie: bool = not Rules.is_true_card(cards[i], String(r.target))
        if flip >= 1.0 and lie: draw_rect(Rect2(-sz / 2.0, sz).grow(4), Color("e02a36"), false, 4.0)
        draw_texture_rect(tex, Rect2(-sz / 2.0, sz), false)
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
    # faixa "DISSE 3 TORRES · TINHA 1 CAVALO"
    var said: String = "DISSE " + _declared(n, String(r.target))
    var tail := ""
    var tail_col := Color("c8102e")
    if bool(r.truthful):
        tail = "ERA VERDADE"
        tail_col = Color("1f7a4d")
    else:
        var counts := {}
        for c in r.false_cards: counts[c] = int(counts.get(c, 0)) + 1
        var parts := []
        for c in counts: parts.append("%d %s" % [counts[c], String(Rules.NAMES[c] if counts[c] == 1 else Rules.PLURAL[c]).to_upper()])
        tail = "TINHA " + " E ".join(parts)
    var fs := 30 if ui.layout != "landscape" else 26
    var w := tw(said + " · ", "ui_sp", fs) + tw(tail, "ui_sp", fs) + 40
    var by := base.y + 360.0 * sc * 1.4 * 0.5 + 26
    var br := Rect2(base.x - w / 2.0, by, w, fs * 1.6)
    stair(br.grow(3), 3, Color("120a06"))
    stair(br, 3, Color("f6ecd2"))
    var x := br.position.x + 20
    text(said + " · ", Vector2(x, br.get_center().y + fs * 0.36), "ui_sp", fs, Color("2a1505"))
    text(tail, Vector2(x + tw(said + " · ", "ui_sp", fs), br.get_center().y + fs * 0.36), "ui_sp", fs, tail_col)

func _declared(n: int, target: String) -> String:
    return "%d %s" % [n, String(Rules.NAMES[target] if n == 1 else Rules.PLURAL[target]).to_upper()]

func _draw_safe():
    var r: Dictionary = ui.result
    var ml: Array = L().mate_line
    var name: String = ui.g.names[int(r.loser)]
    var w := 0.0
    var l1 := "O RELÓGIO NÃO DISPAROU"
    var l2 := "%s ESCAPOU · CHANCE DE XEQUE-MATE AGORA: %s" % [name.to_upper(), "1 EM %d" % ui.g.clock_left(int(r.loser)) if ui.g.clock_left(int(r.loser)) > 1 else "CERTA"]
    var fs: int = ml[1]
    w = maxf(tw(l1, "ui_sp4", fs + 10), tw(l2, "ui_sp", fs - 4)) + 60
    var c: Vector2 = ml[0] - Vector2(0, fs * 1.6)
    var rr := Rect2(c.x - w / 2.0, c.y - fs * 1.4, w, fs * 3.3)
    panel(rr, Color("e8b242"), true)
    text(l1, Vector2(rr.position.x, c.y + 4), "ui_sp4", fs + 10, Color("ffd257"), rr.size.x, HORIZONTAL_ALIGNMENT_CENTER, 4)
    text(l2, Vector2(rr.position.x, c.y + fs * 1.35), "ui_sp", fs - 4, Color("f6ecd2"), rr.size.x, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_mate():
    var r: Dictionary = ui.result
    var d: Vector2 = ui.design
    var loser := int(r.loser)
    # tela tinge de vermelho (a cena continua por baixo, como na referência 04)
    draw_rect(Rect2(Vector2.ZERO, d), Color(0.62, 0.1, 0.07, 0.42))
    draw_rect(Rect2(Vector2.ZERO, d), Color(0.95, 0.55, 0.45, 0.10))
    _draw_plate(loser)
    _draw_xeque_button(true)
    var mc: Array = L().mate_clock
    var shake := Vector2(sin(ui.t * 70.0), cos(ui.t * 53.0)) * (4.0 if ui.phase_t < 0.6 else 1.0)
    tex_center(ui.clock_tex["disparado"], mc[0] + shake, mc[1] * 2.0)
    if ui.phase == "mate": _draw_reveal(true)
    var mt: Array = L().mate_title
    var title := "Xeque-Mate" if ui.phase == "mate" else "Eliminado"
    var tfs: int = mt[1]
    tfs = fit(title, "title", tfs, d.x - 80)
    text(title, Vector2(0, mt[0].y), "title", tfs, Color("fff1d6"), d.x, HORIZONTAL_ALIGNMENT_CENTER, 14, Color("2a0a06"))
    var ml: Array = L().mate_line
    var name := String(ui.g.names[loser]).to_upper()
    var line := ""
    if ui.phase == "elim":
        line = "%s PERDEU A ÚLTIMA COROA · ELIMINADO" % name
    elif loser == int(r.accused):
        line = "%s BLEFOU, O RELÓGIO DISPAROU · %s" % [name, "ELIMINADO" if Rules.LIVES == 1 else "PERDEU UMA COROA"]
    else:
        line = "%s DEU XEQUE À TOA, O RELÓGIO DISPAROU · %s" % [name, "ELIMINADO" if Rules.LIVES == 1 else "PERDEU UMA COROA"]
    var fs: int = ml[1]
    var crowns_w := Rules.LIVES * 44.0
    fs = fit(line, "ui_sp4", fs, d.x - crowns_w - 120)
    var lw := tw(line, "ui_sp4", fs)
    var x0: float = ml[0].x - (lw + 30 + crowns_w) / 2.0
    text(line, Vector2(x0, ml[0].y), "ui_sp4", fs, Color("fff1d6"), -1, HORIZONTAL_ALIGNMENT_LEFT, 6, Color("2a0a06"))
    _crowns(Vector2(x0 + lw + 30 - (3 - Rules.LIVES) * 22.0, ml[0].y - fs * 0.85), loser, 36.0, 8.0)

# ---------------------------------------------------------------- tutorial (salão do modo)
func _draw_tutorial(d: Vector2):
    var portrait: bool = ui.layout == "portrait"
    if portrait:
        nine(ui.TUTORIAL_BG, Rect2(Vector2.ZERO, d), 120, 0.55)
    else:
        draw_texture_rect(ui.TUTORIAL_BG, Rect2(Vector2.ZERO, d), false)
    var maroon := Color("7d0f1c")
    var ink := Color("2a1a10")
    var title_pos := Vector2(150, 150) if not portrait else Vector2(86, 168)
    text("Como jogar", title_pos, "title", 104 if not portrait else 96, maroon, -1, HORIZONTAL_ALIGNMENT_LEFT, 6, Color("f6ecd2"))
    if not portrait:
        text("Xeque", Vector2(0, 124), "ui_sp", 30, Color("5a3a22"), 1768, HORIZONTAL_ALIGNMENT_RIGHT)
        text("blefe de cartas no reino do xadrez", Vector2(0, 157), "ui_sp", 30, Color("5a3a22"), 1768, HORIZONTAL_ALIGNMENT_RIGHT)
    else:
        text("Xeque · blefe de cartas no reino do xadrez", Vector2(90, 222), "ui_sp", 28, Color("5a3a22"))
    var panels := _tutorial_panels()
    var rects := []
    if not portrait:
        for i in 6: rects.append(Rect2(152 + (i % 3) * 546, 182 + (i / 3) * 366, 524, 344))
    else:
        for i in 6: rects.append(Rect2(84 + (i % 2) * 464, 254 + (i / 2) * 470, 448, 450))
    for i in 6: _tutorial_panel(rects[i], i + 1, panels[i], portrait)
    var foot_y := 975.0 if not portrait else 1712.0
    var fx := 150.0 if not portrait else 90.0
    var parts := ["Como vencer: seja o ", "último jogador de pé", "."]
    var x := fx
    var ffs := 38 if not portrait else 34
    for j in 3:
        text(parts[j], Vector2(x, foot_y), "ui_sp", ffs, maroon if j == 1 else ink)
        x += tw(parts[j], "ui_sp", ffs)
    if ui.tutorial_from_game:
        if not portrait: button_dark(Rect2(1400, 912, 368, 94), "VOLTAR", "tut_back", 48)
        else: button_dark(Rect2(90, 1752, 900, 96), "VOLTAR À PARTIDA", "tut_back", 46)
    else:
        if not portrait:
            button_dark(Rect2(1120, 914, 254, 92), "VOLTAR", "tut_back", 58)
            button_gold(Rect2(1396, 912, 372, 96), "JOGAR AGORA", "tut_play", true, 58)
        else:
            button_dark(Rect2(90, 1752, 320, 96), "VOLTAR", "tut_back", 50)
            button_gold(Rect2(430, 1750, 560, 100), "JOGAR AGORA", "tut_play", true, 52)

func _tutorial_panels() -> Array:
    return [
        {"title": "OBJETIVO", "text": "Quatro jogadores à mesa. Vence o *último jogador de pé*.", "art": "crowns"},
        {"title": "AS CARTAS", "text": "5 cartas para cada um. A mesa pede *Rei, Rainha ou Cavalo*. O *Peão Coroado* é coringa.", "art": "cards"},
        {"title": "SUA VEZ", "text": "Baixe de *1 a 3 cartas viradas* e diga que são a peça pedida. Pode ser verdade. Pode ser blefe.", "art": "backs"},
        {"title": "XEQUE", "text": "O próximo jogador joga ou aperta *XEQUE* na jogada anterior: as cartas dela são reveladas.", "art": "xeque"},
        {"title": "RELÓGIO DE XEQUE", "text": "*Quem perde o desafio aciona o seu Relógio*: 6 posições, uma é xeque-mate. A cada aperto o perigo sobe.", "art": "clocks"},
        {"title": "XEQUE-MATE", "text": "Se o Relógio disparar, é *xeque-mate*: o jogador está *fora da partida*.", "art": "mate"},
    ]

func _tutorial_panel(r: Rect2, n: int, p: Dictionary, portrait: bool):
    var ink := Color("2a1a10")
    var maroon := Color("7d0f1c")
    stair(r.grow(4), 4, Color("2b1a0e"))
    stair(r, 4, Color("f6ecd2"))
    draw_rect(Rect2(r.position.x + 8, r.end.y - 6, r.size.x - 16, 2), Color("e2d3ae"))
    var nb := Rect2(r.position + Vector2(18, 18), Vector2(48, 48))
    draw_rect(nb.grow(3), Color("2b1a0e"))
    draw_rect(nb, maroon)
    text(str(n), Vector2(nb.position.x, nb.position.y + 38), "ui", 40, Color("f6ecd2"), nb.size.x, HORIZONTAL_ALIGNMENT_CENTER)
    var tfs := fit(p.title, "ui_sp4", 44, r.size.x - 100)
    text(p.title, Vector2(nb.end.x + 12, nb.position.y + 40), "ui_sp4", tfs, ink)
    var art := Rect2(r.position.x + 18, nb.end.y + 8, r.size.x - 36, 146 if not portrait else 170)
    draw_rect(art.grow(4), Color("2b1a0e"))
    draw_rect(art, Color("17372a"))
    draw_rect(art.grow(-3), Color("e8b242"), false, 1.0)
    _tutorial_art(art.grow(-6), String(p.art))
    # texto com destaques
    var fs := 27
    var words := String(p.text).split(" ")
    var lines := []
    var cur := ""
    for w in words:
        var test := (cur + " " + w).strip_edges()
        if tw(test.replace("*", ""), "ui", fs) > r.size.x - 38 and cur != "":
            lines.append(cur)
            cur = w
        else:
            cur = test
    lines.append(cur)
    var y := art.end.y + 34
    var hl := false
    for line in lines:
        var x := r.position.x + 20
        var segs := String(line).split("*")
        for j in segs.size():
            if j > 0: hl = not hl
            text(segs[j], Vector2(x, y), "ui", fs, maroon if hl else ink)
            x += tw(segs[j], "ui", fs)
        y += fs * 1.16

func _tutorial_art(a: Rect2, kind: String):
    var c := a.get_center()
    match kind:
        "crowns":
            # os 4 jogadores da mesa; só um fica de pé
            var av := minf(a.size.y - 24, (a.size.x - 70) / 4.0)
            for i in 4:
                var ar := Rect2(c.x + (i - 1.5) * (av + 14) - av / 2.0, c.y - av / 2.0 + 4, av, av)
                draw_rect(ar.grow(3), Color("120a06"))
                draw_rect(ar.grow(2), Color("d8c08a"))
                draw_texture_rect(ui.avatars[i] if ui.avatars.size() > i and ui.avatars[i] != null else ui.CARD_BACK, ar, false, Color.WHITE if i == 0 else Color(0.45, 0.45, 0.45))
            draw_texture_rect(ui.CROWN, Rect2(c.x - 1.5 * (av + 14) - 20, c.y - av / 2.0 - 18, 40, 34), false)
        "cards":
            var names := ["rei", "rainha", "cavalo", "peao"]
            for i in 4:
                var h := minf(a.size.y - 10, (a.size.x - 50) / 4.0 / (360.0 / 504.0))
                var w := h * 360.0 / 504.0
                draw_texture_rect(ui.cards[names[i]], Rect2(c.x + (i - 1.5) * (w + 10) - w / 2.0, c.y - h / 2.0, w, h), false)
        "backs":
            var h2 := a.size.y - 16
            tex_center(ui.CARD_BACK, c + Vector2(-110, 0), h2 / 504.0, -0.12)
            tex_center(ui.CARD_BACK, c + Vector2(-50, 0), h2 / 504.0, 0.1)
            var br := Rect2(c.x + 20, c.y - 24, 170, 48)
            stair(br.grow(3), 3, Color("120a06"))
            stair(br, 3, Color("f6ecd2"))
            text("2", Vector2(br.position.x + 16, c.y + 11), "ui", 30, Color("c8102e"))
            text(" × RAINHA", Vector2(br.position.x + 16 + tw("2", "ui", 30), c.y + 11), "ui_sp", 30, Color("2a1505"))
        "xeque":
            var h3 := minf(a.size.y - 10, (a.size.x * 0.46) / 2.0 / (360.0 / 504.0))
            var w3 := h3 * 360.0 / 504.0
            var x3 := a.end.x - 2 * w3 - 18
            draw_texture_rect(ui.cards["rainha"], Rect2(x3, c.y - h3 / 2.0, w3, h3), false)
            draw_texture_rect(ui.cards["rei"], Rect2(x3 + w3 + 8, c.y - h3 / 2.0, w3, h3), false)
            var bsc := minf(0.42, (x3 - a.position.x - 60) / 380.0)
            tex_center(ui.xeque_tex["normal"], Vector2(a.position.x + 10 + 216 * bsc, c.y), bsc)
            text("→", Vector2(x3 - 44, c.y + 12), "ui", 40, Color("e8b242"))
        "clocks":
            var names2 := ["neutro", "perigo", "quase"]   # 6 posições: neutro → em perigo → quase disparando
            for i in 3:
                tex_center(ui.clock_tex[names2[i]], c + Vector2((i - 1) * 140, 4), (a.size.y + 30) / 560.0)
                if i < 2: text("→", Vector2(c.x + (i - 1) * 140 + 56, c.y + 12), "ui", 40, Color("e8b242"))
        "mate":
            tex_center(ui.clock_tex["disparado"], c + Vector2(-120, 4), (a.size.y + 40) / 560.0)
            text("→", Vector2(c.x - 30, c.y + 12), "ui", 40, Color("e8b242"))
            draw_texture_rect(ui.CROWN_LOST, Rect2(c.x + 30, c.y - 34, 80, 67), false)
            text("FORA", Vector2(c.x + 120, c.y + 12), "ui_sp4", 36, Color("ff5a52"))

# ---------------------------------------------------------------- resultado
func _draw_result(d: Vector2):
    var g = ui.g
    if g == null: return
    var portrait: bool = ui.layout == "portrait"
    var won: bool = g.winner == 0
    if portrait:
        draw_texture_rect(ui.RESULT_BG, Rect2(Vector2(-(1920.0 * 1920 / 1080 - 1080) / 2.0, 0), Vector2(1920.0 * 1920 / 1080, 1920)), false)
    else:
        draw_texture_rect(ui.RESULT_BG, Rect2(Vector2.ZERO, d), false)
    var title := "Vitória" if won else "Derrota"
    var tcol := Color("f6c24a") if won else Color("e0574a")
    var cx := d.x / 2.0
    text(title, Vector2(0, 214 if not portrait else 230), "title", 232 if not portrait else 190, tcol, d.x, HORIZONTAL_ALIGNMENT_CENTER, 10, Color("2a1206"))
    draw_string(font("title"), Vector2(0, 208 if not portrait else 224), title, HORIZONTAL_ALIGNMENT_CENTER, d.x, 232 if not portrait else 190, Color(1, 0.95, 0.7, 0.25))
    var hero: int = 0 if won else g.winner
    # retrato grande do vencedor (você, se venceu)
    var fr := Rect2(420, 330, 282, 282) if not portrait else Rect2(399, 300, 282, 282)
    for i in 4: draw_rect(fr.grow(16 + i * 5), Color(1, 0.8, 0.3, 0.06))
    draw_rect(fr.grow(16), Color("120a06"))
    draw_rect(fr.grow(13), Color("ffe08a"))
    draw_rect(fr.grow(10), Color("f2c050"))
    draw_rect(fr.grow(4), Color("8a5a1c"))
    draw_rect(fr.grow(2), Color("120a06"))
    draw_texture_rect(ui.avatars[0] if won else ui.avatars[hero], fr, false)
    for cpt in [fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]:
        var dm := PackedVector2Array([cpt + Vector2(0, -9), cpt + Vector2(9, 0), cpt + Vector2(0, 9), cpt + Vector2(-9, 0)])
        draw_colored_polygon(dm, Color("ffe8a3"))
    var nm: String = "Você" if won else String(g.names[hero])
    var ny := 690.0 if not portrait else 660.0
    var ccx := fr.get_center().x
    text(nm, Vector2(ccx - 400, ny), "ui", 74, Color("f6ecd2"), 800, HORIZONTAL_ALIGNMENT_CENTER, 6)
    var crowns_left: int = g.lives[hero]
    var sub := "ÚLTIMO DE PÉ" if Rules.LIVES == 1 else "ÚLTIMO DE PÉ · %d %s" % [crowns_left, "COROA RESTANTE" if crowns_left == 1 else "COROAS RESTANTES"]
    if not won:
        sub = "VOCÊ FICOU EM %dº LUGAR" % g.placement(0)
    text(sub, Vector2(ccx - 460, ny + 52), "ui_sp4", 30, Color("e8b242"), 920, HORIZONTAL_ALIGNMENT_CENTER, 4)
    for i in Rules.LIVES:
        var lost := i >= crowns_left
        draw_texture_rect(ui.CROWN_LOST if lost else ui.CROWN, Rect2(ccx - (Rules.LIVES - 1) * 66.5 + i * 133 - 48, ny + 92, 96, 81), false)
    # faixa vermelha: xeque-mate final
    var last_loser := -1
    if not g.finish_order.is_empty(): last_loser = int(g.finish_order[g.finish_order.size() - 1])
    var band := Rect2(907, 278, 765, 102) if not portrait else Rect2(60, 900, 960, 96)
    stair(band.grow(4), 4, Color("120a06"))
    stair(band, 4, Color("a3121f"))
    draw_polygon(PackedVector2Array([band.position + Vector2(4, 4), Vector2(band.end.x - 4, band.position.y + 4), band.end - Vector2(4, 4), Vector2(band.position.x + 4, band.end.y - 4)]),
        PackedColorArray([Color("c11a2a"), Color("b0141f"), Color("7d0f1c"), Color("8e1220")]))
    tex_center(ui.clock_tex["disparado"], band.position + Vector2(64, band.size.y / 2.0), (band.size.y + 34) / 560.0)
    var bt := "XEQUE-MATE FINAL EM %s" % String(g.names[last_loser]).to_upper() if last_loser >= 0 else "FIM DE PARTIDA"
    text(bt, Vector2(band.position.x + 130, band.get_center().y + 13), "ui_sp4", fit(bt, "ui_sp4", 36, band.size.x - 160), Color("fff1d6"))
    # classificação
    var lr := Rect2(912, 405, 756, 390) if not portrait else Rect2(60, 1030, 960, 420)
    panel(lr)
    var order := [g.winner]
    for i in range(g.finish_order.size() - 1, -1, -1): order.append(g.finish_order[i])
    var rh := (lr.size.y - 24) / 4.0
    for i in order.size():
        var s: int = order[i]
        var rr := Rect2(lr.position.x + 18, lr.position.y + 14 + i * rh, lr.size.x - 36, rh - 6)
        if i == 0: draw_rect(rr, Color(0.35, 0.55, 0.25, 0.28))
        if i < 3: draw_rect(Rect2(rr.position.x, rr.end.y + 2, rr.size.x, 2), Color(0.85, 0.7, 0.3, 0.35))
        text(str(i + 1), Vector2(rr.position.x + 14, rr.get_center().y + 16), "ui", 46, Color("e8b242"))
        text("o", Vector2(rr.position.x + 14 + tw(str(i + 1), "ui", 46) + 1, rr.get_center().y - 2), "ui", 22, Color("e8b242"))
        draw_rect(Rect2(rr.position.x + 15 + tw(str(i + 1), "ui", 46), rr.get_center().y + 2, 10, 2), Color("e8b242"))
        var ar := Rect2(rr.position.x + 66, rr.position.y + 6, rh - 18, rh - 18)
        draw_rect(ar.grow(3), Color("120a06"))
        draw_rect(ar.grow(2), Color("d8d0bf"))
        draw_texture_rect(ui.avatars[s], ar, false)
        var nx := ar.end.x + 12
        text(g.names[s], Vector2(nx, rr.position.y + 36), "ui", 34, Color("f6ecd2"), -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
        if s != 0: chip(Rect2(nx + tw(g.names[s], "ui", 34) + 10, rr.position.y + 12, 48 * (1.45 if ui.seat_tag(s) != "BOT" else 1.0), 28), ui.seat_tag(s), Color("9fd0ff"), Color("9fd0ff"), Color("13314f"), 16)
        var line := "Último de pé" if i == 0 else ("Xeque-mate final na rodada %d" % g.eliminated_round[s] if i == 1 else "Eliminad%s na rodada %d" % ["a" if s == 1 else "o", g.eliminated_round[s]])
        text(line, Vector2(nx, rr.position.y + 66), "ui_sp", 22, Color("c9d6cf"))
        for c in Rules.LIVES:
            draw_texture_rect(ui.CROWN_LOST if c >= g.lives[s] else ui.CROWN, Rect2(rr.end.x - 56 - (Rules.LIVES - 1 - c) * 52, rr.get_center().y - 18, 42, 35), false)
    # botões
    if not portrait:
        button_gold(Rect2(265, 935, 485, 82), "JOGAR NOVAMENTE", "again", true, 54)
        button_dark(Rect2(785, 935, 388, 82), "VER TUTORIAL", "over_tutorial", 54)
        button_dark(Rect2(1208, 935, 448, 82), "VOLTAR AO MENU", "over_menu", 54)
    else:
        button_gold(Rect2(60, 1500, 960, 100), "JOGAR NOVAMENTE", "again", true, 48)
        button_dark(Rect2(60, 1630, 465, 96), "VER TUTORIAL", "over_tutorial", 42)
        button_dark(Rect2(555, 1630, 465, 96), "VOLTAR AO MENU", "over_menu", 42)

# ---------------------------------------------------------------- menu e confirmação
func _shade():
    draw_rect(Rect2(Vector2(-4000, -4000), Vector2(12000, 12000)), Color(0, 0, 0, 0.62))
    ui.hits.clear()          # nada por baixo recebe toque

func _draw_menu():
    _shade()
    var d: Vector2 = ui.design
    var r := Rect2(d.x / 2.0 - 300, d.y / 2.0 - 210, 600, 420)
    panel(r, Color("e8b242"), true)
    text("MENU", Vector2(r.position.x, r.position.y + 70), "ui_sp4", 52, Color("e8b242"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
    button_gold(Rect2(r.position.x + 50, r.position.y + 104, 500, 84), "CONTINUAR", "menu_continue", true, 42)
    button_dark(Rect2(r.position.x + 50, r.position.y + 206, 500, 80), "COMO JOGAR", "menu_tutorial", 40)
    button_dark(Rect2(r.position.x + 50, r.position.y + 304, 500, 80), "SAIR DA PARTIDA", "menu_quit", 40)

func _draw_confirm():
    _shade()
    var d: Vector2 = ui.design
    var r := Rect2(d.x / 2.0 - 330, d.y / 2.0 - 170, 660, 340)
    panel(r, Color("e02a36"), true)
    text("SAIR DA PARTIDA?", Vector2(r.position.x, r.position.y + 72), "ui_sp4", 48, Color("ffd257"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
    text("A partida conta como abandono no histórico.", Vector2(r.position.x, r.position.y + 128), "ui_sp", 28, Color("f6ecd2"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
    button_dark(Rect2(r.position.x + 40, r.end.y - 120, 270, 84), "SAIR", "quit_yes", 40)
    button_gold(Rect2(r.end.x - 330, r.end.y - 122, 290, 88), "CONTINUAR", "quit_no", true, 40)

func _draw_flash():
    var d: Vector2 = ui.design if ui.mode == "game" else Vector2(1920, 1080)
    var fs := 28
    var w := tw(ui.flash, "ui_sp", fs) + 50
    var r := Rect2(d.x / 2.0 - w / 2.0, d.y * 0.36, w, 56)
    panel(r)
    text(ui.flash, Vector2(r.position.x, r.get_center().y + 10), "ui_sp", fs, Color("f6ecd2"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
