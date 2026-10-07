extends Node
## R49 · PELE DO TABULEIRO RANKED MADEIRA (PC e celular em pé) = as artes de referência do dono.
## Só APARÊNCIA: a arte (tools/board_ref_r49.py) vira o fundo inteiro da partida (cenário, moldura do tabuleiro,
## casas, cartões, chat, barra de cima) e os controles/dados VIVOS que já existem no jogo são reposicionados por
## cima, exatamente nos lugares da arte: nomes, liga/PL, retratos, relógios, material, chat, voz, botões.
## Nenhuma regra muda: os mesmos botões disparam as mesmas ações; o tabuleiro continua sendo o mesmo grid.
## Ativa quando: partida RANKED · tema Madeira ("wood") · PC ou celular em pé. Fora disso, tudo volta como era.
## Tudo que é alterado fica registrado e é desfeito ao sair (restore) — o layout normal do stage refaz o resto.
const ART_PC := preload("res://ranked/art/board_pc.png")
const ART_PC_BOT := preload("res://ranked/art/board_pc_bot.png")
const ART_MOB_BOT := preload("res://ranked/art/board_mob_bot.png")   # R51 · celular: barra de LANCES no lugar do CHAT, sem voz   # R51 · contra o computador: quadro de lances no lugar do chat
const ART_MOB := preload("res://ranked/art/board_mob.png")
const PC_SIZE := Vector2(1672, 941)
## R50 · peças em pixel art do Ranked Madeira (PNGs finais do Aseprite, sem nenhuma alteração).
## Rect2 = parte desenhada de cada PNG (o resto é transparente).
const PECAS := {
    "wP": [preload("res://ranked/pecas/peao_branco.png"), Rect2(18, 17, 51, 61)],
    "wR": [preload("res://ranked/pecas/torre_branca.png"), Rect2(19, 15, 52, 68)],
    "wN": [preload("res://ranked/pecas/cavalo_branco.png"), Rect2(15, 12, 55, 71)],
    "wB": [preload("res://ranked/pecas/bispo_branco.png"), Rect2(17, 9, 53, 72)],
    "wQ": [preload("res://ranked/pecas/dama_branca.png"), Rect2(14, 8, 72, 74)],
    "wK": [preload("res://ranked/pecas/rei_branco.png"), Rect2(18, 9, 51, 74)],
    "bP": [preload("res://ranked/pecas/peao_preto.png"), Rect2(15, 14, 51, 65)],
    "bR": [preload("res://ranked/pecas/torre_preta.png"), Rect2(17, 11, 54, 71)],
    "bN": [preload("res://ranked/pecas/cavalo_preto.png"), Rect2(14, 8, 56, 73)],
    "bB": [preload("res://ranked/pecas/bispo_preto.png"), Rect2(14, 4, 53, 76)],
    "bQ": [preload("res://ranked/pecas/dama_preta.png"), Rect2(13, 7, 62, 75)],
    "bK": [preload("res://ranked/pecas/rei_preto.png"), Rect2(16, 8, 51, 73)],
}
const PC_CLEAN := Rect2(0, 86, 300, 855)   # floresta/rio à esquerda do tabuleiro, abaixo do INÍCIO: sem interface
const MOB_SIZE := Vector2(888, 1772)
const FONT_BOLD := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_SEMI := preload("res://account/fonts/Cinzel-SemiBold.woff")
const MobileLayout := preload("res://ui_v022/mobile_layout.gd")
const ModeSound := preload("res://ui_v022/mode_sound.gd")
const CREAM := Color("f3ede0")
const GOLD := Color("f4ce7f")

## ---- medidas na arte do PC (px da referência 1672 x 941) ----
const PC := {
    "board": Rect2(382.0, 145.5, 693.5, 694.0),
    "home": Rect2(18, 17, 225, 60),
    "mic": Rect2(1099, 22, 45, 42), "ear": Rect2(1151, 22, 45, 42), "off": Rect2(1203, 25, 37, 35),
    "status": Rect2(1248, 27, 162, 37),
    "mark": Rect2(1416, 22, 43, 42), "gear": Rect2(1465, 22, 43, 42), "music": Rect2(1515, 22, 42, 42),
    "fx": Rect2(1563, 22, 43, 42), "full": Rect2(1611, 22, 44, 42), "bar": Rect2(1085, 10, 580, 68),
    # cartão do adversário (o do jogador = +566 px)
    "card": Rect2(1158, 122, 488, 168), "avatar": Rect2(1178, 139, 82, 82), "emblem": Rect2(1274, 188, 33, 34),
    "name": [1282.0, 170.0, 176.0, 26.0], "sub": [1311.0, 210.0, 150.0, 17.5],
    "clock": Rect2(1521, 150, 110, 54), "clock_fs": 40.0, "clock_w": 94.0,
    "material": Rect2(1250, 249, 376, 22), "material_fs": 17.0,
    "card_dy": 566.0,
    # chat
    "chat": Rect2(1158, 305, 488, 370), "title": [1195.0, 351.0, 110.0, 25.0],
    "mute": Rect2(1314, 321, 115, 38), "report": Rect2(1442, 321, 126, 38), "min": Rect2(1581, 321, 41, 38),
    "list": Rect2(1184, 374, 424, 214), "input": Rect2(1182, 607, 309, 50), "send": Rect2(1504, 605, 119, 53),
    "resign": Rect2(1486, 868, 144, 42), "link": Rect2(1186, 548, 420, 40),
}
## ---- medidas na arte do celular (px da referência 888 x 1772) ----
const MOB := {
    "board": Rect2(53.2, 461.0, 781.8, 799.0),
    "home": Rect2(20, 20, 268, 80),
    "sound": Rect2(640, 20, 80, 75), "gear": Rect2(728, 20, 72, 75), "more": Rect2(806, 20, 66, 75),
    "card": Rect2(12, 272, 864, 134), "avatar": Rect2(45, 295, 90, 90), "emblem": Rect2(154, 336, 46, 50),
    "name": [163.0, 330.0, 220.0, 36.0], "sub": [205.0, 372.0, 175.0, 22.5],
    "clock": Rect2(716, 305, 136, 64), "clock_fs": 56.0, "clock_w": 118.0,
    "material": Rect2(499, 339, 138, 32), "material_fs": 22.0,
    "card_dy": 1042.0,
    "chatbar": Rect2(25, 1465, 837, 80), "chat_open": Rect2(14, 470, 860, 990),
    "mic": Rect2(278, 1570, 74, 75), "ear": Rect2(362, 1570, 74, 75), "pill": Rect2(446, 1570, 164, 75),
    "link": Rect2(30, 412, 828, 42),
}

var stage
var on := false
var kind := ""               # "pc" | "mob"
var k := 1.0                 # px de tela por px da arte
var off := Vector2.ZERO      # canto da arte na tela
var bg: Node2D               # arte por baixo do tabuleiro (z -15)
var layer: CanvasLayer       # marcas de estado/hover e botões próprios do celular (por cima do HUD)
var marks: Control
var hits := []               # [Button, Rect2 de tela, id] → brilho de hover + estado (som desligado etc.)
var _orig := {}              # registro do que foi alterado (desfeito em restore)
var _circle: ShaderMaterial
var _bare_clocks := []
# celular: botões próprios (som, opções, mais, barra do chat) e o menu de opções
var mob_buttons := {}
var menu: PanelContainer

func setup(owner_stage) -> void:
    stage = owner_stage
    name = "BoardSkin"
    bg = ArtBg.new()
    bg.name = "RankedBoardArt"
    bg.z_index = -15
    bg.visible = false
    stage.add_child(bg)
    layer = CanvasLayer.new()
    layer.name = "BoardSkinLayer"
    layer.layer = 47
    stage.add_child(layer)
    marks = Marks.new()
    marks.skin = self
    marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(marks)
    _circle = ShaderMaterial.new()
    _circle.shader = Shader.new()
    _circle.shader.code = "shader_type canvas_item;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float d = distance(UV, vec2(0.5)); COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(0.47, 0.5, d))); }"
    _build_mobile_controls()
    layer.hide()

# ------------------------------------------------------------------ quando vale
func wanted() -> bool:
    if stage == null or stage.game == null: return false
    # R51 · contra o computador usa o mesmo layout do Ranked Madeira (a partida força o tema Madeira)
    if not (stage.mode == "ranked" or stage.mode == "bot") or not stage.game.visible: return false
    if String(stage.game.visual_theme) != "wood": return false
    if MobileLayout.active(stage.get_viewport()): return MobileLayout.is_portrait(stage.get_viewport())
    return true

## Chamado no INÍCIO do stage._layout(): se a pele não vale mais, desfaz tudo antes do layout normal.
func before_layout() -> void:
    if on and not wanted(): restore()

## Chamado no FIM do stage._layout(): aplica por cima do layout normal (que acabou de rodar).
func after_layout() -> void:
    if wanted(): apply()

func _process(_d):
    if stage == null: return
    if wanted() != on:
        stage._layout()
        return
    if on:
        _keep()
        marks.queue_redraw()

# ------------------------------------------------------------------ registro / desfazer
func _rec(obj: Object, prop: String, val) -> void:
    if obj == null: return
    var key := "%d|%s" % [obj.get_instance_id(), prop]
    if not _orig.has(key): _orig[key] = [obj, "p", prop, obj.get(prop)]
    obj.set(prop, val)

func _ov(ctrl: Control, what: String, nm: String, val) -> void:
    var key := "%d|%s|%s" % [ctrl.get_instance_id(), what, nm]
    if not _orig.has(key):
        var had := false
        var old = null
        match what:
            "style": had = ctrl.has_theme_stylebox_override(nm); old = ctrl.get_theme_stylebox(nm) if had else null
            "font": had = ctrl.has_theme_font_override(nm); old = ctrl.get_theme_font(nm) if had else null
            "size": had = ctrl.has_theme_font_size_override(nm); old = ctrl.get_theme_font_size(nm) if had else null
            "color": had = ctrl.has_theme_color_override(nm); old = ctrl.get_theme_color(nm) if had else null
            "const": had = ctrl.has_theme_constant_override(nm); old = ctrl.get_theme_constant(nm) if had else null
        _orig[key] = [ctrl, what, nm, old, had]
    match what:
        "style": ctrl.add_theme_stylebox_override(nm, val)
        "font": ctrl.add_theme_font_override(nm, val)
        "size": ctrl.add_theme_font_size_override(nm, int(val))
        "color": ctrl.add_theme_color_override(nm, val)
        "const": ctrl.add_theme_constant_override(nm, int(val))

func restore() -> void:
    for id in bot_after: bot_after[id].hide()
    if is_instance_valid(bot_moves): bot_moves.hide()
    for key in _orig:
        var e: Array = _orig[key]
        var obj = e[0]
        if not is_instance_valid(obj): continue
        if e[1] == "p":
            obj.set(e[2], e[3])
            continue
        var ctrl: Control = obj
        var had: bool = e[4]
        match e[1]:
            "style":
                if had: ctrl.add_theme_stylebox_override(e[2], e[3])
                else: ctrl.remove_theme_stylebox_override(e[2])
            "font":
                if had: ctrl.add_theme_font_override(e[2], e[3])
                else: ctrl.remove_theme_font_override(e[2])
            "size":
                if had: ctrl.add_theme_font_size_override(e[2], e[3])
                else: ctrl.remove_theme_font_size_override(e[2])
            "color":
                if had: ctrl.add_theme_color_override(e[2], e[3])
                else: ctrl.remove_theme_color_override(e[2])
            "const":
                if had: ctrl.add_theme_constant_override(e[2], e[3])
                else: ctrl.remove_theme_constant_override(e[2])
    _orig.clear()
    for ck in _bare_clocks: if is_instance_valid(ck): ck.set_bare(false)
    _bare_clocks.clear()
    for id in mob_buttons: mob_buttons[id].hide()
    hits.clear()
    on = false
    kind = ""
    bg.visible = false
    layer.hide()
    if menu != null: menu.hide()
    if stage.material_hud != null: stage.material_hud.queue_redraw()

# ------------------------------------------------------------------ geometria
func R(r: Rect2) -> Rect2:
    return Rect2(off + r.position * k, r.size * k)

func P(p: Vector2) -> Vector2:
    return off + p * k

func _dy(r: Rect2, dy: float) -> Rect2:
    return Rect2(r.position + Vector2(0, dy), r.size)

func _place(c: Control, r: Rect2, top := true) -> void:
    if top: _rec(c, "top_level", true)
    c.position = R(r).position
    c.size = R(r).size

## Texto na posição da referência: x, LINHA DE BASE, largura e tamanho da fonte (px da arte).
func _text(l: Label, spec: Array, font: Font, color: Color, outline := 3) -> void:
    var px := maxi(8, int(round(float(spec[3]) * k)))
    _ov(l, "font", "font", font)
    _ov(l, "size", "font_size", px)
    _ov(l, "color", "font_color", color)
    _ov(l, "const", "outline_size", outline)
    _ov(l, "color", "font_outline_color", Color(0, 0, 0, 0.55))
    _rec(l, "top_level", true)
    _rec(l, "vertical_alignment", VERTICAL_ALIGNMENT_TOP)
    _rec(l, "autowrap_mode", TextServer.AUTOWRAP_OFF)
    _rec(l, "clip_text", true)
    var asc := font.get_ascent(px)
    l.position = P(Vector2(spec[0], spec[1])) - Vector2(0, asc)
    l.size = Vector2(float(spec[2]) * k, font.get_height(px) + 2.0)

## Botão "fantasma": invisível (o desenho é o da arte), continua clicável; o brilho do hover é das marcas.
func _ghost(b: Control, r: Rect2, id := "") -> void:
    if b == null: return
    _place(b, r)
    _rec(b, "self_modulate", Color(1, 1, 1, 0))
    hits.append([b, r, id])

## Botão com texto vivo (SILENCIAR/REATIVAR, DENUNCIAR/DENUNCIADO): sem fundo (a moldura é da arte).
func _text_button(b: Button, r: Rect2, fs: float) -> void:
    _place(b, r)
    var empty := StyleBoxEmpty.new()
    var lit := StyleBoxFlat.new()
    lit.bg_color = Color(1.0, 0.86, 0.45, 0.10)
    lit.set_corner_radius_all(4)
    for st in ["normal", "disabled", "focus"]: _ov(b, "style", st, empty)
    for st in ["hover", "pressed"]: _ov(b, "style", st, lit)
    _ov(b, "font", "font", FONT_BOLD)
    var px := int(round(fs * k))
    while px > 9 and FONT_BOLD.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > r.size.x * k - 12.0: px -= 1
    _ov(b, "size", "font_size", px)
    for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: _ov(b, "color", c, Color("f4ead2"))
    _ov(b, "color", "font_outline_color", Color(0, 0, 0, 0.6))
    _ov(b, "const", "outline_size", 3)

# ------------------------------------------------------------------ aplicar
func apply() -> void:
    var vs: Vector2 = stage.get_viewport().get_visible_rect().size
    var mobile := MobileLayout.active(stage.get_viewport())
    kind = "mob" if mobile else "pc"
    var size: Vector2 = MOB_SIZE if mobile else PC_SIZE
    var M: Dictionary = MOB if mobile else PC
    k = minf(vs.x / size.x, vs.y / size.y)
    off = (vs - size * k) / 2.0
    if mobile and off.y > 0.0:
        # celular mais alto que a arte: a arte fica colada em cima (logo abaixo do recorte do sistema) e o chão da
        # floresta continua embaixo (espelhado) — nada de faixa escura nem botão cortado.
        var top: float = maxf(0.0, MobileLayout.safe_rect(stage.get_viewport()).position.y - 8.0)
        off.y = minf(top, vs.y - size.y * k)
    hits.clear()
    on = true
    # fundo: a arte; o cenário/tabuleiro pintado do tema e as laterais somem enquanto a pele vale
    var bot_mode: bool = stage.mode == "bot"
    bg.tex = (ART_MOB_BOT if bot_mode else ART_MOB) if mobile else (ART_PC_BOT if bot_mode else ART_PC)
    bg.rect = Rect2(off, size * k)
    bg.full = Rect2(Vector2.ZERO, vs)
    bg.clean = Rect2() if mobile else PC_CLEAN
    bg.visible = true
    bg.queue_redraw()
    _rec(stage.forest, "visible", false)
    var env = stage.game.get_node_or_null("ForestEnvironment")
    if env != null: _rec(env, "visible", false)
    # tabuleiro: o grid de jogo (600 x 600 unidades) em cima das casas da arte
    var br := R(M.board)
    var g = stage.game
    g.scale = Vector2(br.size.x / g.BOARD, br.size.y / g.BOARD)
    g.position = br.position - g.ORIGIN * g.scale
    g.update_presentation(Rect2(-g.position / g.scale.x, vs / g.scale.x))
    _rec(g, "hide_status", true)
    _rec(g, "piece_override", PECAS)
    g.queue_redraw()
    _skin_strips(M)
    _skin_material(M)
    layer.show()
    if mobile: _apply_mobile(M)
    else: _apply_pc(M)
    if stage.mode == "bot": _apply_bot(M)

func _skin_strips(M: Dictionary) -> void:
    var ui = stage.ranked_ui
    if ui == null: return
    for key in ["top", "bottom"]:
        var s: Dictionary = ui.strips[key]
        var dy: float = 0.0 if key == "top" else float(M.card_dy)
        var bgc: Control = s.bg
        _ov(bgc, "style", "panel", StyleBoxEmpty.new())
        bgc.position = R(_dy(M.card, dy)).position
        bgc.size = R(_dy(M.card, dy)).size
        _rec(s.plaque, "visible", false)
        _rec(s.front, "visible", false)
        var pt: Control = s.portrait
        _rec(pt, "custom_minimum_size", R(M.avatar).size)   # antes do tamanho (o mínimo antigo prenderia o tamanho)
        _place(pt, _dy(M.avatar, dy))
        var pbg = pt.get_node_or_null("PortraitBg")
        if pbg != null: _rec(pbg, "visible", false)
        if pt.avatar_rect != null: _rec(pt.avatar_rect, "material", _circle)
        _text(s.name, [M.name[0], M.name[1] + dy, M.name[2], M.name[3]], FONT_BOLD, Color("f6f1e6"), 4)
        _text(s.sub, [M.sub[0], M.sub[1] + dy, M.sub[2], M.sub[3]], FONT_SEMI, Color("f3e3bd"), 3)
        _rec(s.emblem, "custom_minimum_size", R(M.emblem).size)
        _place(s.emblem, _dy(M.emblem, dy))
        var ck = s.clock
        _rec(ck, "custom_minimum_size", R(M.clock).size)
        _place(ck, _dy(M.clock, dy))
        ck.set_bare(true)
        if not _bare_clocks.has(ck): _bare_clocks.append(ck)
        var cpx := int(round(float(M.clock_fs) * k))
        while cpx > 10 and FONT_BOLD.get_string_size("00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, cpx).x > float(M.clock_w) * k: cpx -= 1
        ck.set_font_size(cpx)
        _rec(s.seal, "top_level", true)
        s.seal.size = Vector2(26, 26) * k * (1.4 if kind == "mob" else 1.0)

func _skin_material(M: Dictionary) -> void:
    var mh = stage.material_hud
    if mh == null: return
    _rec(mh, "skin", true)
    mh.skin_font = float(M.material_fs) * k
    mh.top_rect = R(M.material)
    mh.bottom_rect = R(_dy(M.material, M.card_dy))
    mh.queue_redraw()

func _apply_pc(M: Dictionary) -> void:
    # INÍCIO (a arte já tem a casinha, INÍCIO e ESC)
    _ghost(stage.home_button, M.home, "home")
    # barra de cima: a moldura e os ícones são da arte; os botões de verdade ficam por cima (invisíveis)
    _ov(stage.desk_panel, "style", "panel", StyleBoxEmpty.new())
    var dv = stage.desk_voice
    if dv != null:
        _ghost(dv.mic, M.mic, "mic")
        _ghost(dv.ear, M.ear, "ear")
        _ghost(dv.off, M.off, "off")
        _rec(dv.label, "visible", false)
    _ghost(stage.desk_mark, M.mark, "mark")
    _ghost(stage.desk_gear, M.gear, "gear")
    _ghost(stage.desk_music, M.music, "music")
    _ghost(stage.desk_fx, M.fx, "fx")
    _ghost(stage.desk_fullscreen, M.full, "full")
    for b in [stage.desk_analyze, stage.desk_restart]: if b != null: _rec(b, "visible", false)
    # opções da partida (painel desenhado pelo tabuleiro) abrem logo abaixo da barra
    var g = stage.game
    var anchor := Vector2(R(M.bar).end.x, R(M.bar).end.y + 8.0)
    g.place_settings_panel((anchor - g.position) / g.scale.x)
    # DESISTIR fica logo abaixo do cartão VOCÊ (a referência não tem; a ação continua no jogo)
    var ui = stage.ranked_ui
    if ui != null:
        ui.resign_button.position = R(M.resign).position
        ui.resign_button.size = R(M.resign).size
        _ov(ui.resign_button, "size", "font_size", int(round(17 * k)))
        _ov(ui.resign_button, "font", "font", FONT_BOLD)
        ui.link_label.position = R(M.link).position
        ui.link_label.size = R(M.link).size
    _skin_chat_pc(M)

func _skin_chat_pc(M: Dictionary) -> void:
    var c = stage.match_chat
    if c == null: return
    _ov(c.panel, "style", "panel", StyleBoxEmpty.new())
    c.panel.position = R(M.chat).position
    c.panel.size = R(M.chat).size
    _text(c.title, M.title, FONT_BOLD, Color("f3ead8"), 3)
    _text_button(c.mute_button, M.mute, 18.0)
    _text_button(c.report_button, M.report, 18.0)
    _ghost(c.minimize_button, M.min, "min")
    _ghost(c.send_button, M.send, "send")
    _place(c.scroll, M.list)
    _place(c.status, Rect2(M.list.position.x, M.list.end.y - 30, M.list.size.x, 28))
    _place(c.input, M.input)
    var empty := StyleBoxEmpty.new()
    empty.content_margin_left = 14.0 * k
    for st in ["normal", "focus", "read_only"]: _ov(c.input, "style", st, empty)
    _ov(c.input, "size", "font_size", int(round(20 * k)))
    _ov(c.input, "color", "font_placeholder_color", Color(0.78, 0.76, 0.72, 0.62))
    _ov(c.input, "color", "font_color", Color("f1ece2"))
    if c.restore_button.visible:
        c.restore_button.position = R(Rect2(M.title[0] - 8, M.title[1] - 28, 120, 38)).position
        c.restore_button.size = R(Rect2(0, 0, 120, 38)).size

func _apply_mobile(M: Dictionary) -> void:
    _ghost(stage.home_button, M.home, "home")
    # a fileira de botões do celular sai de cena (as ações vão para o menu de opções); a voz fica nos lugares da arte
    if stage.mobile_actions != null: stage.mobile_actions.position = Vector2(-20000, 0)
    for n in [stage.bot_info, stage.mobile_status, stage.player_card]:
        if n != null: _rec(n, "visible", false)
    var mv = stage.mobile_voice
    if mv != null:
        _ghost(mv.mic, M.mic, "mic")
        _ghost(mv.ear, M.ear, "ear")
        _rec(mv.off, "visible", false)
        _rec(mv.label, "visible", false)
    for id in ["sound", "gear", "more"]:
        var b: Button = mob_buttons[id]
        b.show()
        b.position = R(M[id]).position
        b.size = R(M[id]).size
        hits.append([b, M[id], id])
    var cb: Button = mob_buttons.chatbar
    cb.position = R(M.chatbar).position
    cb.size = R(M.chatbar).size
    hits.append([cb, M.chatbar, "chatbar"])
    var ui = stage.ranked_ui
    if ui != null:
        ui.link_label.position = R(M.link).position
        ui.link_label.size = R(M.link).size
        _rec(ui.resign_button, "visible", false)
    var c = stage.match_chat
    if c != null and c.open_mobile:
        c.panel.position = R(M.chat_open).position
        c.panel.size = R(M.chat_open).size
    if menu != null and menu.visible: _layout_menu()

# ------------------------------------------------------------------ R51 · partida contra o computador
var bot_moves: RichTextLabel     # lista de lances no lugar do chat (PC)
var _bot_moves_n := -1

func _apply_bot(M: Dictionary) -> void:
    for n in [stage.get("match_plaque"), stage.get("desk_person")]:
        if n != null: _rec(n, "visible", false)
    # sem chat contra o computador: o quadro do chat vira a lista de lances (escondo os controles do chat)
    var c = stage.match_chat
    if c != null:
        for n in [c.panel, c.restore_button]: _rec(n, "visible", false)
    if kind != "pc":
        # celular: sem voz e sem chat; a barra do chat vira a linha dos últimos lances
        var mv = stage.mobile_voice
        if mv != null:
            for n in [mv.mic, mv.ear]: _rec(n, "visible", false)
        for i in range(hits.size() - 1, -1, -1):
            if String(hits[i][2]) in ["mic", "ear", "chatbar"]: hits.remove_at(i)
        mob_buttons.chatbar.hide()
        _ensure_bot_moves()
        bot_moves.show()
        bot_moves.scroll_following = false
        var r := R(Rect2(MOB.chatbar.position.x + 34, MOB.chatbar.position.y + 14, MOB.chatbar.size.x - 68, MOB.chatbar.size.y - 22))
        bot_moves.position = r.position
        bot_moves.size = r.size
        _style_bot_moves(30)
        return
    _ensure_bot_moves()
    bot_moves.show()
    bot_moves.scroll_following = true
    bot_moves.position = R(Rect2(M.chat.position.x + 36, M.chat.position.y + 30, M.chat.size.x - 70, M.chat.size.y - 50)).position
    bot_moves.size = R(Rect2(0, 0, M.chat.size.x - 70, M.chat.size.y - 50)).size
    _style_bot_moves(21)

func _ensure_bot_moves() -> void:
    if is_instance_valid(bot_moves): return
    bot_moves = RichTextLabel.new()
    bot_moves.name = "BotMoves"
    bot_moves.bbcode_enabled = true
    bot_moves.mouse_filter = Control.MOUSE_FILTER_IGNORE
    marks.add_sibling(bot_moves)

func _style_bot_moves(fs: float) -> void:
    var Kit = load("res://ui_kit/kit.gd")
    bot_moves.add_theme_font_override("normal_font", Kit.SERIF)
    bot_moves.add_theme_font_override("bold_font", FONT_BOLD)
    bot_moves.add_theme_font_size_override("normal_font_size", int(round(fs * k)))
    bot_moves.add_theme_font_size_override("bold_font_size", int(round((fs + 3) * k)))
    bot_moves.add_theme_color_override("default_color", Color("efe6d2"))
    _bot_moves_n = -1

## Texto do quadro de lances (título LANCES + pares numerados).
func _bot_moves_text(log: Array) -> String:
    var t := "[b][color=#f3d27e]LANCES[/color][/b]\n"
    if log.is_empty(): return t + "\n[color=#a8a294]A partida começa com as BRANCAS.[/color]"
    t += "[table=3]"
    for i in range(0, log.size(), 2):
        t += "[cell][color=#a8a294]%d.[/color]   [/cell][cell]%s      [/cell][cell]%s[/cell]" % [i / 2 + 1, _esc(String(log[i])), _esc(String(log[i + 1])) if i + 1 < log.size() else ""]
    return t + "[/table]"

## Celular: uma linha com os últimos lances (os mais novos à direita).
func _bot_moves_line(log: Array) -> String:
    var t := "[b][color=#f3d27e]LANCES[/color][/b]   "
    if log.is_empty(): return t + "[color=#a8a294]a partida começa com as BRANCAS[/color]"
    var first := maxi(0, log.size() - 6)
    if first % 2 == 1: first -= 1
    for i in range(first, log.size()):
        if i % 2 == 0: t += "[color=#a8a294]%d.[/color] " % (i / 2 + 1)
        t += _esc(String(log[i])) + "  "
    return t

static func _esc(t: String) -> String:
    return t.replace("[", "(").replace("]", ")")

func _keep_bot() -> void:
    var bc = stage.bot_controller
    if is_instance_valid(bot_moves) and bot_moves.visible and bc.san_log.size() != _bot_moves_n:
        _bot_moves_n = bc.san_log.size()
        bot_moves.text = _bot_moves_text(bc.san_log) if kind == "pc" else _bot_moves_line(bc.san_log)
    # fim da partida: JOGAR DE NOVO e ANALISAR no lugar do DESISTIR (PC; no celular ficam no menu ⋮)
    var over: bool = stage.game.game_over and kind == "pc"
    if over and bot_after.is_empty(): _make_bot_after()
    for id in bot_after:
        var b: Button = bot_after[id]
        b.visible = over
    if over:
        var r := R(PC.resign)
        var w := r.size.x * 1.45
        bot_after.again.position = Vector2(r.end.x - w, r.position.y)
        bot_after.again.size = Vector2(w, r.size.y)
        bot_after.analyze.position = Vector2(r.end.x - 2.0 * w - 10.0 * k, r.position.y)
        bot_after.analyze.size = Vector2(w, r.size.y)

var bot_after := {}
func _make_bot_after() -> void:
    var Kit = load("res://ui_kit/kit.gd")
    for spec in [["again", "JOGAR DE NOVO", "btn_verde"], ["analyze", "ANALISAR", "btn_azul"]]:
        var b := Button.new()
        b.name = "BotAfter_" + spec[0]
        b.text = spec[1]
        b.focus_mode = Control.FOCUS_NONE
        Kit.button(b, spec[2], 0.4 * k / 0.8, int(round(16 * k)))
        marks.add_sibling(b)
        bot_after[spec[0]] = b
    bot_after.again.pressed.connect(func():
        stage.game.restart_match()
        stage.game.queue_redraw())
    bot_after.analyze.pressed.connect(func(): stage.open_analysis())

## A cada quadro: o que o jogo atualiza sozinho e precisa continuar no lugar da arte.
func _keep() -> void:
    if stage.mode == "bot": _keep_bot()
    # R51 · o botão antigo ANALISAR PARTIDA (barra de cima) cobria os ícones da arte: com a pele ele não aparece
    # (contra o bot: ANALISAR no lugar do DESISTIR; no Ranked: no painel de resultado; no celular: menu ⋮)
    if kind == "pc" and stage.desk_analyze != null and stage.desk_analyze.visible: stage.desk_analyze.visible = false
    var ui = stage.ranked_ui
    if ui != null:
        var M: Dictionary = MOB if kind == "mob" else PC
        for key in ["top", "bottom"]:
            var s: Dictionary = ui.strips[key]
            var pt = s.portrait
            if pt.frame_node != null and pt.frame_node.visible: pt.frame_node.visible = false
            pt.seal_rect.visible = false
            _fit(s.name, FONT_BOLD, float(M.name[3]))
            _fit(s.sub, FONT_SEMI, float(M.sub[3]))
            # selo (Fundador/Club) logo depois do nome
            var nm: Label = s.name
            var px := nm.get_theme_font_size("font_size")
            var w := minf(FONT_BOLD.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, nm.size.x)
            s.seal.position = nm.position + Vector2(w + 8.0 * k, (nm.size.y - s.seal.size.y) / 2.0)
        if kind == "pc" and ui.resign_button.visible:
            ui.resign_button.position = R(PC.resign).position
    if kind == "mob":
        var cb: Button = mob_buttons.chatbar
        cb.visible = stage.mode != "bot" and stage.match_chat != null and stage.match_chat.active()

## Texto vivo maior que a caixa da arte: a fonte encolhe até caber (base = tamanho medido na referência).
func _fit(l: Label, font: Font, base_fs: float) -> void:
    var want := maxi(8, int(round(base_fs * k)))
    var px := want
    while px > 8 and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > l.size.x - 2.0: px -= 1
    if l.get_theme_font_size("font_size") != px:
        var asc_old := font.get_ascent(l.get_theme_font_size("font_size"))
        var base_y := l.position.y + asc_old
        l.add_theme_font_size_override("font_size", px)
        l.position.y = base_y - font.get_ascent(px)

# ------------------------------------------------------------------ celular: botões próprios + menu
func _build_mobile_controls() -> void:
    for id in ["sound", "gear", "more", "chatbar"]:
        var b := Button.new()
        b.name = "Skin_" + id
        b.flat = true
        b.focus_mode = Control.FOCUS_NONE
        for st in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
        b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        layer.add_child(b)
        mob_buttons[id] = b
        b.hide()
    mob_buttons.sound.pressed.connect(func(): stage.hub.toggle_sound())
    mob_buttons.gear.pressed.connect(func(): toggle_menu())
    mob_buttons.more.pressed.connect(func(): toggle_menu())
    mob_buttons.chatbar.pressed.connect(func():
        var c = stage.match_chat
        if c != null: c.set_mobile_open(not c.open_mobile))
    menu = PanelContainer.new()
    menu.name = "SkinMenu"
    var st := StyleBoxFlat.new()
    st.bg_color = Color("120f0b")
    st.border_color = Color("d08a2c")
    st.set_border_width_all(3)
    st.set_corner_radius_all(8)
    st.shadow_color = Color(0, 0, 0, 0.6)
    st.shadow_size = 14
    for side in ["left", "right", "top", "bottom"]: st.set("content_margin_" + side, 14)
    menu.add_theme_stylebox_override("panel", st)
    var col := VBoxContainer.new()
    col.name = "Items"
    col.add_theme_constant_override("separation", 8)
    menu.add_child(col)
    layer.add_child(menu)
    menu.hide()

func _menu_item(col: Control, text: String, action: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    var n := StyleBoxFlat.new()
    n.bg_color = Color("2a1e12")
    n.border_color = Color("c07a26")
    n.set_border_width_all(2)
    n.set_corner_radius_all(6)
    n.content_margin_top = 8
    n.content_margin_bottom = 8
    var h := n.duplicate()
    h.bg_color = Color("3d2b17")
    b.add_theme_stylebox_override("normal", n)
    b.add_theme_stylebox_override("hover", h)
    b.add_theme_stylebox_override("pressed", h)
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    b.add_theme_font_override("font", FONT_BOLD)
    b.add_theme_font_size_override("font_size", 16)
    b.add_theme_color_override("font_color", Color("f4ead2"))
    b.custom_minimum_size.y = 46
    b.pressed.connect(func():
        menu.hide()
        action.call())
    col.add_child(b)
    return b

## Opções da partida no celular (⋮ e engrenagem): as MESMAS ações dos botões de sempre.
func toggle_menu() -> void:
    if menu.visible:
        menu.hide()
        return
    var col: Control = menu.get_node("Items")
    for ch in col.get_children():
        col.remove_child(ch)
        ch.queue_free()
    var st = stage
    var bot_over: bool = st.mode == "bot" and st.game.game_over
    if st.mobile_restart != null and st.mobile_restart.visible: _menu_item(col, "JOGAR DE NOVO" if bot_over else "DESISTIR", func(): st.mobile_restart.pressed.emit()).name = "MenuResign"
    if st.mobile_mark != null and st.mobile_mark.visible: _menu_item(col, "MARCAR PARA REVISAR", func(): st.mobile_mark.pressed.emit())
    if st.mobile_analyze != null and st.mobile_analyze.visible: _menu_item(col, "ANALISAR PARTIDA", func(): st.mobile_analyze.pressed.emit())
    _menu_item(col, "MÚSICA: " + ("DESLIGADA" if ModeSound.music_muted(st.hub) else "LIGADA"), func(): ModeSound.toggle_music(st.hub))
    _menu_item(col, "EFEITOS: " + ("DESLIGADOS" if ModeSound.effects_muted(st.hub) else "LIGADOS"), func(): ModeSound.toggle_effects(st.hub))
    if st.mobile_fullscreen != null and st.mobile_fullscreen.visible: _menu_item(col, "TELA CHEIA", func(): st.mobile_fullscreen.pressed.emit())
    var mv = st.mobile_voice
    if mv != null and st.voice != null and st.voice.active(): _menu_item(col, "SAIR DA VOZ", func(): mv.off.pressed.emit())
    _menu_item(col, "FECHAR", func(): pass)
    menu.show()
    _layout_menu.call_deferred()

func _layout_menu() -> void:
    var vs: Vector2 = stage.get_viewport().get_visible_rect().size
    menu.reset_size()
    var w := minf(vs.x - 40.0, 340.0)
    menu.size = Vector2(w, menu.get_combined_minimum_size().y)
    menu.position = Vector2(vs.x - w - 12.0, R(MOB.more).end.y + 6.0)

# ------------------------------------------------------------------ desenho
class ArtBg extends Node2D:
    var tex: Texture2D
    var rect := Rect2()
    var full := Rect2()
    ## PC: região da arte SEM interface (só floresta). As sobras da tela vêm só daqui — nunca da borda inteira,
    ## que tem INÍCIO, barra de cima e painéis (espelhar a borda duplicava a interface em janela mais larga/alta).
    var clean := Rect2()
    var _fill: ShaderMaterial
    const FILL_SHADER := """
shader_type canvas_item;
uniform vec2 full_size; uniform vec2 art_pos; uniform vec2 art_size; uniform vec2 tex_size;
uniform vec4 clean; uniform float ramp;
float pp(float t, float L) { return clamp(L - abs(mod(t, 2.0 * L) - L), 0.5, L - 0.5); }
// ponto fora da arte (px da arte) -> ponto dentro da floresta limpa
vec2 fold(vec2 a) {
    float cx1 = clean.x + clean.z; float cy1 = clean.y + clean.w;
    vec2 s;
    // esquerda: espelho a partir da coluna 0 da arte (continua o cenário sem emenda);
    // direita/cima/baixo: floresta limpa em vai-e-vem (a borda da arte ali é interface)
    if (a.x < clean.x) s.x = clean.x + pp(clean.x - a.x, clean.z);
    else if (a.x >= tex_size.x) s.x = clean.x + pp(a.x - tex_size.x, clean.z);
    else if (a.x > cx1) s.x = clean.x + pp(a.x - clean.x, clean.z);
    else s.x = a.x;
    if (a.y < clean.y) s.y = clean.y + pp(clean.y - a.y, clean.w);
    else if (a.y > cy1) s.y = cy1 - pp(a.y - cy1, clean.w);
    else s.y = a.y;
    return s;
}
void fragment() {
    vec2 sp = UV * full_size;
    vec2 a = (sp - art_pos) / art_size * tex_size;
    vec2 oa = max(max(-a, a - tex_size), vec2(0.0));
    float da = max(oa.x, oa.y);                       // distância até a arte (px da arte)
    float far = smoothstep(0.0, ramp, da);
    // cenário nítido (o jogador achou feio o desfocado); só uma leve sombra conforme a distância
    vec3 c = texture(TEXTURE, fold(a) / tex_size).rgb;
    // emenda: os primeiros px da sobra repetem a própria borda da arte (espelhada, só 7 px: ali ainda é folhagem)
    // e passam suave para a floresta limpa; uma sombra leve marca a borda
    vec2 e = a;
    if (a.x < 0.0) e.x = min(-a.x, 7.0); else if (a.x >= tex_size.x) e.x = tex_size.x - 1.0 - min(a.x - tex_size.x, 7.0);
    if (a.y < 0.0) e.y = min(-a.y, 7.0); else if (a.y >= tex_size.y) e.y = tex_size.y - 1.0 - min(a.y - tex_size.y, 7.0);
    c = mix(texture(TEXTURE, (e + 0.5) / tex_size).rgb, c, smoothstep(1.0, 14.0, da));
    float k = mix(0.95, 0.82, far) * (1.0 - 0.22 * exp(-da / 7.0));
    COLOR = vec4(c * k, 1.0);
}
"""
    ## Sobras da tela: celular = a própria borda da arte, espelhada; PC = floresta limpa (nó filho com o shader, atrás da arte).
    func _draw():
        if tex == null: return
        if clean.has_area():
            if _fill == null:
                _fill = ShaderMaterial.new()
                _fill.shader = Shader.new()
                _fill.shader.code = FILL_SHADER
                var n := Sprite2D.new()   # cobre a tela toda; o shader recorta a arte e escurece as sobras
                n.name = "Fill"
                n.centered = false
                n.show_behind_parent = true
                n.material = _fill
                add_child(n)
            var f: Sprite2D = get_node("Fill")
            f.texture = tex
            f.position = full.position
            f.scale = full.size / tex.get_size()
            f.visible = true
            _fill.set_shader_parameter("full_size", full.size)
            _fill.set_shader_parameter("art_pos", rect.position)
            _fill.set_shader_parameter("art_size", rect.size)
            _fill.set_shader_parameter("tex_size", tex.get_size())
            _fill.set_shader_parameter("clean", Vector4(clean.position.x, clean.position.y, clean.size.x, clean.size.y))
            _fill.set_shader_parameter("ramp", 260.0)   # px da arte
            f.queue_redraw()
            draw_texture_rect(tex, rect, false)
            return
        if has_node("Fill"): get_node("Fill").visible = false
        var ts := tex.get_size()
        var k := rect.size.x / ts.x
        var tint := Color(0.86, 0.88, 0.85)
        var left := rect.position.x
        var right := full.size.x - rect.end.x
        var top := rect.position.y
        var bottom := full.size.y - rect.end.y
        # espelho em volta da borda: desenha a faixa da borda "para dentro" e reflete com a transformação
        if left > 0.5:
            var sw := minf(left / k, ts.x * 0.25)
            draw_set_transform(Vector2(2.0 * rect.position.x, 0), 0.0, Vector2(-1, 1))
            draw_texture_rect_region(tex, Rect2(rect.position.x, rect.position.y, left, rect.size.y), Rect2(0, 0, sw, ts.y), tint)
        if right > 0.5:
            var sw2 := minf(right / k, ts.x * 0.25)
            draw_set_transform(Vector2(2.0 * rect.end.x, 0), 0.0, Vector2(-1, 1))
            draw_texture_rect_region(tex, Rect2(rect.end.x - right, rect.position.y, right, rect.size.y), Rect2(ts.x - sw2, 0, sw2, ts.y), tint)
        if top > 0.5:
            var sh := minf(top / k, ts.y * 0.08)
            draw_set_transform(Vector2(0, 2.0 * rect.position.y), 0.0, Vector2(1, -1))
            draw_texture_rect_region(tex, Rect2(rect.position.x, rect.position.y, rect.size.x, top), Rect2(0, 0, ts.x, sh), tint)
        if bottom > 0.5:
            var sh2 := minf(bottom / k, 118.0)   # só o chão da floresta (abaixo dos botões da voz)
            draw_set_transform(Vector2(0, 2.0 * rect.end.y), 0.0, Vector2(1, -1))
            draw_texture_rect_region(tex, Rect2(rect.position.x, rect.end.y - bottom, rect.size.x, bottom), Rect2(0, ts.y - sh2, ts.x, sh2), tint)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        draw_texture_rect(tex, rect, false)

## Por cima de tudo da partida: brilho de hover nos botões da arte, estado (desligado/mudo) e o estado da voz.
class Marks extends Control:
    var skin
    func _draw():
        if skin == null or not skin.on: return
        var st = skin.stage
        if st.ranked_ui != null and st.ranked_ui.panel_open(): return
        var k: float = skin.k
        for h in skin.hits:
            var b = h[0]
            if not is_instance_valid(b) or not b.is_visible_in_tree(): continue
            var r: Rect2 = skin.R(h[1])
            if b.is_hovered() or (b is BaseButton and b.button_pressed):
                draw_rect(r.grow(-2.0 * k), Color(1.0, 0.86, 0.45, 0.13))
            var off_state := false
            match String(h[2]):
                "music": off_state = skin.ModeSound.music_muted(st.hub)
                "fx": off_state = skin.ModeSound.effects_muted(st.hub)
                "sound": off_state = bool(st.hub.sound_muted)
                "mic": off_state = st.voice != null and st.voice.state == "MUTED"
                "ear": off_state = st.voice != null and st.voice.active() and bool(st.voice.speaker_muted)
            if off_state: _slash(r, k)
        if skin.kind == "pc": _voice_pc(st, k)
        elif st.mode != "bot": _voice_mob(st, k)
        if skin.kind == "mob" and st.mode != "bot": _unread(st, k)

    func _slash(r: Rect2, k: float):
        var c := r.get_center()
        var a := minf(r.size.x, r.size.y) * 0.32
        draw_line(c + Vector2(-a, -a), c + Vector2(a, a), Color(0.05, 0.02, 0.0, 0.9), 6.0 * k)
        draw_line(c + Vector2(-a, -a), c + Vector2(a, a), Color("e07a5f"), 3.0 * k)

    ## PC: texto do estado da voz no lugar da arte; sem voz neste navegador, os ícones da voz ficam apagados.
    func _voice_pc(st, k: float):
        var v = st.voice
        var M: Dictionary = skin.PC
        var avail: bool = st.mode != "bot" and v != null and v.available() and v.in_match()
        var txt: String = v.status_text() if avail else ("Sem voz contra o computador" if st.mode == "bot" else "Voz indisponível neste navegador")
        if not avail:
            for id in ["mic", "ear", "off"]: draw_rect(skin.R(M[id]).grow(-3.0 * k), Color(0.05, 0.04, 0.03, 0.62))
        elif v != null and not v.active():
            draw_rect(skin.R(M.off).grow(-3.0 * k), Color(0.05, 0.04, 0.03, 0.62))
        var font := get_theme_default_font()
        var fs := int(round(13.5 * k))
        var r: Rect2 = skin.R(M.status)
        var lines := _wrap(font, txt, fs, r.size.x)
        var y := r.position.y + (r.size.y - lines.size() * fs * 1.22) / 2.0 + fs * 0.98
        for line in lines.slice(0, 2):
            draw_string_outline(font, Vector2(r.position.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.6))
            draw_string(font, Vector2(r.position.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ede6d6"))
            y += fs * 1.22

    ## Celular: bolinha (verde = na voz) + "Na voz"/estado curto na placa da arte.
    func _voice_mob(st, k: float):
        var v = st.voice
        var M: Dictionary = skin.MOB
        var avail: bool = v != null and v.available() and v.in_match()
        var p: Rect2 = skin.R(M.pill)
        var dot := Color("52e04a") if avail and v.active() else (Color("d9a441") if avail else Color("6d6a62"))
        var c := p.position + Vector2(34.0 * k, p.size.y / 2.0)
        draw_circle(c, 10.0 * k, Color(0, 0, 0, 0.5))
        draw_circle(c, 8.0 * k, dot)
        draw_circle(c + Vector2(-2.5, -2.5) * k, 3.0 * k, Color(1, 1, 1, 0.45))
        var txt := "Sem voz"
        if avail:
            txt = {"CONNECTED": "Na voz", "MUTED": "Mudo", "CONNECTING": "Conectando", "REQUESTING_PERMISSION": "Permita…", "RECONNECTING": "Reconectando", "ERROR": "Erro"}.get(String(v.state), "Entrar")
        var font: Font = skin.FONT_SEMI
        var fs := int(round(24.0 * k))
        var x := p.position.x + 62.0 * k
        while fs > 9 and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > p.end.x - x - 8.0 * k: fs -= 1
        var base := Vector2(x, p.get_center().y + fs * 0.36)
        draw_string_outline(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.6))
        draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f3ede0"))
        if not avail:
            for id in ["mic", "ear"]: draw_rect(skin.R(M[id]).grow(-4.0 * k), Color(0.05, 0.04, 0.03, 0.55))

    func _unread(st, k: float):
        var c = st.match_chat
        if c == null or int(c.unread) <= 0: return
        var r: Rect2 = skin.R(skin.MOB.chatbar)
        var at := Vector2(r.position.x + 245.0 * k, r.get_center().y)
        draw_circle(at, 16.0 * k, Color("c0392b"))
        var font := get_theme_default_font()
        var t := str(mini(int(c.unread), 99))
        var fs := int(round(18.0 * k))
        var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
        draw_string(font, at + Vector2(-w / 2.0, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

    func _wrap(font: Font, txt: String, fs: int, width: float) -> Array:
        var out := []
        var cur := ""
        for word in txt.split(" "):
            var t := word if cur.is_empty() else cur + " " + word
            if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and not cur.is_empty():
                out.append(cur)
                cur = word
            else: cur = t
        if not cur.is_empty(): out.append(cur)
        return out
