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
## R55.4 · artes SÓ do PC (R54): carregadas no primeiro uso (telas do PC), nunca no celular.
const ART_WIN_PATH := "res://ranked/art/desk_bot_win.png"
const ART_LOSS_PATH := "res://ranked/art/desk_bot_loss.png"
const ART_DRAW_PATH := "res://ranked/art/desk_bot_draw.png"   # R124
const ART_CROWN_PATH := "res://ranked/art/desk_icon_crown.png"
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
    if not preload("res://ui_v022/mobile_layout.gd").active(get_viewport()):   # R55.4 · PC: mesmas artes já carregadas
        for p in [ART_WIN_PATH, ART_LOSS_PATH, ART_CROWN_PATH]: load(p)
    layer = 60
    preload("res://ui_v022/esc_stack.gd").register(self)   # R129 · ESC fecha

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
    # R184e · celular/app: a MESMA arte de vitória do PC (padrão do dono para telas de resultado), com letras maiores,
    # luz girando atrás, faíscas, o avatar ganho "saltando" e as coroas contando (antes: caixinha azul simples).
    if true:
        _desk_victory(bot_id, bot, reward, fresh, true)
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
    dim.color = Color(0.000, 0.010, 0.029, 0.68)
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
    sb.bg_color = Color("182135")
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
        var lead := "Seu próximo rival:"
        var prize := next_prize(next_bot)
        if short:
            _lab(box, lead + " " + String(nb.get("name", "")) + ("  ·  " + prize if not prize.is_empty() else ""), 15, EMERALD)
        else:
            _lab(box, lead, 15, MUTED)
            _lab(box, String(nb.get("name", "")), 22, EMERALD)
            if not prize.is_empty(): _lab(box, prize, 15, GOLD)
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
        buttons["advance"] = _button(actions, challenge_text(next_bot), true, func():
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

## R181 · o próximo bot DESAFIA o jogador (botão principal grande) + o prêmio da 1ª vitória contra ele
static func challenge_text(next_id: String) -> String:
    return String(Ladder.bot(next_id).get("name", "BOT")) + " TE DESAFIOU! JOGAR AGORA"

static func next_prize(next_id: String) -> String:
    var r: Dictionary = Ladder.reward(next_id)
    var aid := String(r.get("id", ""))
    if String(r.get("type", "")) == "avatar" and not aid.is_empty(): return "Vença e ganhe: Avatar " + Catalog.display_name(aid)
    return ""

func _desktop() -> bool:
    return get_viewport() != null and not MobileLayout.active(get_viewport())

func _desk(tex: Texture2D) -> Control:
    var d = DeskArt.new()
    d.name = "DeskBotResult"
    add_child(d)
    d.begin(tex, Vector2(1254, 1254), "bot", true)
    d.side_trim = 56.0 / 940.0   # R133 · as artes do bot têm 56/940 px transparentes de cada lado
    root = d
    return d

func _desk_buttons(d, main_text: String, main_action: Callable, key: String, mob := false):
    buttons.clear()
    d.image(load(ART_CROWN_PATH), Rect2(278, 874, 60, 58) if not mob else Rect2(196, 872, 64, 62)).name = "DeskBotCrown"
    if not mob: d.label(main_text, Rect2(350, 869, 620, 60), 40, DeskArt.CREAM, DeskArt.FONT_TITLE).name = "DeskBotMainText"   # PC congelado (R181)
    else: d.label(main_text, Rect2(266, 862, 820, 74), 54, DeskArt.CREAM, DeskArt.FONT_TITLE).name = "DeskBotMainText"
    buttons[key] = d.button(Rect2(150, 853, 960, 94), main_action, "DeskBotMain", 16)   # advance / replay (mesmas chaves do painel antigo)
    buttons["analyze"] = d.button(Rect2(165, 963, 925, 84), func():
        close()
        analyze_requested.emit(), "DeskBotAnalyze", 14)
    buttons["analyze"].disabled = can_analyze.is_valid() and not bool(can_analyze.call())
    buttons["home"] = d.button(Rect2(165, 1063, 925, 84), func():
        close()
        home_requested.emit(), "DeskBotHome", 14)

## R54 · PC: VITÓRIA contra o bot na arte de referência (brasões, próximo adversário, recompensa e 3 ações).
func _desk_victory(bot_id: String, bot: Dictionary, reward: Dictionary, fresh: bool, mob := false):
    var d = _desk(load(ART_WIN_PATH))
    var final := next_bot.is_empty()
    var bname := String(bot.get("name", "BOT"))
    var F := 1.3 if mob else 1.0   # R184e · celular: letras maiores
    d.label(bname + (" DERROTADO" if fresh else " DERROTADO NOVAMENTE"), Rect2(220, 316, 815, 60) if mob else Rect2(250, 322, 755, 52), 42 * F, DeskArt.CREAM, DeskArt.FONT_BODY).name = "DeskBotSub"
    var left: Texture2D = ThemeCatalog.badge_texture(String(bot.get("league", bot_id)))
    if final:
        d.image(left, Rect2(522, 358, 210, 206)).name = "DeskBotShield"
        d.label("DESAFIO DAS LIGAS CONCLUÍDO" if fresh else "Você venceu todos os bots", Rect2(250, 556, 755, 42), 36, Color("efd9a6"), DeskArt.FONT_BODY).name = "DeskBotNextLead"
        d.label("DO MADEIRA AO CHALLENGER", Rect2(250, 596, 755, 56), 46, DeskArt.EMERALD, DeskArt.FONT_TITLE).name = "DeskBotNext"
    else:
        var nb := Ladder.bot(next_bot)
        d.image(left, Rect2(382, 360, 204, 200)).name = "DeskBotShield"
        d.image(ThemeCatalog.badge_texture(String(nb.get("league", next_bot))), Rect2(666, 360, 204, 200)).name = "DeskBotNextShield"
        d.label("Próximo adversário desbloqueado:" if fresh else "Próximo adversário:", Rect2(220, 552, 815, 46) if mob else Rect2(250, 556, 755, 42), 36 * F, Color("efd9a6"), DeskArt.FONT_BODY).name = "DeskBotNextLead"
        d.label(String(nb.get("name", "")), Rect2(220, 590, 815, 56) if mob else Rect2(250, 596, 755, 56), 58, DeskArt.EMERALD, DeskArt.FONT_TITLE).name = "DeskBotNext"
    # recompensa (avatar da liga do bot)
    var aid := String(reward.get("id", ""))
    if String(reward.get("type", "")) == "avatar" and not aid.is_empty():
        var tex: Texture2D = avatar_for.call(aid) if avatar_for.is_valid() and Catalog.has_art(aid) else null
        if tex != null: d.image(tex, Rect2(215, 679, 145, 132)).name = "DeskBotRewardArt"
        var crowns: int = preload("res://bot/bot_crowns.gd").for_bot(bot_id) if (mob and fresh) else 0
        if mob and fresh and crowns_preview > 0: crowns = crowns_preview
        var ty := 0.0 if crowns <= 0 else -18.0
        var what := "Avatar " + Catalog.display_name(aid)
        if not mob:
            d.label("Recompensa desbloqueada!" if fresh else "Recompensa já conquistada", Rect2(388, 694, 650, 42), 32, Color("e8c37a"), DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT).name = "DeskBotRewardTitle"
            what += (" desbloqueado" + ("" if Catalog.has_art(aid) else " (arte em breve)")) if fresh else " · sem recompensa nova"
            d.label(what, Rect2(388, 734, 650, 52), 36, DeskArt.CREAM, DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT).name = "DeskBotRewardText"
        else:
            d.label("Recompensa desbloqueada!" if fresh else "Recompensa já conquistada", Rect2(388, 690 + ty, 650, 42), 32 * F, Color("e8c37a"), DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT).name = "DeskBotRewardTitle"
            if not fresh: what += " · já é seu"
            d.label(what, Rect2(388, 730 + ty, 650, 52), 36 * F, DeskArt.CREAM, DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT).name = "DeskBotRewardText"
            if crowns > 0:
                var cl0: Label = d.label("+ %d COROAS" % crowns, Rect2(388, 776 + ty, 650, 52), 40 * F, Color("ffe08a"), DeskArt.FONT_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
                cl0.name = "DeskBotCrowns"
                cl0.set_meta("n", crowns)
    else:
        d.label("Sem recompensa nesta partida", Rect2(388, 714, 650, 52), 34, DeskArt.MUTED, DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT).name = "DeskBotRewardText"
    if final:
        _desk_buttons(d, "JOGAR NOVAMENTE", func():
            var target := shown_bot
            close()
            replay_requested.emit(target), "replay", mob)
    else:
        var nb_name := String(Ladder.bot(next_bot).get("name", ""))
        var main := (("AVANÇAR PARA O " + nb_name) if fresh else ("JOGAR PRÓXIMO BOT · " + nb_name)) if not mob else ("DESAFIAR O " + nb_name)
        _desk_buttons(d, main, func():   # PC congelado (R181)
            var target := next_bot
            close()
            advance_requested.emit(target), "advance", mob)
    d.show_modal()
    if mob: _mob_fx(d, fresh)

var crowns_preview := 0   # só para a prévia (tests/r184_bot_victory_shots.gd)

## R184e · celular: luz girando atrás da moldura, faíscas, avatar ganho saltando e coroas contando
func _mob_fx(d, fresh: bool):
    var ar: Rect2 = d.art_rect()
    var k: float = d.scale_k()
    var fx = preload("res://ui_kit/reward_fx.gd").new()
    fx.name = "VictoryFx"
    fx.position = Vector2.ZERO
    fx.size = d.get_viewport_rect().size
    fx.center = ar.position + Vector2(627, 230) * k
    fx.radius = ar.size.x * 0.95
    fx.rays = 16
    fx.ray_color = Color(1.0, 0.84, 0.40, 0.20 if fresh else 0.10)
    fx.sparkle_area = Rect2(ar.position + Vector2(160, 160) * k, Vector2(934, 760) * k) if fresh else Rect2()
    d.add_child(fx)
    d.move_child(fx, 1)   # entre o escuro de fundo e a arte
    var av = d.get_node_or_null("DeskBotRewardArt")
    if av != null and fresh:
        av.pivot_offset = av.size * 0.5
        av.scale = Vector2(0.2, 0.2)
        var tw = av.create_tween()
        tw.tween_interval(0.35)
        tw.tween_property(av, "scale", Vector2(1.18, 1.18), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        tw.tween_property(av, "scale", Vector2.ONE, 0.18)
    var cl = d.get_node_or_null("DeskBotCrowns")
    if cl != null:
        var total := int(cl.get_meta("n", 0))
        var tw2 = cl.create_tween()
        tw2.tween_interval(0.6)
        tw2.tween_method(func(v: float): cl.text = "+ %d COROAS" % int(round(v)), 0.0, float(total), 0.9).set_ease(Tween.EASE_OUT)

## R54 · DERROTA contra o bot (PC): tela de resultado útil — revanche, analisar ou voltar ao início.
## O bot que venceu aparece com o brasão da liga; nada é desbloqueado.
func show_defeat(bot_id: String, display_name := ""):
    close()
    shown_bot = bot_id
    next_bot = next_of(bot_id)
    var bot := Ladder.bot(bot_id)
    var bname := String(bot.get("name", display_name if not display_name.is_empty() else "COMPUTADOR"))
    var d = _desk(load(ART_LOSS_PATH))
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

## R124 · EMPATE contra o bot (afogamento, repetição, material insuficiente, 50 lances…): mesmo painel da derrota.
func show_draw(bot_id: String, display_name := "", reason := ""):
    close()
    shown_bot = bot_id
    next_bot = next_of(bot_id)
    var bot := Ladder.bot(bot_id)
    var bname := String(bot.get("name", display_name if not display_name.is_empty() else "COMPUTADOR"))
    var d = _desk(load(ART_DRAW_PATH))
    d.label("NINGUÉM VENCEU CONTRA " + bname, Rect2(250, 322, 755, 52), 40, DeskArt.CREAM, DeskArt.FONT_BODY).name = "DeskBotSub"
    if not bot.is_empty():
        d.image(ThemeCatalog.badge_texture(String(bot.get("league", bot_id))), Rect2(522, 358, 210, 206)).name = "DeskBotShield"
    var why := reason.strip_edges()
    if "—" in why: why = why.get_slice("—", 1).strip_edges()
    var info := ("Empate por %s. " % why.to_lower()) if not why.is_empty() and why.to_upper() != "EMPATE" else ""
    info += "Para avançar no Desafio das Ligas é preciso vencer."
    d.label(info, Rect2(200, 590, 855, 110), 36, Color("efd9a6"), DeskArt.FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER, true).name = "DeskBotInfo"
    d.label("Analise a partida para ver onde a vitória escapou.", Rect2(230, 712, 795, 60), 34, DeskArt.MUTED, DeskArt.FONT_MED).name = "DeskBotTip"
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
    dim.color = Color(0.000, 0.010, 0.029, 0.6)
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
        s.bg_color = (Color("6b4a12") if primary else Color("1e2c48")).lightened(maxf(0.0, states[st])).darkened(maxf(0.0, -states[st]))
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
