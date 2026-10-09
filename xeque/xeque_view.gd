extends Control
## XEQUE — desenho das telas. Tudo é desenhado em coordenadas da tela de referência do formato
## (PC 1920x1080, celular retrato 1080x1920, celular paisagem 1950x900) e escalado para a janela.
## As posições abaixo foram medidas nas telas de referência aprovadas (telas_referencia/*.jpg):
## a cena da mesa casa com o tabuleiro do JSON; relógio e cartas da mão foram ajustados pixel a pixel.
const Rules := preload("res://xeque/rules.gd")
const Cosmetics := preload("res://profile/premium_cosmetics.gd")

# ---------------------------------------------------------------- medidas por formato
const VoiceGlyph := preload("res://voice/voice_glyph.gd")
const LAYOUTS := {
    "desktop": {
        "scene": [1.1832, Vector2(-29.2, -112.6)], "board": Rect2(650, 208, 620, 536),
        "title": [Vector2(20, 92), 96], "sub": [Vector2(20, 127), 23],
        # R55 · referência nova (tools/ui_ref/xeque/xeque_ref_r55.png): tela = ref × 1,156 + (−5,8; −20,8)
        "mesa": Rect2(29, 166, 387, 218), "como": Rect2(29, 399, 387, 357),
        "plates": {0: ["h", Rect2(35, 887, 368, 133)], 1: ["v", Vector2(515, 475), 180], 2: ["hc", Rect2(817, 6, 293, 104)], 3: ["v", Vector2(1406, 475), 180]},
        "turn": Rect2(1535, 22, 355, 69), "meter": Rect2(1522, 155, 370, 146),
        "xeque": [Vector2(1718, 636), 0.92], "xeque_rect": Rect2(1541, 573, 355, 127), "play": Rect2(1536, 721, 362, 90),
        "hint": [Vector2(1718, 875), 24], "help": Rect2(1763, 975, 58, 58), "menu": Rect2(1834, 975, 58, 58),
        "music": Rect2(1621, 975, 58, 58), "fx": Rect2(1692, 975, 58, 58), "full": Rect2(1550, 975, 58, 58), "voice": Rect2(1479, 975, 58, 58), "voice_ear": Rect2(1408, 975, 58, 58),
        "hand": [Vector2(960, 930), 0.212], "pile": [Vector2(960, 478), 0.128], "clock": [Vector2(960, 333), 0.22],
        "reveal": [Vector2(960, 476), 0.19], "mate_clock": [Vector2(960, 262), 0.36], "mate_title": [Vector2(960, 862), 196],
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
        "music": Rect2(330, 22, 60, 60), "fx": Rect2(400, 22, 60, 60), "full": Rect2(260, 22, 60, 60), "voice": Rect2(620, 22, 60, 60), "voice_ear": Rect2(620, 92, 60, 60),
        "hand": [Vector2(540, 1664), 0.167], "pile": [Vector2(540, 912), 0.18], "clock": [Vector2(540, 703), 0.32],
        "reveal": [Vector2(540, 884), 0.25], "mate_clock": [Vector2(540, 690), 0.48], "mate_title": [Vector2(540, 1252), 128],
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
        "music": Rect2(1682, 2, 50, 48), "fx": Rect2(1740, 2, 50, 48), "full": Rect2(1624, 2, 50, 48), "voice": Rect2(1566, 2, 50, 48), "voice_ear": Rect2(1508, 2, 50, 48),
        "hand": [Vector2(975, 772), 0.183], "pile": [Vector2(975, 369), 0.122], "clock": [Vector2(975, 248), 0.185],
        "reveal": [Vector2(975, 356), 0.16], "mate_clock": [Vector2(975, 222), 0.31], "mate_title": [Vector2(975, 690), 124],
        "mate_line": [Vector2(975, 800), 26],
    },
}
const STATUS_COLOR := {"aguardando": Color("e8b242"), "sua_vez": Color("ffd257"), "pensando": Color("6fb4ee"), "declarou": Color("e8b242"),
    "em_risco": Color("e02a36"), "com_o_relogio": Color("b068ff"), "xeque_mate": Color("e02a36"), "eliminado": Color("6b6f72")}

var ui
var grey_avatars := {}
var vignette: ImageTexture = null
var vignette_layout := ""
# R35.1 · cenário sem "caixa preta": a cena nítida tem as bordas esfumadas e, por trás, a MESMA cena
# desfocada cobre a tela inteira (janela do navegador mais larga/baixa que 16:9 não mostra faixas pretas).
const SCENE_SOFT := preload("res://xeque/art/mesa/mesa_cena_soft.png")   # tools/xeque_scene_soft.py
const SCENE_BLUR := preload("res://xeque/art/mesa/mesa_cena_blur.png")

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
            var f := 0.97 - 0.25 * tt          # R35.1: vinheta mais leve (antes 0,94 − 0,44)
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

## seta desenhada (a fonte "ui" não tem o glifo →); pos = linha de base, como em text()
func arrow(pos: Vector2, col: Color):
    var c := pos + Vector2(16, -13)
    draw_rect(Rect2(c + Vector2(-16, -3), Vector2(20, 6)), col)
    draw_colored_polygon(PackedVector2Array([c + Vector2(2, -11), c + Vector2(18, 0), c + Vector2(2, 11)]), col)

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

const Crisp := preload("res://ui_v022/crisp_tex.gd")
func tex_center(tex: Texture2D, c: Vector2, sc: float, rot := 0.0, mod: Color = Color.WHITE):
    var sz := tex.get_size() * sc
    # R37.2 · cartas: reduzidas com Lanczos para o tamanho real na tela (texto legível com filtro NEAREST)
    if tex == ui.CARD_BACK or ui.cards.values().has(tex): tex = Crisp.at(tex, sz * ui.k)
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
    if desk(): desk_square(r, hov)
    else: panel(r, Color("e8b242") if not hov else Color("ffeea5"), false, Color("12382a"), Color("0b2219"))
    ui.Sound.glyph(self, r.grow(-6), kind, off, Color("f6ecd2") if not off else Color("8d9092"))
    hit(r, id)

## R43 · TELA CHEIA (o mesmo botão da Home), ao lado da música.
func fullscreen_button(r: Rect2, on: bool):
    var hov: bool = ui.hover_id == "fullscreen"
    if desk(): desk_square(r, hov)
    else: panel(r, Color("e8b242") if not hov else Color("ffeea5"), false, Color("12382a"), Color("0b2219"))
    preload("res://ui_v022/fullscreen_control.gd").draw_glyph(self, r.grow(-6), on, Color("f6ecd2"), 2.5)
    hit(r, "fullscreen")

## R45 · FRAIHA Voice: microfone só em partida online com outro humano (no navegador).
func _draw_voice(lay: Dictionary):
    var vo = ui.voice()
    if vo == null or not vo.in_match() or not vo.available() or not lay.has("voice"): return
    var r: Rect2 = lay.voice
    var hov: bool = ui.hover_id == "voice"
    panel(r, Color("e8b242") if not hov else Color("ffeea5"), false, Color("12382a"), Color("0b2219"))
    VoiceGlyph.draw_mic(self, r.grow(-7), vo.state, Color("f6ecd2"), vo.is_speaking(vo.my_uid))
    hit(r, "voice")
    if vo.active() or vo.state == "ERROR": hit(VoiceGlyph.draw_leave_badge(self, r), "voice_off")
    var text_right := r.position.x - 10
    if vo.active() and lay.has("voice_ear"):
        # ÁUDIO RECEBIDO (fone): ouvir / não ouvir os outros, sem sair da sala nem mexer no microfone
        var er: Rect2 = lay.voice_ear
        panel(er, Color("e8b242") if ui.hover_id != "voice_ear" else Color("ffeea5"), false, Color("12382a"), Color("0b2219"))
        VoiceGlyph.draw_headphones(self, er.grow(-8), vo.speaker_muted, Color("f6ecd2"))
        hit(er, "voice_ear")
        if er.position.y == r.position.y: text_right = er.position.x - 10
    if ui.layout != "portrait": VoiceGlyph.draw_status(self, text_right, r.get_center().y, 300, vo.status_text(), 18, Color("f6ecd2"))

func square_button(r: Rect2, glyph: String, id: String):
    var hov: bool = ui.hover_id == id
    if desk(): desk_square(r, hov)
    else: panel(r, Color("e8b242") if not hov else Color("ffeea5"), false, Color("12382a"), Color("0b2219"))
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
    if ui.mode == "game":
        # fundo que cobre a janela toda: a própria cena, desfocada e um pouco mais escura
        var cov := maxf(vs.x / 1672.0, vs.y / 941.0)
        var cs := Vector2(1672, 941) * cov
        draw_texture_rect(SCENE_BLUR, Rect2((vs - cs) / 2.0, cs), false, Color(0.62, 0.6, 0.58))
    # telas 16:9 (tutorial e resultado) usam o desenho do PC também no celular deitado
    var dsg: Vector2 = ui.design
    if ui.mode in ["tutorial", "over"] and ui.layout == "landscape": dsg = Vector2(1920, 1080)
    ui.k = minf(vs.x / dsg.x, vs.y / dsg.y)
    ui.origin = (vs - dsg * ui.k) / 2.0 + ui.shake_offset() * ui.k      # R36: tremor de tela
    draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
    match ui.mode:
        "game": _draw_game()
        "tutorial": _draw_tutorial(dsg)
        "over": _draw_result(dsg)
    if ui.mode in ["game", "over"]: _draw_fx()
    if ui.mode == "game" and ui.intro_anim >= 0.0: _draw_intro()
    if ui.menu_open: _draw_menu()
    if ui.confirm_quit: _draw_confirm()
    if not ui.flash.is_empty(): _draw_flash()
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------- partida
func _draw_scene():
    var sc: Array = L().scene
    var s: float = sc[0]
    var o: Vector2 = sc[1]
    draw_texture_rect(SCENE_SOFT, Rect2(o, Vector2(1672, 941) * s), false)
    var d: Vector2 = ui.design
    draw_texture_rect(_vignette(), Rect2(Vector2.ZERO, d), false)
    var end_y: float = minf(o.y + 941 * s, d.y)
    # R35.1 · sombra suave embaixo (a mão continua legível) — sem faixa preta chapada
    var fade := 220.0
    var shade := Color(0.027, 0.043, 0.04, 0.45)
    draw_polygon(PackedVector2Array([Vector2(-2000, end_y - fade), Vector2(d.x + 2000, end_y - fade), Vector2(d.x + 2000, end_y), Vector2(-2000, end_y)]),
        PackedColorArray([Color(shade, 0.0), Color(shade, 0.0), shade, shade]))
    if end_y < d.y + 600: draw_rect(Rect2(-2000, end_y, d.x + 4000, 600), shade)

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
    # R35.1 · a torre-relógio só aparece quando alguém errou (o relógio é acionado); fora disso a mesa fica livre
    if not mate and ui.phase in ["clock", "safe"]: _draw_center_clock()
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
    var sm = ui.screen_mode()
    if sm != null and sm.supported(): fullscreen_button(lay.full, sm.on_cached())   # R43
    _draw_voice(lay)
    if not mate: _draw_hand()
    _draw_fly()
    if ui.phase in ["reveal", "clock", "safe"]: _draw_reveal(false)
    if ui.deal_anim >= 0.0 and ui.intro_anim < 0.0: _draw_deal()
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
    if desk(): return _desk_title()
    var lay := L()
    var tp: Array = lay.title
    text("Xeque", tp[0], "title", tp[1], Color("f2c050"), -1, HORIZONTAL_ALIGNMENT_LEFT, 8, Color("2a1206"))
    draw_string(font("title"), tp[0] + Vector2(0, -2), "Xeque", HORIZONTAL_ALIGNMENT_LEFT, -1, tp[1], Color(1, 0.93, 0.62, 0.35))
    var sp: Array = lay.sub
    var sub := "RODADA %d · BLEFE DE CARTAS" % ui.g.round_no if ui.layout != "portrait" else "RODADA %d" % ui.g.round_no
    text(sub, sp[0], "ui_sp4", sp[1], Color("caa14a"), -1, HORIZONTAL_ALIGNMENT_LEFT, 2, Color(0.07, 0.04, 0.02, 0.85))

func _draw_mesa_pede():
    if desk(): return _desk_mesa_pede()
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
    # R35.1 · a CARTA da rodada (a mesma arte da mão), levemente inclinada: identificação imediata
    var card: Texture2D = ui.cards[g.target]
    var ih := (r.size.y - 52.0) if compact else (r.size.y - 62.0)
    var isz := card.get_size() * (ih / card.get_size().y)
    var ipos := r.position + Vector2(pad + 4, (40 if compact else 48))
    var cc := ipos + isz / 2.0
    draw_set_transform(ui.origin + cc * ui.k, -0.07, Vector2(ui.k, ui.k))
    draw_rect(Rect2(-isz / 2.0 + Vector2(5, 6), isz), Color(0, 0, 0, 0.45))
    draw_texture_rect(card, Rect2(-isz / 2.0, isz), false)
    draw_rect(Rect2(-isz / 2.0, isz).grow(1), Color("ffd257"), false, 2.0)
    draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
    var x := ipos.x + isz.x + (14 if compact else 18)
    var big := fit(name.to_upper(), "ui", 66 if compact else 78, r.end.x - x - 12)
    text(name.to_upper(), Vector2(x, r.position.y + (101 if compact else 107)), "ui", big, Color("f6ecd2"), -1, HORIZONTAL_ALIGNMENT_LEFT, 5, Color("120a06"))
    if compact:
        text("Diga que são %s" % plural.to_lower(), Vector2(x, r.position.y + 131), "ui_sp", fit("Diga que são %s" % plural.to_lower(), "ui_sp", 21, r.end.x - x - 8), Color("e8dcc0"))
    else:
        text("Diga que suas cartas", Vector2(x, r.position.y + 137), "ui_sp", 21, Color("e8dcc0"))
        text("são %s" % plural.to_lower(), Vector2(x, r.position.y + 164), "ui_sp", fit("são %s" % plural.to_lower(), "ui_sp", 21, r.end.x - x - 8), Color("e8dcc0"))

func _draw_como_jogar(r: Rect2):
    if desk(): return _desk_como_jogar(r)
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
    var grow := 1.0
    if ui.phase == "clock": grow = 0.55 + 0.45 * ease(clampf(ui.phase_t / 0.3, 0.0, 1.0), -2.0)   # entra crescendo
    tex_center(tex, pos + shake, c[1] * 2.0 * pulse * grow)      # versões do jogo têm metade do tamanho do arquivo aprovado

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

## R35.1 · distribuição: cada carta (verso) sai do centro da mesa e voa até o jogador, uma a uma.
func _draw_deal():
    var pl: Array = L().pile
    var hl := hand_layout()
    for k in ui.deal_order.size():
        var t0: float = ui.deal_start(k)
        var f: float = (ui.deal_anim - t0) / ui.DEAL_FLIGHT
        if f < 0.0 or f >= 1.0: continue
        var it: Dictionary = ui.deal_order[k]
        var s := int(it.seat)
        var to := _seat_anchor(s)
        if s == 0:
            var slot := int(it.slot)
            to = Vector2(hl[slot].c) if slot < hl.size() else L().hand[0]
        var e := ease(f, -2.0)
        var p: Vector2 = Vector2(pl[0]).lerp(to, e) + Vector2(0, -60.0 * sin(PI * f))
        tex_center(ui.CARD_BACK, p, pl[1] * (2.0 + 0.6 * sin(PI * f)), -0.6 + 1.2 * f + s * 0.4)

func _draw_fly():
    var pl: Array = L().pile
    for f in ui.fly:
        var from := _seat_anchor(int(f.from))
        if int(f.from) == 0: from = L().hand[0]
        var tt: float = ease(clampf(f.t, 0.0, 1.0), -2.0)
        for i in int(f.count):
            tex_center(ui.CARD_BACK, from.lerp(pl[0], tt) + Vector2(i * 12, i * -4), pl[1] * 2.0, -0.2 + i * 0.15)

# ---------------------------------------------------------------- placas
## R41 · moldura (Club / Fundador) e selo do jogador humano sobre o retrato.
func _look(pr: Rect2, look: Dictionary):
    if look.is_empty(): return
    match Cosmetics.public_frame(look):
        "club":
            draw_rect(pr.grow(3), Color("e9b94a"), false, 4.0)
            draw_rect(pr.grow(-1), Color("fff1c0"), false, 1.0)
        "fundador":
            draw_rect(pr.grow(4), Color("1b150e"), false, 5.0)
            draw_rect(pr.grow(2), Color("d9a441"), false, 2.0)
    var tex: Texture2D = Cosmetics.badge_texture(Cosmetics.public_badge(look))
    if tex != null:
        var side := clampf(pr.size.x * 0.42, 16.0, 44.0)
        draw_texture_rect(tex, Rect2(pr.end - Vector2(side * 0.8, side * 0.8), Vector2(side, side)), false)

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

## R37 · relógio de CADA jogador na placa dele: 5 pauzinhos (1 por XEQUE perdido e sobrevivido) e a
## chance do próximo aperto. Mesmo valor do motor (clock_used / CLOCK_CHANCES) — nada é sorteado aqui.
func _clock_row(pos: Vector2, w: float, h: float, s: int, fs: int):
    var vis: String = ui.clock_visual(s)
    var used: int = ui.clock_used(s)
    var segs := Rules.CLOCK_SLOTS - 1
    var lit := segs if vis == "disparado" else used
    var col: Color = {"neutro": Color("e8b242"), "pulsando": Color("b068ff"), "perigo": Color("e02a36"), "quase": Color("e02a36"), "disparado": Color("e02a36")}[vis]
    var ch: float = 1.0 if vis == "disparado" else ui.clock_next_chance(s)
    var pct := "%d%%" % roundi(ch * 100.0)
    var tw_ := tw("100%", "ui_sp", fs) + 6
    var gap := maxf(2.0, h * 0.22)
    var sw := (w - tw_ - (segs - 1) * gap) / float(segs)
    draw_rect(Rect2(pos - Vector2(2, 2), Vector2(w - tw_ + 2, h + 4)), Color("0a1712"))
    for i in segs:
        var sr := Rect2(pos + Vector2(i * (sw + gap), 0), Vector2(sw, h))
        draw_rect(sr, Color("10241b"))
        draw_rect(sr, Color("2d4a3c"), false, 1.5)
        var blink: bool = ui.phase == "clock" and int(ui.result.get("loser", -1)) == s and i == used and int(ui.t * 5) % 2 == 0
        if i < lit or blink:
            draw_rect(sr.grow(-1.5), col)
    var pcol := Color("e8b242").lerp(Color("ff4a42"), clampf((ch - 0.12) / 0.6, 0.0, 1.0))
    text(pct, Vector2(pos.x + w - tw_ + 6, pos.y + h * 0.5 + fs * 0.36), "ui_sp", fs, pcol)

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
    if desk(): return _desk_plate(s)
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
            ui.hits.append({"rect": r, "id": "seat_%d" % s})     # R37: cartão de perfil (mouse / toque)
            panel(r, border, glow, fill_t, fill_b)
            var av := r.size.y - (24.0 if compact else 30.0)
            var ar := Rect2(r.position + Vector2(11, (r.size.y - av) / 2.0), Vector2(av, av))
            draw_rect(ar.grow(3), Color("120a06"))
            draw_rect(ar.grow(2), Color("d8d0bf") if not elim else Color("555"))
            draw_texture_rect(_avatar(s, elim), ar, false)
            _look(ar, ui.seat_look(s))
            if ui.online: VoiceGlyph.draw_seat_voice(self, ar, ui.voice(), s)   # R46 · quem está na voz / falando
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
            # R37 · relógio deste jogador, ao lado das coroas
            var rx := x + 2 + 2 * cw + cw * 0.27 + 10        # depois da coroa (centrada no espaço de 3)
            var rw := r.end.x - rx - 12.0
            if rw > 36: _clock_row(Vector2(rx, top + (10 if compact else 14)), rw, cw * 0.5, s, 14 if compact else 16)
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
            var h := (330.0 if not one_line else 304.0) * u      # R37: + linha do relógio do jogador
            var r := Rect2(c.x - w / 2.0, c.y - h / 2.0, w, h)
            ui.set_meta("plate_top_%d" % s, r.position.y)
            ui.hits.append({"rect": r, "id": "seat_%d" % s})     # R37: cartão de perfil (mouse / toque)
            panel(r, border, glow, fill_t, fill_b)
            var ar := Rect2(c.x - avs / 2.0, r.position.y + 13 * u, avs, avs)
            draw_rect(ar.grow(4), Color("120a06"))
            draw_rect(ar.grow(3), Color("d8c08a") if not elim else Color("555"))
            draw_rect(ar.grow(1), Color("5a3a12") if not elim else Color("333"))
            draw_texture_rect(_avatar(s, elim), ar, false)
            _look(ar, ui.seat_look(s))
            if ui.online: VoiceGlyph.draw_seat_voice(self, ar, ui.voice(), s)   # R46 · quem está na voz / falando
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
            _clock_row(Vector2(r.position.x + 14 * u, y), w - 28 * u, 14 * u, s, int(round(16 * u)))
            y += 26 * u
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
    if desk():
        w = tw(label_n, "o7", fs) + tw(label_t, "o7_sp", fs) + 32
        return _desk_bubble_style(Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h)), c, label_n, label_t, fs)
    var r := Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h))
    stair(r.grow(3), 3, Color("120a06"))
    stair(r, 3, Color("f6ecd2"))
    draw_rect(Rect2(r.position.x + 4, r.end.y - 4, r.size.x - 8, 2), Color("d6c7a1"))
    var x := r.position.x + 14
    text(label_n, Vector2(x, c.y + fs * 0.36), "ui", fs, Color("c8102e"))
    text(label_t, Vector2(x + tw(label_n, "ui", fs), c.y + fs * 0.36), "ui_sp", fs, Color("2a1505"))

func _draw_turn_banner():
    if desk(): return _desk_turn_banner()
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
    if desk(): return _desk_meter()
    var r: Rect2 = L().meter
    var who: int = ui.clock_focus()
    var vis: String = ui.clock_visual(who)
    panel(r)
    var compact: bool = ui.layout != "desktop"
    text("RELÓGIO DE XEQUE", r.position + Vector2(18, 33 if not compact else 31), "ui_sp4", 21 if not compact else 19, Color("e8b242"))
    var total: int = Rules.CLOCK_SLOTS
    var used: int = ui.clock_used(who)
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
    var owner: String = "Seu relógio" if who == 0 else String(ui.g.names[who])
    text(owner, Vector2(r.position.x, ty), "ui", fit(owner, "ui", 20, r.size.x * 0.34), Color("c9d6cf"), r.size.x - 18, HORIZONTAL_ALIGNMENT_RIGHT)
    # R36 · chance do próximo acionamento de quem está em foco (12% → 100%)
    var ch: float = ui.clock_next_chance(who) if vis != "disparado" else 1.0
    var ct := "%d%%" % roundi(ch * 100.0)
    var ccol := Color("e8b242").lerp(Color("ff4a42"), clampf((ch - 0.12) / 0.6, 0.0, 1.0))
    text(ct, Vector2(r.position.x, r.position.y + (33 if not compact else 31)), "ui_sp", 22 if not compact else 19, ccol, r.size.x - 18, HORIZONTAL_ALIGNMENT_RIGHT)

func _draw_xeque_button(active: bool):
    if desk(): return _desk_xeque_button(active)
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
    if desk(): return _desk_play_button()
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
    if desk(): return _desk_hint()
    var lines: Array = ui.help_text()
    if String(lines[0]).is_empty(): return
    var fs: int = h[1]
    rich(lines[0], h[0], "ui_sp", fs, Color("f6ecd2"), Color("ffd257"))
    rich(lines[1], h[0] + Vector2(0, fs * 1.3), "ui_sp", fs, Color("f6ecd2"), Color("ffd257"))

# ---------------------------------------------------------------- mão
func hand_layout() -> Array:
    if desk(): return _desk_hand_layout()
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
    if desk(): return _desk_hand()
    var g = ui.g
    var hand: Array = g.hands[0]
    var lay := hand_layout()
    var my_turn: bool = ui.phase == "" and g.turn == 0 and g.state == Rules.TURN_WAITING and not ui.input_locked
    var landed: int = ui.deal_landed(0)
    for i in hand.size():
        if i >= landed: continue            # distribuição: a carta ainda está voando
        var it: Dictionary = lay[i]
        var tex: Texture2D = ui.cards[hand[i]]
        var sz: Vector2 = tex.get_size() * it.sc
        if i in ui.selected:
            draw_set_transform(ui.origin + Vector2(it.c) * ui.k, it.rot, Vector2(ui.k, ui.k))
            var a := 0.55 + 0.25 * sin(ui.t * 6.0)
            for gi in 4: draw_rect(Rect2(-sz / 2.0, sz).grow(3 + gi * 3), Color(1, 0.85, 0.35, a * (0.5 - gi * 0.11)), false, 3.0)
            draw_rect(Rect2(-sz / 2.0, sz).grow(2), Color("ffd257"), false, 3.0)
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
        if hand[i] == Rules.JOKER:
            # R36 · Peão = CORINGA: aura verde-dourada pulsando em volta da carta (vale como qualquer peça)
            draw_set_transform(ui.origin + Vector2(it.c) * ui.k, it.rot, Vector2(ui.k, ui.k))
            var pj := 0.5 + 0.5 * sin(ui.t * 5.0 + i)
            for gj in 4: draw_rect(Rect2(-sz / 2.0, sz).grow(4 + gj * 4 + pj * 3), Color(0.35, 1.0, 0.55, 0.30 - gj * 0.07), false, 4.0)
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
        var mod := Color.WHITE if my_turn or g.turn != 0 else Color(0.9, 0.9, 0.9)
        var cpos: Vector2 = it.c
        if my_turn:
            # R37 · SUA VEZ: as cartas da mão brilham e "respiram" (onda que passa carta por carta)
            var wv := 0.5 + 0.5 * sin(ui.t * 4.0 - i * 0.7)
            if not (i in ui.selected): cpos = cpos + Vector2(0, -6.0 * wv)
            draw_set_transform(ui.origin + cpos * ui.k, it.rot, Vector2(ui.k, ui.k))
            for gk in 5: draw_rect(Rect2(-sz / 2.0, sz).grow(4 + gk * 5), Color(1.0, 0.82, 0.32, (0.16 - gk * 0.03) * (0.55 + 0.45 * wv)), false, 5.0)
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
            mod = Color(1.0 + 0.16 * wv, 1.0 + 0.13 * wv, 1.0 + 0.04 * wv)
        tex_center(tex, cpos, it.sc, it.rot, mod)
        if hand[i] == Rules.JOKER:
            var tagc := Vector2(it.c) + Vector2(0, -sz.y / 2.0 - 16)
            chip(Rect2(tagc - Vector2(62, 15), Vector2(124, 30)), "CORINGA", Color("1d7a4a"), Color("ffd257"), Color("fff1c2"), 18)
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
    if desk(): _desk_reveal_cards()
    for i in (0 if desk() else n):
        # R37.2 · as cartas viram devagar, uma de cada vez (tempos em xeque_ui.gd: FLIP_*)
        var flip: float = ui.flip_progress(i) if ui.phase == "reveal" else 1.0
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
        draw_texture_rect(Crisp.at(tex, sz * ui.k), Rect2(-sz / 2.0, sz), false)
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
    var fk := "o7_sp" if desk() else "ui_sp"      # R55 · PC: a fonte da referência
    var w := tw(said + " · ", fk, fs) + tw(tail, fk, fs) + 40
    var by := base.y + (105.0 + 30.0 if desk() else 360.0 * sc * 1.4 * 0.5 + 26)
    var br := Rect2(base.x - w / 2.0, by, w, fs * 1.6)
    stair(br.grow(3), 3, Color("120a06"))
    stair(br, 3, Color("f6ecd2"))
    var x := br.position.x + 20
    var yy: float = br.get_center().y + fs * (0.405 if desk() else 0.36)
    text(said + " · ", Vector2(x, yy), fk, fs, Color("2a1505"))
    text(tail, Vector2(x + tw(said + " · ", fk, fs), yy), fk, fs, tail_col)

func _declared(n: int, target: String) -> String:
    return "%d %s" % [n, String(Rules.NAMES[target] if n == 1 else Rules.PLURAL[target]).to_upper()]

func _draw_safe():
    var r: Dictionary = ui.result
    var ml: Array = L().mate_line
    var name: String = ui.g.names[int(r.loser)]
    var w := 0.0
    var l1 := "O RELÓGIO NÃO DISPAROU"
    var nxt: float = ui.g.clock_chance(int(r.loser))
    var l2 := "%s ESCAPOU · PRÓXIMO ACIONAMENTO: %s" % [name.to_upper(), ("%d%% DE XEQUE-MATE" % roundi(nxt * 100.0)) if nxt < 1.0 else "XEQUE-MATE CERTO"]
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
    # R36 · onda de choque e clarão saindo do relógio
    var pt: float = ui.phase_t
    for k in 3:
        var tk := pt - k * 0.18
        if tk > 0.0 and tk < 1.1:
            var rad := 40.0 + tk * 1100.0
            draw_arc(mc[0], rad, 0, TAU, 72, Color(1.0, 0.75 - k * 0.2, 0.4 - k * 0.1, (1.0 - tk / 1.1) * 0.85), 26.0 * (1.0 - tk / 1.1) + 3.0)
    if pt < 0.5:
        for gl in 6: draw_circle(mc[0], (90.0 + gl * 60.0) * (0.6 + pt), Color(1.0, 0.85, 0.5, (0.5 - pt) * (0.28 - gl * 0.04)))
    var pop := 1.0 + 0.55 * maxf(0.0, 1.0 - pt / 0.25)
    tex_center(ui.clock_tex["disparado"], mc[0] + shake, mc[1] * 2.0 * pop)
    if ui.phase == "mate": _draw_reveal(true)
    var mt: Array = L().mate_title
    var title := "Xeque-Mate" if ui.phase == "mate" else "Eliminado"
    var tfs: int = mt[1]
    tfs = fit(title, "title", tfs, d.x - 80)
    # R36 · o título cai pesado (escala 2,4 → 1) e treme junto com a tela
    var ts := 1.0 + 1.4 * pow(maxf(0.0, 1.0 - (pt - 0.15) / 0.3), 2.0) if pt > 0.15 else 0.0
    if ts > 0.0:
        var tc := Vector2(d.x / 2.0, mt[0].y - tfs * 0.35)
        draw_set_transform(ui.origin + tc * ui.k, 0.0, Vector2(ui.k * ts, ui.k * ts))
        text(title, Vector2(-d.x / 2.0, tfs * 0.35), "title", tfs, Color("fff1d6"), d.x, HORIZONTAL_ALIGNMENT_CENTER, 14, Color("2a0a06"))
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
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
            button_dark(Rect2(880, 914, 220, 92), "VOLTAR", "tut_back", 50)
            button_dark(Rect2(1120, 914, 256, 92), "CONVIDAR", "tut_invite", 46)
            button_gold(Rect2(1396, 912, 372, 96), "JOGAR AGORA", "tut_play", true, 58)
        else:
            button_dark(Rect2(90, 1752, 250, 96), "VOLTAR", "tut_back", 44)
            button_dark(Rect2(356, 1752, 290, 96), "CONVIDAR", "tut_invite", 44)
            button_gold(Rect2(662, 1750, 328, 100), "JOGAR", "tut_play", true, 50)

func _tutorial_panels() -> Array:
    return [
        {"title": "OBJETIVO", "text": "Quatro jogadores à mesa. Vence o *último jogador de pé*.", "art": "crowns"},
        {"title": "AS CARTAS", "text": "*%d cartas*: %d Rei, %d Rainha, %d Cavalo e %d Peão Coroado, o *CORINGA*. %d para cada um." % [Rules.deck_size(), Rules.DECK_COUNTS[Rules.KING], Rules.DECK_COUNTS[Rules.QUEEN], Rules.DECK_COUNTS[Rules.KNIGHT], Rules.DECK_COUNTS[Rules.JOKER], Rules.HAND], "art": "cards"},
        {"title": "SUA VEZ", "text": "Baixe de *1 a 3 cartas viradas* e diga que são a peça pedida. Pode ser verdade. Pode ser blefe.", "art": "backs"},
        {"title": "XEQUE", "text": "O próximo jogador joga ou aperta *XEQUE* na jogada anterior: as cartas dela são reveladas.", "art": "xeque"},
        {"title": "RELÓGIO DE XEQUE", "text": "*Quem perde o desafio aciona o seu Relógio*: pode estourar já no primeiro aperto (%d%%) e o perigo sobe a cada nível, até %d%%." % [roundi(Rules.CLOCK_CHANCES[0] * 100.0), roundi(Rules.CLOCK_CHANCES[-1] * 100.0)], "art": "clocks"},
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
            arrow(Vector2(x3 - 44, c.y + 12), Color("e8b242"))
        "clocks":
            var names2 := ["neutro", "perigo", "quase"]   # 6 posições: neutro → em perigo → quase disparando
            for i in 3:
                tex_center(ui.clock_tex[names2[i]], c + Vector2((i - 1) * 140, 4), (a.size.y + 30) / 560.0)
                if i < 2: arrow(Vector2(c.x + (i - 1) * 140 + 56, c.y + 12), Color("e8b242"))
        "mate":
            tex_center(ui.clock_tex["disparado"], c + Vector2(-120, 4), (a.size.y + 40) / 560.0)
            arrow(Vector2(c.x - 30, c.y + 12), Color("e8b242"))
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
    var ot: float = ui.over_t
    # R36 · raios girando atrás do título (vitória) / pulso vermelho escuro (derrota)
    var tyb := 214.0 if not portrait else 230.0
    var tc := Vector2(cx, tyb - 80)
    if won:
        var grow := clampf(ot / 0.7, 0.0, 1.0)
        for i in 20:
            var a := ot * 0.3 + TAU * i / 20.0
            var ln := (700.0 + 160.0 * (i % 3)) * grow
            draw_colored_polygon(PackedVector2Array([tc, tc + Vector2.from_angle(a - 0.06) * ln, tc + Vector2.from_angle(a + 0.06) * ln]), Color(1.0, 0.84, 0.35, 0.12 + 0.05 * (i % 2)))
    else:
        var pul := 0.5 + 0.5 * sin(ot * 2.4)
        draw_rect(Rect2(Vector2(-3000, -3000), Vector2(8000, 8000)), Color(0.35, 0.02, 0.02, 0.10 + 0.08 * pul))
    # título entra pesado (escala 2,2 → 1) com um tremor curto
    var ts := 1.0 + 1.2 * pow(maxf(0.0, 1.0 - ot / 0.35), 2.0)
    var tsh := Vector2(sin(ot * 80.0), cos(ot * 61.0)) * 10.0 * maxf(0.0, 1.0 - (ot - 0.3) / 0.4) if ot > 0.3 else Vector2.ZERO
    draw_set_transform(ui.origin + (tc + tsh) * ui.k, 0.0, Vector2(ui.k * ts, ui.k * ts))
    text(title, Vector2(-d.x / 2.0, tyb - tc.y), "title", 232 if not portrait else 190, tcol, d.x, HORIZONTAL_ALIGNMENT_CENTER, 10, Color("2a1206"))
    draw_string(font("title"), Vector2(-d.x / 2.0, tyb - 6 - tc.y), title, HORIZONTAL_ALIGNMENT_CENTER, d.x, 232 if not portrait else 190, Color(1, 0.95, 0.7, 0.25))
    draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
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


# ---------------------------------------------------------------- R36 · efeitos de tela
func _draw_fx():
    var d: Vector2 = ui.design
    var big := Rect2(Vector2(-3000, -3000), Vector2(8000, 8000))
    # partículas: estilhaços, faíscas, fumaça, confete
    for q in ui.particles:
        var a: float = clampf(q.life / q.max, 0.0, 1.0)
        var c: Color = q.col
        match String(q.kind):
            "smoke":
                draw_circle(q.p, float(q.size) * (1.6 - a * 0.6), Color(c.r, c.g, c.b, c.a * a * 0.8))
            "spark":
                draw_line(q.p, q.p - Vector2(q.v) * 0.03, Color(c.r, c.g, c.b, a), float(q.size) * 0.6)
                draw_circle(q.p, float(q.size) * 0.5, Color(1, 1, 0.9, a))
            "confetti", "ash":
                var u := Vector2.from_angle(q.rot) * float(q.size) * 0.5
                var v := Vector2.from_angle(q.rot + PI / 2) * float(q.size) * 0.3 * absf(sin(q.rot * 2.0))
                draw_colored_polygon(PackedVector2Array([q.p - u - v, q.p + u - v, q.p + u + v, q.p - u + v]), Color(c.r, c.g, c.b, a if q.kind == "confetti" else a * 0.7))
            _:
                var u2 := Vector2.from_angle(q.rot) * float(q.size)
                var v2 := Vector2.from_angle(q.rot + 2.2) * float(q.size) * 0.6
                draw_colored_polygon(PackedVector2Array([q.p + u2, q.p + v2, q.p - u2 * 0.7]), Color(c.r, c.g, c.b, a))
    # carimbo grande ("XEQUE!")
    if not ui.slam.is_empty():
        var st: float = ui.slam.t
        var sc := 1.0 + 2.2 * pow(maxf(0.0, 1.0 - st / 0.22), 2.0)
        var al := clampf(1.0 - (st - 1.0) / 0.6, 0.0, 1.0)
        var cc := Vector2(d.x / 2.0, d.y * 0.42)
        draw_set_transform(ui.origin + cc * ui.k, -0.06, Vector2(ui.k * sc, ui.k * sc))
        var txt: String = ui.slam.text
        var col: Color = ui.slam.col
        var fs := 210 if ui.layout != "portrait" else 170
        for i in 3: draw_rect(Rect2(-d.x, -fs * 0.62 - i * 6, d.x * 2, fs * 1.1 + i * 12), Color(0.1, 0.0, 0.0, 0.10 * al))
        text(txt, Vector2(-d.x / 2.0 + 8, fs * 0.36 + 8), "title", fs, Color(0, 0, 0, 0.55 * al), d.x, HORIZONTAL_ALIGNMENT_CENTER)
        text(txt, Vector2(-d.x / 2.0, fs * 0.36), "title", fs, Color(col.r, col.g, col.b, al), d.x, HORIZONTAL_ALIGNMENT_CENTER, 16, Color(0.16, 0.02, 0.0, al))
        if String(ui.slam.sub) != "":
            text(String(ui.slam.sub), Vector2(-d.x / 2.0, fs * 0.36 + 70), "ui_sp4", 44, Color(1, 0.94, 0.8, al), d.x, HORIZONTAL_ALIGNMENT_CENTER, 8, Color(0.16, 0.02, 0.0, al))
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
    # tensão do relógio: borda vermelha pulsando no ritmo do coração
    if ui.phase == "clock":
        var hb := pow(maxf(0.0, sin(ui.phase_t * TAU / 0.62)), 6.0)
        for i in 8: draw_rect(Rect2(Vector2(-i * 14, -i * 14), d + Vector2(i * 28, i * 28)), Color(0.8, 0.05, 0.05, (0.10 + 0.18 * hb) * (1.0 - i / 8.0)), false, 30.0)
    # clarão
    if ui.flash_col.a > 0.01: draw_rect(big, ui.flash_col)

## Apresentação do baralho (antes da 1ª rodada): as 4 cartas entram em leque com a quantidade de cada uma.
func _draw_intro():
    var d: Vector2 = ui.design
    var t: float = ui.intro_anim
    var fade_in := clampf(t / 0.3, 0.0, 1.0)
    var fade_out := clampf((ui.INTRO_T - t) / 0.4, 0.0, 1.0)
    var al := fade_in * fade_out
    draw_rect(Rect2(Vector2(-3000, -3000), Vector2(8000, 8000)), Color(0.02, 0.03, 0.02, 0.78 * al))
    var portrait: bool = ui.layout == "portrait"
    text("O BARALHO DESTA PARTIDA", Vector2(0, d.y * (0.2 if not portrait else 0.22)), "title", 86 if not portrait else 70, Color(1, 0.86, 0.45, al), d.x, HORIZONTAL_ALIGNMENT_CENTER, 10, Color(0.1, 0.05, 0, al))
    # a fonte é o motor: Rules.DECK_COUNTS / Rules.HAND (a UI não guarda números próprios)
    var kinds: Array = Rules.TARGETS + [Rules.JOKER]
    var counts: Dictionary = Rules.DECK_COUNTS
    var cw := 300.0 if not portrait else 230.0
    var sc := cw / 360.0
    var gap := 40.0 if not portrait else 18.0
    var total := 4 * cw + 3 * gap
    var y := d.y * (0.52 if not portrait else 0.5)
    for i in 4:
        var ti := clampf((t - 0.25 - i * 0.18) / 0.35, 0.0, 1.0)
        if ti <= 0.0: continue
        var e := 1.0 - pow(1.0 - ti, 3.0)
        var x := d.x / 2.0 - total / 2.0 + cw / 2.0 + i * (cw + gap)
        var c := Vector2(x, y + (1.0 - e) * 260.0)
        var rot := deg_to_rad((i - 1.5) * 4.0) * e
        var tex: Texture2D = ui.cards[kinds[i]]
        var sz := tex.get_size() * sc
        draw_set_transform(ui.origin + c * ui.k, rot, Vector2(ui.k, ui.k))
        if kinds[i] == Rules.JOKER:
            var pul := 0.5 + 0.5 * sin(ui.t * 6.0)
            for gl in 5: draw_rect(Rect2(-sz / 2.0, sz).grow(6 + gl * 6 + pul * 4), Color(0.3, 1.0, 0.55, (0.20 - gl * 0.035) * al), false, 6.0)
        draw_rect(Rect2(-sz / 2.0 + Vector2(8, 10), sz), Color(0, 0, 0, 0.45 * al))
        draw_texture_rect(tex, Rect2(-sz / 2.0, sz), false, Color(1, 1, 1, al))
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
        # quantidade grande embaixo (entra com um pulo)
        var tn := clampf((t - 0.7 - i * 0.18) / 0.25, 0.0, 1.0)
        if tn > 0.0:
            var bump := 1.0 + 0.6 * (1.0 - tn)
            var label := ("%d ×" % counts[kinds[i]]) if kinds[i] != Rules.JOKER else ("%d × CORINGA" % counts[kinds[i]])
            var fs := int((64 if not portrait else 48) * bump)
            text(label, Vector2(x - cw, y + sz.y / 2.0 + 70), "ui_sp4", fs, Color("7cf0a0") if kinds[i] == Rules.JOKER else Color("ffd257"), cw * 2.0, HORIZONTAL_ALIGNMENT_CENTER, 8, Color(0.1, 0.05, 0, al))
    var foot_al := al * clampf((t - 1.4) / 0.4, 0.0, 1.0)
    var foot := "%d CARTAS  ·  %d PARA CADA JOGADOR" % [Rules.deck_size(), Rules.HAND]
    if portrait:
        text(foot, Vector2(0, d.y * 0.68), "ui_sp4", 32, Color(0.95, 0.92, 0.82, foot_al), d.x, HORIZONTAL_ALIGNMENT_CENTER, 6, Color(0, 0, 0, al))
        text("O PEÃO VALE COMO QUALQUER PEÇA", Vector2(0, d.y * 0.68 + 46), "ui_sp4", 32, Color(0.49, 0.94, 0.63, foot_al), d.x, HORIZONTAL_ALIGNMENT_CENTER, 6, Color(0, 0, 0, al))
    else:
        text(foot + "  ·  O PEÃO VALE COMO QUALQUER PEÇA", Vector2(0, d.y * 0.9), "ui_sp4", 38, Color(0.95, 0.92, 0.82, foot_al), d.x, HORIZONTAL_ALIGNMENT_CENTER, 6, Color(0, 0, 0, al))

# ================================================================ R55 · PC: visual da referência nova
# (tools/ui_ref/xeque/xeque_ref_r55.png). Painéis azul-marinho com moldura dourada e cantos, faixa vinho
# nos títulos, chips de borda azul-aço, faixa da vez azul, botão XEQUE de aço e JOGAR CARTAS vinho, e
# cartas com o texto desenhado AO VIVO no tamanho exato da tela (nítido). Só o PC; celular sem mudança.
const NAVY_T := Color("13264d")
const NAVY_B := Color("0a1631")
const FRAME_GOLD := Color("d6a23c")
const FRAME_HI := Color("ffe39a")
const WINE_T := Color("7c1322")
const WINE_B := Color("4a0911")
const STEEL := Color("3d5a88")
const CHIP_FILL := Color("0b1832")
const CREAM_TXT := Color("f4efe4")
const CARD_TEXT := {"rei": ["PEÇA", "Pode ser a peça pedida", Color("ff6a5c")], "rainha": ["PEÇA", "Pode ser a peça pedida", Color("ffd257")],
    "cavalo": ["PEÇA", "Pode ser a peça pedida", Color("5d8eff")], "peao": ["CORINGA", "Vale como qualquer peça", Color("38c483")]}

func desk() -> bool:
    return ui.layout == "desktop"

func grad(r: Rect2, top: Color, bot: Color):
    draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))

## Painel da referência: borda escura, moldura dourada fina com brilho, miolo azul-marinho (ou vinho→azul)
## e, se header > 0, faixa vinho no alto (títulos A MESA PEDE / COMO JOGAR). Cantos com ornamento dourado.
func npanel(r: Rect2, header := 0.0, border: Color = FRAME_GOLD, glow := false, wine_full := false, fill_t: Color = NAVY_T, fill_b: Color = NAVY_B):
    if glow:
        for i in 5: draw_rect(r.grow(4 + i * 3), Color(border.r, border.g, border.b, 0.16 - i * 0.03), false, 3.0)
    draw_rect(r.grow(3), Color("0b0703"))
    draw_rect(r, border.darkened(0.25))
    draw_rect(Rect2(r.position, Vector2(r.size.x, 1.5)), border.lightened(0.45))
    draw_rect(r.grow(-1.5), border)
    var inner := r.grow(-3.5)
    draw_rect(inner, Color("0d0904"))
    var f := inner.grow(-1.0)
    if wine_full:
        grad(Rect2(f.position, Vector2(f.size.x, f.size.y * 0.45)), WINE_T, WINE_B.lerp(fill_t, 0.4))
        grad(Rect2(f.position + Vector2(0, f.size.y * 0.45), Vector2(f.size.x, f.size.y * 0.55)), WINE_B.lerp(fill_t, 0.4), fill_b)
    else:
        grad(f, fill_t, fill_b)
    if header > 0.0:
        var hb := Rect2(f.position, Vector2(f.size.x, header))
        grad(hb, WINE_T, WINE_B)
        draw_rect(Rect2(hb.position.x, hb.end.y - 2, hb.size.x, 2), Color(0.02, 0.01, 0.01, 0.8))
        draw_rect(Rect2(hb.position.x, hb.position.y, hb.size.x, 1), Color(1, 0.6, 0.5, 0.18))
    corners(r, border)

## Cantoneiras douradas (L com ponto) nos quatro cantos da moldura.
func corners(r: Rect2, col: Color = FRAME_GOLD, s := 11.0):
    for c in [[r.position, 1, 1], [Vector2(r.end.x, r.position.y), -1, 1], [Vector2(r.position.x, r.end.y), 1, -1], [r.end, -1, -1]]:
        var p: Vector2 = c[0]
        var dx: float = c[1]
        var dy: float = c[2]
        var a := PackedVector2Array([p + Vector2(-2 * dx, -2 * dy), p + Vector2((s + 1) * dx, -2 * dy), p + Vector2((s + 1) * dx, 2 * dy), p + Vector2(2 * dx, 2 * dy), p + Vector2(2 * dx, (s + 1) * dy), p + Vector2(-2 * dx, (s + 1) * dy)])
        draw_colored_polygon(a, Color("0b0703"))
        var b := PackedVector2Array([p + Vector2(-0.5 * dx, -0.5 * dy), p + Vector2(s * dx, -0.5 * dy), p + Vector2(s * dx, 1.2 * dy), p + Vector2(1.2 * dx, 1.2 * dy), p + Vector2(1.2 * dx, s * dy), p + Vector2(-0.5 * dx, s * dy)])
        draw_colored_polygon(b, col.lightened(0.15))
        var q := p + Vector2(4.5 * dx, 4.5 * dy)
        draw_colored_polygon(PackedVector2Array([q + Vector2(0, -2.2), q + Vector2(2.2, 0), q + Vector2(0, 2.2), q + Vector2(-2.2, 0)]), FRAME_HI)

## Chip da referência: miolo azul-escuro, borda azul-aço, texto claro (Oswald).
func nchip(r: Rect2, label: String, fill: Color = CHIP_FILL, border: Color = STEEL, col: Color = CREAM_TXT, fs := 18, glow := false):
    if glow:
        for i in 3: draw_rect(r.grow(2 + i * 2), Color(border.r, border.g, border.b, 0.22 - i * 0.07), false, 2.0)
    draw_rect(r.grow(1), Color("05080f"))
    draw_rect(r, border)
    draw_rect(r.grow(-2), fill)
    var f := fit(label, "o7_sp", fs, r.size.x - 12)
    text(label, Vector2(r.position.x, r.get_center().y + f * 0.405), "o7_sp", f, col, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)

## Texto com contorno (títulos grandes da referência).
func otext(s: String, pos: Vector2, key: String, fs: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 4):
    text(s, pos, key, fs, col, width, align, outline, Color(0.03, 0.02, 0.01, 0.92))

# ---------------------------------------------------------------- cartas nítidas
## Carta (frente) na posição c (centro, px de referência), largura w; o texto (nome, PEÇA/CORINGA e a linha
## pequena) é desenhado em pixels de TELA no tamanho exato: sempre nítido. squash < 1 = carta virando.
func card_face(kind: String, c: Vector2, w: float, rot := 0.0, mod: Color = Color.WHITE, squash := 1.0):
    var tex: Texture2D = ui.cards_clean.get(kind, ui.cards.get(kind))
    var want: Vector2 = Vector2(w, w * 1.4) * ui.k
    var t := Crisp.at(tex, want)
    var px: Vector2 = t.get_size() if t != tex else want         # 1:1 com a textura reduzida (sem reamostrar)
    var center: Vector2 = ui.origin + c * ui.k
    draw_set_transform(center, rot, Vector2(maxf(0.04, squash), 1.0))
    draw_rect(Rect2(-px / 2.0 + Vector2(3, 4), px), Color(0, 0, 0, 0.35))
    draw_texture_rect(t, Rect2((-px / 2.0).round(), px), false, mod)
    if squash >= 0.97 and ui.cards_clean.has(kind):
        var u := px.x / 720.0
        var tl := -px / 2.0
        var info: Array = CARD_TEXT.get(kind, ["", "", Color.WHITE])
        var name := String(Rules.NAMES.get(kind, kind)).to_upper()
        var nf := maxi(9, int(round(94.0 * u)))
        var room := 600.0 * u
        while nf > 8 and tw(name, "o7", nf) > room: nf -= 1
        var ny := tl.y + 790.0 * u + nf * 0.405
        var ol := maxi(2, int(round(nf * 0.16)))
        draw_string_outline(font("o7"), Vector2(tl.x, ny).round(), name, HORIZONTAL_ALIGNMENT_CENTER, px.x, nf, ol, Color(0.03, 0.02, 0.01, 0.95))
        draw_string(font("o7"), Vector2(tl.x, ny).round(), name, HORIZONTAL_ALIGNMENT_CENTER, px.x, nf, Color("fbf3dc"))
        var wf := maxi(8, int(round(52.0 * u)))
        draw_string(font("o7_sp3"), Vector2(tl.x, tl.y + 905.0 * u).round(), String(info[0]), HORIZONTAL_ALIGNMENT_CENTER, px.x, wf, info[2])
        var lf := maxi(8, int(round(48.0 * u)))
        while lf > 7 and font("o6").get_string_size(String(info[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, lf).x > 640.0 * u: lf -= 1
        draw_string(font("o6"), Vector2(tl.x, tl.y + 958.0 * u).round(), String(info[1]), HORIZONTAL_ALIGNMENT_CENTER, px.x, lf, Color("ece2c8"))
    draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))

# ---------------------------------------------------------------- R55 · partes da tela (PC)
func _desk_title():
    draw_texture_rect(ui.LOGO_R55, Rect2(36, 0, 340, 130), false)
    var sub := "RODADA %d · BLEFE DE CARTAS" % ui.g.round_no
    otext(sub, Vector2(46, 141), "o7_sp3", fit(sub, "o7_sp3", 18, 316), Color("ecc35e"), -1, HORIZONTAL_ALIGNMENT_LEFT, 3)

func _desk_mesa_pede():
    var r: Rect2 = L().mesa
    var g = ui.g
    var landing: float = clampf((ui.mesa_anim - 1.45) / 0.45, 0.0, 1.0) if ui.mesa_anim >= 0.0 else 0.0
    var pulse := 0.5 + 0.5 * sin(ui.t * 3.2)
    for i in 4: draw_rect(r.grow(5 + i * 3), Color(1.0, 0.82, 0.3, (0.07 - i * 0.015) * (0.6 + 0.4 * pulse)), false, 3.0)
    npanel(r, 47.0, FRAME_GOLD.lerp(Color("fff3c0"), landing))
    otext("A MESA PEDE", Vector2(r.position.x + 23, r.position.y + 36), "o7_sp3", 18, Color("f7cf5c"), -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
    var name: String = String(Rules.NAMES[g.target]).to_upper()
    var plural: String = Rules.PLURAL[g.target]
    # a carta da rodada, levemente inclinada, com moldura dourada fina
    var cc := Vector2(r.position.x + 81, r.position.y + 126)
    card_face(String(g.target), cc, 104.0, -0.05)
    var x := r.position.x + 148
    var big := fit(name, "o7", 60, r.end.x - x - 14)
    otext(name, Vector2(x, r.position.y + 122), "o7", big, Color("f8ecd0"), -1, HORIZONTAL_ALIGNMENT_LEFT, 5)
    var l2 := "são %s" % plural.to_lower()
    text("Diga que suas cartas", Vector2(x, r.position.y + 156), "o6_sp", 19, Color("ece7dc"))
    text(l2, Vector2(x, r.position.y + 182), "o6_sp", fit(l2, "o6_sp", 19, r.end.x - x - 10), Color("ece7dc"))

func _desk_como_jogar(r: Rect2):
    npanel(r, 46.0)
    otext("COMO JOGAR", Vector2(r.position.x + 23, r.position.y + 37), "o7_sp3", 18, Color("f7cf5c"), -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
    var steps := [["A mesa pede uma peça."], ["Baixe de 1 a 3 cartas", "viradas e diga que são", "essa peça."], ["Duvidou de alguém? *XEQUE!*"], ["Quem errou aciona o seu", "Relógio. Se disparar, é", "xeque-mate: está fora."]]
    var base := [83.0, 127.0, 225.0, 268.0]
    for i in steps.size():
        var y: float = r.position.y + base[i]
        var nb := Rect2(r.position.x + 26, y - 26, 35, 34)
        draw_rect(nb.grow(1.5), Color("0b0703"))
        grad(nb, Color("ffd76a"), Color("e09a2c"))
        draw_rect(Rect2(nb.position, Vector2(nb.size.x, 2)), Color(1, 1, 0.85, 0.7))
        text(str(i + 1), Vector2(nb.position.x, nb.position.y + 26), "o7", 23, Color("2a1505"), nb.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        for line in steps[i]:
            var parts := String(line).split("*")
            var x := r.position.x + 77
            for j in parts.size():
                var red: bool = j % 2 == 1
                text(parts[j], Vector2(x, y), "o7_sp" if red else "o6_sp", 19, Color("ff4b44") if red else Color("f1ede4"), -1, HORIZONTAL_ALIGNMENT_LEFT, 2 if red else 0)
                x += tw(parts[j], "o7_sp" if red else "o6_sp", 19)
            y += 29.0

func _desk_status_chip(r: Rect2, st: Dictionary, fs := 17):
    match String(st.id):
        "sua_vez": nchip(r, st.text, Color("ffd257"), Color("fff0b0"), Color("2a1505"), fs)
        "pensando": nchip(r, st.text, Color("0f2d5e"), Color("86bdf5"), Color("d8ecff"), fs, true)
        "em_risco": nchip(r, st.text, Color("8f0f1c"), Color("ff5a52"), Color("fff1ec"), fs, true)
        "xeque_mate": nchip(r, st.text, Color("c11a28"), Color("ff7a70"), Color("fff6ee"), fs, true)
        "com_o_relogio": nchip(r, st.text, Color("2a1544"), Color("b880ff"), Color("eedcff"), fs, true)
        "eliminado": nchip(r, st.text, Color("1a1c1f"), Color("4a4d52"), Color("8d9092"), fs)
        _: nchip(r, st.text, CHIP_FILL, STEEL, CREAM_TXT, fs)

func _desk_bot_tag(r: Rect2, tag: String, elim: bool):
    var f := Color("a9d4f5") if not elim else Color("55595e")
    draw_rect(r.grow(1), Color("05080f"))
    draw_rect(r, f)
    var fs := fit(tag, "o7_sp", int(r.size.y * 0.72), r.size.x - 8)
    text(tag, Vector2(r.position.x, r.get_center().y + fs * 0.405), "o7_sp", fs, Color("0c2340"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)

func _desk_clock_row(pos: Vector2, w: float, h: float, s: int, fs: int):
    var vis: String = ui.clock_visual(s)
    var used: int = ui.clock_used(s)
    var segs := Rules.CLOCK_SLOTS - 1
    var lit := segs if vis == "disparado" else used
    var col: Color = {"neutro": Color("f2bd3c"), "pulsando": Color("b068ff"), "perigo": Color("e02a36"), "quase": Color("e02a36"), "disparado": Color("e02a36")}[vis]
    var ch: float = 1.0 if vis == "disparado" else ui.clock_next_chance(s)
    var pct := "%d%%" % roundi(ch * 100.0)
    var tw_ := tw(pct, "o7", fs) + 8
    var gap := maxf(2.0, h * 0.28)
    var sw := (w - tw_ - (segs - 1) * gap) / float(segs)
    for i in segs:
        var sr := Rect2(pos + Vector2(i * (sw + gap), 0), Vector2(sw, h))
        draw_rect(sr, Color("0a1530"))
        draw_rect(sr, STEEL, false, 1.5)
        var blink: bool = ui.phase == "clock" and int(ui.result.get("loser", -1)) == s and i == used and int(ui.t * 5) % 2 == 0
        if i < lit or blink: draw_rect(sr.grow(-1.5), col)
    var pcol := Color("f2c14e").lerp(Color("ff4a42"), clampf((ch - 0.12) / 0.6, 0.0, 1.0))
    text(pct, Vector2(pos.x + w - tw_ + 6, pos.y + h * 0.5 + fs * 0.405), "o7", fs, pcol)

func _desk_cards_count(pos: Vector2, s: int, fs: int):
    var n: int = ui.g.hands[s].size()
    var h := fs * 1.15
    var w := h * 0.71
    var r := Rect2(pos - Vector2(0, h * 0.85), Vector2(w, h))
    draw_rect(r.grow(1.5), Color("d6a23c"))
    draw_texture_rect(ui.CARD_BACK, r, false)
    text("×%d" % n, pos + Vector2(w + 5, 0), "o7", fs, CREAM_TXT)

## Retrato com moldura dourada fina e cantos (placas dos jogadores).
func _desk_portrait(ar: Rect2, s: int, elim: bool):
    draw_rect(ar.grow(5), Color("0b0703"))
    draw_rect(ar.grow(4), FRAME_GOLD if not elim else Color("55595e"))
    draw_rect(ar.grow(2.5), Color("0b0703"))
    draw_rect(ar.grow(1.5), Color("f0d48a") if not elim else Color("6a6d70"))
    draw_texture_rect(_avatar(s, elim), ar, false)
    for p in [ar.position, Vector2(ar.end.x, ar.position.y), Vector2(ar.position.x, ar.end.y), ar.end]:
        draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), FRAME_HI)

func _desk_plate(s: int):
    var g = ui.g
    var spec: Array = L().plates[s]
    var st: Dictionary = ui.seat_status(s)
    var elim: bool = st.id == "eliminado"
    var border: Color = {"em_risco": Color("ff5a52"), "xeque_mate": Color("ff5a52"), "com_o_relogio": Color("b880ff"), "sua_vez": Color("ffe08a"), "eliminado": Color("55595e")}.get(st.id, FRAME_GOLD)
    var glow: bool = st.id in ["xeque_mate", "com_o_relogio", "em_risco", "sua_vez"]
    var ft := Color("1d2024") if elim else NAVY_T
    var fb := Color("121417") if elim else NAVY_B
    var name: String = g.names[s]
    var bot := s != 0
    var tag: String = ui.seat_tag(s)
    var namecol := Color("8d9092") if elim else Color("f6f3ec")
    match spec[0]:
        "h", "hc":
            var r: Rect2 = spec[1]
            var compact: bool = spec[0] == "hc"
            ui.hits.append({"rect": r, "id": "seat_%d" % s})
            npanel(r, 0.0, border, glow, false, ft, fb)
            var av := r.size.y - (24.0 if compact else 28.0)
            var ar := Rect2(r.position + Vector2(14, (r.size.y - av) / 2.0), Vector2(av, av))
            _desk_portrait(ar, s, elim)
            _look(ar, ui.seat_look(s))
            if ui.online: VoiceGlyph.draw_seat_voice(self, ar, ui.voice(), s)
            var x := ar.end.x + 14
            var nfs := 22 if compact else 25
            var top := r.position.y + (32 if compact else 42)
            nfs = fit(name, "o6", nfs, r.end.x - x - (54 if bot else 10))
            otext(name, Vector2(x, top), "o6", nfs, namecol, -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
            if bot:
                var bw := 44.0 * (1.45 if tag != "BOT" else 1.0)
                _desk_bot_tag(Rect2(x + tw(name, "o6", nfs) + 10, top - nfs * 0.82, bw, nfs * 0.9), tag, elim)
            # linha da referência: coroa(s), 5 casas do relógio e a chance (%)
            var cw := 28.0 if compact else 32.0
            var row_y := top + (12 if compact else 16)
            var crown_left := x + (44.0 if compact else 50.0)
            _crowns(Vector2(crown_left - (3 - Rules.LIVES) * (cw + cw * 0.27) / 2.0, row_y), s, cw, cw * 0.27, elim)
            var rx := crown_left + Rules.LIVES * (cw + cw * 0.27) + 8
            var rw := r.end.x - rx - 12.0
            if rw > 36: _desk_clock_row(Vector2(rx, row_y + 2), rw, cw * 0.52, s, 16 if compact else 18)
            var chh := 26.0 if compact else 30.0
            var cy := r.end.y - chh - (12 if compact else 14)
            var label: String = st.text
            var chw := maxf(tw(label, "o7_sp", 17) + 26, 112)
            _desk_status_chip(Rect2(x, cy, chw, chh), st)
            if s != 0: _desk_cards_count(Vector2(r.end.x - 50, r.end.y - 16), s, 20 if compact else 22)
        "v":
            var c: Vector2 = spec[1]
            var w: float = spec[2]
            var u := w / 180.0
            var nfs := fit(name, "o6", int(round(24 * u)), w - 16)
            var h := 302.0 * u
            var r := Rect2(c.x - w / 2.0, c.y - h / 2.0, w, h)
            ui.set_meta("plate_top_%d" % s, r.position.y)
            ui.hits.append({"rect": r, "id": "seat_%d" % s})
            npanel(r, 0.0, border, glow, false, ft, fb)
            var avs := 86.0 * u
            var ar := Rect2(c.x - avs / 2.0, r.position.y + 14 * u, avs, avs)
            _desk_portrait(ar, s, elim)
            _look(ar, ui.seat_look(s))
            if ui.online: VoiceGlyph.draw_seat_voice(self, ar, ui.voice(), s)
            var y := ar.end.y + 30 * u
            otext(name, Vector2(r.position.x, y), "o6", nfs, namecol, w, HORIZONTAL_ALIGNMENT_CENTER, 3)
            if bot:
                var bw := 46.0 * u * (1.45 if tag != "BOT" else 1.0)
                _desk_bot_tag(Rect2(c.x - bw / 2.0, y + 9 * u, bw, 22 * u), tag, elim)
            y += 38 * u
            var cw := 34.0 * u
            _crowns(Vector2(c.x - (cw * 3 + cw * 0.36 * 2) / 2.0, y), s, cw, cw * 0.36, elim)
            y += 36 * u
            _desk_clock_row(Vector2(r.position.x + 14 * u, y), w - 26 * u, 13 * u, s, int(round(17 * u)))
            y += 26 * u
            var label: String = st.text
            var chh := 30.0 * u
            var chw := minf(w - 24, maxf(tw(label, "o7_sp", 17) + 30, 132 * u))
            _desk_status_chip(Rect2(c.x - chw / 2.0, y, chw, chh), st, int(round(17 * u)))
            y += chh + 30 * u
            _desk_cards_count(Vector2(c.x - 18 * u, y), s, int(round(21 * u)))

func _desk_bubble_style(r: Rect2, c: Vector2, label_n: String, label_t: String, fs: int):
    draw_rect(r.grow(3), Color("120a06"))
    grad(r, Color("fff8e6"), Color("f1e2bd"))
    draw_rect(Rect2(r.position.x + 3, r.end.y - 3, r.size.x - 6, 2), Color("d6c7a1"))
    var x := r.position.x + 16
    text(label_n, Vector2(x, c.y + fs * 0.405), "o7", fs, Color("d0121f"))
    text(label_t, Vector2(x + tw(label_n, "o7", fs), c.y + fs * 0.405), "o7_sp", fs, Color("1f1209"))

func _desk_turn_banner():
    var r: Rect2 = L().turn
    var g = ui.g
    var label := ""
    var timer := ""
    var top := Color("2153b4")
    var bot := Color("0d2a6e")
    var col := Color("f3f5f9")
    if ui.phase != "":
        top = Color("a3152a"); bot = Color("5e0a15"); label = "XEQUE!"
    elif g.state == Rules.TURN_WAITING and g.turn == 0:
        label = "SUA VEZ"; col = Color("ffd257")
        var secs := int(ceil(ui.turn_left_ms / 1000.0))
        timer = "%d:%02d" % [secs / 60, secs % 60]
    elif g.state == Rules.TURN_WAITING:
        label = "VEZ DE " + String(g.names[g.turn]).to_upper()
    else:
        label = "RODADA %d" % g.round_no
    npanel(r, 0.0, FRAME_GOLD, false, false, top, bot)
    draw_rect(Rect2(r.position.x + 5, r.position.y + 5, r.size.x - 10, 3), Color(1, 1, 1, 0.12))
    var fs := 30
    var low: bool = timer != "" and ui.turn_left_ms <= ui.LOW_TIME_MS
    if timer == "":
        var f := fit(label, "o7_sp", fs, r.size.x - 36)
        otext(label, Vector2(r.position.x, r.get_center().y + f * 0.405), "o7_sp", f, col, r.size.x, HORIZONTAL_ALIGNMENT_CENTER, 4)
    else:
        otext(label, Vector2(r.position.x + 24, r.get_center().y + fs * 0.405), "o7_sp", fs, col, -1, HORIZONTAL_ALIGNMENT_LEFT, 4)
        var tcol := col
        if low:
            tcol = Color("ff5a52") if int(ui.t * 4.0) % 2 == 0 else col
            draw_rect(r.grow(3), Color(0.88, 0.16, 0.2, 0.25 + 0.2 * sin(ui.t * 12.0)), false, 3.0)
        otext(timer, Vector2(r.position.x, r.get_center().y + fs * 0.405), "o7", fs, tcol, r.size.x - 24, HORIZONTAL_ALIGNMENT_RIGHT, 4)

func _desk_meter():
    var r: Rect2 = L().meter
    var who: int = ui.clock_focus()
    var vis: String = ui.clock_visual(who)
    npanel(r, 0.0, FRAME_GOLD, false, true)
    otext("RELÓGIO DE XEQUE", Vector2(r.position.x + 22, r.position.y + 37), "o7_sp3", 21, Color("f7cf5c"), -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
    var used: int = ui.clock_used(who)
    var segs := Rules.CLOCK_SLOTS - 1
    var lit := segs if vis == "disparado" else used
    var seg_col: Color = {"neutro": Color("f2bd3c"), "pulsando": Color("b068ff"), "perigo": Color("e02a36"), "quase": Color("e02a36"), "disparado": Color("e02a36")}[vis]
    var gap := 7.0
    var sx := r.position.x + 20
    var sw := (r.size.x - 40 - (segs - 1) * gap) / float(segs)
    var sy := r.position.y + 54
    var shh := 29.0
    for i in segs:
        var sr := Rect2(sx + i * (sw + gap), sy, sw, shh)
        draw_rect(sr, Color("0a1530"))
        draw_rect(sr, STEEL.lightened(0.1), false, 2.0)
        if i < lit or (ui.phase == "clock" and int(ui.result.loser) == who and i == used and int(ui.t * 5) % 2 == 0):
            draw_rect(sr.grow(-2), seg_col)
            draw_rect(Rect2(sr.position.x + 2, sr.position.y + 2, sr.size.x - 4, 4), seg_col.lightened(0.35))
    var words: String = {"neutro": "NEUTRO", "pulsando": "PULSANDO", "perigo": "EM PERIGO", "quase": "QUASE DISPARANDO", "disparado": "DISPAROU!"}[vis]
    var wcol: Color = {"neutro": Color("f7cf5c"), "pulsando": Color("c58bff"), "perigo": Color("ff5a52"), "quase": Color("ff5a52"), "disparado": Color("ff5a52")}[vis]
    var ty := r.end.y - 24
    otext(words, Vector2(r.position.x + 22, ty), "o7_sp3", fit(words, "o7_sp3", 27, r.size.x * 0.6), wcol, -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
    var owner: String = "Seu relógio" if who == 0 else String(ui.g.names[who])
    otext(owner, Vector2(r.position.x, ty), "o6", fit(owner, "o6", 20, r.size.x * 0.36), Color("eef0f4"), r.size.x - 22, HORIZONTAL_ALIGNMENT_RIGHT, 2)
    var ch: float = ui.clock_next_chance(who) if vis != "disparado" else 1.0
    var ccol := Color("f7e7c0").lerp(Color("ff4a42"), clampf((ch - 0.12) / 0.6, 0.0, 1.0))
    otext("%d%%" % roundi(ch * 100.0), Vector2(r.position.x, r.position.y + 37), "o7", 22, ccol, r.size.x - 22, HORIZONTAL_ALIGNMENT_RIGHT, 3)

## Botão XEQUE de aço com rebites (referência). Estados: normal, hover, pressionado, desabilitado, ativado.
func _desk_xeque_button(active: bool):
    var r: Rect2 = L().xeque_rect
    var enabled: bool = ui.can_human_challenge()
    var state := "desabilitado"
    if active or ui.phase != "": state = "ativado"
    elif enabled:
        state = "normal"
        if ui.pressed_id == "xeque": state = "pressionado"
        elif ui.hover_id == "xeque": state = "hover"
    var rr := r
    if state == "pressionado": rr = Rect2(r.position + Vector2(0, 3), r.size)
    if state == "ativado":
        var p := 0.5 + 0.5 * sin(ui.t * 10.0)
        for i in 5: draw_rect(rr.grow(4 + i * 4), Color(1.0, 0.25, 0.2, (0.22 - i * 0.04) * (0.6 + 0.4 * p)), false, 4.0)
    var lt: Color = {"normal": Color("9aa1aa"), "hover": Color("b4bbc4"), "pressionado": Color("80868f"), "desabilitado": Color("5d6268"), "ativado": Color("b8a0a0")}[state]
    var dk: Color = {"normal": Color("50565e"), "hover": Color("5f666f"), "pressionado": Color("3f444b"), "desabilitado": Color("33363b"), "ativado": Color("6e3a3a")}[state]
    draw_rect(rr.grow(4), Color("0b0703"))
    draw_rect(rr.grow(2), Color("2b2f35"))
    grad(rr, lt, dk)
    draw_rect(Rect2(rr.position.x, rr.position.y, rr.size.x, 3), Color(1, 1, 1, 0.35))
    draw_rect(Rect2(rr.position.x, rr.end.y - 3, rr.size.x, 3), Color(0, 0, 0, 0.35))
    # filete pontilhado e rebites (losangos azuis com borda dourada)
    var inner := rr.grow(-12)
    for x in range(int(inner.position.x) + 4, int(inner.end.x) - 4, 9):
        draw_rect(Rect2(x, inner.position.y, 3, 1.5), Color(0, 0, 0, 0.3))
        draw_rect(Rect2(x, inner.end.y, 3, 1.5), Color(0, 0, 0, 0.3))
    for p in [Vector2(rr.position.x + 22, rr.position.y + 22), Vector2(rr.end.x - 22, rr.position.y + 22), Vector2(rr.position.x + 22, rr.end.y - 22), Vector2(rr.end.x - 22, rr.end.y - 22)]:
        draw_colored_polygon(PackedVector2Array([p + Vector2(0, -10), p + Vector2(10, 0), p + Vector2(0, 10), p + Vector2(-10, 0)]), Color("c99a3a"))
        draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)]), Color("27354d"))
    for p in [Vector2(rr.position.x + 22, rr.get_center().y), Vector2(rr.end.x - 22, rr.get_center().y)]:
        draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(4, 0), p + Vector2(0, 7), p + Vector2(-4, 0)]), Color("e7b64c"))
    var fs := 92
    var tcol := Color("f4f6f9") if state != "desabilitado" else Color("9ca0a6")
    var by := rr.get_center().y + fs * 0.405
    text("XEQUE", Vector2(rr.position.x + 3, by + 5), "o7_sp3", fs, Color(0, 0, 0, 0.45), rr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
    otext("XEQUE", Vector2(rr.position.x, by), "o7_sp3", fs, tcol, rr.size.x, HORIZONTAL_ALIGNMENT_CENTER, 7)
    if enabled and ui.phase == "": hit(r, "xeque")

func _desk_play_button():
    var r: Rect2 = L().play
    var g = ui.g
    var my_turn: bool = ui.phase == "" and g.state == Rules.TURN_WAITING and g.turn == 0 and not ui.input_locked
    var id := "play"
    var enabled: bool = ui.can_human_play()
    if my_turn and not enabled:
        id = "play_empty"
        enabled = true
    var hov: bool = ui.hover_id == id and enabled
    var down: bool = ui.pressed_id == id and enabled
    var rr := Rect2(r.position + Vector2(0, 2 if down else 0), r.size)
    var top := Color("b1182e") if enabled else Color("4e1d24")
    var bot := Color("6c0915") if enabled else Color("2c1014")
    if hov: top = top.lightened(0.12)
    npanel(rr, 0.0, FRAME_GOLD if enabled else Color("7a6440"), false, false, top, bot)
    draw_rect(Rect2(rr.position.x + 5, rr.position.y + 5, rr.size.x - 10, 3), Color(1, 1, 1, 0.12))
    var label := "JOGAR CARTAS"
    var f := fit(label, "o7_sp", 42, rr.size.x - 50)
    otext(label, Vector2(rr.position.x, rr.get_center().y + f * 0.405), "o7_sp", f, Color("f8dc8e") if enabled else Color(0.9, 0.82, 0.7, 0.5), rr.size.x, HORIZONTAL_ALIGNMENT_CENTER, 4)
    if enabled: hit(r, id)

func _desk_hint():
    var h = L().hint
    var lines: Array = ui.help_text()
    if String(lines[0]).is_empty(): return
    for i in 2:
        var parts := String(lines[i]).split("*")
        var total := 0.0
        for p in parts: total += tw(p, "o6_sp", 21)
        var x: float = h[0].x - total / 2.0
        var y: float = h[0].y + i * 27.0
        for j in parts.size():
            otext(parts[j], Vector2(x, y), "o6_sp", 21, Color("ffd257") if j % 2 == 1 else Color("f3ead6"), -1, HORIZONTAL_ALIGNMENT_LEFT, 3)
            x += tw(parts[j], "o6_sp", 21)

## Botões quadrados de baixo (tela cheia, música, efeitos, ajuda, menu): azul-marinho com moldura dourada.
func desk_square(r: Rect2, hov: bool):
    npanel(r, 0.0, FRAME_GOLD if not hov else FRAME_HI, false, false, Color("162a52"), Color("0b1733"))

# ---------------------------------------------------------------- R55 · mão e revelação (PC)
const DESK_CARD_W := 170.0
func _desk_hand_layout() -> Array:
    var n: int = ui.g.hands[0].size()
    var step := minf(DESK_CARD_W * 0.97, (820.0 - DESK_CARD_W) / maxf(1.0, n - 1.0))
    var mid := (n - 1) / 2.0
    var out := []
    for i in n:
        var off := i - mid
        var c := Vector2(960.0 + off * step, 922.0 + off * off * 2.5)
        if i in ui.selected: c.y -= 30.0
        out.append({"c": c, "rot": 0.0, "sc": DESK_CARD_W / 360.0})
    return out

func _desk_hand():
    var g = ui.g
    var hand: Array = g.hands[0]
    var lay := _desk_hand_layout()
    var my_turn: bool = ui.phase == "" and g.turn == 0 and g.state == Rules.TURN_WAITING and not ui.input_locked
    var landed: int = ui.deal_landed(0)
    var sz := Vector2(DESK_CARD_W, DESK_CARD_W * 1.4)
    for i in hand.size():
        if i >= landed: continue
        var c: Vector2 = lay[i].c
        if my_turn and not (i in ui.selected):
            c.y -= 5.0 * (0.5 + 0.5 * sin(ui.t * 4.0 - i * 0.7))     # SUA VEZ: as cartas "respiram"
        var rect := Rect2(c - sz / 2.0, sz)
        if i in ui.selected:
            var a := 0.55 + 0.25 * sin(ui.t * 6.0)
            for gi in 4: draw_rect(rect.grow(3 + gi * 3), Color(1, 0.85, 0.35, a * (0.5 - gi * 0.11)), false, 3.0)
            draw_rect(rect.grow(2), Color("ffd257"), false, 3.0)
        elif my_turn:
            for gk in 3: draw_rect(rect.grow(3 + gk * 4), Color(1.0, 0.82, 0.32, 0.12 - gk * 0.035), false, 4.0)
        if hand[i] == Rules.JOKER:
            var pj := 0.5 + 0.5 * sin(ui.t * 5.0 + i)
            for gj in 3: draw_rect(rect.grow(4 + gj * 4 + pj * 3), Color(0.35, 1.0, 0.55, 0.26 - gj * 0.07), false, 4.0)
        var mod := Color.WHITE if my_turn or g.turn != 0 else Color(0.92, 0.92, 0.92)
        card_face(String(hand[i]), c, DESK_CARD_W, 0.0, mod)
        if hand[i] == Rules.JOKER:
            nchip(Rect2(c + Vector2(-58, -sz.y / 2.0 - 30), Vector2(116, 26)), "CORINGA", Color("1d7a4a"), Color("ffd257"), Color("fff1c2"), 17)
        if my_turn: hit(rect, "card_%d" % i)
        if ui.hover_id == "card_%d" % i and my_turn and not (i in ui.selected):
            draw_rect(rect.grow(1), Color(1, 0.93, 0.6, 0.8), false, 2.0)

func _desk_reveal_cards():
    var r: Dictionary = ui.result
    var rv: Array = L().reveal
    var cards: Array = r.cards
    var n := cards.size()
    var w := 150.0
    var base: Vector2 = rv[0]
    for i in n:
        var flip: float = ui.flip_progress(i) if ui.phase == "reveal" else 1.0
        var off := i - (n - 1) / 2.0
        var c := base + Vector2(off * w * 1.06, absf(off) * w * 0.12)
        var rot := deg_to_rad(4.0 * off)
        var wscale := absf(flip * 2.0 - 1.0)
        var lie: bool = not Rules.is_true_card(cards[i], String(r.target))
        if flip >= 0.5:
            if flip >= 1.0 and lie:
                draw_set_transform(ui.origin + c * ui.k, rot, Vector2(ui.k, ui.k))
                draw_rect(Rect2(-Vector2(w, w * 1.4) / 2.0, Vector2(w, w * 1.4)).grow(5), Color("e02a36"), false, 5.0)
                draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
            card_face(String(cards[i]), c, w, rot, Color.WHITE, wscale)
        else:
            var sz := Vector2(w, w * 1.4)
            draw_set_transform(ui.origin + c * ui.k, rot, Vector2(ui.k * maxf(0.05, wscale), ui.k))
            draw_texture_rect(Crisp.at(ui.CARD_BACK, sz * ui.k), Rect2(-sz / 2.0, sz), false)
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
