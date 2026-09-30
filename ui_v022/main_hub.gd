extends CanvasLayer
## One proportional composition; artwork stays untouched and text remains live.
signal play_local_requested
signal play_online_requested
signal play_bot_requested(difficulty: String, side: String)
signal theme_preview_requested(theme_id: String)
signal piece_set_requested(theme_id: String)
signal quit_requested
signal ranked_requested
signal account_requested
signal friends_requested

const DESIGN = Vector2(1672, 941)
const FRAME_MARGIN = 12.0
# Home oficial (Fase 8.2): mesma composição com painéis, conta, versão e Ranqueado já desenhados na arte.
const FOREST = preload("res://ui_v022/assets/home_forest_v2.png")
const FOREST_V2 = FOREST
# Arte anterior: continua sendo a fonte das molduras das páginas internas (_frame) e dos temas que a usam.
const FOREST_LEGACY = preload("res://ui_v022/assets/home_forest.png")
const BUTTON_ATLAS = preload("res://ui_v022/assets/menu_atlas.png")
const AVATAR = preload("res://ui_v022/assets/profile_avatar.png")
const ROWS = [Rect2(23,53,1116,147), Rect2(23,220,1116,149), Rect2(23,388,1116,153), Rect2(23,560,1116,156), Rect2(23,736,1116,161), Rect2(23,920,1116,165), Rect2(23,1104,1116,161)]
const GOLD = Color("f4ce7f")
const CREAM = Color("f4edda")
const MUTED = Color("c4cbbd")
const PREFS = "user://home_preferences.cfg"
const LeagueCatalog = preload("res://league/catalog.gd")
const LocalProfile = preload("res://league/local_profile.gd")
const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const Ranked = preload("res://ranked/progression.gd")
var ranked = Ranked.new()
var ranked_details: Label
var league_profile = LocalProfile.new()
var selected_league := "madeira"
var league_buttons := {}
var league_status_labels := {}
var ranked_unlock_index := 0 # maior liga alcançada no Ranked (definida pela stage)
const LOCKED_TEXT = "Bloqueada · alcance esta liga no Ranked"
const DEV_PREVIEW_BUTTON := false # "TESTAR UNIVERSO": ferramenta interna, fora da interface do jogador
var league_details: Label
var league_detail_title: Label
var league_detail_badge: TextureRect
var league_scene_preview: TextureRect
var league_preview_pieces: Array[TextureRect] = []
var league_preview_button: TextureButton
var preview_caption: Label
var piece_choice_buttons := {}
var root: Control
var canvas: Control
var presentation_frame: Control
var mobile_ui: Control
var pages_pending := false
var pages := {}
var page_scrolls := {}
var page := "main"
var selected_difficulty := "easy"
var difficulty_label: Label
var menu_buttons: Array[TextureButton] = []
var difficulty_buttons := {}
var side_buttons := {}
var profile_button: TextureButton
var profile_name: Label
var player_name := "Jogador"
var avatar_id := "warrior"
var profile_portrait: TextureRect
var avatar_choices := {}
var about_title: Label
var about_body: Label
var volume := 0.8
var music_volume := 0.65
var fullscreen := true
var volume_label: Label
var music_volume_label: Label
var display_label: Label
var account_caption := "ENTRAR / CRIAR CONTA"
var account_card: TextureButton
var account_card_title: Label
var account_card_subtitle: Label
var account_card_logged := false

func _ready():
    layer = 30
    _load_preferences()
    for bus_name in ["Music","Effects"]:
        if AudioServer.get_bus_index(bus_name) < 0:
            AudioServer.add_bus()
            AudioServer.set_bus_name(AudioServer.bus_count-1,bus_name)
    AudioServer.set_bus_volume_db(0,0)
    AudioServer.set_bus_mute(0,false)
    league_profile.load_profile()
    ranked.load_local()
    _build()
    get_viewport().size_changed.connect(_layout)
    _layout()
    show_page("main")
    # Fullscreen is set by project.godot before the first window is created.

func _slice(texture: Texture2D, region: Rect2) -> AtlasTexture:
    var t = AtlasTexture.new()
    t.atlas = texture
    t.region = region
    t.filter_clip = true
    return t

func _label(parent: Node, value: String, font_size: int, color: Color = CREAM) -> Label:
    var label = Label.new()
    label.text = value
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.9))
    label.add_theme_constant_override("shadow_offset_y", 1)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

func _stack(parent: Node, pos: Vector2, dimensions: Vector2, margins := Vector4(0,0,0,0), separation := 3) -> VBoxContainer:
    var margin = MarginContainer.new()
    margin.position = pos
    margin.size = dimensions
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_theme_constant_override("margin_left", int(margins.x))
    margin.add_theme_constant_override("margin_top", int(margins.y))
    margin.add_theme_constant_override("margin_right", int(margins.z))
    margin.add_theme_constant_override("margin_bottom", int(margins.w))
    parent.add_child(margin)
    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", separation)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_child(box)
    return box

func _frame(parent: Node, pos: Vector2, dimensions: Vector2) -> NinePatchRect:
    var frame = NinePatchRect.new()
    frame.texture = _slice(FOREST_LEGACY, Rect2(596, 318, 482, 550))
    frame.patch_margin_left = 26
    frame.patch_margin_right = 26
    frame.patch_margin_top = 26
    frame.patch_margin_bottom = 26
    frame.position = pos
    frame.size = dimensions
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(frame)
    return frame

func _button(parent: Node, row: int, title: String, subtitle: String, pos: Vector2, callback: Callable, dimensions := Vector2(450,66)) -> TextureButton:
    var button = TextureButton.new()
    button.texture_normal = _slice(BUTTON_ATLAS, ROWS[row])
    button.texture_hover = button.texture_normal
    button.texture_pressed = button.texture_normal
    button.texture_disabled = button.texture_normal
    button.ignore_texture_size = true
    button.stretch_mode = TextureButton.STRETCH_SCALE
    button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    button.position = pos
    button.size = dimensions
    button.custom_minimum_size = Vector2(0, dimensions.y)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.focus_mode = Control.FOCUS_ALL
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    button.tooltip_text = title
    button.name = "MenuButton" + str(row)
    parent.add_child(button)
    var margin = MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", int(dimensions.x * 0.232))
    margin.add_theme_constant_override("margin_right", int(dimensions.x * 0.094))
    margin.add_theme_constant_override("margin_top", 3 if dimensions.y < 60 else 7)
    margin.add_theme_constant_override("margin_bottom", 3 if dimensions.y < 60 else 7)
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.add_child(margin)
    var labels = VBoxContainer.new()
    labels.add_theme_constant_override("separation", 1)
    labels.alignment = BoxContainer.ALIGNMENT_CENTER
    labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_child(labels)
    _label(labels, title, 18)
    _label(labels, subtitle, 14, MUTED)
    button.pressed.connect(callback)
    button.pressed.connect(func():
        var audio = get_parent().get_node_or_null("GameAudio")
        if audio != null: audio.play_cue("ui")
    )
    button.mouse_entered.connect(func(): _highlight(button, true))
    button.mouse_exited.connect(func(): _highlight(button, button.has_focus()))
    button.focus_entered.connect(func(): _highlight(button, true))
    button.focus_exited.connect(func(): _highlight(button, false))
    button.button_down.connect(func(): button.self_modulate = Color(0.78,0.85,0.74))
    button.button_up.connect(func(): _highlight(button, true))
    return button

func _highlight(button: TextureButton, active: bool):
    if button.disabled:
        button.self_modulate = Color(0.55,0.59,0.55)
    else:
        button.self_modulate = Color(1.22,1.24,1.12) if active else Color.WHITE

func _build():
    root = Control.new()
    root.name = "HomeRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    presentation_frame = Control.new()
    presentation_frame.name = "PresentationFrame"
    presentation_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    presentation_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    presentation_frame.draw.connect(_draw_presentation_frame)
    root.add_child(presentation_frame)
    canvas = Control.new()
    canvas.name = "ReferenceComposition"
    canvas.size = DESIGN
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(canvas)
    var art = TextureRect.new()
    art.name = "ForestArtwork"
    art.texture = FOREST_V2
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_SCALE
    art.size = DESIGN
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(art)
    var main = Control.new()
    main.name = "MainMenu"
    main.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(main)
    pages["main"] = main
    var theme_frame = _frame(main,Vector2(596,318),Vector2(482,550))
    theme_frame.name = "ThemeMenuFrame"
    theme_frame.hide()
    # JOGAR LOCAL saiu da Home pública; o modo continua disponível internamente (play_local_requested).
    var titles = ["JOGAR CONTRA O BOT", "JOGAR ONLINE", "JOGAR RANQUEADO", "LIGAS E RANKING", "AMIGOS", "CONFIGURAÇÕES", "CONHEÇA O FRAIHA", "SAIR"]
    var subtitles = ["Treine e evolua seu jogo", "Partida casual · fila automática", "Compita, evolua e conquiste seu lugar", "Acompanhe seu progresso", "Amigos, mensagens e convites", "Áudio, vídeo e preferências", "Sobre o projeto", "Até a próxima partida!"]
    var actions = [func(): show_page("bot"), func(): play_online_requested.emit(), func(): ranked_requested.emit(), func(): show_page("ranking"), func(): friends_requested.emit(), func(): show_page("settings"), func(): show_page("about"), func(): quit_requested.emit()]
    var icons = [1,2,3,3,0,4,5,6]
    for i in range(8):
        var item = _button(main, icons[i], titles[i], subtitles[i], Vector2(611,341+i*63), actions[i], Vector2(450,57))
        item.name = "MainAction" + str(i)
        menu_buttons.append(item)
        if titles[i] == "JOGAR RANQUEADO": _feature_ranked(item)
    _build_profile()
    pages_pending = preload("res://ui_v022/mobile_layout.gd").active(get_viewport())
    if not pages_pending: _build_pages()
    # Versão só no rodapé direito, em moldura discreta (o cabeçalho do topo foi removido).
    _ornate_panel(canvas, Vector2(1400,864), Vector2(250,62)).name = "VersionPanel"
    var signature = _label(_stack(canvas, Vector2(1414,872), Vector2(222,46)), "Versão 0.30 · Ligas\nMaringá · PR · Brasil", 14, MUTED)
    signature.name = "VersionLabel"
    signature.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _build_account_card()
    _build_reference_chrome()
    _sync_chrome()
    if preload("res://ui_v022/mobile_layout.gd").active(get_viewport()):
        mobile_ui = preload("res://ui_v022/mobile_hub.gd").new()
        root.add_child(mobile_ui)
        mobile_ui.setup(self)

func _build_profile():
    # Moldura própria, desenhada exatamente dentro da borda dourada (sem recorte da arte da floresta).
    _ornate_panel(canvas, Vector2(1254,24), Vector2(396,178)).name = "ProfilePanel"
    var profile = _stack(canvas, Vector2(1254,24), Vector2(396,178), Vector4(20,16,20,12), 6)
    profile.get_parent().name = "ProfileStack"
    profile_button = TextureButton.new()
    profile_button.name = "ProfileButton"
    profile_button.custom_minimum_size = Vector2(0,100)
    profile_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    profile_button.focus_mode = Control.FOCUS_ALL
    profile.add_child(profile_button)
    var portrait = TextureRect.new()
    profile_portrait = portrait
    portrait.name = "ProfilePortrait"
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    portrait.texture = avatar_texture()
    portrait.position = Vector2(8,8)
    portrait.size = Vector2(80,80)
    portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    profile_button.add_child(portrait)
    attach_league_frame(portrait)
    var words = _stack(profile_button, Vector2(106,4), Vector2(250,92), Vector4.ZERO, 3)
    profile_name = _label(words, player_name, 21)
    profile_name.name = "ProfileName"
    profile_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _single_line(profile_name)
    var current = LeagueCatalog.entry(league_profile.data.current_league,league_profile.data)
    _label(words, "%s · %d / 100 PL" % [current.display_name,league_profile.data.lp], 14, GOLD).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _progress(words,league_profile.data.lp,8)
    var caption = _label(words, "Ligas conquistadas no Ranked", 11, MUTED)
    caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _single_line(caption)
    profile_button.pressed.connect(func(): show_page("profile"))
    profile_button.mouse_entered.connect(func(): profile_name.modulate = GOLD)
    profile_button.mouse_exited.connect(func(): profile_name.modulate = Color.WHITE)
    var rule = ColorRect.new()
    rule.color = Color(0.85,0.7,0.37,0.35)
    rule.custom_minimum_size = Vector2(0,1)
    rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
    profile.add_child(rule)
    var quote = _label(profile, "“O xadrez é a ginástica da inteligência.” — Blaise Pascal", 12, MUTED)
    quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    desk_profile = {"button": profile_button, "name": profile_name, "portrait": portrait, "stack": profile.get_parent()}

## Moldura ornamental FRAIHA (verde escuro + dourado): borda dupla, cantos e losangos, tudo dentro do retângulo.
func _ornate_panel(parent: Node, pos: Vector2, dimensions: Vector2, fill := Color(0.043,0.094,0.067,0.95)) -> Control:
    var panel = Control.new()
    panel.position = pos
    panel.size = dimensions
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.draw.connect(func():
        var r = Rect2(Vector2(4,4), panel.size - Vector2(8,8))
        panel.draw_rect(r, fill)
        panel.draw_rect(r, Color("d9b45e"), false, 2.0)
        panel.draw_rect(r.grow(-5), Color(0.62,0.48,0.22,0.9), false, 1.0)
        var dia = func(c: Vector2, s: float): panel.draw_colored_polygon(PackedVector2Array([c+Vector2(0,-s),c+Vector2(s,0),c+Vector2(0,s),c+Vector2(-s,0)]), Color("f0cf7a"))
        for c in [r.position, Vector2(r.end.x,r.position.y), r.end, Vector2(r.position.x,r.end.y)]: dia.call(c, 4.0)
        dia.call(Vector2(r.get_center().x, r.position.y), 5.0)
        dia.call(Vector2(r.get_center().x, r.end.y), 5.0)
    )
    parent.add_child(panel)
    return panel

## Cartão da conta (canto inferior esquerdo): convidado ou conta, sempre abre Entrar/Conta.
func _build_account_card():
    _ornate_panel(canvas, Vector2(22,856), Vector2(334,70)).name = "AccountPanel"
    account_card = TextureButton.new()
    account_card.name = "AccountCard"
    account_card.ignore_texture_size = true
    account_card.position = Vector2(26,860)
    account_card.size = Vector2(326,62)
    account_card.focus_mode = Control.FOCUS_ALL
    account_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    account_card.tooltip_text = "Entrar / criar conta"
    canvas.add_child(account_card)
    var icon = Control.new()
    icon.name = "AccountIcon"
    icon.position = Vector2(14,9)
    icon.size = Vector2(44,44)
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon.draw.connect(func():
        var c = icon.size / 2.0
        icon.draw_circle(c, 21.0, Color("14261c"))
        if account_card_logged and avatar_texture() != null:
            icon.draw_texture_rect(avatar_texture(), Rect2(Vector2(3,3), icon.size - Vector2(6,6)), false)
        else:
            icon.draw_circle(c + Vector2(0,-6), 7.0, GOLD)
            icon.draw_colored_polygon(PackedVector2Array([c+Vector2(-12,14),c+Vector2(-9,5),c+Vector2(-4,2),c+Vector2(4,2),c+Vector2(9,5),c+Vector2(12,14)]), GOLD)
        icon.draw_arc(c, 21.0, 0, TAU, 40, Color("d9b45e"), 2.0)
    )
    account_card.add_child(icon)
    var words = _stack(account_card, Vector2(70,8), Vector2(214,48), Vector4.ZERO, 0)
    account_card_title = _label(words, "CONVIDADO", 18, GOLD)
    account_card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _single_line(account_card_title)
    account_card_subtitle = _label(words, "ENTRAR / CRIAR CONTA", 13, MUTED)
    account_card_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _single_line(account_card_subtitle)
    var chevron = Control.new()
    chevron.position = Vector2(292,19)
    chevron.size = Vector2(20,24)
    chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
    chevron.draw.connect(func(): chevron.draw_polyline(PackedVector2Array([Vector2(5,3),Vector2(15,12),Vector2(5,21)]), GOLD, 3.0))
    account_card.add_child(chevron)
    account_card.pressed.connect(func(): account_requested.emit())
    account_card.mouse_entered.connect(func(): account_card.modulate = Color(1.18,1.18,1.08))
    account_card.mouse_exited.connect(func(): account_card.modulate = Color.WHITE)

## Chamado pela stage quando a conta muda.
func set_account_card(title: String, subtitle: String, logged_in: bool):
    account_card_logged = logged_in
    if not is_instance_valid(account_card): return
    account_card_title.text = title
    account_card_title.add_theme_color_override("font_color", CREAM if logged_in else GOLD)
    account_card_subtitle.text = subtitle
    account_card.tooltip_text = "Minha conta" if logged_in else "Entrar / criar conta"
    account_card.get_node("AccountIcon").queue_redraw()
    _refresh_ref_account()

## JOGAR RANQUEADO: moldura dourada com brilho, leve tom quente e ramos de louro nas laterais.
## Mais forte que os demais botões, mas no mesmo sistema visual (verde + dourado).
func _feature_ranked(button: TextureButton):
    # Brilho: fica ATRÁS do botão (só aparece em volta); a moldura dourada fica por cima.
    var glow = Panel.new()
    glow.name = "RankedGlow"
    glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var under = StyleBoxFlat.new()
    under.bg_color = Color("0c1a12")
    under.set_corner_radius_all(6)
    under.shadow_color = Color(1.0,0.76,0.28,0.55)
    under.shadow_size = 16
    under.set_expand_margin_all(2)
    glow.add_theme_stylebox_override("panel", under)
    glow.position = button.position
    glow.size = button.size
    button.get_parent().add_child(glow)
    button.get_parent().move_child(glow, button.get_index())
    ranked_extras.append(glow)
    var rim = Panel.new()
    rim.name = "RankedRim"
    rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var st = StyleBoxFlat.new()
    st.bg_color = Color(1.0,0.82,0.4,0.05)
    st.border_color = Color("f6d27c")
    st.set_border_width_all(3)
    st.set_corner_radius_all(6)
    st.set_expand_margin_all(3)
    rim.add_theme_stylebox_override("panel", st)
    rim.position = button.position
    rim.size = button.size
    button.get_parent().add_child(rim)
    button.get_parent().move_child(rim, button.get_index() + 1)
    ranked_extras.append(rim)
    var ornaments = Control.new()
    ornaments.name = "RankedOrnaments"
    ornaments.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ornaments.position = button.position - Vector2(26,0)
    ornaments.size = button.size + Vector2(52,0)
    ornaments.draw.connect(func():
        var h = ornaments.size.y / 2.0
        var gold = Color("f6d27c")
        var deep = Color("b8903f")
        for side in [[Vector2(14,h), 1.0], [Vector2(ornaments.size.x-14,h), -1.0]]:
            var c: Vector2 = side[0]
            var d: float = side[1]
            # ramo de louro: caule curvo + folhas, apontando para o botão
            for k in range(3):
                var y = 9.0 + k * 7.0
                for sgn in [-1.0, 1.0]:
                    var base = c + Vector2(d * (k * 4.0 - 2.0), sgn * y)
                    var tip = base + Vector2(d * 11.0, sgn * 6.0)
                    var leaf = gold if k % 2 == 0 else deep
                    ornaments.draw_colored_polygon(PackedVector2Array([base, tip, base + Vector2(d * 6.0, sgn * -2.5)]), leaf)
                    ornaments.draw_colored_polygon(PackedVector2Array([base, base + Vector2(d * 4.0, sgn * 5.0), tip]), leaf)
            ornaments.draw_colored_polygon(PackedVector2Array([c+Vector2(0,-8),c+Vector2(7,0),c+Vector2(0,8),c+Vector2(-7,0)]), gold)
            ornaments.draw_colored_polygon(PackedVector2Array([c+Vector2(0,-4),c+Vector2(3.5,0),c+Vector2(0,4),c+Vector2(-3.5,0)]), Color("7a5a22"))
    )
    button.get_parent().add_child(ornaments)
    ranked_extras.append(ornaments)
    var labels = button.find_children("*","Label",true,false)
    if labels.size() >= 2:
        labels[0].add_theme_color_override("font_color", Color("ffd98a"))
        labels[0].add_theme_font_size_override("font_size", 20)
        labels[0].add_theme_constant_override("outline_size", 3)
        labels[0].add_theme_color_override("font_outline_color", Color("2a1c06"))
        labels[1].add_theme_color_override("font_color", Color("efe2b8"))

## Texto de uma linha só: quebra ligada (regra do layout), 1 linha visível e reticências se não couber.
func _single_line(label: Label):
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.max_lines_visible = 1
    label.clip_text = true
    label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    # clip_text zera a altura mínima: dentro de containers a linha precisa de altura explícita
    label.custom_minimum_size.y = ceilf(label.get_theme_font_size("font_size") * 1.6)

func _new_page(id: String, title: String, eyebrow: String) -> VBoxContainer:
    var panel = Control.new()
    panel.name = id.capitalize() + "Page"
    panel.position = Vector2(611,341)
    panel.size = Vector2(450,505)
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    canvas.add_child(panel)
    var scroll = ScrollContainer.new()
    scroll.name = "PageScroll"
    scroll.position = Vector2(24,16)
    scroll.size = Vector2(402,411)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.follow_focus = true
    panel.add_child(scroll)
    var margin = MarginContainer.new()
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.add_theme_constant_override("margin_right", 8)
    margin.add_theme_constant_override("margin_bottom", 10)
    scroll.add_child(margin)
    var content = VBoxContainer.new()
    content.name = "PageContent"
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 13)
    margin.add_child(content)
    _label(content, eyebrow, 13, GOLD)
    _label(content, title, 25)
    _button(panel, 6, "VOLTAR AOS NÍVEIS" if id == "bot_side" else "VOLTAR À HOME", "ESC também volta", Vector2(0,439), back)
    pages[id] = panel
    page_scrolls[id] = scroll
    return content

func _body(parent: Node, value: String, font_size := 18) -> Label:
    var label = _label(parent, value, font_size, MUTED)
    label.add_theme_constant_override("line_spacing", 4)
    return label

func _page_button(parent: Node, row: int, title: String, subtitle: String, callback: Callable) -> TextureButton:
    return _button(parent, row, title, subtitle, Vector2.ZERO, callback, Vector2(394,68))

func _build_pages():
    var bot = _new_page("bot", "ESCOLHA A DIFICULDADE", "JOGAR CONTRA O BOT")
    difficulty_buttons.easy = _page_button(bot, 1, "FÁCIL", "Para começar e praticar", func(): _choose_difficulty("easy"))
    difficulty_buttons.medium = _page_button(bot, 1, "MÉDIO", "Planeje suas próximas jogadas", func(): _choose_difficulty("medium"))
    difficulty_buttons.hard = _page_button(bot, 1, "DIFÍCIL", "Um desafio mais profundo", func(): _choose_difficulty("hard"))
    difficulty_buttons.expert = _page_button(bot, 1, "EXPERT", "Seu desafio mais exigente", func(): _choose_difficulty("expert"))
    var sides = _new_page("bot_side", "ESCOLHA SEU LADO", "JOGAR CONTRA O BOT")
    difficulty_label = _label(sides, "Nível: Fácil", 18, GOLD)
    side_buttons.w = _page_button(sides, 0, "BRANCAS", "Você faz a primeira jogada", func(): play_bot_requested.emit(selected_difficulty, "w"))
    side_buttons.b = _page_button(sides, 0, "PRETAS", "O bot começa a partida", func(): play_bot_requested.emit(selected_difficulty, "b"))
    side_buttons.random = _page_button(sides, 2, "ALEATÓRIO", "Deixe a escolha para o sorteio", func(): play_bot_requested.emit(selected_difficulty, "random"))
    _build_ranked()
    _build_ranking()
    _build_about_page()
    var profile_panel = _wide_page("profile","PERFIL DO JOGADOR")
    var portraits = GridContainer.new()
    portraits.columns = 2
    portraits.position = Vector2(85,95)
    portraits.add_theme_constant_override("h_separation",50)
    portraits.add_theme_constant_override("v_separation",20)
    profile_panel.add_child(portraits)
    for id in ["warrior","archer","mage","paladin"]:
        var option = VBoxContainer.new()
        portraits.add_child(option)
        var portrait_button = TextureButton.new()
        portrait_button.custom_minimum_size = Vector2(155,155)
        portrait_button.ignore_texture_size = true
        portrait_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
        portrait_button.texture_normal = avatar_texture(id)
        portrait_button.pressed.connect(func(): choose_avatar(id))
        option.add_child(portrait_button)
        attach_league_frame(portrait_button)
        var caption = _label(option,{"warrior":"GUERREIRO","archer":"ARQUEIRA","mage":"MAGO","paladin":"PALADINO"}[id],18,GOLD)
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        avatar_choices[id] = portrait_button
    var hint = _label(profile_panel,"Escolha seu avatar. A moldura representa a liga do perfil.",17)
    hint.position = Vector2(45,500)
    hint.size = Vector2(610,45)
    var profile = _stack(profile_panel,Vector2(745,115),Vector2(640,480),Vector4.ZERO,10)
    _label(profile,"COMO VOCÊ QUER SER CONHECIDO?",20,GOLD)
    var name_input = LineEdit.new()
    name_input.name = "PlayerName"
    name_input.custom_minimum_size.y = 46
    name_input.max_length = 20
    name_input.text = player_name
    name_input.placeholder_text = "Seu nome"
    name_input.add_theme_font_size_override("font_size",20)
    profile.add_child(name_input)
    name_input.text_changed.connect(func(value):
        player_name = value.strip_edges()
        if player_name.is_empty(): player_name = "Jogador"
        profile_name.text = player_name
        _save_preferences()
    )
    for mode in Ranked.MODES:
        _body(profile,ranked.summary(mode),16)
    _refresh_avatars()
    var settings = _new_page("settings", "DO SEU JEITO", "CONFIGURAÇÕES")
    music_volume_label = _label(settings, "", 19, GOLD)
    var music_slider = HSlider.new()
    music_slider.name = "MusicVolume"
    music_slider.custom_minimum_size.y = 35
    music_slider.max_value = 100
    music_slider.step = 1
    music_slider.value = round(music_volume*100)
    settings.add_child(music_slider)
    music_slider.value_changed.connect(_set_music_volume)
    _set_music_volume(music_slider.value,false)
    volume_label = _label(settings, "", 19, GOLD)
    var slider = HSlider.new()
    slider.name = "EffectsVolume"
    slider.custom_minimum_size.y = 35
    slider.min_value = 0
    slider.max_value = 100
    slider.step = 1
    slider.value = round(volume*100)
    settings.add_child(slider)
    slider.value_changed.connect(_set_volume)
    _set_volume(slider.value, false)
    _page_button(settings, 1, "TELA CHEIA", "Alternar janela / tela cheia", _toggle_fullscreen)
    display_label = _label(settings, "", 17, MUTED)
    _body(settings, "As preferências são salvas automaticamente.\nAlt + Enter também alterna a tela.", 16)
    _refresh_display_label()

func _choose_difficulty(id: String):
    if id not in ["easy", "medium", "hard", "expert"]: return
    selected_difficulty = id
    difficulty_label.text = "Nível: " + {"easy":"Fácil","medium":"Médio","hard":"Difícil","expert":"Expert"}[id]
    show_page("bot_side")

func _wide_page(id: String, title: String) -> Control:
    var panel = Control.new()
    panel.position = Vector2(110,260)
    panel.size = Vector2(1452,640)
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    canvas.add_child(panel)
    _frame(panel,Vector2.ZERO,panel.size)
    var heading = _label(panel,title,29,GOLD)
    heading.position = Vector2(40,28)
    heading.size = Vector2(1370,55)
    _button(panel,6,"VOLTAR À HOME","ESC também volta",Vector2(40,546),back,Vector2(410,64))
    pages[id] = panel
    return panel

func avatar_texture(id: String = "") -> Texture2D:
    if id.is_empty(): id = avatar_id
    if id == "paladin": return ThemeCatalog.texture("res://profile/paladin.png")
    if id == "warrior": return AVATAR
    var atlas = ThemeCatalog.texture("res://cosmetics/v025/avatars.png")
    if atlas == null: return AVATAR
    var half = atlas.get_width()/2.0
    return _slice(atlas,Rect2(0 if id == "archer" else half,0,half,atlas.get_height()))

func choose_avatar(id: String):
    if id not in ["warrior","archer","mage","paladin"]: return
    avatar_id = id
    _refresh_avatars()
    _save_preferences()

func _refresh_avatars():
    if is_instance_valid(profile_portrait): profile_portrait.texture = avatar_texture()
    if is_instance_valid(profile_portrait): attach_league_frame(profile_portrait)
    if ref_mode and not ref_profile.is_empty(): _use_profile(true)
    _refresh_ref_account()
    for id in avatar_choices:
        attach_league_frame(avatar_choices[id])
        avatar_choices[id].self_modulate = Color.WHITE if id == avatar_id else Color(0.60,0.65,0.63)
    if get_parent().has_method("refresh_player_card"): get_parent().refresh_player_card()

func _build_about_page():
    var panel = _wide_page("about","CONHEÇA O FRAIHA  ·  MUITO MAIS QUE UM XADREZ")
    var topics = [["O PROJETO","Um tabuleiro, muitas histórias.\n\nFRAIHA Xadrez combina o jogo clássico com um mundo medieval em pixel art. Planeje suas jogadas, pratique e compartilhe partidas.\n\nFeito por jogadores, para jogadores. Maringá · Paraná · Brasil."],["COMO JOGAR","Clique em uma peça e depois em uma casa marcada, ou arraste a peça.\n\nESC abre a confirmação para abandonar. Alt+Enter alterna tela cheia. Ao jogar de pretas, suas peças ficam na parte inferior do tabuleiro."],["SISTEMA DE LIGAS","Madeira, Ferro, Bronze, Prata, Ouro, Platina, Esmeralda, Diamante, Mestre, Grande Mestre e Challenger.\n\nO Ranked tem quatro ritmos (3, 5, 10 e 20 minutos), cada um com PL e liga próprios. A cada 100 PL você sobe de liga. A maior liga alcançada em qualquer ritmo libera o cenário e as peças daquela liga."],["MODOS DE JOGO","Bot: quatro dificuldades, escolha entre brancas, pretas ou aleatório.\nOnline: escolha o ritmo (3, 5, 10 ou 20 min) e entre na fila; o adversário é encontrado automaticamente. Não vale PL.\nRanqueado: entre na sua conta e dispute PL em quatro ritmos."],["PERSONALIZAÇÃO","Escolha Guerreiro, Arqueira ou Mago no Perfil.\n\nNa página Ligas, veja o universo de cada liga. Madeira já está disponível; as demais são liberadas conforme você alcança a liga no Ranked. As peças clássicas também continuam disponíveis."],["COMUNIDADE E SUPORTE","Esta é uma build de teste. Compartilhe suas observações sobre interface, peças e partidas com o responsável pelo projeto.\n\nAinda não há comunidade ou suporte conectados pelo jogo.\n\nEstratégia para ir mais longe."]]
    var navigation = _stack(panel,Vector2(38,108),Vector2(390,418),Vector4.ZERO,4)
    var details = _stack(panel,Vector2(482,117),Vector2(870,392),Vector4.ZERO,22)
    about_title = _label(details,"",27,GOLD)
    about_body = _body(details,"",23)
    for i in range(topics.size()):
        var topic: Array = topics[i]
        _button(navigation,i,topic[0],"",Vector2.ZERO,func():
            about_title.text = topic[0]
            about_body.text = topic[1]
        ,Vector2(380,65))
    about_title.text = topics[0][0]
    about_body.text = topics[0][1]

func _progress(parent: Node, value: int, height: int = 14):
    var bar = ProgressBar.new()
    bar.max_value = 100
    bar.value = value
    bar.show_percentage = false
    bar.custom_minimum_size.y = height
    var fill = StyleBoxFlat.new()
    fill.bg_color = GOLD
    var background = StyleBoxFlat.new()
    background.bg_color = Color("223b33")
    background.border_color = Color("708577")
    background.set_border_width_all(1)
    bar.add_theme_stylebox_override("fill",fill)
    bar.add_theme_stylebox_override("background",background)
    parent.add_child(bar)

func _badge(parent: Node, league_id: String, dimensions: Vector2) -> TextureRect:
    var icon = TextureRect.new()
    icon.texture = ThemeCatalog.badge_texture(league_id)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.custom_minimum_size = dimensions
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(icon)
    return icon

func _build_ranking():
    var panel = Control.new()
    panel.name = "RankingPage"
    panel.position = Vector2(110,260)
    panel.size = Vector2(1452,640)
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    canvas.add_child(panel)
    _frame(panel,Vector2.ZERO,panel.size)
    pages.ranking = panel
    var header = _stack(panel,Vector2(35,24),Vector2(1380,76),Vector4.ZERO,5)
    var current = LeagueCatalog.entry(league_profile.data.current_league,league_profile.data)
    _label(header,"SISTEMA DE LIGAS  ·  %s — %s  ·  %d / 100 PL" % [player_name,current.display_name,league_profile.data.lp],26,GOLD)
    _progress(header,league_profile.data.lp,12)
    _label(header,"Sua jornada começa na Madeira. Cada liga possui sua própria faixa de 0 a 100 PL.",16)
    var journey = HBoxContainer.new()
    journey.position = Vector2(36,119)
    journey.size = Vector2(1380,151)
    journey.add_theme_constant_override("separation",10)
    panel.add_child(journey)
    for entry in LeagueCatalog.entries(league_profile.data):
        var id: String = entry.league_id
        var button = Button.new()
        button.name = "League_"+id
        button.custom_minimum_size = Vector2(115,160)
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.tooltip_text = entry.display_name + " · 0–100 PL"
        var base = StyleBoxFlat.new()
        base.bg_color = Color("10251f")
        base.border_color = Color("786b40")
        base.set_border_width_all(1)
        var focus = base.duplicate()
        focus.border_color = GOLD
        focus.set_border_width_all(2)
        button.add_theme_stylebox_override("normal",base)
        for state in ["hover","pressed","focus"]: button.add_theme_stylebox_override(state,focus)
        journey.add_child(button)
        var content = _stack(button,Vector2(5,5),Vector2(105,140),Vector4.ZERO,2)
        _badge(content,id,Vector2(103,96))
        var title = _label(content,entry.display_name.to_upper(),13,GOLD)
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var status = _label(content,"DISPONÍVEL" if league_unlocked(id) else "BLOQUEADA",10,MUTED)
        status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        league_status_labels[id] = status
        button.pressed.connect(func(): _select_league(id))
        league_buttons[id] = button
    var details = _stack(panel,Vector2(190,293),Vector2(635,229),Vector4.ZERO,12)
    league_detail_title = _label(details,"",25,GOLD)
    league_details = _body(details,"",18)
    league_detail_badge = _badge(panel,"madeira",Vector2(140,170))
    league_detail_badge.position = Vector2(37,296)
    league_detail_badge.size = Vector2(140,170)
    var preview = _stack(panel,Vector2(870,292),Vector2(540,204),Vector4.ZERO,12)
    preview_caption = _label(preview,"PRÉVIA DAS PEÇAS",18,GOLD)
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation",8)
    preview.add_child(row)
    league_scene_preview = TextureRect.new()
    league_scene_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    league_scene_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    league_scene_preview.custom_minimum_size = Vector2(226,132)
    row.add_child(league_scene_preview)
    var pieces_grid = GridContainer.new()
    pieces_grid.columns = 3
    pieces_grid.add_theme_constant_override("h_separation",12)
    row.add_child(pieces_grid)
    for i in range(6):
        var piece = TextureRect.new()
        piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        piece.custom_minimum_size = Vector2(76,64)
        pieces_grid.add_child(piece)
        league_preview_pieces.append(piece)
    league_preview_button = _button(panel,2,"TESTAR UNIVERSO","Prévia de desenvolvimento · sem alterar PL",Vector2(872,488),_preview_league,Vector2(530,67))
    league_preview_button.visible = DEV_PREVIEW_BUTTON
    _button(panel,6,"VOLTAR À HOME","ESC também volta",Vector2(35,548),back,Vector2(410,64))
    _button(panel,0,"PEÇAS CLÁSSICAS","Usar o conjunto original",Vector2(483,548),func(): piece_set_requested.emit("classic"),Vector2(390,64))
    var note = _label(panel,"Ligas conquistadas no Ranked. Cada ritmo tem PL próprio; a maior liga alcançada libera cenário e peças.",14,MUTED)
    note.position = Vector2(895,568)
    note.size = Vector2(510,44)

func league_unlocked(id: String) -> bool:
    return LeagueCatalog.index_of(id) <= ranked_unlock_index

func set_ranked_unlock(index: int):
    ranked_unlock_index = index
    for key in league_status_labels:
        if is_instance_valid(league_status_labels[key]):
            league_status_labels[key].text = "DISPONÍVEL" if league_unlocked(key) else "BLOQUEADA"

func _select_league(id: String):
    selected_league = id
    var unlocked = league_unlocked(id)
    if unlocked: theme_preview_requested.emit(LeagueCatalog.theme_for(id))
    var entry = LeagueCatalog.entry(id,league_profile.data)
    league_detail_title.text = "LIGA " + entry.display_name.to_upper() + "  ·  0–100 PL"
    league_detail_badge.texture = ThemeCatalog.badge_texture(id)
    var theme: String = entry.environment_theme
    var available = ThemeCatalog.THEME_DATA.has(theme)
    var description = "Floresta, equilíbrio e o começo da sua jornada.\nRecompensas: cenário natural, tabuleiro e peças de madeira." if id == "madeira" else "Fortaleza, montanhas e forjas.\nRecompensas: arena de pedra, tabuleiro de aço e peças de ferro."
    if id == "bronze": description = "Conquista, prestígio e novos horizontes.\nRecompensas: cidadela ao pôr do sol, tabuleiro e peças de bronze."
    elif id == "prata": description = "Elegância, conhecimento e novos desafios.\nRecompensas: palácio de mármore, tabuleiro e peças de prata."
    elif id == "ouro": description = "Maestria, poder e grandes vitórias.\nRecompensas: reino dourado, tabuleiro real e peças de ouro."
    if available and ThemeCatalog.get_theme(theme).has("description"): description = ThemeCatalog.get_theme(theme).description + "\nRecompensas: cenário, tabuleiro e conjunto de peças próprios."
    if not available: description = "Recompensas visuais em desenvolvimento.\nSeu emblema já faz parte da jornada."
    league_details.text = ("Disponível" if unlocked else LOCKED_TEXT)+"\n"+description+"\n\nConquiste esta liga no Ranked: cada ritmo tem PL próprio e a promoção acontece a cada 100 PL."
    var textures = ThemeCatalog.piece_textures(theme) if available else {}
    league_scene_preview.texture = ThemeCatalog.texture(ThemeCatalog.get_theme(theme).arena_path) if available else null
    for i in range(league_preview_pieces.size()):
        league_preview_pieces[i].texture = textures.get("w"+ThemeCatalog.PIECE_ORDER[i])
    preview_caption.text = "CENÁRIO E PEÇAS · "+entry.display_name.to_upper() if available else "VISUAIS EM DESENVOLVIMENTO"
    league_preview_button.visible = DEV_PREVIEW_BUTTON and available and unlocked
    for key in league_buttons:
        league_buttons[key].modulate = Color.WHITE if key == id else Color(0.78,0.82,0.79)

func _preview_league():
    if not ThemeCatalog.THEME_DATA.has(LeagueCatalog.theme_for(selected_league)): return
    if not league_unlocked(selected_league): return
    theme_preview_requested.emit(LeagueCatalog.theme_for(selected_league))
    open_home()

func _layout():
    if is_instance_valid(mobile_ui):
        canvas.hide()
        presentation_frame.hide()
        mobile_ui.layout()
        return
    var dimensions = get_viewport().get_visible_rect().size
    # Fit the intact composition and its frame together, using all available space.
    var framed_size = DESIGN + Vector2.ONE * FRAME_MARGIN * 2.0
    var factor = minf(dimensions.x / framed_size.x, dimensions.y / framed_size.y)
    canvas.scale = Vector2.ONE * factor
    canvas.position = (dimensions - DESIGN*factor) / 2.0
    presentation_frame.queue_redraw()

func _draw_presentation_frame():
    # All ornament stays outside the composition; no duplicated scenery or input layer.
    var artwork = Rect2(canvas.position, DESIGN * canvas.scale)
    var unit = canvas.scale.x
    presentation_frame.draw_rect(Rect2(Vector2.ZERO, presentation_frame.size), Color("08090b"))
    # A faint brushed finish stays neutral for every league; it contains no artwork.
    for row in range(0, ceili(presentation_frame.size.y), 4):
        presentation_frame.draw_line(Vector2(0, row), Vector2(presentation_frame.size.x, row), Color(1,1,1,0.008))
    presentation_frame.draw_rect(artwork.grow(11 * unit), Color("131416"))
    presentation_frame.draw_rect(artwork.grow(10 * unit), Color("383a3d"), false, unit)
    presentation_frame.draw_rect(artwork.grow(9 * unit), Color("81858a"), false, unit)
    presentation_frame.draw_rect(artwork.grow(8 * unit), Color("222427"), false, unit)
    # Recessed inner lip, softly shaded toward the artwork without covering any pixels.
    for step in range(1, 7):
        presentation_frame.draw_rect(artwork.grow(step * unit), Color(0, 0, 0, (7-step) * 0.1), false, unit)
    for corner in [Vector2.ZERO, Vector2(1,0), Vector2(0,1), Vector2.ONE]:
        var direction = Vector2.ONE - corner * 2
        var point = artwork.position + artwork.size * corner - direction * 9 * unit
        var horizontal = Vector2(direction.x, 0)
        var vertical = Vector2(0, direction.y)
        var metal = Color("a0a3a7")
        presentation_frame.draw_polyline(PackedVector2Array([
            point + horizontal * 30 * unit, point + horizontal * 7 * unit,
            point + vertical * 7 * unit, point + vertical * 30 * unit
        ]), metal, unit, true)
        var gem = 2 * unit
        presentation_frame.draw_colored_polygon(PackedVector2Array([
            point + Vector2(0,-gem), point + Vector2(gem,0),
            point + Vector2(0,gem), point + Vector2(-gem,0)
        ]), metal)

func show_page(id: String):
    if pages_pending and id != "main":
        pages_pending = false
        _build_pages()
    if not pages.has(id): return
    page = id
    for key in pages:
        pages[key].visible = key == id
    _sync_menu_cover()
    if page_scrolls.has(id): page_scrolls[id].scroll_vertical = 0
    if is_instance_valid(display_label): _refresh_display_label()
    if id == "ranking": _select_league(selected_league)
    if id == "profile": _refresh_avatars()
    if is_instance_valid(mobile_ui): mobile_ui.show_page(id)

func apply_theme(texture: Texture2D, theme_id: String = "wood"):
    if texture == FOREST_LEGACY: texture = FOREST   # temas que usavam a Home da floresta passam a usar a arte oficial
    if texture != null:
        canvas.get_node("ForestArtwork").texture = texture
        _sync_chrome()
        var logo = canvas.get_node_or_null("ThemeLogo")
        var needs_logo = ThemeCatalog.get_theme(theme_id).get("free_arena",false)
        if logo == null and needs_logo:
            logo = TextureRect.new()
            logo.name = "ThemeLogo"
            logo.texture = load("res://ui_v022/assets/theme_logo.png")
            logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            logo.position = Vector2(450,0)
            logo.size = Vector2(790,318)
            logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
            canvas.add_child(logo)
            canvas.move_child(logo,1)
        if logo != null: logo.visible = needs_logo
        pages.main.get_node("ThemeMenuFrame").visible = needs_logo
        selected_league = ThemeCatalog.get_theme(theme_id).get("unlock_league","madeira")
        if selected_league == "wood": selected_league = "madeira"

func back():
    show_page("bot" if page == "bot_side" else "main")

func open_home():
    root.show()
    show_page("main")

func hide_hub():
    root.hide()

func is_home_visible() -> bool:
    return root.visible

func _set_volume(value: float, save := true):
    volume = value / 100.0
    var bus = AudioServer.get_bus_index("Effects")
    AudioServer.set_bus_volume_db(bus,linear_to_db(maxf(volume,0.0001)))
    AudioServer.set_bus_mute(bus, volume <= 0.0)
    volume_label.text = "EFEITOS SONOROS  ·  %d%%" % round(value)
    if save: _save_preferences()

func _set_music_volume(value: float, save := true):
    music_volume = value/100.0
    var bus = AudioServer.get_bus_index("Music")
    AudioServer.set_bus_volume_db(bus,linear_to_db(maxf(music_volume,0.0001)))
    AudioServer.set_bus_mute(bus,music_volume <= 0.0)
    music_volume_label.text = "MÚSICA  ·  %d%%" % round(value)
    if save: _save_preferences()

func _toggle_fullscreen():
    get_parent().toggle_fullscreen()
    fullscreen = get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
    _save_preferences()
    _refresh_display_label()

func _refresh_display_label():
    display_label.text = "Modo atual: " + ("tela cheia" if get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] else "janela")

func _load_preferences():
    var config = ConfigFile.new()
    if config.load(PREFS) != OK: return
    player_name = String(config.get_value("profile","name","Jogador")).left(20)
    avatar_id = String(config.get_value("profile","avatar","warrior"))
    if avatar_id not in ["warrior","archer","mage","paladin"]: avatar_id = "warrior"
    volume = clampf(float(config.get_value("audio","volume",0.8)),0,1)
    music_volume = clampf(float(config.get_value("audio","music_volume",0.65)),0,1)
    fullscreen = true

func _save_preferences():
    var config = ConfigFile.new()
    config.set_value("profile","name",player_name)
    config.set_value("profile","avatar",avatar_id)
    config.set_value("audio","volume",volume)
    config.set_value("audio","music_volume",music_volume)
    config.set_value("video","fullscreen",fullscreen)
    config.save(PREFS)

func _build_ranked():
    var content = _new_page("ranked", "ESCOLHA SEU RITMO", "JOGAR RANQUEADO")
    _body(content,"Cada ritmo possui liga, PL e estatísticas próprios. Entre na sua conta para jogar partidas ranqueadas online.",16)
    for mode in Ranked.MODES:
        var id: String = mode
        _page_button(content,3,Ranked.MODES[id].name.to_upper(),"%d minutos por jogador" % Ranked.MODES[id].minutes,func(): ranked_details.text = ranked.summary(id))
    ranked_details = _body(content,ranked.summary("blitz"),17)
    _body(content,"Vitórias e derrotas valem PL conforme o nível do adversário. Promoção a cada 100 PL, com excedente. Sem rebaixamento; o PL não fica abaixo de 0. Empates: 0 PL. Bot e Online Casual não alteram estas classificações.",15)
    var play = _page_button(content,2,"BUSCAR PARTIDA","Use JOGAR RANQUEADO na Home",func(): pass)
    play.disabled = true
    _highlight(play,false)
func attach_league_frame(portrait: Control):
    if portrait.has_meta("no_league_frame"): return   # retrato da Home oficial: a moldura já está na arte
    var border = portrait.get_node_or_null("LeagueFrame")
    if border == null:
        border = preload("res://profile/league_frame.gd").new()
        border.name = "LeagueFrame"
        portrait.add_child(border)
    border.league_id = league_profile.data.current_league
    border.queue_redraw()

# ---------- Home "referência" (arte oficial com moldura, perfil, conta, versão e Ranqueado desenhados) ----------
# Na arte FOREST_V2 os painéis e botões já estão desenhados; aqui só entra o conteúdo vivo
# (retrato, nickname, liga/PL, barra, insígnia, texto da conta) e as áreas de clique.
const REF_MENU_RECT = Rect2(614,336,446,516)
var ref_nodes: Array = []
var ref_mode := false
var desk_profile := {}
var ref_profile := {}
var ref_account_avatar: TextureRect
var ref_badge: TextureRect
var ref_badge_plate: Panel
var ref_menu_cover: Panel
var ref_hovers := {}
var ranked_extras: Array = []

func _is_ref_art(texture: Texture2D) -> bool:
    return texture == FOREST_V2

func _build_reference_chrome():
    # Perfil
    var pbtn = TextureButton.new()
    pbtn.name = "RefProfileButton"
    pbtn.ignore_texture_size = true
    pbtn.position = Vector2(1240,40)
    pbtn.size = Vector2(390,130)
    pbtn.focus_mode = Control.FOCUS_ALL
    pbtn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    pbtn.tooltip_text = "Perfil"
    canvas.add_child(pbtn)
    ref_nodes.append(pbtn)
    var clip = Control.new()
    clip.name = "RefPortraitClip"
    clip.clip_contents = true
    clip.position = Vector2(1253,62) - pbtn.position
    clip.size = Vector2(93,100)
    clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(clip)
    var portrait = TextureRect.new()
    portrait.name = "RefPortrait"
    portrait.set_meta("no_league_frame", true)
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.size = clip.size
    portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip.add_child(portrait)
    var name_label = _label(pbtn, player_name, 22)
    name_label.name = "RefProfileName"
    _single_line(name_label)
    name_label.position = Vector2(1394,56) - pbtn.position
    name_label.size = Vector2(158,32)
    var current = LeagueCatalog.entry(league_profile.data.current_league,league_profile.data)
    var league = _label(pbtn, "%s · %d / 100 PL" % [current.display_name,league_profile.data.lp], 16, GOLD)
    _single_line(league)
    league.position = Vector2(1362,88) - pbtn.position
    league.size = Vector2(190,24)
    var fill = ColorRect.new()
    fill.color = GOLD
    fill.position = Vector2(1371,118) - pbtn.position
    fill.size = Vector2(170.0 * clampf(league_profile.data.lp / 100.0, 0.0, 1.0), 6)
    fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(fill)
    # Insígnia da liga: a arte já traz a da Madeira; outras ligas cobrem com a insígnia viva.
    ref_badge_plate = Panel.new()
    var plate = StyleBoxFlat.new()
    plate.bg_color = Color(0.0,0.13,0.07)
    plate.set_corner_radius_all(6)
    ref_badge_plate.add_theme_stylebox_override("panel", plate)
    ref_badge_plate.position = Vector2(1552,54) - pbtn.position
    ref_badge_plate.size = Vector2(58,98)
    ref_badge_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(ref_badge_plate)
    ref_badge = TextureRect.new()
    ref_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    ref_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    ref_badge.position = Vector2(1552,62) - pbtn.position
    ref_badge.size = Vector2(58,80)
    ref_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(ref_badge)
    pbtn.pressed.connect(func(): show_page("profile"))
    pbtn.mouse_entered.connect(func(): name_label.modulate = GOLD)
    pbtn.mouse_exited.connect(func(): name_label.modulate = Color.WHITE)
    ref_profile = {"button": pbtn, "name": name_label, "portrait": portrait}
    # Conta: avatar redondo sobre o medalhão quando logado (o ícone de convidado já está na arte)
    ref_account_avatar = TextureRect.new()
    ref_account_avatar.name = "RefAccountAvatar"
    ref_account_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    ref_account_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    ref_account_avatar.position = Vector2(49,851)
    ref_account_avatar.size = Vector2(62,62)
    ref_account_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mask = ShaderMaterial.new()
    mask.shader = Shader.new()
    mask.shader.code = "shader_type canvas_item;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float d = distance(UV, vec2(0.5)); COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(0.47, 0.5, d))); }"
    ref_account_avatar.material = mask
    canvas.add_child(ref_account_avatar)
    ref_nodes.append(ref_account_avatar)
    # Páginas internas: cobre os botões desenhados na arte (a moldura dourada continua visível).
    ref_menu_cover = Panel.new()
    ref_menu_cover.name = "RefMenuCover"
    var cover = StyleBoxFlat.new()
    cover.bg_color = Color(0.03,0.12,0.075)
    cover.set_corner_radius_all(4)
    ref_menu_cover.add_theme_stylebox_override("panel", cover)
    ref_menu_cover.position = REF_MENU_RECT.position
    ref_menu_cover.size = REF_MENU_RECT.size
    ref_menu_cover.clip_contents = false
    ref_menu_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(ref_menu_cover)
    canvas.move_child(ref_menu_cover, canvas.get_node("MainMenu").get_index())
    ref_nodes.append(ref_menu_cover)
    # Os louros do Ranqueado ficam sobre a borda da moldura: nas páginas internas, a borda é
    # recomposta com as mesmas colunas da própria arte, logo abaixo (sem emenda).
    for x in [596.0, 1060.0]:
        var patch = TextureRect.new()
        patch.name = "RefLaurelPatch"
        patch.texture = _slice(FOREST_V2, Rect2(x, 560, 18, 82))
        patch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        patch.stretch_mode = TextureRect.STRETCH_SCALE
        patch.position = Vector2(x, 454)
        patch.size = Vector2(18, 82)
        patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
        ref_menu_cover.add_child(patch)
        patch.top_level = false
        patch.position = Vector2(x, 454) - ref_menu_cover.position
    # Botões do menu: realce dourado ao passar o mouse / foco (o botão desenhado na arte fica visível).
    for button in menu_buttons:
        var hover = Panel.new()
        hover.name = "RefHover"
        var st = StyleBoxFlat.new()
        st.bg_color = Color(1.0,0.86,0.5,0.10)
        st.border_color = Color("ffe08f")
        st.set_border_width_all(2)
        st.set_corner_radius_all(5)
        hover.add_theme_stylebox_override("panel", st)
        var ranked = button.tooltip_text == "JOGAR RANQUEADO"
        hover.position = Vector2(6, -8 if ranked else 0)
        hover.size = button.size + Vector2(-12, 16 if ranked else -1)
        hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hover.hide()
        button.add_child(hover)
        ref_hovers[button] = hover
        button.mouse_entered.connect(func(): if ref_mode: hover.show())
        button.mouse_exited.connect(func(): if ref_mode and not button.has_focus(): hover.hide())
        button.focus_entered.connect(func(): if ref_mode: hover.show())
        button.focus_exited.connect(func(): hover.hide())

func _sync_chrome():
    var ref = _is_ref_art(canvas.get_node("ForestArtwork").texture)
    ref_mode = ref
    for n in ref_nodes: n.visible = ref
    for name in ["ProfilePanel","AccountPanel","VersionPanel"]:
        var n = canvas.get_node_or_null(name)
        if n != null: n.visible = not ref
    var ver = canvas.find_child("VersionLabel", true, false)
    if ver != null: ver.get_parent().get_parent().visible = not ref
    if not desk_profile.is_empty(): desk_profile.stack.visible = not ref
    for n in ranked_extras: n.visible = not ref
    # Botões: na arte de referência o botão já está desenhado; o nosso vira área de clique transparente.
    for button in menu_buttons:
        if not button.has_meta("atlas_texture"): button.set_meta("atlas_texture", button.texture_normal)
        var tex = null if ref else button.get_meta("atlas_texture")
        button.texture_normal = tex
        button.texture_hover = tex
        button.texture_pressed = tex
        button.texture_disabled = tex
        if button.get_child_count() > 0 and button.get_child(0) is MarginContainer: button.get_child(0).visible = not ref
        if ref_hovers.has(button) and not ref: ref_hovers[button].hide()
    # Cartão da conta: arte traz moldura, medalhão e seta; ficam só os textos vivos.
    if is_instance_valid(account_card):
        account_card.position = Vector2(38,846) if ref else Vector2(26,860)
        account_card.size = Vector2(322,72) if ref else Vector2(326,62)
        account_card.get_node("AccountIcon").visible = not ref
        var words = account_card_title.get_parent().get_parent()
        words.position = Vector2(98,11) if ref else Vector2(70,8)
        words.size = Vector2(172,50) if ref else Vector2(214,48)
        account_card_title.add_theme_font_size_override("font_size", 20 if ref else 18)
        account_card_subtitle.add_theme_font_size_override("font_size", 14 if ref else 13)
        account_card_subtitle.add_theme_color_override("font_color", Color("e8e2d0") if ref else MUTED)
        for c in account_card.get_children():
            if c is Control and c.name != "AccountIcon" and c != words and not c is MarginContainer: c.visible = not ref
    _refresh_ref_account()
    _use_profile(ref)
    _sync_menu_cover()

func _use_profile(ref: bool):
    if desk_profile.is_empty() or ref_profile.is_empty(): return
    var text = profile_name.text if is_instance_valid(profile_name) else player_name
    var src = ref_profile if ref else desk_profile
    profile_button = src.button
    profile_name = src.name
    profile_portrait = src.portrait
    profile_name.text = text
    profile_portrait.texture = avatar_texture()
    if ref:
        # retratos quadrados preenchem a moldura; o medalhão redondo (Guerreiro) fica centralizado
        profile_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if avatar_id == "warrior" else TextureRect.STRETCH_KEEP_ASPECT_COVERED
        var league_id = String(league_profile.data.current_league)
        var madeira = league_id in ["madeira", "wood"]
        ref_badge.texture = null if madeira else ThemeCatalog.badge_texture(league_id)
        ref_badge.visible = not madeira
        ref_badge_plate.visible = not madeira
    else:
        attach_league_frame(profile_portrait)

func _refresh_ref_account():
    if not is_instance_valid(ref_account_avatar): return
    ref_account_avatar.visible = ref_mode and account_card_logged
    ref_account_avatar.texture = avatar_texture()

func _sync_menu_cover():
    if is_instance_valid(ref_menu_cover): ref_menu_cover.visible = ref_mode and page != "main"
