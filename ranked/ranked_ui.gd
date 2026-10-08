extends CanvasLayer
## Telas de partida online (Ranked e Casual): modalidades, busca, adversário encontrado,
## HUD com relógios e resultado. Só exibe o que o servidor informa; não calcula PL nem resultado.
## kind = "ranked" (PL, conta) | "casual" (sem PL, aceita convidado).
signal invite_requested   # R35.1: CONVIDAR AMIGO (só no JOGAR ONLINE casual; nunca no Ranqueado)
signal back_requested
signal play_requested
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const TouchScroll = preload("res://ui_v022/touch_scroll.gd")
const ClockView = preload("res://ranked/clock_view.gd")
const Catalog = preload("res://league/catalog.gd")
const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const MODES = [["ranked_3min", "RELÂMPAGO", 3], ["ranked_5min", "RÁPIDA", 5], ["ranked_10min", "NORMAL", 10], ["ranked_20min", "CONVENCIONAL", 20]]
const CASUAL_MODES = [["casual_3min", "RELÂMPAGO", 3], ["casual_5min", "RÁPIDA", 5], ["casual_10min", "NORMAL", 10], ["casual_20min", "CONVENCIONAL", 20]]
const LEAGUES = ["Madeira","Ferro","Bronze","Prata","Ouro","Platina","Esmeralda","Diamante","Mestre","Grande Mestre","Challenger"]
const GOLD = Color("f4ce7f")
const Cosmetics = preload("res://profile/premium_cosmetics.gd")
const PlayerPortrait = preload("res://profile/player_portrait.gd")
const Plaque = preload("res://ranked/player_plaque.gd")   # R46 · placa do jogador (proposta A aprovada)
const LEAGUE_ACCENT := [Color("b07a44"), Color("a9b1b6"), Color("c98a4a"), Color("d3dbe0"), Color("f4ce7f"), Color("86dccf"), Color("68d48a"), Color("94c9ff"), Color("c99bff"), Color("ff9b8f"), Color("ffd76a")]
var hub = null   # main_hub (meu selo na faixa "Você")
var account
var controller
var dim: ColorRect
var panel: PanelContainer
var box: VBoxContainer
var scroll: ScrollContainer
var art_frame: Control
var art_panel
signal switch_requested(kind: String)
var footer: VBoxContainer
var screen := ""
var search_started := 0
var search_label: Label
var found_label: Label
var notice: Label
var hud: Control
var strips := {}
var resign_button: Button
var link_label: Label
var result_bar: ProgressBar
var bar_target := 0.0
var last_mode := ""
var hud_font := 18
var two_line := false
var kind := "ranked"
var promo = null   # R49 · ranked/promotion_modal.gd
## R52c · BUSCANDO ADVERSÁRIO: painel/modal da referência (ui_kit/pages/buscando_bg.png, 1448 x 1086),
## centralizado por cima do jogo escurecido, com fade. Título, molduras e CANCELAR são da arte;
## ritmo e contador são do jogo. (O painel de texto antigo continua montado por baixo, oculto.)
const SEARCH_REF := Vector2(1448, 1086)
var search_art: Control
var search_mode_label: Label
var search_time_label: Label
## R53 · JOGAR RANQUEADO no celular: painel da referência do celular (ranked/mobile_ranked_art.gd); a lista
## antiga continua montada por baixo, oculta, como fonte das ações (Queue_<ritmo>, BackButton).
var mobile_art = null

func rated() -> bool:
    return kind == "ranked"

## Ritmos MOSTRADOS: só os que o servidor diz que estão abertos (Admin controla a liquidez) — Ranked e Casual.
func mode_list() -> Array:
    if not rated(): return CASUAL_MODES.filter(func(m): return account == null or account.casual_mode_open(String(m[0])))
    return MODES.filter(func(m): return account == null or account.ranked_mode_open(String(m[0])))

## Texto quando o Admin fechou todos os ritmos (ou a fila inteira).
func unavailable_title() -> String:
    return "RANQUEADA TEMPORARIAMENTE INDISPONÍVEL" if rated() else "CASUAL TEMPORARIAMENTE INDISPONÍVEL"

func all_modes() -> Array:
    return MODES if rated() else CASUAL_MODES

func setup(service, ranked_controller):
    account = service
    controller = ranked_controller
    layer = 45
    hud = Control.new()
    hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(hud)
    dim = ColorRect.new()
    dim.color = Color(0.02, 0.04, 0.03, 0.82)
    add_child(dim)
    # Moldura medieval (mesma da tela de entrada: ouro, brasão, cavalos) atrás do conteúdo.
    art_panel = preload("res://ranked/online_art_panel.gd").new()
    art_panel.name = "OnlineArtPanel"
    art_frame = preload("res://account/login_frame.gd").new()
    art_frame.name = "QueueFrame"
    add_child(art_frame)
    add_child(art_panel)
    art_panel.setup(self)
    _build_search_art()
    mobile_art = preload("res://ranked/mobile_ranked_art.gd").new()
    add_child(mobile_art)
    mobile_art.setup(self)
    panel = PanelContainer.new()
    var style = StyleBoxEmpty.new()
    style.content_margin_left = 34
    style.content_margin_right = 34
    style.content_margin_top = 64
    style.content_margin_bottom = 24
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    var frame = VBoxContainer.new()
    frame.add_theme_constant_override("separation", 10)
    panel.add_child(frame)
    scroll = ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    frame.add_child(scroll)
    TouchScroll.attach(scroll)
    # Rodapé fixo (fora da rolagem): VOLTAR sempre visível, mesmo em telas baixas.
    footer = VBoxContainer.new()
    footer.name = "Footer"
    frame.add_child(footer)
    box = VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 10)
    scroll.add_child(box)
    for side in ["top", "bottom"]: strips[side] = _make_strip()
    promo = preload("res://ranked/promotion_modal.gd").new()
    var promo_layer := CanvasLayer.new()   # acima do chat (46) e das marcas da pele (47)
    promo_layer.name = "PromotionLayer"
    promo_layer.layer = 48
    add_child(promo_layer)
    promo_layer.add_child(promo)
    promo.play_again.connect(func():
        var m := String(promo.get_meta("mode", controller.last_result.get("mode", "")))
        close_panel()
        play_requested.emit()
        controller.queue(m))
    promo.back_to_ranked.connect(func():
        play_requested.emit()
        _show("modes"))
    promo.analyze.connect(func():
        close_panel()
        var st = get_parent()
        if st != null and st.has_method("open_analysis"): st.open_analysis())
    resign_button = Button.new()
    resign_button.text = "DESISTIR"
    resign_button.add_theme_font_size_override("font_size", 16)
    resign_button.pressed.connect(_confirm_resign)
    hud.add_child(resign_button)
    link_label = Label.new()
    link_label.add_theme_font_size_override("font_size", 15)
    link_label.add_theme_color_override("font_color", Color("ff9d86"))
    link_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hud.add_child(link_label)
    controller.queued.connect(func(_m): _show("searching"))
    controller.found.connect(func(_m): _show("found"))
    controller.finished.connect(func(_m): _show("result"))
    controller.problem.connect(_on_problem)
    controller.state_changed.connect(func(): if screen == "found" and controller.status == "playing": close_panel())
    account.changed.connect(_refresh_modes_keep_notice)
    get_viewport().size_changed.connect(_layout_panel)
    close_panel()
    hud.hide()

func _make_strip() -> Dictionary:
    var bg = PanelContainer.new()
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0, 0, 0, 0)   # R46: a placa (player_plaque.gd) desenha fundo e borda
    style.border_color = Color("5d6b58")
    style.set_border_width_all(1)
    style.set_corner_radius_all(6)
    style.content_margin_left = 8
    style.content_margin_right = 6
    bg.add_theme_stylebox_override("panel", style)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var plaque = Plaque.new()
    bg.add_child(plaque)
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    bg.add_child(row)
    # R41 · retrato público (avatar + moldura Club/Fundador + selo) de quem está naquela cor.
    var portrait = PlayerPortrait.make(hub, {}, 34.0)
    portrait.show_seal = false   # o selo já fica ao lado do nome, maior
    portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(portrait)
    # R31 · Destaque social: selo (Fundador / Club) do jogador, já filtrado pelo servidor.
    var seal = TextureRect.new()
    seal.name = "StripBadge"
    seal.custom_minimum_size = Vector2(26, 26)
    seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
    seal.visible = false
    row.add_child(seal)
    var col = VBoxContainer.new()
    col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    col.add_theme_constant_override("separation", 0)
    row.add_child(col)
    var name = Label.new()
    name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name.clip_text = true
    name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name.add_theme_color_override("font_color", Color("f4edda"))
    name.add_theme_font_override("font", preload("res://account/login_art.gd").FONT_BOLD)
    name.add_theme_color_override("font_outline_color", Color("0b150f"))
    name.add_theme_constant_override("outline_size", 4)
    col.add_child(name)
    var subrow = HBoxContainer.new()
    subrow.add_theme_constant_override("separation", 6)
    col.add_child(subrow)
    var emblem = TextureRect.new()
    emblem.custom_minimum_size = Vector2(24, 24)
    emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    emblem.visible = false
    subrow.add_child(emblem)
    var sub = Label.new()
    sub.add_theme_font_size_override("font_size", 16)
    sub.add_theme_color_override("font_color", GOLD)
    sub.add_theme_color_override("font_outline_color", Color("0b150f"))
    sub.add_theme_constant_override("outline_size", 3)
    sub.clip_text = true
    sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    subrow.add_child(sub)
    var clock = ClockView.new()
    clock.custom_minimum_size.x = 96
    row.add_child(clock)
    var front = Plaque.new()      # camada da frente: indicador de voz por cima do retrato
    front.front = true
    bg.add_child(front)
    hud.add_child(bg)
    var strip := {"front": front, "bg": bg, "name": name, "clock": clock, "style": style, "seal": seal, "seal_id": "", "color": "", "portrait": portrait, "plaque": plaque, "sub": sub, "emblem": emblem}
    # R37 · passar o mouse (ou tocar) na faixa do jogador abre o cartão de perfil com o placar deste modo
    bg.mouse_filter = Control.MOUSE_FILTER_PASS
    bg.mouse_entered.connect(func(): _strip_hover(strip, true))
    bg.mouse_exited.connect(func(): _strip_hover(strip, false))
    bg.gui_input.connect(func(ev):
        if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
            var pp = _popup()
            if pp != null and not String(strip.color).is_empty(): pp.toggle("chess_" + String(strip.color), strip_info(String(strip.color)), bg.get_global_rect()))
    return strip

# ---------- R37 · cartão de perfil ----------
func _popup():
    var st = get_parent()
    return st.get("profile_popup") if st != null else null

func strip_info(color: String) -> Dictionary:
    var info: Dictionary = controller.player(color)
    var me: bool = color == controller.human_color
    var mode: String = String(controller.mode)
    var d := {"user_id": String(info.get("user_id", "")) if not me else (String(account.user_id) if account != null and account.has_profile() else ""),
        "name": "Você" if me else String(info.get("nickname", "Adversário")), "bot": false,
        "mode": mode if rated() else "casual", "mode_label": ("RANQUEADO · " if rated() else "CASUAL · ") + String(controller.mode_name).to_upper(),
        "subtitle": ("BRANCAS" if color == "w" else "PRETAS")}
    if hub != null and hub.has_method("avatar_texture"): d.avatar = hub.avatar_texture() if me else hub.avatar_texture(String(info.get("avatar_id", "")))
    d.merge(PlayerPortrait.self_info(hub) if me else {"badge": info.get("badge", ""), "title": info.get("title", ""), "frame": info.get("frame", "liga")})   # R41
    return d

func _strip_hover(strip: Dictionary, entered: bool):
    var pp = _popup()
    var c := String(strip.color)
    if pp == null or c.is_empty(): return
    if entered: pp.hover("chess_" + c, strip_info(c), (strip.bg as Control).get_global_rect())
    else: pp.unhover("chess_" + c)

# ---------- Painéis ----------
func open_modes():
    _show("modes")

func _build_search_art():
    search_art = Control.new()
    search_art.name = "SearchArt"
    search_art.size = SEARCH_REF
    search_art.mouse_filter = Control.MOUSE_FILTER_STOP
    search_art.visible = false
    add_child(search_art)
    var bg := TextureRect.new()
    bg.name = "SearchBg"
    bg.texture = load("res://ui_kit/pages/buscando_bg.png")
    bg.size = SEARCH_REF
    bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    bg.stretch_mode = TextureRect.STRETCH_SCALE
    bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    search_art.add_child(bg)
    var serif: Font = load("res://ui_kit/fonts/Alegreya-Bold.woff")
    search_mode_label = _art_label(serif, Rect2(380, 672, 688, 64), 44, Color("efe3c4"))
    search_mode_label.name = "SearchMode"
    search_time_label = _art_label(serif, Rect2(644, 742, 160, 62), 46, Color("e6e0cf"))
    search_time_label.name = "SearchTime"
    var cancel := Button.new()
    cancel.name = "SearchCancel"
    cancel.flat = true
    cancel.focus_mode = Control.FOCUS_NONE
    cancel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    cancel.position = Vector2(250, 820)
    cancel.size = Vector2(950, 140)
    var lit := StyleBoxFlat.new()
    lit.bg_color = Color(1.0, 0.86, 0.45, 0.10)
    lit.set_corner_radius_all(10)
    for st in ["normal", "focus", "disabled"]: cancel.add_theme_stylebox_override(st, StyleBoxEmpty.new())
    for st in ["hover", "pressed"]: cancel.add_theme_stylebox_override(st, lit)
    cancel.pressed.connect(func():
        controller.cancel_queue()
        _show("modes"))
    search_art.add_child(cancel)

func _art_label(font: Font, r: Rect2, px: int, color: Color) -> Label:
    var l := Label.new()
    l.position = r.position
    l.size = r.size
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.clip_text = true
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    l.add_theme_font_override("font", font)
    l.add_theme_font_size_override("font_size", px)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
    l.add_theme_constant_override("outline_size", 6)
    search_art.add_child(l)
    return l

## texto do ritmo: diminui a fonte até caber entre as molduras (nada é cortado)
func _set_search_mode(t: String):
    search_mode_label.text = t
    var f: Font = search_mode_label.get_theme_font("font")
    for px in [44, 40, 36, 32, 28]:
        search_mode_label.add_theme_font_size_override("font_size", px)
        if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= search_mode_label.size.x - 16.0: break

## centralizado, cabendo em 92% da tela (celular em pé: limitado pela largura)
func _layout_search_art():
    var vs := get_viewport().get_visible_rect().size
    dim.size = vs
    var k := minf(vs.x * 0.92 / SEARCH_REF.x, vs.y * 0.92 / SEARCH_REF.y)
    search_art.scale = Vector2.ONE * k
    search_art.position = ((vs - SEARCH_REF * k) / 2.0).round()

func close_panel():
    screen = ""
    dim.hide(); panel.hide(); art_frame.hide(); art_panel.hide(); search_art.hide()
    if mobile_art != null: mobile_art.close()
    if promo != null: promo.hide()

func panel_open() -> bool:
    return panel.visible or art_panel.visible or search_art.visible or (promo != null and promo.visible) or (mobile_art != null and mobile_art.visible)

## R49 · VOCÊ SUBIU DE LIGA! (ranked/promotion_modal.gd): os botões fazem o mesmo que no painel de resultado.
func _promotion(r: Dictionary):
    if account.ranked is Dictionary and r.has("stats"): account.ranked[String(r.mode)] = r.stats
    dim.hide(); panel.hide(); art_frame.hide(); art_panel.hide(); search_art.hide()
    if mobile_art != null: mobile_art.close()
    var st = get_parent()
    var can: bool = st != null and st.has_method("analysis_available") and st.analysis_available()
    promo.set_meta("mode", String(r.get("mode", "")))
    promo.open(r, can)

func _clear():
    for parent in [box, footer]:
        for child in parent.get_children():
            parent.remove_child(child)
            child.queue_free()
    footer.hide()

func _label(text: String, size := 16, color := Color("e8e0c8"), center := false) -> Label:
    var l = Label.new()
    l.text = text
    if size >= 22:
        # Títulos no estilo do jogo (Cinzel, dourado com contorno).
        l.add_theme_font_override("font", preload("res://account/login_art.gd").FONT_BOLD)
        size += 8
        l.add_theme_color_override("font_outline_color", Color("2a1905"))
        l.add_theme_constant_override("outline_size", 6)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(l)
    return l

func _button(parent: Node, text: String, action: Callable, primary := false) -> Button:
    # Botão ornamentado do jogo (pontas em V, ouro); hover = o próprio botão mais claro.
    var b = preload("res://account/login_widgets.gd").OrnateButton.new()
    b.text = text
    b.label = text
    b.primary = primary
    b.font_size = 20 if primary else 17
    b.custom_minimum_size.y = 52 if primary else 48
    b.pressed.connect(action)
    parent.add_child(b)
    return b

func _bar(parent: Node, value: float) -> ProgressBar:
    var bar = ProgressBar.new()
    bar.max_value = 100
    bar.value = value
    bar.show_percentage = false
    bar.custom_minimum_size.y = 12
    var fill = StyleBoxFlat.new()
    fill.bg_color = GOLD
    var bg = StyleBoxFlat.new()
    bg.bg_color = Color("223b33")
    bg.border_color = Color("708577")
    bg.set_border_width_all(1)
    bar.add_theme_stylebox_override("fill", fill)
    bar.add_theme_stylebox_override("background", bg)
    parent.add_child(bar)
    return bar

static func league_line(league: int, pl: int) -> String:
    return "%s — %d/100 PL" % [LEAGUES[clampi(league, 0, 10)].to_upper(), pl]

func _show(which: String):
    screen = which
    _clear()
    notice = null
    if promo != null: promo.hide()
    # R49 · subida de liga: a tela da arte de referência no lugar do painel (mesmas ações)
    if which == "result" and rated() and bool(controller.last_result.get("promoted", false)):
        _promotion(controller.last_result)
        return
    match which:
        "modes":
            if rated():
                _label("JOGAR RANQUEADO", 22, GOLD, true)
                _label("Cada ritmo tem liga, PL e estatísticas próprios. Cores sorteadas pelo servidor.", 15, Color("c4cbbd"), true)
                if not account.persistent_backend:
                    _label("Servidor em modo de teste: resultados NÃO ficam salvos.", 14, Color("ff9d86"), true)
            else:
                _label("JOGAR ONLINE", 22, GOLD, true)
                _label("Partida casual contra outro jogador: escolha o ritmo e entre na fila. Não vale PL e não altera o Ranked.", 15, Color("c4cbbd"), true)
                if account.online_ready():
                    var who = account.display_name()
                    _label(("Jogando como %s. Entre na sua conta para usar seu nome." % who) if not account.has_profile() else "Jogando como %s." % who, 14, Color("a9b2a4"), true)
                else:
                    _label("Conectando ao servidor…", 15, GOLD, true)
            var shown := mode_list()
            if shown.is_empty():
                # Admin fechou todos os ritmos: nada de tela vazia nem cartões bloqueados.
                var off = _label(unavailable_title(), 20, GOLD, true)
                off.name = "RankedUnavailable" if rated() else "CasualUnavailable"
                _label("Novas filas serão abertas em breve." if rated() else "As partidas online voltam em breve. Enquanto isso, jogue contra o computador.", 16, Color("efe3c4"), true)
            # Grade sem buracos: linhas de 2 (1 no celular estreito); linha com 1 cartão fica centralizada.
            var per_row := 1 if _narrow() else 2
            var grid = VBoxContainer.new()
            grid.name = "ModeGrid"
            grid.add_theme_constant_override("separation", 10)
            grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            box.add_child(grid)
            for i in range(0, shown.size(), per_row):
                var row = HBoxContainer.new()
                row.add_theme_constant_override("separation", 10)
                row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                grid.add_child(row)
                var chunk := shown.slice(i, i + per_row)
                var lone: bool = per_row == 2 and chunk.size() == 1
                if lone: row.add_child(_spacer(0.5))
                for item in chunk:
                    if rated(): _mode_card(row, item)
                    else: _casual_card(row, item)
                if lone: row.add_child(_spacer(0.5))
            if not rated() and not shown.is_empty():   # Casual fechado: sem convite (o servidor também recusa)
                var inv = _button(box, "CONVIDAR AMIGO PARA UMA PARTIDA", func(): invite_requested.emit(), true)
                inv.name = "InviteFriendButton"
            notice = _label("", 15, Color("ff9d86"), true)
            footer.show()
            _button(footer, "VOLTAR", func():
                close_panel()
                back_requested.emit()).name = "BackButton"
        "searching":
            var m = _mode_info(controller_mode_or_last())
            _label("BUSCANDO ADVERSÁRIO…", 22, GOLD, true)
            if not rated(): _label("CASUAL · SEM PL", 14, Color("a9b2a4"), true)
            _label("%s · %d min" % [m[1], m[2]], 17, Color("efe3c4"), true)
            search_started = Time.get_ticks_msec()
            search_label = _label("0:00", 18, Color("c4cbbd"), true)
            _button(box, "CANCELAR", func():
                controller.cancel_queue()
                _show("modes"), true)
        "found":
            var opp: Dictionary = controller.opponent
            _label("ADVERSÁRIO ENCONTRADO", 22, GOLD, true)
            # R41 · retrato do adversário com moldura e selo (o que ele escolheu e tem direito)
            var ph := CenterContainer.new()
            ph.name = "FoundPortraitHolder"
            var fp = PlayerPortrait.make(hub, opp, 96.0 if get_viewport().get_visible_rect().size.y >= 600.0 else 48.0)
            fp.name = "FoundPortrait"
            ph.add_child(fp)
            box.add_child(ph)
            _label(String(opp.get("nickname", "")), 24, Color("f4edda"), true)
            var ttl := Cosmetics.title_text(Cosmetics.public_title(opp))
            if not ttl.is_empty():
                var tl = _label(ttl, 15, GOLD, true)
                tl.name = "FoundTitle"
            if rated(): _label(league_line(int(opp.get("league", 0)), int(opp.get("pl", 0))), 16, Color("c4cbbd"), true)
            _label("%s%s · Você joga de %s" % ["" if rated() else "Casual · ", controller.mode_name, "BRANCAS" if controller.human_color == "w" else "PRETAS"], 16, Color("efe3c4"), true)
            found_label = _label("", 16, GOLD, true)
        "result":
            _result(controller.last_result)
        "confirm_resign":
            _label("DESISTIR?", 22, GOLD, true)
            _label("A desistência conta como DERROTA contra o computador. O relógio continua correndo enquanto você decide." if src() != controller else "A desistência conta como DERROTA nesta modalidade e o relógio continua correndo enquanto você decide." if rated() else "A desistência encerra a partida como DERROTA (Casual: não altera PL). O relógio continua correndo enquanto você decide.", 16, Color("efe3c4"), true)
            _button(box, "CONTINUAR JOGANDO", close_panel, true)
            _button(box, "DESISTIR", func():
                close_panel()
                src().resign())
    dim.show(); panel.show()
    # Desktop: escolha de ritmo com a arte da referência (a lista acima continua sendo a fonte das ações).
    var was_search := search_art.visible
    search_art.visible = which == "searching"
    if search_art.visible:
        var mi = _mode_info(controller_mode_or_last())
        _set_search_mode("%s · %d min" % [mi[1], mi[2]] if rated() else "CASUAL · %s · %d min" % [mi[1], mi[2]])
        search_time_label.text = "0:00"
        panel.hide()
        art_frame.hide()
        _layout_search_art()
        if not was_search:   # fade de entrada (igual às outras telas)
            search_art.modulate.a = 0.0
            dim.modulate.a = 0.0
            var tw := create_tween().set_parallel(true)
            tw.tween_property(search_art, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
            tw.tween_property(dim, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
    else:
        dim.modulate.a = 1.0
    art_panel.visible = which == "modes" and not Mobile.active(get_viewport())
    # R53 · celular + Ranqueado: a tela de ritmos é o painel da referência do celular (o JOGAR ONLINE casual segue a lista)
    var mob_art: bool = which == "modes" and rated() and Mobile.active(get_viewport())
    if mob_art:
        panel.hide()
        art_frame.hide()
        dim.hide()
        if mobile_art.visible: mobile_art.rebuild()
        else: mobile_art.open()
    elif mobile_art.visible:
        mobile_art.close()
    if art_panel.visible:
        panel.hide()
        art_frame.hide()
        dim.size = get_viewport().get_visible_rect().size
        art_panel.layout(get_viewport().get_visible_rect().size)
    _layout_panel()
    _layout_panel.call_deferred()

func _spacer(ratio: float) -> Control:
    var c := Control.new()
    c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    c.size_flags_stretch_ratio = ratio
    c.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return c

func controller_mode_or_last() -> String:
    return last_mode if not last_mode.is_empty() else all_modes()[1][0]

func _mode_info(id: String) -> Array:
    for item in all_modes():
        if item[0] == id: return item
    return all_modes()[1]

func _mode_card(grid: Container, item: Array):
    var id: String = item[0]
    var stats: Dictionary = account.ranked.get(id, {})
    var card = PanelContainer.new()
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var style = StyleBoxFlat.new()
    style.bg_color = Color("0a1a10")
    style.border_color = Color("c99a45")
    style.set_border_width_all(2)
    style.set_corner_radius_all(6)
    style.shadow_color = Color(0, 0, 0, 0.35)
    style.shadow_size = 4
    for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 10)
    card.add_theme_stylebox_override("panel", style)
    grid.add_child(card)
    var col = VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    card.add_child(col)
    var head = HBoxContainer.new()
    col.add_child(head)
    var badge = TextureRect.new()
    badge.texture = ThemeCatalog.badge_texture(Catalog.IDS[clampi(int(stats.get("league", 0)), 0, 10)])
    badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    badge.custom_minimum_size = Vector2(40, 40)
    head.add_child(badge)
    var titles = VBoxContainer.new()
    titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(titles)
    var t = Label.new()
    t.text = item[1]
    t.add_theme_font_size_override("font_size", 20)
    t.add_theme_font_override("font", preload("res://account/login_art.gd").FONT_BOLD)
    t.add_theme_color_override("font_color", GOLD)
    titles.add_child(t)
    var mins = Label.new()
    mins.text = "%d min por jogador" % item[2]
    mins.add_theme_font_size_override("font_size", 14)
    mins.add_theme_color_override("font_color", Color("c4cbbd"))
    titles.add_child(mins)
    var line = Label.new()
    line.text = league_line(int(stats.get("league", 0)), int(stats.get("pl", 0)))
    line.add_theme_font_size_override("font_size", 15)
    line.add_theme_color_override("font_color", Color("efe3c4"))
    col.add_child(line)
    _bar(col, int(stats.get("pl", 0)))
    var rec = Label.new()
    var total = int(stats.get("matches", 0))
    var rate = (100.0 * int(stats.get("wins", 0)) / total) if total > 0 else 0.0
    rec.text = "%dV · %dD · %dE · %d partidas · %d%%" % [int(stats.get("wins", 0)), int(stats.get("losses", 0)), int(stats.get("draws", 0)), total, roundi(rate)]
    rec.add_theme_font_size_override("font_size", 13)
    rec.add_theme_color_override("font_color", Color("a9b2a4"))
    col.add_child(rec)
    var qb = _button(col, "BUSCAR PARTIDA", func():
        last_mode = id
        controller.queue(id), true)
    qb.name = "Queue_" + id

func _casual_card(grid: Container, item: Array):
    var id: String = item[0]
    var card = PanelContainer.new()
    card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var style = StyleBoxFlat.new()
    style.bg_color = Color("0a1a10")
    style.border_color = Color("c99a45")
    style.set_border_width_all(2)
    style.set_corner_radius_all(6)
    style.shadow_color = Color(0, 0, 0, 0.35)
    style.shadow_size = 4
    for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 10)
    card.add_theme_stylebox_override("panel", style)
    grid.add_child(card)
    var col = VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    card.add_child(col)
    var t = Label.new()
    t.text = item[1]
    t.add_theme_font_size_override("font_size", 20)
    t.add_theme_font_override("font", preload("res://account/login_art.gd").FONT_BOLD)
    t.add_theme_color_override("font_color", GOLD)
    col.add_child(t)
    var mins = Label.new()
    mins.text = "%d min por jogador · sem PL" % item[2]
    mins.add_theme_font_size_override("font_size", 14)
    mins.add_theme_color_override("font_color", Color("c4cbbd"))
    col.add_child(mins)
    var b = _button(col, "ENTRAR NA FILA", func():
        last_mode = id
        controller.queue(id), true)
    b.name = "Queue_" + id
    b.disabled = not account.online_ready()

func _result(r: Dictionary):
    var outcome = String(r.get("outcome", "draw"))
    var title = {"win": "VITÓRIA", "loss": "DERROTA", "draw": "EMPATE"}[outcome]
    var color = {"win": GOLD, "loss": Color("ff9d86"), "draw": Color("dfe6d6")}[outcome]
    _label(title, 30, color, true)
    _label("%s · %s" % [String(r.get("mode_name", "")).to_upper(), String(r.get("reason_text", ""))], 16, Color("efe3c4"), true)
    _analyze_button()
    if not rated():
        _label("Partida casual · sem alteração de PL", 16, Color("c4cbbd"), true)
        _button(box, "JOGAR NOVAMENTE", func():
            close_panel()
            play_requested.emit()
            controller.queue(String(r.mode)), true)
        _button(box, "VOLTAR", func():
            play_requested.emit()
            _show("modes"))
        return
    var change = int(r.get("pl_change", 0))
    _label(("%+d PL" % change) if change != 0 else "0 PL", 26, color, true)
    var after_league = int(r.get("league_after", 0))
    var after_pl = int(r.get("pl_after", 0))
    if bool(r.get("promoted", false)):
        _label("PROMOVIDO!", 24, GOLD, true)
        _label("%s\nPROMOVIDO PARA %s" % [String(r.get("mode_name", "")).to_upper(), LEAGUES[after_league].to_upper()], 18, Color("f4edda"), true)
        _label("de %s para %s" % [LEAGUES[int(r.get("league_before", 0))], LEAGUES[after_league]], 15, Color("c4cbbd"), true)
        var badge_row = CenterContainer.new()
        box.add_child(badge_row)
        var badge = TextureRect.new()
        badge.texture = ThemeCatalog.badge_texture(Catalog.IDS[after_league])
        badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        badge.custom_minimum_size = Vector2(88, 88)
        badge_row.add_child(badge)
    if bool(r.get("demoted", false)):
        # R51 · perdeu com 0 PL: volta para a liga de baixo (com 75 PL)
        _label("REBAIXADO", 24, Color("ff9d86"), true)
        _label("de %s para %s" % [LEAGUES[int(r.get("league_before", 0))], LEAGUES[after_league]], 15, Color("c4cbbd"), true)
    _label(LEAGUES[after_league].to_upper(), 18, Color("f4edda"), true)
    _label("%d / 100 PL" % after_pl, 16, Color("c4cbbd"), true)
    # Barra anima do PL anterior ao atual (reinicia do zero ao promover; no rebaixamento desce do topo).
    var start_value = 0.0 if bool(r.get("promoted", false)) else (100.0 if bool(r.get("demoted", false)) else float(r.get("pl_before", after_pl)))
    result_bar = _bar(box, start_value)
    bar_target = after_pl
    if not bool(r.get("saved", true)):
        _label("Atenção: o servidor não conseguiu salvar este resultado.", 14, Color("ff9d86"), true)
    if account.ranked is Dictionary and r.has("stats"): account.ranked[String(r.mode)] = r.stats
    _button(box, "JOGAR NOVAMENTE", func():
        close_panel()
        play_requested.emit()
        controller.queue(String(r.mode)), true)
    _button(box, "VOLTAR AO RANKED", func():
        play_requested.emit()
        _show("modes"))

## A tela de ritmos se refaz quando o servidor muda a lista (Admin). O aviso já mostrado (ex.: "modo
## temporariamente desativado" para quem foi tirado da fila) continua visível depois de refazer.
func _refresh_modes_keep_notice():
    if screen != "modes": return
    var keep: String = notice.text if is_instance_valid(notice) else ""
    _show("modes")
    if not keep.is_empty() and is_instance_valid(notice): notice.text = keep
    if not keep.is_empty() and mobile_art != null and mobile_art.visible: mobile_art.set_notice(keep)

func _on_problem(text: String):
    if text.is_empty(): return
    if controller.in_match(): link_label.text = text
    elif screen in ["modes", "searching"]:
        if screen == "searching": _show("modes")
        if notice != null: notice.text = text
        if mobile_art != null and mobile_art.visible: mobile_art.set_notice(text)

func _confirm_resign():
    if src().in_match(): _show("confirm_resign")

func _narrow() -> bool:
    return get_viewport().get_visible_rect().size.x < 700.0 or (Mobile.active(get_viewport()) and Mobile.is_portrait(get_viewport()))

func _process(_delta):
    if panel.visible: _layout_panel()
    if search_art.visible: _layout_search_art()
    if art_panel.visible:
        dim.size = get_viewport().get_visible_rect().size
        art_panel.layout(get_viewport().get_visible_rect().size)
    if screen == "searching" and is_instance_valid(search_label):
        var s = (Time.get_ticks_msec() - search_started) / 1000
        search_label.text = "%d:%02d" % [s / 60, s % 60]
        if is_instance_valid(search_time_label): search_time_label.text = search_label.text
        if controller.requeue_pending: search_label.text += "  ·  reconectando…"
        if is_instance_valid(search_mode_label) and search_art.visible:
            var mi = _mode_info(controller_mode_or_last())
            var base: String = "%s · %d min" % [mi[1], mi[2]] if rated() else "CASUAL · %s · %d min" % [mi[1], mi[2]]
            var want: String = "RECONECTANDO…" if controller.requeue_pending else base
            if search_mode_label.text != want: _set_search_mode(want)
    if screen == "found" and is_instance_valid(found_label):
        var left = maxi(0, controller.starts_in_ms - (Time.get_ticks_msec() - controller.state_at))
        found_label.text = "Começa em %d…" % ceili(left / 1000.0) if left > 0 else ""
    if is_instance_valid(result_bar) and result_bar.value != bar_target:
        result_bar.value = move_toward(result_bar.value, bar_target, 40.0 * _delta)
    if hud.visible: _refresh_strips()

## R51 · de onde vêm os dados dos cartões: o controlador do Ranked ou, na partida contra o computador, o bot_view
## (mesmo layout do Ranked Madeira para todos).
func src():
    var st = get_parent()
    if kind == "ranked" and st != null and String(st.get("mode")) == "bot" and st.get("bot_view") != null: return st.bot_view
    return controller

func _refresh_strips():
    var ctl = src()
    var me = ctl.human_color
    var opp = "b" if me == "w" else "w"
    for pair in [["top", opp], ["bottom", me]]:
        var strip = strips[pair[0]]
        strip.color = pair[1]
        var info = ctl.player(pair[1])
        var who = "Você" if pair[1] == me else String(info.get("nickname", "Adversário"))
        if pair[1] != me and not bool(info.get("connected", true)): who += " (reconectando…)"
        var lg := clampi(int(info.get("league", 0)), 0, 10)
        strip.name.text = who
        var ttl := Cosmetics.title_text(Cosmetics.public_title(info if pair[1] != me else PlayerPortrait.self_info(hub)))
        if info.has("sub"):
            strip.sub.text = String(info.sub)
            strip.emblem.texture = ThemeCatalog.badge_texture(Catalog.IDS[lg])
            strip.emblem.visible = strip.emblem.texture != null
            strip.plaque.accent = LEAGUE_ACCENT[lg]
        elif rated():
            strip.sub.text = "%s · %d PL%s" % [LEAGUES[lg].to_upper(), int(info.get("pl", 0)), ("  ·  " + ttl) if ttl != "" and not two_line else ""]
            strip.emblem.texture = ThemeCatalog.badge_texture(Catalog.IDS[lg])
            strip.emblem.visible = strip.emblem.texture != null
            strip.plaque.accent = LEAGUE_ACCENT[lg]
        else:
            strip.sub.text = ttl if ttl != "" else "CASUAL"
            strip.emblem.visible = false
            strip.plaque.accent = Color("f4ce7f")
        # voz (só leitura do FraihaVoice): na sala (fone dourado) / falando (verde + brilho) / silenciado por mim (risco)
        var stg = get_parent()
        var vo = stg.get("voice") if stg != null else null
        var seat := 1 if pair[1] == "w" else 2
        var vs := ""
        if vo != null and vo.active():
            var here: bool = (pair[1] == me) or vo.remote.has(seat)
            if here: vs = "speaking" if vo.is_speaking(seat) else ("deaf" if pair[1] != me and vo.is_participant_muted(seat) else "in")
        strip.plaque.voice_state = vs
        strip.plaque.speaking = vs == "speaking"
        strip.front.voice_state = vs
        strip.front.speaking = vs == "speaking"
        strip.front.accent = strip.plaque.accent
        strip.plaque.portrait_rect = Rect2(strip.portrait.global_position - strip.bg.global_position, strip.portrait.size)
        strip.front.portrait_rect = strip.plaque.portrait_rect
        strip.plaque.queue_redraw()
        strip.front.queue_redraw()
        var mine_side: bool = pair[1] == me
        var look: Dictionary = info if not mine_side else PlayerPortrait.self_info(hub)
        strip.portrait.hub = hub
        strip.portrait.mine = mine_side
        strip.portrait.set_info(look)
        var bot_pt: bool = info.get("portrait_tex") is Texture2D
        if bot_pt: strip.portrait.avatar_rect.texture = info.portrait_tex
        strip.portrait.avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if bot_pt else TextureRect.STRETCH_KEEP_ASPECT_COVERED
        strip.portrait.visible = true   # R46: retrato pequeno também no celular deitado (placa aprovada)
        var bid: String = Cosmetics.public_badge(info) if pair[1] != me else (String(hub.current_badge()) if hub != null and hub.has_method("current_badge") else "")
        if bid != strip.seal_id:
            strip.seal_id = bid
            strip.seal.texture = Cosmetics.badge_texture(bid)
        # celular deitado (faixa estreita): o selo vai para o canto do retrato e o nome ganha o espaço
        strip.seal.visible = strip.seal.texture != null and not two_line
        strip.portrait.seal_rect.texture = strip.seal.texture
        strip.portrait.seal_rect.visible = two_line and strip.seal.texture != null
        var running = ctl.status == "playing" and ctl.clock.active == pair[1]
        strip.clock.show_time(ctl.clock.remaining_ms(pair[1]), running)
        strip.style.border_color = Color(0, 0, 0, 0)
        strip.plaque.active = running
    resign_button.visible = ctl.in_match() and not Mobile.active(get_viewport())
    if ctl.status == "playing" and account.server_ready: link_label.text = ""

# Posiciona as faixas dos jogadores em volta do tabuleiro (retângulo em pixels de tela).
const PLAQUE_H := 98.0
func layout_hud(board: Rect2, mobile: bool, portrait: bool, safe: Rect2, top_slot: Rect2, bottom_slot: Rect2):
    # Desktop usa coordenadas 1920x1080 (escala da janela); mobile usa pixels CSS.
    two_line = mobile and not portrait
    hud_font = 16 if mobile else 26
    for key in strips:
        strips[key].name.add_theme_font_size_override("font_size", (13 if two_line else hud_font - 2) if mobile else hud_font)
        # celular deitado (faixa estreita): nome em fonte compacta, até 2 linhas, sem a 2ª linha de título
        # (o título continua no cartão de perfil) → nicks de até 20 letras aparecem inteiros
        var nm: Label = strips[key].name
        if two_line:
            nm.add_theme_font_override("font", ThemeDB.fallback_font)
            nm.add_theme_font_size_override("font_size", 11)
            nm.clip_text = false
            nm.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
            nm.max_lines_visible = 2
        else:
            nm.add_theme_font_override("font", preload("res://account/login_art.gd").FONT_BOLD)
            nm.clip_text = true
            nm.autowrap_mode = TextServer.AUTOWRAP_OFF
            nm.max_lines_visible = -1
        strips[key].sub.visible = not two_line
        strips[key].clock.set_font_size(hud_font + 4 if mobile else 34)
        strips[key].clock.custom_minimum_size.x = (58 if two_line else 84) if mobile else 150
        if two_line: strips[key].clock.set_font_size(14)
    resign_button.add_theme_font_size_override("font_size", 22)
    if not resign_button.has_meta("styled"):
        resign_button.set_meta("styled", true)
        var st = StyleBoxFlat.new()
        st.bg_color = Color(0.06, 0.11, 0.09, 0.9)
        st.border_color = Color("84754b")
        st.set_border_width_all(1)
        st.set_corner_radius_all(6)
        resign_button.add_theme_stylebox_override("normal", st)
        resign_button.add_theme_color_override("font_color", Color("efe3c4"))
    if mobile:
        for key in strips:
            var side := 30.0 if two_line else 38.0
            strips[key].portrait.custom_minimum_size = Vector2(side, side)
            strips[key].portrait.size = Vector2(side, side)
            strips[key].sub.add_theme_font_size_override("font_size", 11)
            strips[key].emblem.custom_minimum_size = Vector2(16, 16)
        strips.top.bg.position = top_slot.position
        strips.top.bg.size = top_slot.size
        strips.bottom.bg.position = bottom_slot.position
        strips.bottom.bg.size = bottom_slot.size
        link_label.position = Vector2(safe.position.x, bottom_slot.end.y + 4)
        link_label.size = Vector2(safe.size.x, 40)
        return
    var width = 460.0
    var x = board.end.x + 28.0
    if x + width > safe.end.x - 8.0: x = maxf(safe.position.x + 8.0, board.position.x - width - 28.0)
    strips.top.bg.position = Vector2(x, board.position.y)
    strips.top.bg.size = Vector2(width, PLAQUE_H)
    strips.bottom.bg.position = Vector2(x, board.end.y - PLAQUE_H)
    strips.bottom.bg.size = Vector2(width, PLAQUE_H)
    for key in strips:
        strips[key].portrait.custom_minimum_size = Vector2(76, 76)
        strips[key].portrait.size = Vector2(76, 76)
        strips[key].name.add_theme_font_size_override("font_size", 24)
        strips[key].style.content_margin_left = 12
        strips[key].style.content_margin_right = 10
    resign_button.position = Vector2(x, board.end.y - PLAQUE_H - 60 - 126)     # R38.3: acima da faixa de capturas (stage.MATERIAL_H)
    resign_button.size = Vector2(220, 56)
    link_label.position = Vector2(x, board.get_center().y - 30)
    link_label.size = Vector2(width, 60)

func _layout_panel():
    if not panel.visible: return
    var mobile = Mobile.active(get_viewport())
    var area = Mobile.safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    dim.size = get_viewport().get_visible_rect().size
    var ui_scale = 1.0 if mobile else 1.4
    panel.scale = Vector2.ONE * ui_scale
    var max_w = 640.0 if screen == "modes" and not _narrow() else 460.0
    var width = minf(max_w, (area.size.x - 16.0) / ui_scale)
    box.custom_minimum_size.x = width - (44.0 if mobile else 68.0)
    var foot = (footer.get_combined_minimum_size().y + 10.0) if footer.visible else 0.0
    # Celular: moldura mais enxuta (mais espaço para a lista, principalmente deitado).
    var st: StyleBoxEmpty = panel.get_theme_stylebox("panel")
    st.content_margin_top = 40 if mobile else 64
    st.content_margin_bottom = 14 if mobile else 24
    st.content_margin_left = 22 if mobile else 34
    st.content_margin_right = st.content_margin_left
    var pad_v = st.content_margin_top + st.content_margin_bottom
    var pad_h = st.content_margin_left * 2.0
    var wanted = box.get_combined_minimum_size().y + foot + pad_v
    var above = 26.0 if mobile else 56.0   # cavalos e brasão acima da moldura
    var height = minf(wanted, (area.size.y - 16.0) / ui_scale - above)
    scroll.custom_minimum_size = Vector2(width - pad_h, maxf(40.0, height - pad_v - foot))
    panel.custom_minimum_size = Vector2.ZERO
    panel.reset_size()
    panel.size = Vector2(width, height)
    panel.position = area.position + (area.size - panel.size * ui_scale) / 2.0 + Vector2(0, above * ui_scale * 0.5)
    art_frame.compact = mobile
    art_frame.visible = panel.visible
    art_frame.position = panel.position
    art_frame.size = panel.size
    art_frame.scale = panel.scale


## ANALISAR PARTIDA na tela de resultado (só aqui, depois do fim — nunca durante a partida).
func _analyze_button():
    var stage = get_parent()
    if stage == null or not stage.has_method("analysis_available") or not stage.analysis_available(): return
    var access = stage.get("analysis_access")
    var line := ""
    if access != null: line = ("CLUB  " if access.club_unlimited() and not access.status_line().begins_with("CLUB") else "") + access.status_line()
    var b = _button(box, "ANALISAR PARTIDA", func():
        close_panel()
        stage.open_analysis(), true)
    b.name = "AnalyzeMatch"
    if not line.is_empty(): _label(line, 13, GOLD if (access != null and access.club_unlimited()) else Color("c4cbbd"), true)
