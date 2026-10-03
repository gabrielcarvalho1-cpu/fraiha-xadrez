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
signal premove_changed(enabled: bool)
signal cosmetics_changed   # R31: ícone/título/moldura/avatar mudaram (a conta sincroniza com o servidor)

const DESIGN = Vector2(1672, 941)
const FRAME_MARGIN = 0.0
const EDGE_CROP = 1.035
const APP_VERSION = "0.35"
# Home oficial (Fase 8.2): mesma composição com painéis, conta, versão e Ranqueado já desenhados na arte.
const FOREST = preload("res://ui_v022/assets/home_forest_v6.png")   # R35: arte oficial intacta (logo original) + miolo do menu em 11 linhas (tools/home_menu_v6.py)
## R32 · linhas do menu na arte v3 (y, altura da moldura) — saída de tools/home_menu_10rows.py
const MENU_ROWS := [Vector2(338.4, 38.7), Vector2(382.2, 39.4), Vector2(426.0, 51.8), Vector2(482.2, 40.8), Vector2(527.8, 40.7), Vector2(573.8, 40.7), Vector2(620.2, 40.8), Vector2(666.9, 41.1), Vector2(713.9, 41.1), Vector2(759.7, 39.8), Vector2(805.9, 41.0)]
const MENU_SCALE := 0.74   # R35: escala das linhas (o conteúdo encolhe por igual a partir de x=628)
const MENU_TEXT_X := 691.0  # onde começam os textos das linhas na arte v6
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
var premove_enabled := true
var premove_button: TextureButton
var premium = null   # FRAIHA PREMIUM (Monetização V1, simulação)
var monetization_state = null   # flags dev_mock_* (simulação)
var entitlements = null         # direitos (servidor + simulação) — única leitura para a interface
var avatar_gallery = null       # profile/avatar_gallery.gd (página Perfil, PC)
var avatar_detail := {}         # área de detalhe do avatar em foco
var gallery_count: Label
var inspected_avatar := ""
var inspected_badge := "auto"   # R32: ícone em foco na aba ÍCONES do Perfil
var profile_tab := "avatars"    # "avatars" | "icons"
var badge_gallery = null        # profile/badge_gallery.gd
var profile_tabs := {}
var gallery_scrolls := {}
const AvatarCatalog = preload("res://profile/avatar_catalog.gd")
var bot_progress = null         # bot/bot_progress.gd — escada de bots e avatares desbloqueados
var bot_ladder_ui = null        # bot/bot_ladder_ui.gd (página larga do PC)
const BotLadder = preload("res://bot/bot_ladder.gd")
var club_entry = null           # fita CLUB FRAIHA na Home (desktop)
var account = null              # account_service (ligado pelo stage em bind_account)
var avatar_store                # profile/avatar_store.gd (cache local + download)
var image_picker = null         # escolha de arquivo (desktop/web)
var avatar_editor = null        # editor de enquadramento
var nickname_editor = null      # editor do nome público (página Perfil, desktop)
var avatar_note: Label = null   # mensagens do avatar (página Perfil, desktop)
var local_name_box: Control = null
const FOUNDER_BADGE = preload("res://monetization/art/founder_badge.png")
const FOUNDER_BADGE_SMALL = preload("res://monetization/art/founder_badge_small.png")
var founder_row: HBoxContainer
var ref_founder_badge: TextureRect
const Cosmetics = preload("res://profile/premium_cosmetics.gd")
## R31 · Identidade premium: preferências ("auto" = melhor item que o jogador possui).
var badge_pref := "auto"
var title_pref := "auto"
var frame_pref := ""
var lab_coords := false         # LABORATÓRIO (acesso antecipado): coordenadas no tabuleiro
var founder_seal: TextureRect
var desk_badge: TextureRect
var founder_title_label: Label
var founder_sub_label: Label
var sound_muted := false        # botão SOM da Home: silencia o bus Master (mesmo sistema de áudio)
var music_muted := false        # R34: MUTAR MÚSICA (botões dentro do XEQUE e da MARCHA REAL)
var effects_muted := false      # R34: MUTAR EFEITOS
var sound_button: Button
var volume_label: Label
var music_volume_label: Label
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
    AudioServer.set_bus_mute(0, sound_muted)   # botão SOM da Home (preferência "audio/muted")
    league_profile.load_profile()
    ranked.load_local()
    avatar_store = load("res://profile/avatar_store.gd").new()
    avatar_store.name = "AvatarStore"
    add_child(avatar_store)
    avatar_store.texture_ready.connect(func(_k): _refresh_avatars())
    monetization_state = load("res://monetization/monetization_state.gd").new()
    entitlements = load("res://monetization/entitlements.gd").new(monetization_state)
    entitlements.changed.connect(refresh_club)
    bot_progress = load("res://bot/bot_progress.gd").new()
    bot_progress.name = "BotProgress"
    add_child(bot_progress)
    bot_progress.setup(null)
    bot_progress.changed.connect(func(): _refresh_avatars())
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
    # Título guardado como dado (usado pelo menu mobile/testes); sem tooltip: o próprio botão
    # já mostra o nome, e o balão repetia o mesmo texto embaixo dele.
    button.set_meta("title", title)
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
    presentation_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
    # Detalhes vivos da arte oficial (gato dormindo, viajantes na ponte, easter eggs): camada
    # transparente por cima — a arte original fica intacta. Só aparece com a arte oficial.
    var details = TextureRect.new()
    details.name = "ForestDetails"
    details.texture = preload("res://ui_v022/assets/home_forest_v6_details.png")
    details.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    details.stretch_mode = TextureRect.STRETCH_SCALE
    details.size = DESIGN
    details.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(details)
    # A placa do cartão da conta era desenhada DENTRO da arte (e a camada de detalhes trazia uma cópia antiga
    # dela, um pouco acima — o "fantasma" atrás de MINHA CONTA). Agora a arte de fundo não tem placa nenhuma
    # (folhagem no lugar) e a placa é um recorte exato da arte original, desenhado só na Home.
    var art_scale := Vector2(1672.0 / DESIGN.x, 941.0 / DESIGN.y)
    var plaque := TextureRect.new()
    plaque.name = "RefAccountPlaque"
    plaque.texture = preload("res://ui_v022/assets/home_account_plaque.png")
    plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    plaque.stretch_mode = TextureRect.STRETCH_SCALE
    plaque.position = Vector2(28, 832) / art_scale
    plaque.size = Vector2(plaque.texture.get_size()) / art_scale
    plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(plaque)
    # Espírito das águas sobre o lago (abaixo da cachoeira, à esquerda da placa), animado.
    var spirit = preload("res://ui_v022/water_spirit.gd").new()
    spirit.position = Vector2(1258, 642)
    spirit.size = Vector2(112, 112)
    canvas.add_child(spirit)
    var main = Control.new()
    main.name = "MainMenu"
    main.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(main)
    pages["main"] = main
    var theme_frame = _frame(main,Vector2(596,318),Vector2(482,550))
    theme_frame.name = "ThemeMenuFrame"
    theme_frame.hide()
    # JOGAR LOCAL saiu da Home pública; o modo continua disponível internamente (play_local_requested).
    # R32: + MARCHA REAL (novo modo) e + HISTÓRICO DE PARTIDAS (abaixo de CONHEÇA O FRAIHA)
    # R33: + XEQUE (novo modo de blefe de cartas), logo abaixo da MARCHA REAL
    var titles = ["JOGAR CONTRA O COMPUTADOR", "JOGAR ONLINE", "JOGAR RANQUEADO", "LIGAS E RANKING", "MARCHA REAL", "XEQUE", "AMIGOS", "CONFIGURAÇÕES", "CONHEÇA O FRAIHA", "HISTÓRICO DE PARTIDAS", "SAIR"]
    var subtitles = ["Treine e evolua seu jogo", "Partida casual · fila automática", "Compita, evolua e conquiste seu lugar", "Acompanhe seu progresso", "Novo modo · cartas e corrida", "Novo modo · blefe de cartas", "Amigos, mensagens e convites", "Áudio, vídeo e preferências", "Sobre o projeto", "Suas partidas e análises", "Até a próxima partida!"]
    var actions = [func(): show_page("bot"), func(): play_online_requested.emit(), func(): ranked_requested.emit(), func(): show_page("ranking"), open_marcha, open_xeque, func(): friends_requested.emit(), func(): show_page("settings"), func(): show_page("about"), func(): show_page("history"), func(): quit_requested.emit()]
    var icons = [1,2,3,3,5,5,0,4,5,5,6]
    for i in range(titles.size()):
        var row: Vector2 = MENU_ROWS[i]
        var item = _button(main, icons[i], titles[i], subtitles[i], Vector2(611, row.x), actions[i], Vector2(450, row.y))
        item.name = "MainAction" + str(i)
        menu_buttons.append(item)
        if titles[i] == "JOGAR RANQUEADO": _feature_ranked(item)
    _build_profile()
    pages_pending = preload("res://ui_v022/mobile_layout.gd").active(get_viewport())
    if not pages_pending: _build_pages()
    # Sem placa de versão na Home (R29): a versão fica no log e no rodapé das Configurações.
    print("FRAIHA Xadrez versão %s" % APP_VERSION)
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
    # R31: ícone escolhido ao lado do nome também no cartão sem a arte de referência.
    desk_badge = TextureRect.new()
    desk_badge.name = "DeskBadge"
    desk_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    desk_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    desk_badge.size = Vector2(30, 30)
    desk_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    desk_badge.visible = false
    profile_button.add_child(desk_badge)

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

## Nome do botão do menu (antes vinha do tooltip, que foi removido por ser redundante).
static func title_of(button: Control) -> String:
    return String(button.get_meta("title", button.tooltip_text))

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
    if not eyebrow.is_empty(): _label(content, eyebrow, 13, GOLD)
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
    _build_bot_ladder_page()
    var sides = _new_page("bot_side", "ESCOLHA SEU LADO", "JOGAR CONTRA O COMPUTADOR")
    difficulty_label = _label(sides, "Adversário: BOT MADEIRA", 18, GOLD)
    side_buttons.w = _page_button(sides, 0, "BRANCAS", "Você faz a primeira jogada", func(): play_bot_requested.emit(selected_difficulty, "w"))
    side_buttons.b = _page_button(sides, 0, "PRETAS", "O bot começa a partida", func(): play_bot_requested.emit(selected_difficulty, "b"))
    side_buttons.random = _page_button(sides, 2, "ALEATÓRIO", "Deixe a escolha para o sorteio", func(): play_bot_requested.emit(selected_difficulty, "random"))
    _build_ranked()
    _build_ranking()
    _build_about_page()
    _build_history_page()
    var profile_panel = _wide_page("profile","PERFIL DO JOGADOR")
    # GALERIA DE PROGRESSÃO (esquerda): todos os avatares; bloqueados em cinza com o requisito.
    gallery_count = _label(profile_panel, "", 15, GOLD)
    gallery_count.name = "GalleryCount"
    gallery_count.position = Vector2(372,76)
    gallery_count.size = Vector2(380,24)
    gallery_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var gscroll = ScrollContainer.new()
    gscroll.name = "AvatarGalleryScroll"
    gscroll.position = Vector2(36,108)
    gscroll.size = Vector2(716,356)
    gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    profile_panel.add_child(gscroll)
    avatar_gallery = load("res://profile/avatar_gallery.gd").new()
    avatar_gallery.name = "AvatarGallery"
    gscroll.add_child(avatar_gallery)
    avatar_gallery.setup(self, 5, Vector2(132,170))
    avatar_gallery.inspected.connect(_inspect_avatar)
    # R32: ÍCONES separados dos avatares — aba própria, mesma área, botão APLICAR ÍCONE no detalhe.
    var bscroll = ScrollContainer.new()
    bscroll.name = "BadgeGalleryScroll"
    bscroll.position = gscroll.position
    bscroll.size = gscroll.size
    bscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    bscroll.visible = false
    profile_panel.add_child(bscroll)
    badge_gallery = load("res://profile/badge_gallery.gd").new()
    badge_gallery.name = "BadgeGallery"
    bscroll.add_child(badge_gallery)
    badge_gallery.setup(self, 5, Vector2(132,170))
    badge_gallery.inspected.connect(_inspect_badge)
    gallery_scrolls = {"avatars": gscroll, "icons": bscroll}
    var tabs = HBoxContainer.new()
    tabs.name = "ProfileTabs"
    tabs.position = Vector2(44,70)
    tabs.size = Vector2(340,34)
    tabs.add_theme_constant_override("separation", 10)
    profile_panel.add_child(tabs)
    for pair in [["avatars", "AVATARES"], ["icons", "ÍCONES"]]:
        var tab_id: String = pair[0]
        var tb = _hud_text_button(pair[1], Vector2(150,34))
        tb.name = "Tab_" + tab_id
        tb.pressed.connect(func(): set_profile_tab(tab_id))
        tabs.add_child(tb)
        profile_tabs[tab_id] = tb
    for id in avatar_gallery.cards: avatar_choices[id] = avatar_gallery.cards[id]
    # Foto própria: escolher arquivo → enquadrar → salvar (512x512). Remover volta ao avatar.
    var photo_row = HBoxContainer.new()
    photo_row.name = "PhotoRow"
    photo_row.position = Vector2(44,474)
    photo_row.size = Vector2(700,44)
    photo_row.add_theme_constant_override("separation", 12)
    profile_panel.add_child(photo_row)
    var change_photo = _hud_text_button("ALTERAR FOTO", Vector2(200,44))
    change_photo.name = "ChangePhoto"
    change_photo.pressed.connect(pick_photo)
    photo_row.add_child(change_photo)
    var remove_photo = _hud_text_button("REMOVER FOTO", Vector2(200,44))
    remove_photo.name = "RemovePhoto"
    remove_photo.pressed.connect(remove_custom_avatar)
    photo_row.add_child(remove_photo)
    # R31: ícone, título, moldura, universo e peças exclusivos (Fundador / Club).
    var personalize = _hud_text_button("PERSONALIZAR", Vector2(240,44))
    personalize.name = "OpenPersonalize"
    personalize.tooltip_text = "Ícone, título, moldura, universo e peças"
    personalize.pressed.connect(func(): open_premium("personalize"))
    photo_row.add_child(personalize)
    avatar_note = _label(profile_panel, "", 13, MUTED)
    avatar_note.name = "AvatarNote"
    avatar_note.position = Vector2(44,520)
    avatar_note.size = Vector2(700,20)
    # DETALHE (direita, topo): avatar em foco, nome, origem e status.
    avatar_detail = _build_avatar_detail(profile_panel, Rect2(790,80,622,206))
    var right_scroll = ScrollContainer.new()
    right_scroll.name = "ProfileInfoScroll"
    right_scroll.position = Vector2(790,296)
    right_scroll.size = Vector2(622,248)
    right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    profile_panel.add_child(right_scroll)
    var right_holder = MarginContainer.new()
    right_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_holder.add_theme_constant_override("margin_right", 10)
    right_scroll.add_child(right_holder)
    var profile = VBoxContainer.new()
    profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    profile.add_theme_constant_override("separation", 10)
    right_holder.add_child(profile)
    # Selo Fundador (Pacote Fundador): emblema + título; só aparece para quem tem o pacote.
    founder_row = HBoxContainer.new()
    founder_row.name = "FounderRow"
    founder_row.add_theme_constant_override("separation", 12)
    profile.add_child(founder_row)
    var seal = TextureRect.new()
    seal.name = "FounderSeal"
    founder_seal = seal
    seal.texture = FOUNDER_BADGE
    seal.custom_minimum_size = Vector2(64, 64)
    seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    founder_row.add_child(seal)
    var seal_words = VBoxContainer.new()
    seal_words.alignment = BoxContainer.ALIGNMENT_CENTER
    seal_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    founder_row.add_child(seal_words)
    founder_title_label = _label(seal_words, "FUNDADOR DO REINO", 18, GOLD)
    founder_title_label.name = "IdentityTitle"
    founder_sub_label = _label(seal_words, "Selo Fundador permanente · Pacote Fundador", 13, MUTED)
    founder_sub_label.name = "IdentitySub"
    founder_row.visible = false
    # Nome público da conta (único, troca a cada 30 dias) — servidor decide tudo.
    nickname_editor = preload("res://account/nickname_editor.gd").new()
    profile.add_child(nickname_editor)
    if account != null: nickname_editor.setup(account, 18)
    # Sem conta: nome local só para a partida contra o computador / tela inicial.
    local_name_box = VBoxContainer.new()
    local_name_box.name = "LocalNameBox"
    local_name_box.add_theme_constant_override("separation", 6)
    profile.add_child(local_name_box)
    _label(local_name_box,"NOME LOCAL (SEM CONTA)",16,GOLD)
    var name_input = LineEdit.new()
    name_input.name = "PlayerName"
    name_input.custom_minimum_size.y = 46
    name_input.max_length = 20
    name_input.text = player_name
    name_input.placeholder_text = "Seu nome"
    name_input.add_theme_font_size_override("font_size",20)
    local_name_box.add_child(name_input)
    name_input.text_changed.connect(func(value):
        player_name = value.strip_edges()
        if player_name.is_empty(): player_name = "Jogador"
        profile_name.text = player_name
        refresh_founder()
        _save_preferences()
    )
    _refresh_name_boxes()
    var stats_grid = GridContainer.new()
    stats_grid.columns = 2
    stats_grid.add_theme_constant_override("h_separation", 18)
    stats_grid.add_theme_constant_override("v_separation", 4)
    profile.add_child(stats_grid)
    for mode in Ranked.MODES:
        var cell = _body(stats_grid,ranked.summary(mode),13)
        cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    set_profile_tab("avatars")
    _build_settings_page()

## CONFIGURAÇÕES (R29): painel próprio, centralizado e do mesmo sistema das páginas largas
## (moldura FRAIHA, título dourado, VOLTAR À HOME no rodapé). Uma coluna que cabe inteira em 1600x900
## sem rolar; no celular a mesma coluna é emprestada pelo mobile_hub (page_scrolls).
func _build_settings_page():
    var panel = Control.new()
    panel.name = "SettingsPage"
    panel.position = Vector2(476,260)
    panel.size = Vector2(720,640)
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    canvas.add_child(panel)
    _frame(panel, Vector2.ZERO, panel.size)
    var heading = _label(panel, "CONFIGURAÇÕES", 29, GOLD)
    heading.name = "SettingsHeading"
    heading.position = Vector2(48,28)
    heading.size = Vector2(624,44)
    var scroll = ScrollContainer.new()
    scroll.name = "PageScroll"
    scroll.position = Vector2(48,82)
    scroll.size = Vector2(624,458)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    panel.add_child(scroll)
    var margin = MarginContainer.new()
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(margin)
    var settings = VBoxContainer.new()
    settings.name = "PageContent"
    settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    settings.add_theme_constant_override("separation", 7)
    margin.add_child(settings)
    # FRAIHA PREMIUM (Fundador + Club) — Monetização V1 em modo de teste.
    var premium_entry = preload("res://monetization/premium_entry.gd").new()
    premium_entry.pressed.connect(func(): open_premium())
    settings.add_child(premium_entry)
    _settings_section(settings, "ÁUDIO")
    music_volume_label = _label(settings, "", 18, CREAM)
    var music_slider = _settings_slider(settings, "MusicVolume")
    music_slider.value = round(music_volume*100)
    music_slider.value_changed.connect(_set_music_volume)
    _set_music_volume(music_slider.value,false)
    volume_label = _label(settings, "", 18, CREAM)
    var slider = _settings_slider(settings, "EffectsVolume")
    slider.value = round(volume*100)
    slider.value_changed.connect(_set_volume)
    _set_volume(slider.value, false)
    _settings_section(settings, "PARTIDA")
    premove_button = _page_button(settings, 1, "", "", _toggle_premove)
    premove_button.name = "PremoveToggle"
    # mesma proporção do botão da arte (450x66): esticar deformava o ícone por cima do texto
    if not preload("res://ui_v022/mobile_layout.gd").active(get_viewport()):
        premove_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        premove_button.custom_minimum_size = Vector2(450, 66)
    _refresh_premove_button()
    var note = _body(settings, "Preferências salvas automaticamente. O botão de som da tela inicial silencia tudo.", 14)
    note.name = "SettingsNote"
    var footer = _button(panel, 6, "VOLTAR À HOME", "ESC também volta", Vector2(48,548), back, Vector2(410,64))
    footer.name = "SettingsBack"
    var ver = _label(panel, "FRAIHA Xadrez · versão %s" % APP_VERSION, 13, MUTED)
    ver.name = "SettingsVersion"
    ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    ver.position = Vector2(470,568)
    ver.size = Vector2(202,24)
    pages["settings"] = panel
    page_scrolls["settings"] = scroll

## Título de seção: texto dourado pequeno + filete dourado (mesmo vocabulário das molduras).
func _settings_section(parent: Node, title: String):
    var gap = Control.new()
    gap.custom_minimum_size.y = 4
    parent.add_child(gap)
    var row = VBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    parent.add_child(row)
    _label(row, title, 14, GOLD)
    var line = ColorRect.new()
    line.color = Color(0.85, 0.71, 0.37, 0.55)
    line.custom_minimum_size = Vector2(0, 1)
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(line)

## Slider no estilo FRAIHA: trilho verde-escuro com borda dourada, parte preenchida em ouro, botão dourado.
func _settings_slider(parent: Node, node_name: String) -> HSlider:
    var slider = HSlider.new()
    slider.name = node_name
    slider.custom_minimum_size.y = 30
    slider.min_value = 0
    slider.max_value = 100
    slider.step = 1
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var track = StyleBoxFlat.new()
    track.bg_color = Color("0b1a12")
    track.border_color = Color(0.85, 0.71, 0.37, 0.7)
    track.set_border_width_all(1)
    track.set_corner_radius_all(4)
    track.content_margin_top = 5
    track.content_margin_bottom = 5
    var fill = StyleBoxFlat.new()
    fill.bg_color = Color("c99a3e")
    fill.set_corner_radius_all(4)
    fill.content_margin_top = 5
    fill.content_margin_bottom = 5
    slider.add_theme_stylebox_override("slider", track)
    slider.add_theme_stylebox_override("grabber_area", fill)
    slider.add_theme_stylebox_override("grabber_area_highlight", fill)
    var knob = Image.create(22, 22, false, Image.FORMAT_RGBA8)
    for y in 22:
        for x in 22:
            var d = Vector2(x + 0.5, y + 0.5).distance_to(Vector2(11, 11))
            if d <= 10.5: knob.set_pixel(x, y, Color("f4d58a") if d <= 7.5 else Color("8a6420"))
    var knob_tex = ImageTexture.create_from_image(knob)
    slider.add_theme_icon_override("grabber", knob_tex)
    slider.add_theme_icon_override("grabber_highlight", knob_tex)
    parent.add_child(slider)
    return slider

func _choose_difficulty(id: String):
    if BotLadder.is_bot_id(id):
        if bot_progress != null and not bot_progress.is_unlocked(id): return
        selected_difficulty = id
        difficulty_label.text = "Adversário: " + String(BotLadder.bot(id).get("name", ""))
        show_page("bot_side")
        return
    if id not in ["easy", "medium", "hard", "expert"]: return
    selected_difficulty = id
    difficulty_label.text = "Nível: " + {"easy":"Fácil","medium":"Médio","hard":"Difícil","expert":"Expert"}[id]
    show_page("bot_side")

## PC: escada de bots pelas ligas em página larga (2 fileiras de cartões).
func _build_bot_ladder_page():
    var panel = _wide_page("bot", "JOGAR CONTRA O COMPUTADOR  ·  DESAFIO DAS LIGAS")
    var sub = _label(panel, "Comece pelo BOT MADEIRA. Cada vitória libera o próximo adversário e uma recompensa.", 16, MUTED)
    sub.position = Vector2(42, 74)
    sub.size = Vector2(1370, 26)
    var scroll = ScrollContainer.new()
    scroll.name = "BotLadderScroll"
    scroll.position = Vector2(30, 104)
    scroll.size = Vector2(1392, 436)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    bot_ladder_ui = load("res://bot/bot_ladder_ui.gd").new()
    bot_ladder_ui.name = "BotLadder"
    scroll.add_child(bot_ladder_ui)
    bot_ladder_ui.setup(bot_progress, 6, Vector2(220, 196), false)
    bot_ladder_ui.challenge.connect(_choose_difficulty)
    storage_note = _label(panel, "", 13, MUTED)
    storage_note.position = Vector2(470, 566)
    storage_note.size = Vector2(940, 22)
    bot_progress.changed.connect(_refresh_storage_note)
    _refresh_storage_note()

var storage_note: Label
func _refresh_storage_note():
    if is_instance_valid(storage_note) and bot_progress != null: storage_note.text = bot_progress.storage_label()

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

## Chave do cache local da foto: user_id da conta, ou "local" sem conta.
func avatar_key() -> String:
    if account != null and account.has_profile() and not String(account.user_id).is_empty(): return String(account.user_id)
    return "local"

## Foto personalizada do jogador (cache local), se houver.
func custom_avatar() -> Texture2D:
    return avatar_store.texture_for(avatar_key()) if avatar_store != null else null

func avatar_texture(id: String = "") -> Texture2D:
    if id.is_empty():
        var custom := custom_avatar()
        if custom != null: return custom
        id = avatar_id
        # Avatar do Fundador sem o pacote ativo (ex.: conta ainda carregando): mostra o Guerreiro sem apagar a escolha.
        if AvatarCatalog.is_founder_avatar(id) and not is_founder(): id = "warrior"
        if AvatarCatalog.is_club_avatar(id) and not club_active(): id = "warrior"
    if id == "paladin": return ThemeCatalog.texture("res://profile/paladin.png")
    if id == "warrior": return AVATAR
    if id != "archer" and id != "mage":
        # Recompensas da escada: arte em profile/avatars/<id>.png quando existir.
        return ThemeCatalog.texture(AvatarCatalog.art_path(id)) if AvatarCatalog.has_art(id) else null
    var atlas = ThemeCatalog.texture("res://cosmetics/v025/avatars.png")
    if atlas == null: return AVATAR
    var half = atlas.get_width()/2.0
    return _slice(atlas,Rect2(0 if id == "archer" else half,0,half,atlas.get_height()))

## Avatar liberado? Iniciais sempre; recompensas da escada pelo progresso dos bots; o do Fundador pelo
## Pacote Fundador (entitlements: servidor is_founder ou simulação de dev).
func avatar_unlocked(id: String) -> bool:
    if AvatarCatalog.is_founder_avatar(id): return is_founder()
    if AvatarCatalog.is_club_avatar(id): return club_active()
    return bot_progress == null or bot_progress.avatar_unlocked(id)

func avatar_lock_hint(id: String) -> String:
    if AvatarCatalog.is_founder_avatar(id): return "Exclusivo do Pacote Fundador"
    if AvatarCatalog.is_club_avatar(id): return "Exclusivo do Club FRAIHA"
    return String(bot_progress.unlock_hint(id)) if bot_progress != null else ""

func is_founder() -> bool:
    return entitlements != null and entitlements.founder()

func choose_avatar(id: String):
    if id not in AvatarCatalog.ids(): return
    if not avatar_unlocked(id) and id != avatar_id:
        _avatar_message("Bloqueado · " + avatar_lock_hint(id) + ".", true)
        return
    if not AvatarCatalog.has_art(id):
        _avatar_message("Avatar conquistado! A arte dele ainda será adicionada ao jogo.", false)
        return
    avatar_id = id
    inspected_avatar = id
    _refresh_avatars()
    _save_preferences()
    cosmetics_changed.emit()

## Botão de texto no estilo do HUD (verde profundo + moldura dourada).
func _hud_text_button(caption: String, min_size: Vector2) -> Button:
    var b = Button.new()
    b.text = caption
    b.custom_minimum_size = min_size
    b.focus_mode = Control.FOCUS_ALL
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    b.add_theme_font_size_override("font_size", 16)
    var states = {"normal": [Color("12301c"), Color("b8913f")], "hover": [Color("1d4a2b"), Color("f0c45c")], "pressed": [Color("0a1d11"), Color("f0c45c")], "focus": [Color("1d4a2b"), Color("f0c45c")]}
    for st in states:
        var sb = StyleBoxFlat.new()
        sb.bg_color = states[st][0]
        sb.border_color = states[st][1]
        sb.set_border_width_all(2)
        sb.set_corner_radius_all(4)
        sb.shadow_color = Color(0,0,0,0.45)
        sb.shadow_size = 3
        if st == "pressed": sb.content_margin_top = 3
        b.add_theme_stylebox_override(st, sb)
    b.add_theme_color_override("font_color", Color("f6d27a"))
    b.add_theme_color_override("font_hover_color", Color("ffe6a0"))
    b.add_theme_color_override("font_pressed_color", Color("ffe6a0"))
    b.add_theme_color_override("font_focus_color", Color("ffe6a0"))
    return b

## Área de detalhe da galeria: retrato grande + nome + origem + status do avatar em foco.
func _build_avatar_detail(parent: Control, r: Rect2) -> Dictionary:
    var box = Panel.new()
    box.name = "AvatarDetail"
    box.position = r.position
    box.size = r.size
    var sb = StyleBoxFlat.new()
    sb.bg_color = Color(0.03,0.09,0.05,0.85)
    sb.border_color = Color("8a6a2c")
    sb.set_border_width_all(2)
    sb.set_corner_radius_all(6)
    box.add_theme_stylebox_override("panel", sb)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(box)
    var pic = TextureRect.new()
    pic.name = "DetailPortrait"
    pic.position = Vector2(12,12)
    pic.size = Vector2(r.size.y - 24, r.size.y - 24)
    pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(pic)
    var words = _stack(box, Vector2(r.size.y + 4, 14), Vector2(r.size.x - r.size.y - 16, r.size.y - 24), Vector4.ZERO, 4)
    var title = _label(words, "", 24, GOLD)
    var origin = _label(words, "", 15, CREAM)
    var status = _label(words, "", 15, MUTED)
    var brief = _label(words, "", 13, MUTED)
    # R32: aplicar é explícito (tocar no cartão só inspeciona)
    var apply = _hud_text_button("APLICAR AVATAR", Vector2(230,42))
    apply.name = "ApplyInspected"
    apply.position = Vector2(r.size.x - 244, r.size.y - 54)
    apply.size = Vector2(230,42)
    apply.mouse_filter = Control.MOUSE_FILTER_STOP
    apply.pressed.connect(apply_inspected)
    box.add_child(apply)
    return {"box": box, "pic": pic, "title": title, "origin": origin, "status": status, "brief": brief, "apply": apply}

func _inspect_avatar(id: String):
    inspected_avatar = id
    _refresh_avatar_detail()

func _inspect_badge(id: String):
    inspected_badge = id
    _refresh_avatar_detail()

func set_profile_tab(tab: String):
    profile_tab = tab
    for k in gallery_scrolls: gallery_scrolls[k].visible = k == tab
    for k in profile_tabs: profile_tabs[k].modulate = Color.WHITE if k == tab else Color(0.62, 0.66, 0.62)
    if tab == "icons": inspected_badge = cosmetic_pref("badge")
    if badge_gallery != null:
        badge_gallery.focus_id = inspected_badge
        badge_gallery.update_states()
    _refresh_avatars()

## R32 · botão APLICAR da área de detalhe: aplica o avatar ou o ícone em foco.
func apply_inspected() -> bool:
    if profile_tab == "icons": return apply_badge(inspected_badge)
    return apply_avatar(inspected_avatar if not inspected_avatar.is_empty() else avatar_id)

func apply_badge(bid: String) -> bool:
    if true:
        if not set_cosmetic("badge", bid):
            _avatar_message("Bloqueado · " + Cosmetics.lock_hint("badge", bid) + ".", true)
            return false
        _avatar_message("Ícone aplicado: " + preload("res://profile/badge_gallery.gd").display_name(bid) + ".", false)
        return true
    return false

func apply_avatar(id: String) -> bool:
    if not avatar_unlocked(id) or not AvatarCatalog.has_art(id):
        _avatar_message("Bloqueado · " + avatar_lock_hint(id) + ".", true)
        return false
    var had_photo := custom_avatar() != null
    if had_photo: remove_custom_avatar()   # avatar e foto não convivem: aplicar o avatar tira a foto
    choose_avatar(id)
    _avatar_message("Avatar aplicado: " + AvatarCatalog.display_name(id) + (" (a foto foi removida)." if had_photo else "."), false)
    return avatar_id == id

func _refresh_avatar_detail():
    if avatar_detail.is_empty() or avatar_gallery == null: return
    if profile_tab == "icons" and badge_gallery != null:
        _refresh_badge_detail()
        return
    var id: String = inspected_avatar if not inspected_avatar.is_empty() else avatar_id
    var e: Dictionary = AvatarCatalog.entry(id)
    var st: String = avatar_gallery.state_of(id)
    avatar_detail.pic.texture = avatar_texture(id) if AvatarCatalog.has_art(id) else null
    avatar_detail.pic.material = avatar_gallery.gray_material() if st == "locked" else null
    avatar_detail.title.text = String(e.get("name", id)).to_upper()
    var src := String(e.get("source", ""))
    avatar_detail.origin.text = "Avatar inicial do FRAIHA" if src == "initial" else ("Exclusivo do Pacote Fundador" if src == "founder" else ("Exclusivo do Club FRAIHA" if src == "club" else "Recompensa: 1ª vitória contra o " + String(BotLadder.bot(src).get("name", "bot"))))
    match st:
        "locked":
            avatar_detail.status.text = "BLOQUEADO · " + avatar_gallery.hint(id)
            avatar_detail.status.add_theme_color_override("font_color", Color("e89a7a"))
        "selected":
            avatar_detail.status.text = "EM USO no seu perfil"
            avatar_detail.status.add_theme_color_override("font_color", Color("49d17a"))
        "no_art_unlocked":
            avatar_detail.status.text = "CONQUISTADO · a arte será adicionada em breve"
            avatar_detail.status.add_theme_color_override("font_color", GOLD)
        _:
            avatar_detail.status.text = "CONQUISTADO · toque em APLICAR AVATAR"
            avatar_detail.status.add_theme_color_override("font_color", GOLD)
    avatar_detail.brief.text = "" if AvatarCatalog.has_art(id) else "Arte em produção."
    if avatar_detail.has("apply"):
        var b: Button = avatar_detail.apply
        b.text = "EM USO" if st == "selected" else ("BLOQUEADO" if st in ["locked", "no_art_unlocked"] else "APLICAR AVATAR")
        b.disabled = st != "unlocked"

func _refresh_badge_detail():
    var id: String = inspected_badge
    var st: String = badge_gallery.state_of(id)
    var shown: String = Cosmetics.effective("badge", id, is_founder(), club_active()) if id == "auto" else id
    avatar_detail.pic.texture = Cosmetics.badge_texture(shown, false)
    avatar_detail.pic.material = avatar_gallery.gray_material() if st == "locked" else null
    avatar_detail.title.text = badge_gallery.display_name(id).to_upper()
    var req := Cosmetics.requirement("badge", id) if id != "auto" else ""
    avatar_detail.origin.text = "Selo ao lado do seu nome (Home, Perfil, Amigos, chat e partidas)" if req.is_empty() else ("Exclusivo do Pacote Fundador" if req == "founder" else "Exclusivo do Club FRAIHA")
    match st:
        "locked":
            avatar_detail.status.text = "BLOQUEADO · " + badge_gallery.hint(id)
            avatar_detail.status.add_theme_color_override("font_color", Color("e89a7a"))
        "selected":
            avatar_detail.status.text = "EM USO"
            avatar_detail.status.add_theme_color_override("font_color", Color("49d17a"))
        _:
            avatar_detail.status.text = "DISPONÍVEL · toque em APLICAR ÍCONE"
            avatar_detail.status.add_theme_color_override("font_color", GOLD)
    avatar_detail.brief.text = "Automático usa o melhor selo que você tem." if id == "auto" else ("Sem selo ao lado do nome." if id.is_empty() else "")
    var b: Button = avatar_detail.apply
    b.text = "EM USO" if st == "selected" else ("BLOQUEADO" if st == "locked" else "APLICAR ÍCONE")
    b.disabled = st != "unlocked"

func _refresh_avatars():
    if is_instance_valid(profile_portrait): profile_portrait.texture = avatar_texture()
    if is_instance_valid(profile_portrait): attach_league_frame(profile_portrait)
    if ref_mode and not ref_profile.is_empty(): _use_profile(true)
    _refresh_ref_account()
    if avatar_gallery != null:
        avatar_gallery.update_states()
        gallery_count.text = "%d de %d avatares conquistados" % [avatar_gallery.count_unlocked(), avatar_gallery.cards.size()]
    if badge_gallery != null:
        badge_gallery.update_states()
        if profile_tab == "icons": gallery_count.text = "Ícone em uso: " + badge_gallery.display_name(cosmetic_pref("badge"))
    _refresh_avatar_detail()
    if get_parent().has_method("refresh_player_card"): get_parent().refresh_player_card()

# ---------- R32 · HISTÓRICO DE PARTIDAS (todas as partidas terminadas + análise) ----------
var history_list: VBoxContainer = null
var history_filter := "all"
var history_filter_buttons := {}
const HISTORY_FILTERS := [["all", "TODAS"], ["bot", "COMPUTADOR"], ["casual", "ONLINE"], ["ranked", "RANQUEADAS"], ["local", "LOCAL"], ["marcha", "MARCHA REAL"], ["xeque", "XEQUE"]]

func _build_history_page():
    var panel = _wide_page("history", "HISTÓRICO DE PARTIDAS")
    var filters = HBoxContainer.new()
    filters.name = "HistoryFilters"
    filters.position = Vector2(40, 86)
    filters.size = Vector2(1370, 40)
    filters.add_theme_constant_override("separation", 10)
    panel.add_child(filters)
    for f in HISTORY_FILTERS:
        var fid: String = f[0]
        var b = _hud_text_button(f[1], Vector2(170, 38))
        b.name = "HistoryFilter_" + fid
        b.pressed.connect(func():
            history_filter = fid
            refresh_history())
        filters.add_child(b)
        history_filter_buttons[fid] = b
    var scroll = ScrollContainer.new()
    scroll.name = "HistoryScroll"
    scroll.position = Vector2(40, 136)
    scroll.size = Vector2(1372, 396)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    history_list = VBoxContainer.new()
    history_list.name = "HistoryList"
    history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    history_list.add_theme_constant_override("separation", 8)
    scroll.add_child(history_list)

func refresh_history():
    if history_list == null: return
    for k in history_filter_buttons: history_filter_buttons[k].modulate = Color.WHITE if k == history_filter else Color(0.62, 0.66, 0.62)
    build_history_list(history_list, false)

## Lista do histórico (PC e celular). Cada partida: resultado, modo, adversário, data, lances e
## REVER ANÁLISE (já analisada) ou ANALISAR (usa a cota; Club = ilimitado).
func build_history_list(parent: VBoxContainer, compact: bool):
    for c in parent.get_children():
        parent.remove_child(c)
        c.queue_free()
    var st = get_parent()
    var mh = st.get("match_history") if st != null else null
    var list: Array = mh.entries if mh != null else []
    var shown := 0
    for e in list:
        var entry: Dictionary = e
        if history_filter != "all" and String(entry.get("mode", "")) != history_filter: continue
        shown += 1
        parent.add_child(_history_row(entry, compact, st, mh))
    if shown == 0:
        var empty = _label(parent, "Nenhuma partida aqui ainda. As partidas terminadas (contra o computador, online, ranqueadas, locais, da Marcha Real e do Xeque) aparecem neste histórico; as de xadrez ficam prontas para analisar.", 16, MUTED)
        empty.name = "HistoryEmpty"

func _history_row(e: Dictionary, compact: bool, st, mh) -> Control:
    var MH = preload("res://analysis/match_history.gd")
    var box = PanelContainer.new()
    box.name = "HistoryRow"
    var sb = StyleBoxFlat.new()
    sb.bg_color = Color(0.03, 0.10, 0.06, 0.92)
    sb.border_color = Color("8a6a2c")
    sb.set_border_width_all(2)
    sb.set_corner_radius_all(6)
    sb.content_margin_left = 14
    sb.content_margin_right = 14
    sb.content_margin_top = 8
    sb.content_margin_bottom = 8
    box.add_theme_stylebox_override("panel", sb)
    var row: BoxContainer = VBoxContainer.new() if compact else HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    box.add_child(row)
    var info = VBoxContainer.new()
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_theme_constant_override("separation", 2)
    row.add_child(info)
    var mode := String(e.get("mode", ""))
    var res := String(e.get("result", ""))
    var head := "%s  ·  %s" % [MH.result_name(res, mode), MH.mode_name(mode)]
    var opp := String(e.get("opponent", ""))
    if String(e.get("mode_id", MH.CHESS_MODE_ID)) != MH.CHESS_MODE_ID:
        # modo especial (Marcha Real): sem lances de xadrez → sem análise; mostra o placar do modo
        if not opp.is_empty(): head += "  ·  vs " + opp
        var colm: Color = Color("8fe08a") if res == "win" else (Color("f2a070") if res in ["loss", "abandon"] else GOLD)
        _label(info, head, 18, colm).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        var dm := Time.get_datetime_dict_from_unix_time(int(e.get("finished_at", e.get("started_at", 0))))
        var data: Dictionary = e.get("data", {}) if e.get("data") is Dictionary else {}
        if String(e.get("mode_id", "")) == "xeque":
            var dur := int(e.get("duration_s", 0))
            _label(info, "%02d/%02d/%d %02d:%02d  ·  %d rodadas  ·  %dº de %d  ·  %d:%02d min" % [dm.day, dm.month, dm.year, dm.hour, dm.minute, int(data.get("rounds", e.get("plies", 0))), int(e.get("placement", 0)), int(e.get("players", 4)), dur / 60, dur % 60], 14, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            _label(info, "Modo de blefe · sem análise de lances", 14, MUTED)
            return box
        var cr: Array = data.get("crowned", [0, 0])
        var ally := String(e.get("ally", ""))
        _label(info, "%02d/%02d/%d %02d:%02d  ·  %d jogadas  ·  coroados %d x %d%s" % [dm.day, dm.month, dm.year, dm.hour, dm.minute, int(e.get("plies", 0)), int(cr[0]) if cr.size() > 0 else 0, int(cr[1]) if cr.size() > 1 else 0, ("  ·  aliado " + ally) if not ally.is_empty() else ""], 14, MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _label(info, "Modo de cartas · sem análise de lances", 14, MUTED)
        return box
    if not opp.is_empty() and mode != "local": head += "  ·  vs " + opp
    var col: Color = Color("8fe08a") if res == "win" else (Color("f2a070") if res == "loss" else GOLD)
    _label(info, head, 18, col).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var d := Time.get_datetime_dict_from_unix_time(int(e.get("finished_at", e.get("started_at", 0))))
    var color_txt := "" if String(e.get("color", "")).is_empty() else ("  ·  de " + ("Brancas" if String(e.color) == "w" else "Pretas"))
    _label(info, "%02d/%02d/%d %02d:%02d  ·  %d lances%s" % [d.day, d.month, d.year, d.hour, d.minute, int(e.get("plies", 0)), color_txt], 14, MUTED)
    var rec = mh.record_of(e) if mh != null else null
    var an: Dictionary = st.analysis_entry_for(rec) if st != null and st.has_method("analysis_entry_for") else {}
    if not an.is_empty():
        _label(info, "Analisada · precisão %d%%" % int(round(float(an.get("accuracy", 0.0)))), 14, Color("bfe8a8"))
    var buttons = HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 10)
    row.add_child(buttons)
    var can_review: bool = not an.is_empty() and st.analysis_history != null and st.analysis_history.has_report(an)
    if can_review:
        var rv = _hud_text_button("REVER ANÁLISE", Vector2(200, 42))
        rv.name = "HistoryReview"
        rv.pressed.connect(func(): st.open_history_report(an))
        buttons.add_child(rv)
    var az = _hud_text_button("ANALISAR" if not can_review else "ANALISAR DE NOVO", Vector2(200 if not can_review else 230, 42))
    az.name = "HistoryAnalyze"
    az.disabled = rec == null or rec.moves.size() < 2
    az.tooltip_text = "Usa uma análise da cota do dia (Club: ilimitado)"
    az.pressed.connect(func(): if rec != null: st.open_analysis_for(rec))
    buttons.add_child(az)
    return box

func _build_about_page():
    var panel = _wide_page("about","CONHEÇA O FRAIHA  ·  MUITO MAIS QUE UM XADREZ")
    var topics = [["O PROJETO","Um tabuleiro, muitas histórias.\n\nFRAIHA Xadrez combina o jogo clássico com um mundo medieval em pixel art. Planeje suas jogadas, pratique e compartilhe partidas.\n\nFeito por jogadores, para jogadores. Maringá · Paraná · Brasil."],["COMO JOGAR","Clique em uma peça e depois em uma casa marcada, ou arraste a peça.\n\nESC abre a confirmação para abandonar. O jogo ocupa a tela inteira (no PC, Alt+Enter alterna janela/tela cheia). Ao jogar de pretas, suas peças ficam na parte inferior do tabuleiro."],["SISTEMA DE LIGAS","Madeira, Ferro, Bronze, Prata, Ouro, Platina, Esmeralda, Diamante, Mestre, Grande Mestre e Challenger.\n\nO Ranked tem quatro ritmos (3, 5, 10 e 20 minutos), cada um com PL e liga próprios. A cada 100 PL você sobe de liga. A maior liga alcançada em qualquer ritmo libera o cenário e as peças daquela liga."],["MODOS DE JOGO","Contra o computador: Desafio das Ligas — 11 bots com Stockfish, do BOT MADEIRA ao BOT CHALLENGER. Cada vitória libera o próximo e uma recompensa.\nOnline: escolha o ritmo (3, 5, 10 ou 20 min) e entre na fila; o adversário é encontrado automaticamente. Não vale PL.\nRanqueado: entre na sua conta e dispute PL em quatro ritmos."],["PERSONALIZAÇÃO","Escolha seu avatar no Perfil. Novos avatares são liberados vencendo os bots do Desafio das Ligas.\n\nNa página Ligas, veja o universo de cada liga. Madeira já está disponível; as demais são liberadas conforme você alcança a liga no Ranked. As peças clássicas também continuam disponíveis."],["COMUNIDADE E SUPORTE","Esta é uma build de teste. Compartilhe suas observações sobre interface, peças e partidas com o responsável pelo projeto.\n\nAinda não há comunidade ou suporte conectados pelo jogo.\n\nEstratégia para ir mais longe."]]
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
    var contain = minf(dimensions.x / framed_size.x, dimensions.y / framed_size.y)
    var cover = maxf(dimensions.x / DESIGN.x, dimensions.y / DESIGN.y)
    # Aba mais larga/alta que 16:9: amplia um pouco além do "caber" (corta no máximo ~1,7% de
    # cada borda, só céu/folhagem) para sobrar menos faixa; o resto é preenchido pela própria arte.
    var factor = minf(cover, contain * EDGE_CROP)
    canvas.scale = Vector2.ONE * factor
    canvas.position = (dimensions - DESIGN*factor) / 2.0
    presentation_frame.queue_redraw()

func _draw_presentation_frame():
    # Sobras fora da composição: a própria arte, ampliada para cobrir a tela e escurecida
    # (cor sempre derivada da arte atual, nunca cinza neutro). Nada disso recebe clique.
    var artwork = Rect2(canvas.position, DESIGN * canvas.scale)
    var full = Rect2(Vector2.ZERO, presentation_frame.size)
    if artwork.encloses(full.grow(-0.5)): return
    var art = canvas.get_node_or_null("ForestArtwork")
    var tex: Texture2D = art.texture if art != null else null
    if tex == null:
        presentation_frame.draw_rect(full, Color("0f1a12"))
        return
    var cover = maxf(full.size.x / DESIGN.x, full.size.y / DESIGN.y) * 1.04
    var cover_rect = Rect2((full.size - DESIGN * cover) / 2.0, DESIGN * cover)
    # Sobras da tela (fora da tela cheia): panorama de folhagem em pixel art, levemente escurecido.
    var foliage: Texture2D = preload("res://ui_v022/assets/home_side_foliage.png")
    var fs = maxf(full.size.x / foliage.get_width(), full.size.y / foliage.get_height())
    var fr = Rect2((full.size - foliage.get_size() * fs) / 2.0, foliage.get_size() * fs)
    # Quase sem escurecer: com a barra do navegador visível (antes da tela cheia) a folhagem continua a cena
    # em vez de parecer uma "moldura" em volta de uma janela menor.
    presentation_frame.draw_texture_rect(foliage, fr, false, Color(0.86, 0.9, 0.84))
    if false: presentation_frame.draw_texture_rect(_backdrop_for(tex), cover_rect, false, Color(0.5, 0.52, 0.48))
    # Junto à arte: continuação espelhada e suavizada da própria borda (cores casam na emenda),
    # escurecendo para fora. Sem moldura, sem cinza.
    var soft := _soft_for(tex)
    var sw := float(soft.get_width())
    var sh := float(soft.get_height())
    var gaps := [artwork.position.x, full.size.x - artwork.end.x, artwork.position.y, full.size.y - artwork.end.y]
    for side in 4:
        var gap: float = gaps[side]
        if true: continue   # substituído pelo panorama de folhagem
        if gap < 0.5: continue
        var horizontal := side < 2
        var span := minf(gap, (artwork.size.x if horizontal else artwork.size.y) * 0.35)
        var dest: Rect2
        var src: Rect2
        var outer_a: Vector2
        var outer_b: Vector2
        var inner_a: Vector2
        var inner_b: Vector2
        match side:
            0:
                dest = Rect2(artwork.position.x, artwork.position.y, -span, artwork.size.y)
                src = Rect2(0, 0, sw * span / artwork.size.x, sh)
                inner_a = artwork.position; inner_b = Vector2(artwork.position.x, artwork.end.y)
                outer_a = inner_a - Vector2(span, 0); outer_b = inner_b - Vector2(span, 0)
            1:
                dest = Rect2(artwork.end.x, artwork.position.y, -span, artwork.size.y)
                dest.position.x += span
                src = Rect2(sw - sw * span / artwork.size.x, 0, sw * span / artwork.size.x, sh)
                inner_a = Vector2(artwork.end.x, artwork.position.y); inner_b = artwork.end
                outer_a = inner_a + Vector2(span, 0); outer_b = inner_b + Vector2(span, 0)
            2:
                dest = Rect2(artwork.position.x, artwork.position.y, artwork.size.x, -span)
                src = Rect2(0, 0, sw, sh * span / artwork.size.y)
                inner_a = artwork.position; inner_b = Vector2(artwork.end.x, artwork.position.y)
                outer_a = inner_a - Vector2(0, span); outer_b = inner_b - Vector2(0, span)
            3:
                dest = Rect2(artwork.position.x, artwork.end.y + span, artwork.size.x, -span)
                src = Rect2(0, sh - sh * span / artwork.size.y, sw, sh * span / artwork.size.y)
                inner_a = Vector2(artwork.position.x, artwork.end.y); inner_b = artwork.end
                outer_a = inner_a + Vector2(0, span); outer_b = inner_b + Vector2(0, span)
        presentation_frame.draw_texture_rect_region(soft, dest, src, Color(0.86, 0.88, 0.84))
        var clear := Color(0, 0, 0, 0.0)
        var dark := Color(0, 0, 0, 0.5)
        presentation_frame.draw_polygon(PackedVector2Array([inner_a, inner_b, outer_b, outer_a]), PackedColorArray([clear, clear, dark, dark]))
    # Sombra bem leve na emenda para a arte "assentar" sem parecer moldura.
    var unit = canvas.scale.x
    for step in range(1, 5):
        presentation_frame.draw_rect(artwork.grow(step * 2 * unit), Color(0, 0, 0, (5 - step) * 0.03), false, 2 * unit)

var _soft_cache := {}
# Versão levemente suavizada (1/5 da resolução): esconde letras/detalhes espelhados, mantém as cores.
func _soft_for(tex: Texture2D) -> Texture2D:
    var key = tex.get_rid()
    if _soft_cache.has(key): return _soft_cache[key]
    var img: Image = tex.get_image()
    if img == null: return tex
    img = img.duplicate()
    if img.is_compressed(): img.decompress()
    img.resize(maxi(8, img.get_width() / 5), maxi(8, img.get_height() / 5), Image.INTERPOLATE_LANCZOS)
    var soft = ImageTexture.create_from_image(img)
    _soft_cache[key] = soft
    return soft

var _backdrop_cache := {}
# Versão desfocada da arte (reduzida a poucos pixels e ampliada com filtro linear): só cores da própria arte.
func _backdrop_for(tex: Texture2D) -> Texture2D:
    var key = tex.get_rid()
    if _backdrop_cache.has(key): return _backdrop_cache[key]
    var img: Image = tex.get_image()
    if img == null: return tex
    img = img.duplicate()
    if img.is_compressed(): img.decompress()
    img.resize(24, 14, Image.INTERPOLATE_LANCZOS)
    img.resize(96, 54, Image.INTERPOLATE_CUBIC)
    var blurred = ImageTexture.create_from_image(img)
    _backdrop_cache[key] = blurred
    return blurred

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
    if id == "ranking": _select_league(selected_league)
    if id == "profile": _refresh_avatars()
    if id == "history": refresh_history()
    if is_instance_valid(mobile_ui): mobile_ui.show_page(id)

func apply_theme(texture: Texture2D, theme_id: String = "wood"):
    if texture == FOREST_LEGACY: texture = FOREST   # temas que usavam a Home da floresta passam a usar a arte oficial
    if texture != null:
        canvas.get_node("ForestArtwork").texture = texture
        var details = canvas.get_node_or_null("ForestDetails")
        if details != null: details.visible = _is_ref_art(texture)
        var spirit = canvas.get_node_or_null("WaterSpirit")
        if spirit != null: spirit.visible = _is_ref_art(texture)
        _sync_chrome()
        _sync_menu_cover()
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
    AudioServer.set_bus_mute(bus, volume <= 0.0 or effects_muted)
    volume_label.text = "EFEITOS SONOROS  ·  %d%%" % round(value)
    if save:
        _save_preferences()
        _osd().show_volume("effects", value)

func _set_music_volume(value: float, save := true):
    music_volume = value/100.0
    var bus = AudioServer.get_bus_index("Music")
    AudioServer.set_bus_volume_db(bus,linear_to_db(maxf(music_volume,0.0001)))
    AudioServer.set_bus_mute(bus,music_volume <= 0.0 or music_muted)
    music_volume_label.text = "MÚSICA  ·  %d%%" % round(value)
    if save:
        _save_preferences()
        _osd().show_volume("music", value)

var volume_osd
func _osd():
    if not is_instance_valid(volume_osd):
        volume_osd = preload("res://ui_v022/volume_osd.gd").new()
        volume_osd.name = "VolumeOSD"
        add_child(volume_osd)
    return volume_osd

## R34: liga/desliga só a música ou só os efeitos (os volumes guardados não mudam).
func set_music_muted(value: bool):
    music_muted = value
    var bus = AudioServer.get_bus_index("Music")
    AudioServer.set_bus_mute(bus, music_volume <= 0.0 or music_muted)
    _save_preferences()

func set_effects_muted(value: bool):
    effects_muted = value
    var bus = AudioServer.get_bus_index("Effects")
    AudioServer.set_bus_mute(bus, volume <= 0.0 or effects_muted)
    _save_preferences()

## SOM da Home: liga/desliga todo o áudio (bus Master). Volumes de música/efeitos ficam como estão.
func toggle_sound():
    set_sound_muted(not sound_muted)

func set_sound_muted(value: bool):
    sound_muted = value
    AudioServer.set_bus_mute(0, sound_muted)
    _save_preferences()
    _refresh_sound_button()
    if is_instance_valid(mobile_ui) and mobile_ui.has_method("refresh_sound"): mobile_ui.refresh_sound()

## Tela cheia (R29.2): botão ao lado do som; o estado vem do ui_v022/fullscreen_control.gd (stage).
var screen_mode
var fullscreen_button: Button
func attach_screen_mode(sm):
    screen_mode = sm
    if not is_instance_valid(fullscreen_button):
        fullscreen_button = preload("res://ui_v022/hud_button.gd").make("fullscreen")
        fullscreen_button.name = "FullscreenButton"
        fullscreen_button.size = Vector2(62, 62)
        fullscreen_button.position = Vector2(434, 16)
        fullscreen_button.pressed.connect(func(): if screen_mode != null: screen_mode.toggle())
        canvas.add_child(fullscreen_button)
    sm.changed.connect(func(_on): refresh_fullscreen_button())
    refresh_fullscreen_button()
    if is_instance_valid(mobile_ui) and mobile_ui.has_method("refresh_fullscreen"): mobile_ui.refresh_fullscreen()
    _build_web_quit_caption()

func refresh_fullscreen_button():
    var ok: bool = screen_mode != null and screen_mode.supported()
    var on: bool = ok and screen_mode.is_on()
    for b in [fullscreen_button, mobile_ui.fullscreen_button if is_instance_valid(mobile_ui) else null]:
        if not is_instance_valid(b): continue
        b.visible = ok   # iPhone/Safari sem a API: o botão some
        b.glyph = "exit_fullscreen" if on else "fullscreen"
        b.tooltip_text = "Sair da tela cheia" if on else "Tela cheia"
        b.queue_redraw()

## Web: SAIR volta para o site — o subtítulo desenhado na arte ("Até a próxima partida!") é coberto
## com o mesmo verde do botão e recebe "Voltar para o site".
func _build_web_quit_caption():
    if not OS.has_feature("web") or canvas.get_node_or_null("WebQuitCaption") != null: return
    var patch = ColorRect.new()
    patch.name = "WebQuitCaption"
    patch.color = Color8(1, 36, 21)
    var sair_row: Vector2 = MENU_ROWS[MENU_ROWS.size() - 1]
    patch.position = Vector2(MENU_TEXT_X, sair_row.x + 24.0)   # coordenadas da arte v6 (DESIGN 1672x941)
    patch.size = Vector2(240, 19)
    patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(patch)
    canvas.move_child(patch, canvas.get_node("MainMenu").get_index())
    var cap = _label(patch, "Voltar para o site", 12, Color("e8e2d0"))
    cap.position = Vector2(1, -2)
    cap.size = Vector2(236, 24)
    cap.autowrap_mode = TextServer.AUTOWRAP_OFF
    ref_nodes.append(patch)
    patch.visible = ref_mode
    var last := menu_buttons.size() - 1
    if last >= 0:
        menu_buttons[last].tooltip_text = "Voltar para o site fraihaxadrez.com"

func _refresh_sound_button():
    if not is_instance_valid(sound_button): return
    sound_button.glyph = "sound_off" if sound_muted else "sound_on"
    sound_button.tooltip_text = "Som desligado · clique para ligar" if sound_muted else "Som ligado · clique para silenciar"
    sound_button.queue_redraw()

func open_premium(page_id := "hub"):
    if premium == null:
        premium = load("res://monetization/premium_hub.gd").new(monetization_state)
        premium.main_hub = self
        add_child(premium)
    premium.open(page_id)

func open_club():
    open_premium("club")

## R32 · MARCHA REAL (novo modo; Club ilimitado, sem Club 1 partida por dia).
var marcha = null
var xeque = null
func open_xeque():
    if xeque == null:
        xeque = load("res://xeque/xeque_ui.gd").new()
        xeque.setup(self, get_parent())
        get_parent().add_child(xeque)
    xeque.open()

func open_marcha():
    if marcha == null:
        marcha = load("res://marcha/marcha_ui.gd").new()
        marcha.setup(self, get_parent())
        get_parent().add_child(marcha)
    marcha.open()

## Club ativo (real OU simulação) → atualiza a fita da Home e o cartão do jogador.
## Selo Fundador: cartão da Home (ao lado do nome), Perfil e cartão do celular.
func refresh_founder():
    var badge := current_badge()
    var title := current_title()
    var on := not badge.is_empty() or not title.is_empty()
    if is_instance_valid(founder_row):
        founder_row.visible = on
        founder_seal.texture = Cosmetics.badge_texture(badge, false)
        founder_seal.visible = founder_seal.texture != null
        founder_title_label.text = (Cosmetics.title_text(title) if not title.is_empty() else String(Cosmetics.BADGE_NAMES.get(badge, ""))).to_upper()
        var parts: Array = []
        if not badge.is_empty(): parts.append(String(Cosmetics.BADGE_NAMES.get(badge, "")))
        parts.append("Pacote Fundador" if is_founder() else "Club FRAIHA")
        founder_sub_label.text = " · ".join(parts)
    if is_instance_valid(ref_founder_badge):
        ref_founder_badge.texture = Cosmetics.badge_texture(badge)
        ref_founder_badge.tooltip_text = String(Cosmetics.BADGE_NAMES.get(badge, "")) + ("  ·  " + Cosmetics.title_text(title) if not title.is_empty() else "")
    on = not badge.is_empty()
    if is_instance_valid(desk_badge) and not desk_profile.is_empty():
        var dl: Label = desk_profile.name
        var df: Font = dl.get_theme_font("font")
        var dw: float = minf(df.get_string_size(dl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, dl.get_theme_font_size("font_size")).x, 200.0)
        desk_badge.texture = Cosmetics.badge_texture(badge)
        desk_badge.position = Vector2(106.0 + dw + 6.0, 2.0)
        desk_badge.visible = on and not ref_mode
    if is_instance_valid(ref_founder_badge) and not ref_profile.is_empty():
        var nl: Label = ref_profile.name
        var f: Font = nl.get_theme_font("font")
        var w: float = minf(f.get_string_size(nl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, nl.get_theme_font_size("font_size")).x, nl.size.x)
        ref_founder_badge.position = nl.position + Vector2(w + 6.0, -2.0)
        ref_founder_badge.visible = on and ref_mode
    if is_instance_valid(mobile_ui): mobile_ui.queue_redraw_cards()

func refresh_club():
    refresh_founder()
    var on: bool = entitlements != null and entitlements.club_active()
    if is_instance_valid(club_entry): club_entry.set_active(on)
    if is_instance_valid(mobile_ui) and mobile_ui.has_method("refresh_club"): mobile_ui.refresh_club(on)
    _refresh_avatars()   # molduras (Home, Perfil, cartão do jogador)
    _apply_lab()

func _toggle_premove():
    premove_enabled = not premove_enabled
    _save_preferences()
    _refresh_premove_button()
    premove_changed.emit(premove_enabled)

func _refresh_premove_button():
    if premove_button == null: return
    var title := "PRÉ-MOVE: " + ("LIGADO" if premove_enabled else "DESLIGADO")
    var sub := "Jogue na vez do adversário" if premove_enabled else "Clique para ligar"
    premove_button.set_meta("title", title)
    var labels := premove_button.get_child(0).get_child(0)
    (labels.get_child(0) as Label).text = title
    (labels.get_child(1) as Label).text = sub

func _load_preferences():
    var config = ConfigFile.new()
    if config.load(PREFS) != OK: return
    player_name = String(config.get_value("profile","name","Jogador")).left(20)
    avatar_id = String(config.get_value("profile","avatar","warrior"))
    if avatar_id not in AvatarCatalog.ids() or not AvatarCatalog.has_art(avatar_id): avatar_id = "warrior"
    volume = clampf(float(config.get_value("audio","volume",0.8)),0,1)
    music_volume = clampf(float(config.get_value("audio","music_volume",0.65)),0,1)
    premove_enabled = bool(config.get_value("game","premove",true))
    sound_muted = bool(config.get_value("audio","muted",false))
    music_muted = bool(config.get_value("audio","music_muted",false))
    effects_muted = bool(config.get_value("audio","effects_muted",false))
    badge_pref = String(config.get_value("profile","badge","auto"))
    title_pref = String(config.get_value("profile","title","auto"))
    frame_pref = String(config.get_value("profile","frame",""))
    lab_coords = bool(config.get_value("lab","coordinates",false))

func _save_preferences():
    var config = ConfigFile.new()
    config.set_value("profile","name",player_name)
    config.set_value("profile","avatar",avatar_id)
    config.set_value("audio","volume",volume)
    config.set_value("audio","music_volume",music_volume)
    config.set_value("audio","muted",sound_muted)
    config.set_value("audio","music_muted",music_muted)
    config.set_value("audio","effects_muted",effects_muted)
    config.set_value("game","premove",premove_enabled)
    config.set_value("profile","badge",badge_pref)
    config.set_value("profile","title",title_pref)
    config.set_value("profile","frame",frame_pref)
    config.set_value("lab","coordinates",lab_coords)
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
    if portrait.has_meta("no_league_frame"):
        attach_club_frame(portrait)   # a moldura de liga já está na arte; a do Club vai por cima
        return
    var border = portrait.get_node_or_null("LeagueFrame")
    if border == null:
        border = preload("res://profile/league_frame.gd").new()
        border.name = "LeagueFrame"
        portrait.add_child(border)
    border.league_id = league_profile.data.current_league
    border.queue_redraw()
    attach_club_frame(portrait)

## Moldura CLUB por cima de qualquer retrato (só com Club ativo: servidor ou simulação).
func attach_club_frame(portrait: Control, round_shape := false, compact := false):
    if portrait.has_meta("no_club_frame"): return   # avatares de escolha no Perfil não recebem a moldura
    var fr := current_frame()
    var on: bool = fr != "liga"
    var frame = portrait.get_node_or_null("ClubFrame")
    if not on:
        if frame != null: frame.visible = false
        return
    if frame == null:
        frame = preload("res://monetization/club_frame.gd").new()
        portrait.add_child(frame)
    frame.style = fr
    frame.round_shape = round_shape
    frame.compact = compact or portrait.size.x < 60.0
    frame.visible = true
    frame.queue_redraw()

func club_active() -> bool:
    return entitlements != null and entitlements.club_active()

# ---------- R31 · Identidade premium (ícone, título, moldura) ----------
func current_badge() -> String:
    return Cosmetics.effective("badge", badge_pref, is_founder(), club_active())

func current_title() -> String:
    return Cosmetics.effective("title", title_pref, is_founder(), club_active())

func current_frame() -> String:
    return Cosmetics.effective("frame", frame_pref, is_founder(), club_active())

func current_badge_texture(small := true) -> Texture2D:
    return Cosmetics.badge_texture(current_badge(), small)

## kind: "badge" | "title" | "frame". id "auto" volta ao automático. Bloqueado → false (nada muda).
func set_cosmetic(kind: String, id: String) -> bool:
    var options: Array = Cosmetics.BADGES if kind == "badge" else (Cosmetics.TITLES if kind == "title" else Cosmetics.FRAMES)
    if id != "auto" and id not in options: return false
    if id != "auto" and not Cosmetics.allowed(kind, id, is_founder(), club_active()): return false
    match kind:
        "badge": badge_pref = id
        "title": title_pref = id
        _: frame_pref = id
    _save_preferences()
    refresh_club()
    cosmetics_changed.emit()
    return true

func cosmetic_pref(kind: String) -> String:
    match kind:
        "badge": return badge_pref
        "title": return title_pref
    return frame_pref if not frame_pref.is_empty() else "auto"

## LABORATÓRIO · acesso antecipado (Fundador ou Club): novidades em teste antes do lançamento geral.
func early_access() -> bool:
    return is_founder() or club_active()

func lab_coordinates_on() -> bool:
    return lab_coords and early_access()

func set_lab_coordinates(on: bool) -> bool:
    if on and not early_access(): return false
    lab_coords = on
    _save_preferences()
    _apply_lab()
    return true

func _apply_lab():
    var st = get_parent()
    if st != null and st.get("game") != null:
        st.game.show_coordinates = lab_coordinates_on()
        st.game.queue_redraw()

## O que o servidor recebe (acct_set_cosmetics): itens EFETIVOS, já respeitando os direitos atuais.
## Usa só os direitos REAIS (servidor): a simulação dev_mock_* nunca vai para a conta.
func public_cosmetics() -> Dictionary:
    var f: bool = entitlements != null and bool(entitlements.real.is_founder)
    var c: bool = entitlements != null and bool(entitlements.real.club_active)
    var av := avatar_id
    if not avatar_unlocked(av) or (AvatarCatalog.is_founder_avatar(av) and not f) or (AvatarCatalog.is_club_avatar(av) and not c): av = "warrior"
    return {"avatar_id": av, "badge": Cosmetics.effective("badge", badge_pref, f, c), "title": Cosmetics.effective("title", title_pref, f, c), "frame": Cosmetics.effective("frame", frame_pref, f, c)}

# ---------- Home "referência" (arte oficial com moldura, perfil, conta, versão e Ranqueado desenhados) ----------
# Na arte FOREST_V2 os painéis e botões já estão desenhados; aqui só entra o conteúdo vivo
# (retrato, nickname, liga/PL, barra, insígnia, texto da conta) e as áreas de clique.
const REF_MENU_RECT = Rect2(614,296,446,556)
var ref_nodes: Array = []
var ref_mode := false
var desk_profile := {}
var ref_profile := {}
var ref_account_avatar: TextureRect
var ref_account_frame_host: Control = null
var ref_profile_club_host: Control = null
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
    # CLUB FRAIHA: fita pendurada no cartão de perfil (entrada própria, fora de Configurações).
    # Canto superior esquerdo do HUD (antes ficava pendurado no cartão de perfil e invadia as páginas).
    club_entry = preload("res://monetization/club_home_entry.gd").new()
    club_entry.position = Vector2(22, 16)
    club_entry.size = Vector2(330, 62)
    club_entry.pressed.connect(open_club)
    canvas.add_child(club_entry)
    ref_nodes.append(club_entry)
    refresh_club()
    sound_button = preload("res://ui_v022/hud_button.gd").make("sound_on")
    sound_button.name = "SoundButton"
    sound_button.size = Vector2(62, 62)
    sound_button.position = Vector2(364, 16)
    sound_button.pressed.connect(toggle_sound)
    canvas.add_child(sound_button)
    _refresh_sound_button()
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
    portrait.set_meta("no_club_frame", true)   # a moldura Club fica no RefPortraitClubHost (fora do recorte)
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.size = clip.size
    portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip.add_child(portrait)
    # Moldura CLUB fora do recorte (a coroa fica acima do retrato); só aparece com Club ativo.
    var club_host = Control.new()
    club_host.name = "RefPortraitClubHost"
    club_host.position = clip.position - Vector2(4, 4)
    club_host.size = clip.size + Vector2(8, 8)
    club_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(club_host)
    ref_profile_club_host = club_host
    attach_club_frame(club_host)
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
    # Selo Fundador ao lado do nome (só para quem tem o Pacote Fundador).
    ref_founder_badge = TextureRect.new()
    ref_founder_badge.name = "RefFounderBadge"
    ref_founder_badge.texture = FOUNDER_BADGE_SMALL
    ref_founder_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    ref_founder_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    ref_founder_badge.size = Vector2(36, 36)
    ref_founder_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ref_founder_badge.tooltip_text = "Selo Fundador"
    ref_founder_badge.visible = false
    pbtn.add_child(ref_founder_badge)
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
    var acct_frame_host = Control.new()
    acct_frame_host.name = "RefAccountAvatarFrameHost"
    acct_frame_host.position = ref_account_avatar.position
    acct_frame_host.size = ref_account_avatar.size
    acct_frame_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    acct_frame_host.set_meta("round_club_frame", true)
    canvas.add_child(acct_frame_host)
    ref_nodes.append(acct_frame_host)
    ref_account_frame_host = acct_frame_host
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
        patch.texture = _slice(FOREST_V2, Rect2(x, 600, 18, 76))
        patch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        patch.stretch_mode = TextureRect.STRETCH_SCALE
        patch.position = Vector2(x, MENU_ROWS[2].x - 5.3)
        patch.size = Vector2(18, 76.0 * MENU_SCALE / 0.891)
        patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
        ref_menu_cover.add_child(patch)
        patch.top_level = false
        patch.position = Vector2(x, MENU_ROWS[2].x - 5.3) - ref_menu_cover.position
    # Botões do menu: ao passar o mouse / foco o PRÓPRIO botão da arte reluz (mesmos pixels,
    # somando luz nas partes douradas). Nada de caixa por cima nem texto extra.
    var glow_material = ShaderMaterial.new()
    glow_material.shader = preload("res://ui_v022/home_button_glow.gdshader")
    for button in menu_buttons:
        var ranked = title_of(button) == "JOGAR RANQUEADO"
        var offset = Vector2(-5, -11) if ranked else Vector2(0, -2)
        var region = Rect2(button.position + offset, button.size + (Vector2(11, 23) if ranked else Vector2(0, 4)))
        var atlas = AtlasTexture.new()
        atlas.atlas = FOREST
        atlas.region = region
        var hover = TextureRect.new()
        hover.name = "RefHover"
        hover.texture = atlas
        hover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        hover.stretch_mode = TextureRect.STRETCH_SCALE
        hover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        hover.material = glow_material
        hover.position = offset
        hover.size = region.size
        hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hover.hide()
        button.add_child(hover)
        ref_hovers[button] = hover
        button.mouse_entered.connect(func(): if ref_mode: hover.show())
        button.mouse_exited.connect(func(): if ref_mode and not button.has_focus(): hover.hide())
        button.focus_entered.connect(func(): if ref_mode: hover.show())
        button.focus_exited.connect(func(): hover.hide())
        # R32: linhas novas da arte v3 (moldura sem texto): título, subtítulo e ícone vivos por cima
        var title := title_of(button)
        if title in ["MARCHA REAL", "XEQUE", "HISTÓRICO DE PARTIDAS"]:
            var cap = Control.new()
            cap.name = "RefCaption"
            cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
            cap.size = button.size
            button.add_child(cap)
            var t1 = _label(cap, title, 15, Color("f4f1e6"))
            t1.position = Vector2(MENU_TEXT_X - 611.0, 1)
            t1.size = Vector2(300, 24)
            t1.autowrap_mode = TextServer.AUTOWRAP_OFF
            var t2 = _label(cap, {"MARCHA REAL": "Novo modo · cartas e corrida", "XEQUE": "Novo modo · blefe de cartas"}.get(title, "Suas partidas e análises"), 12, Color("e8e2d0"))
            t2.position = Vector2(MENU_TEXT_X - 611.0, 19)
            t2.size = Vector2(300, 20)
            t2.autowrap_mode = TextServer.AUTOWRAP_OFF
            if title in ["MARCHA REAL", "XEQUE"]:
                var tag = preload("res://monetization/premium_art.gd").Stamp.new("NOVO", "new", 11)
                tag.position = Vector2(285, 4)
                tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
                cap.add_child(tag)
            else:
                var ic = preload("res://monetization/premium_art.gd").Glyph.new("hourglass", 30, Color("f2c14e"))
                ic.position = Vector2(20, 2)
                ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
                cap.add_child(ic)

func _sync_chrome():
    var ref = _is_ref_art(canvas.get_node("ForestArtwork").texture)
    ref_mode = ref
    if is_instance_valid(presentation_frame): presentation_frame.queue_redraw()
    for n in ref_nodes: n.visible = ref
    for name in ["ProfilePanel","AccountPanel"]:
        var n = canvas.get_node_or_null(name)
        if n != null: n.visible = not ref
    var plaque = canvas.get_node_or_null("RefAccountPlaque")
    if plaque != null: plaque.visible = ref
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
        var rcap = button.get_node_or_null("RefCaption")
        if rcap != null: rcap.visible = ref
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
    refresh_founder.call_deferred()
    if ref:
        if is_instance_valid(ref_profile_club_host): attach_club_frame(ref_profile_club_host)
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
    if is_instance_valid(ref_account_frame_host):
        ref_account_frame_host.visible = ref_account_avatar.visible
        attach_club_frame(ref_account_frame_host, true, true)
    ref_account_avatar.texture = avatar_texture()

func _sync_menu_cover():
    if is_instance_valid(ref_menu_cover): ref_menu_cover.visible = ref_mode and page != "main"
    # Páginas internas usam o painel largo (y 260 → 900): o HUD de baixo da Home (cartão da conta,
    # versão) fica escondido enquanto a página está aberta — antes os textos vivos atravessavam a moldura.
    var home := page == "main"
    for n in [account_card, ref_account_avatar, ref_account_frame_host, canvas.get_node_or_null("RefAccountPlaque")]:
        if is_instance_valid(n): n.modulate.a = 1.0 if home else 0.0
    if is_instance_valid(account_card): account_card.mouse_filter = Control.MOUSE_FILTER_STOP if home else Control.MOUSE_FILTER_IGNORE
    var acct = canvas.get_node_or_null("AccountPanel")
    if acct != null: acct.modulate.a = 1.0 if home else 0.0
    var quit_cap = canvas.get_node_or_null("WebQuitCaption")
    if quit_cap != null: quit_cap.visible = ref_mode and home


# ---------- Conta ligada ao Home: nome público e foto (0004) ----------
func bind_account(acc):
    account = acc
    if bot_progress != null: bot_progress.setup(acc)
    if nickname_editor != null and nickname_editor.account == null: nickname_editor.setup(acc, 18)
    acc.changed.connect(_on_account_changed)
    acc.avatar_saved.connect(func(url):
        _server_avatar_url = String(url)
        # A cópia local é exatamente a foto que acabou de ser enviada: marca a URL para não baixar de novo.
        if avatar_store != null and not String(url).is_empty() and avatar_store.has_local(avatar_key()): avatar_store.set_cached_url(avatar_key(), String(url))
        _avatar_message("Foto enviada para a sua conta." if not String(url).is_empty() else "Foto removida da conta.", false)
        _refresh_avatars())
    acc.avatar_failed.connect(func(_code, msg):
        _avatar_message("A foto ficou salva neste aparelho, mas a conta não a recebeu: " + msg, true))
    acc.entitlements_changed.connect(func(data): if entitlements != null: entitlements.apply_server(data))
    # R31: identidade (avatar, ícone, título, moldura) sincronizada com a conta — agrupa mudanças em 1,2 s.
    _cosmetics_timer = Timer.new()
    _cosmetics_timer.name = "CosmeticsSync"
    _cosmetics_timer.one_shot = true
    _cosmetics_timer.wait_time = 1.2
    add_child(_cosmetics_timer)
    _cosmetics_timer.timeout.connect(_push_cosmetics)
    cosmetics_changed.connect(func(): if account != null and account.has_profile(): _cosmetics_timer.start())
    if entitlements != null: entitlements.changed.connect(func(): if _cosmetics_differ(): _cosmetics_timer.start())
    acc.cosmetics_state.connect(_on_server_cosmetics)
    acc.cosmetics_failed.connect(func(code, _msg, field):
        _last_pushed = {}
        if code == "rate_limited": _cosmetics_timer.start()
        elif field == "avatar_id" and not _cosmetics_skip_avatar:
            _cosmetics_skip_avatar = true   # avatar recusado (ex.: escada sem tabela no servidor): manda o resto
            _cosmetics_timer.start())
    _on_account_changed()

var _cosmetics_timer: Timer
var _cosmetics_skip_avatar := false
var _cosmetics_adopted := {}   # contas cuja escolha do servidor já foi aplicada nesta sessão
var _last_pushed := {}
var _server_look := {}         # último {avatar_id, badge, title, frame} informado pelo servidor

func _cosmetics_differ() -> bool:
    if account == null or not account.has_profile() or _server_look.is_empty(): return false
    var mine := public_cosmetics()
    for k in mine:
        if k == "avatar_id" and _cosmetics_skip_avatar: continue
        if String(mine[k]) != String(_server_look.get(k, "")): return true
    return false

func _push_cosmetics():
    if account == null or not account.has_profile(): return
    if not _server_look.is_empty() and not _cosmetics_differ(): return
    var data := public_cosmetics()
    if _cosmetics_skip_avatar: data.erase("avatar_id")
    if data == _last_pushed: return   # mesmo pedido já enviado (ex.: servidor sem a 0007 guarda só o avatar)
    _last_pushed = data
    account.set_cosmetics(data)

const COSMETICS_SYNC := "user://cosmetics_sync.cfg"
## 1º login desta conta NESTE aparelho: a escolha local vai para a conta (preserva o avatar de antes).
## Logins seguintes: a escolha da conta vem para o aparelho (troca feita em outro aparelho).
func _on_server_cosmetics(data: Dictionary):
    if account == null: return
    _server_look = data.duplicate()
    var uid := String(account.user_id)
    if uid.is_empty() or _cosmetics_adopted.has(uid): return
    _cosmetics_adopted[uid] = true
    var cfg := ConfigFile.new()
    cfg.load(COSMETICS_SYNC)
    if not bool(cfg.get_value("synced", uid, false)):
        cfg.set_value("synced", uid, true)
        cfg.save(COSMETICS_SYNC)
        if is_instance_valid(_cosmetics_timer): _cosmetics_timer.start()
        return
    var av := String(data.get("avatar_id", ""))
    if av in AvatarCatalog.ids() and AvatarCatalog.has_art(av): avatar_id = av
    if not String(data.get("badge", "")).is_empty(): badge_pref = String(data.badge)
    if not String(data.get("title", "")).is_empty(): title_pref = String(data.title)
    if String(data.get("frame", "liga")) != "liga": frame_pref = String(data.frame)
    _save_preferences()
    refresh_club()

var _server_avatar_url := ""   # última URL informada pelo servidor nesta sessão (por conta)
var _avatar_resent := {}       # contas para as quais a foto local já foi reenviada nesta sessão

func _on_account_changed():
    _refresh_name_boxes()
    # Foto da conta ainda não está no cache local → baixa da URL pública.
    if account != null and account.has_profile() and avatar_store != null:
        var url: String = account.avatar_url()
        if avatar_store.needs_fetch(avatar_key(), url): avatar_store.fetch(avatar_key(), url)
        elif url.is_empty() and not _server_avatar_url.is_empty() and avatar_store.has_local(avatar_key()) and avatar_key() != "local":
            avatar_store.clear_local(avatar_key())   # a conta TINHA foto e ela foi removida em outro aparelho
        elif url.is_empty() and avatar_store.has_local(avatar_key()) and avatar_key() != "local" and not _avatar_resent.has(avatar_key()) and account.server_ready:
            # A conta não tem foto mas este aparelho tem: reenvia uma vez (upload anterior pode ter falhado).
            _avatar_resent[avatar_key()] = true
            var local_bytes := FileAccess.get_file_as_bytes(avatar_store.local_path(avatar_key()))
            if not local_bytes.is_empty(): account.upload_avatar(local_bytes)
        _server_avatar_url = url
    _refresh_avatars()

func _refresh_name_boxes():
    var logged: bool = account != null and account.has_profile()
    if is_instance_valid(local_name_box): local_name_box.visible = not logged
    if nickname_editor != null and nickname_editor.account != null: nickname_editor.refresh()

func pick_photo():
    if image_picker == null:
        image_picker = load("res://profile/image_picker.gd").new()
        image_picker.name = "ImagePicker"
        add_child(image_picker)
        image_picker.picked.connect(_on_photo_picked)
        image_picker.failed.connect(func(msg): _avatar_message(msg, true))
    if avatar_editor == null:
        avatar_editor = load("res://profile/avatar_editor.gd").new()
        add_child(avatar_editor)
        avatar_editor.saved.connect(_on_photo_saved)
    image_picker.open()

func _on_photo_picked(bytes: PackedByteArray, _filename: String):
    var err: String = avatar_editor.open_with(bytes)
    if not err.is_empty(): _avatar_message(err, true)

func _on_photo_saved(image: Image, bytes: PackedByteArray):
    avatar_store.save_local(avatar_key(), image)
    _refresh_avatars()
    if account != null and account.has_profile():
        if account.upload_avatar(bytes): _avatar_message("Foto salva. Enviando para a sua conta…", false)
        else: _avatar_message("Foto salva neste aparelho. Conecte-se para enviá-la à conta.", false)
    else:
        _avatar_message("Foto salva neste aparelho. Entre na conta para usá-la em todo lugar.", false)

func remove_custom_avatar():
    avatar_store.clear_local(avatar_key())
    if account != null and account.has_profile(): account.clear_avatar()
    _refresh_avatars()
    _avatar_message("Foto removida. Avatar padrão de volta.", false)

func _avatar_message(text: String, is_error: bool):
    if is_instance_valid(avatar_note):
        avatar_note.text = text
        avatar_note.add_theme_color_override("font_color", Color("ff9d86") if is_error else MUTED)
    if is_instance_valid(mobile_ui) and mobile_ui.has_method("avatar_message"): mobile_ui.avatar_message(text, is_error)
