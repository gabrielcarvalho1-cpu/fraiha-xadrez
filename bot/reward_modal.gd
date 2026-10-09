extends CanvasLayer
## Painel de PROGRESSÃO depois da 1ª vitória contra um bot da escada.
## Só é aberto a partir de bot_progress.reward_unlocked — que só dispara com vitória CONFIRMADA
## (conta: servidor confirmou o bot_victory; convidado/servidor sem 0006: progresso local previsto).
## Espera a animação de VITÓRIA terminar. Mostra: bot derrotado, próximo adversário (ordem oficial de
## bot/bot_ladder.json), recompensa e duas ações: AVANÇAR PARA O PRÓXIMO BOT / VOLTAR PARA O INÍCIO.
## Último bot (Challenger): "DESAFIO DAS LIGAS CONCLUÍDO" com VOLTAR PARA O INÍCIO / JOGAR NOVAMENTE.
signal advance_requested(bot_id: String)
signal home_requested
signal replay_requested(bot_id: String)
signal analyze_requested

const DeskArt = preload("res://ranked/desk_art_modal.gd")   # R54 · PC: telas na arte de referência
const ART_WIN := preload("res://ranked/art/desk_bot_win.png")
const ART_LOSS := preload("res://ranked/art/desk_bot_loss.png")
const ART_CROWN := preload("res://ranked/art/desk_icon_crown.png")
const MobileLayout = preload("res://ui_v022/mobile_layout.gd")

const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const Ladder = preload("res://bot/bot_ladder.gd")
const Catalog = preload("res://profile/avatar_catalog.gd")
const GOLD := Color("ffd98a")
const CREAM := Color("f4ead2")
const MUTED := Color("b9b29c")
const EMERALD := Color("8fe0a0")

var root: Control
var avatar_for: Callable   # id -> Texture2D (avatar do hub)
var shown_bot := ""
var shown_fresh := true
var next_bot := ""
var buttons := {}
var can_analyze: Callable          # stage.analysis_available (ANALISAR PARTIDA só quando há o que analisar)

func _ready():
    layer = 60

## Próximo bot da escada (ordem oficial do bot_ladder.json); "" depois do Challenger.
static func next_of(bot_id: String) -> String:
    var i := Ladder.index_of(bot_id)
    if i < 0 or i + 1 >= Ladder.ids().size(): return ""
    return Ladder.ids()[i + 1]

## Compatibilidade com a chamada antiga.
func show_reward(bot_id: String, reward: Dictionary):
    show_progress(bot_id, reward)

## fresh=true: 1ª vitória (próximo bot desbloqueado agora + recompensa nova).
## fresh=false: revanche contra bot já derrotado (nenhuma recompensa nova; próximo bot já liberado).
func show_progress(bot_id: String, reward: Dictionary, fresh := true):
    close()
    shown_fresh = fresh
    shown_bot = bot_id
    next_bot = next_of(bot_id)
    var bot := Ladder.bot(bot_id)
    if _desktop():
        _desk_victory(bot_id, bot, reward, fresh)
        return
    var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1600, 900)
    var narrow := vp.x < 700.0
    var short := vp.y < 520.0
    root = Control.new()
    root.name = "ProgressionPanel"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    var dim := ColorRect.new()
    dim.color = Color(0, 0.02, 0.01, 0.68)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(dim)
    var scroll := ScrollContainer.new()
    scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    root.add_child(scroll)
    var center := CenterContainer.new()
    center.custom_minimum_size = vp
    scroll.add_child(center)
    var panel := PanelContainer.new()
    panel.name = "Panel"
    panel.custom_minimum_size = Vector2(minf(560.0, vp.x - 24.0), 0)
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color("11261a")
    sb.border_color = Color("f0c45c")
    sb.set_border_width_all(3)
    sb.set_corner_radius_all(8)
    sb.shadow_color = Color(0.96, 0.78, 0.36, 0.45)
    sb.shadow_size = 18
    var m := 14.0 if narrow else 24.0
    for side in ["left", "right", "top", "bottom"]: sb.set("content_margin_" + side, m)
    panel.add_theme_stylebox_override("panel", sb)
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 6 if short else 10)
    panel.add_child(box)
    var final := next_bot.is_empty()
    _lab(box, ("DESAFIO DAS LIGAS CONCLUÍDO" if fresh else "VITÓRIA!") if final else "VITÓRIA!", 24 if (narrow or short) else 32, GOLD)
    _lab(box, String(bot.get("name", "BOT")) + (" DERROTADO" if fresh else " DERROTADO NOVAMENTE"), 18 if narrow else 20, CREAM)
    # brasões: derrotado → próximo (ou só o último, coroado)
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 14)
    box.add_child(row)
    var bs := 44 if short else (64 if narrow else 88)
    _tex(row, ThemeCatalog.badge_texture(String(bot.get("league", bot_id))), bs, 1.0)
    if not final:
        var arrow := Label.new()
        arrow.text = ">"
        arrow.add_theme_font_size_override("font_size", 34)
        arrow.add_theme_color_override("font_color", GOLD)
        row.add_child(arrow)
        var nb := Ladder.bot(next_bot)
        _tex(row, ThemeCatalog.badge_texture(String(nb.get("league", next_bot))), bs, 1.0)
        var lead := "Próximo adversário desbloqueado:" if fresh else "Próximo adversário:"
        if short:
            _lab(box, lead + " " + String(nb.get("name", "")), 16, EMERALD)
        else:
            _lab(box, lead, 15, MUTED)
            _lab(box, String(nb.get("name", "")), 22, EMERALD)
    else:
        _lab(box, "Você venceu todos os bots, do MADEIRA ao CHALLENGER.", 15, MUTED)
    # recompensa
    var aid := String(reward.get("id", ""))
    if String(reward.get("type", "")) == "avatar" and not aid.is_empty():
        var rrow := HBoxContainer.new()
        rrow.alignment = BoxContainer.ALIGNMENT_CENTER
        rrow.add_theme_constant_override("separation", 12)
        box.add_child(rrow)
        var tex: Texture2D = avatar_for.call(aid) if avatar_for.is_valid() and Catalog.has_art(aid) else null
        if tex != null: _tex(rrow, tex, 48 if short else (64 if narrow else 84), 1.0)
        var words := VBoxContainer.new()
        # largura explícita: Label com quebra automática dentro de HBox tem largura mínima 0 (texto em coluna)
        words.custom_minimum_size.x = minf(380.0, maxf(160.0, panel.custom_minimum_size.x - 2.0 * m - (64.0 if (narrow or short) else 84.0) - 16.0))
        rrow.add_child(words)
        if fresh:
            _lab(words, "Recompensa", 14, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
            _lab(words, "Avatar " + Catalog.display_name(aid) + " desbloqueado" + ("" if Catalog.has_art(aid) else " (arte em breve)"), 17, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
        else:
            _lab(words, "Recompensa já conquistada", 14, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
            _lab(words, "Avatar " + Catalog.display_name(aid) + " · sem recompensa nova", 16, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
    var gap := Control.new()
    gap.custom_minimum_size.y = 4
    box.add_child(gap)
    buttons.clear()
    # celular deitado (pouca altura): os dois botões lado a lado para tudo caber sem rolar
    var actions: Container = box
    if short and not narrow:
        actions = HBoxContainer.new()
        actions.add_theme_constant_override("separation", 10)
        box.add_child(actions)
    if not final:
        var nb_name := String(Ladder.bot(next_bot).get("name", ""))
        buttons["advance"] = _button(actions, ("AVANÇAR PARA O " + nb_name) if fresh else ("JOGAR PRÓXIMO BOT · " + nb_name), true, func():
            var target := next_bot
            close()
            advance_requested.emit(target))
    else:
        buttons["replay"] = _button(actions, "JOGAR NOVAMENTE", true, func():
            var target := shown_bot
            close()
            replay_requested.emit(target))
    buttons["home"] = _button(actions, "VOLTAR PARA O INÍCIO", false, func():
        close()
        home_requested.emit())
    panel.pivot_offset = panel.custom_minimum_size / 2.0
    panel.scale = Vector2(0.85, 0.85)
    panel.modulate.a = 0.0
    var tw := create_tween().set_parallel(true)
    tw.tween_property(panel, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_property(panel, "modulate:a", 1.0, 0.22)

func _desktop() -> bool:
    return get_viewport() != null and not MobileLayout.active(get_viewport())

func _desk(tex: Texture2D) -> Control:
    var d = DeskArt.new()
    d.name = "DeskBotResult"
    add_child(d)
    d.begin(tex, Vector2(1254, 1254), "bot", true)
    root = d
    return d

func _desk_buttons(d, main_text: String, main_action: Callable, key: String):
    buttons.clear()
    d.image(ART_CROWN, Rect2(278, 874, 60, 58)).name = "DeskBotCrown"
    d.label(main_text, Rect2(350, 869, 620, 60), 40, DeskArt.CREAM, DeskArt.FONT_TITLE).name = "DeskBotMainText"
    buttons[key] = d.button(Rect2(150, 853, 960, 94), main_action, "DeskBotMain", 16)   # advance / replay (mesmas chaves do painel antigo)
    buttons["analyze"] = d.button(Rect2(165, 963, 925, 84), func():
        close()
        analyze_requested.emit(), "DeskBotAnalyze", 14)
    buttons["analyze"].disabled = can_analyze.is_valid() and not bool(can_analyze.call())
    buttons["home"] = d.button(Rect2(165, 1063, 925, 84), func():
        close()
        home_requested.emit(), "DeskBotHome", 14)

## R54 · PC: VITÓRIA contra o bot na arte de referência (brasões, próximo adversário, recompensa e 3 ações).
func _desk_victory(bot_id: String, bot: Dictionary, reward: Dictionary, fresh: bool):
    var d = _desk(ART_WIN)
    var final := next_bot.is_empty()
    var bname := String(bot.get("name", "BOT"))
    d.label(bname + (" DERROTADO" if fresh else " DERROTADO NOVAMENTE"), Rect2(250, 322, 755, 52), 42, DeskArt.CREAM, DeskArt.FONT_BODY).name = "DeskBotSub"
    var left: Texture2D = ThemeCatalog.badge_texture(String(bot.get("league", bot_id)))
    if final:
        d.image(left, Rect2(522, 358, 210, 206)).name = "DeskBotShield"
        d.label("DESAFIO DAS LIGAS CONCLUÍDO" if fresh else "Você venceu todos os bots", Rect2(250, 556, 755, 42), 36, Color("efd9a6"), DeskArt.FONT_BODY).name = "DeskBotNextLead"
        d.label("DO MADEIRA AO CHALLENGER", Rect2(250, 596, 755, 56), 46, DeskArt.EMERALD, DeskArt.FONT_TITLE).name = "DeskBotNext"
    else:
        var nb := Ladder.bot(next_bot)
        d.image(left, Rect2(382, 360, 204, 200)).name = "DeskBotShield"
        d.image(ThemeCatalog.badge_texture(String(nb.get("league", next_bot))), Rect2(666, 360, 204, 200)).name = "DeskBotNextShield"
        d.label("Próximo adversário desbloqueado:" if fresh else "Próximo adversário:", Rect2(250, 556, 755, 42), 36, Color("efd9a6"), DeskArt.FONT_BODY).name = "DeskBotNextLead"
        d.label(String(nb.get("name", "")), Rect2(250, 596, 755, 56), 58, DeskArt.EMERALD, DeskArt.FONT_TITLE).name = "DeskBotNext"
    # recompensa (avatar da liga do bot)
    var aid := String(reward.get("id", ""))
    if String(reward.get("type", "")) == "avatar" and not aid.is_empty():
        var tex: Texture2D = avatar_for.call(aid) if avatar_for.is_valid() and Catalog.has_art(aid) else null
        if tex != null: d.image(tex, Rect2(215, 679, 145, 132)).name = "DeskBotRewardArt"
        d.label("Recompensa desbloqueada!" if fresh else "Recompensa já conquistada", Rect2(388, 694, 650, 42), 32, Color("e8c37a"), DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT).name = "DeskBotRewardTitle"
        var what := "Avatar " + Catalog.display_name(aid)
        what += (" desbloqueado" + ("" if Catalog.has_art(aid) else " (arte em breve)")) if fresh else " · sem recompensa nova"
        d.label(what, Rect2(388, 734, 650, 52), 36, DeskArt.CREAM, DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT).name = "DeskBotRewardText"
    else:
        d.label("Sem recompensa nesta partida", Rect2(388, 714, 650, 52), 34, DeskArt.MUTED, DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT).name = "DeskBotRewardText"
    if final:
        _desk_buttons(d, "JOGAR NOVAMENTE", func():
            var target := shown_bot
            close()
            replay_requested.emit(target), "replay")
    else:
        var nb_name := String(Ladder.bot(next_bot).get("name", ""))
        _desk_buttons(d, ("AVANÇAR PARA O " + nb_name) if fresh else ("JOGAR PRÓXIMO BOT · " + nb_name), func():
            var target := next_bot
            close()
            advance_requested.emit(target), "advance")
    d.show_modal()

## R54 · DERROTA contra o bot (PC): tela de resultado útil — revanche, analisar ou voltar ao início.
## O bot que venceu aparece com o brasão da liga; nada é desbloqueado.
func show_defeat(bot_id: String, display_name := ""):
    close()
    if not _desktop(): return
    shown_bot = bot_id
    next_bot = next_of(bot_id)
    var bot := Ladder.bot(bot_id)
    var bname := String(bot.get("name", display_name if not display_name.is_empty() else "COMPUTADOR"))
    var d = _desk(ART_LOSS)
    d.label(bname + " VENCEU A PARTIDA", Rect2(250, 322, 755, 52), 42, DeskArt.CREAM, DeskArt.FONT_BODY).name = "DeskBotSub"
    if not bot.is_empty():
        d.image(ThemeCatalog.badge_texture(String(bot.get("league", bot_id))), Rect2(522, 358, 210, 206)).name = "DeskBotShield"
    var info := "Não desanime: cada partida é treino."
    if not next_bot.is_empty():
        info = "Vença o %s para liberar o %s." % [bname, String(Ladder.bot(next_bot).get("name", ""))]
    d.label(info, Rect2(200, 590, 855, 110), 38, Color("efd9a6"), DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER, true).name = "DeskBotInfo"
    d.label("Analise a partida para ver onde o jogo virou.", Rect2(230, 712, 795, 60), 34, DeskArt.MUTED, DeskArt.FONT_MED).name = "DeskBotTip"
    _desk_buttons(d, "ENFRENTAR O BOT NOVAMENTE", func():
        var target := shown_bot
        close()
        replay_requested.emit(target), "replay")
    d.show_modal()

## Vitória NÃO confirmada (sem conexão, servidor recusou…): só o aviso, sem desbloqueio nem "avançar".
func show_error(message: String):
    close()
    shown_bot = ""
    next_bot = ""
    var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1600, 900)
    root = Control.new()
    root.name = "ProgressionError"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    var dim := ColorRect.new()
    dim.color = Color(0, 0.02, 0.01, 0.6)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(minf(480.0, vp.x - 24.0), 0)
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color("1f1a12")
    sb.border_color = Color("c9764f")
    sb.set_border_width_all(3)
    sb.set_corner_radius_all(8)
    for side in ["left", "right", "top", "bottom"]: sb.set("content_margin_" + side, 18.0)
    panel.add_theme_stylebox_override("panel", sb)
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 10)
    panel.add_child(box)
    _lab(box, "VITÓRIA NÃO REGISTRADA", 22, Color("f0a07a"))
    _lab(box, message, 16, CREAM)
    _lab(box, "Nenhum bot foi desbloqueado. Tente novamente quando estiver conectado.", 13, MUTED)
    buttons.clear()
    buttons["ok"] = _button(box, "OK", false, close)

func close():
    if is_instance_valid(root): root.queue_free()
    root = null

func is_open() -> bool:
    return is_instance_valid(root)

func _lab(parent: Node, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
    var l := Label.new()
    l.text = text
    l.horizontal_alignment = align
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    l.add_theme_constant_override("shadow_offset_y", 1)
    parent.add_child(l)
    return l

func _tex(parent: Node, tex: Texture2D, px: int, alpha: float):
    var t := TextureRect.new()
    t.texture = tex
    t.custom_minimum_size = Vector2(px, px)
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    t.modulate.a = alpha
    parent.add_child(t)

func _button(parent: Node, caption: String, primary: bool, cb: Callable) -> Button:
    var b := Button.new()
    b.text = caption
    b.custom_minimum_size = Vector2(0, 56)
    b.focus_mode = Control.FOCUS_ALL
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b.add_theme_font_size_override("font_size", 18 if primary else 16)
    var states := {"normal": 0.0, "hover": 0.15, "pressed": -0.1, "focus": 0.15}
    for st in states:
        var s := StyleBoxFlat.new()
        s.bg_color = (Color("6b4a12") if primary else Color("163522")).lightened(maxf(0.0, states[st])).darkened(maxf(0.0, -states[st]))
        s.border_color = Color("f0c45c") if primary else Color("b8913f")
        s.set_border_width_all(2)
        s.set_corner_radius_all(5)
        s.content_margin_left = 12
        s.content_margin_right = 12
        b.add_theme_stylebox_override(st, s)
    b.add_theme_color_override("font_color", Color("ffe9b0") if primary else Color("f1e4c2"))
    b.add_theme_color_override("font_hover_color", Color("fff4c8"))
    b.pressed.connect(cb)
    parent.add_child(b)
    return b
