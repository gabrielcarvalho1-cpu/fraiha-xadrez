extends CanvasLayer
## One proportional composition; artwork stays untouched and text remains live.
signal play_local_requested
signal play_online_requested
signal play_bot_requested(difficulty: String, side: String)
signal theme_preview_requested(theme_id: String)
signal piece_set_requested(theme_id: String)
signal quit_requested

const DESIGN = Vector2(1672, 941)
const FOREST = preload("res://ui_v022/assets/home_forest.png")
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
var league_profile = LocalProfile.new()
var selected_league := "madeira"
var league_buttons := {}
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
var volume := 0.8
var fullscreen := false
var volume_label: Label
var display_label: Label

func _ready():
    layer = 30
    _load_preferences()
    league_profile.load_profile()
    _build()
    get_viewport().size_changed.connect(_layout)
    _layout()
    show_page("main")
    AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
    AudioServer.set_bus_mute(0, volume <= 0.0)
    if fullscreen:
        get_window().set_deferred("mode", Window.MODE_FULLSCREEN)

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
    frame.texture = _slice(FOREST, Rect2(596, 318, 482, 550))
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
    margin.add_theme_constant_override("margin_top", 7)
    margin.add_theme_constant_override("margin_bottom", 7)
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
    var backdrop = ColorRect.new()
    backdrop.name = "DeepForestBackdrop"
    backdrop.color = Color("061b15")
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(backdrop)
    canvas = Control.new()
    canvas.name = "ReferenceComposition"
    canvas.size = DESIGN
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(canvas)
    var art = TextureRect.new()
    art.name = "ForestArtwork"
    art.texture = FOREST
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
    var titles = ["JOGAR LOCAL", "JOGAR CONTRA O BOT", "JOGAR ONLINE", "LIGAS E RANKING", "CONFIGURAÇÕES", "CONHEÇA O FRAIHA", "SAIR"]
    var subtitles = ["Duas pessoas no mesmo computador", "Treine e evolua seu jogo", "Crie ou entre em uma sala", "Acompanhe seu progresso", "Áudio, vídeo e preferências", "Sobre o projeto", "Até a próxima partida!"]
    var actions = [func(): play_local_requested.emit(), func(): show_page("bot"), func(): play_online_requested.emit(), func(): show_page("ranking"), func(): show_page("settings"), func(): show_page("about"), func(): quit_requested.emit()]
    for i in range(7):
        menu_buttons.append(_button(main, i, titles[i], subtitles[i], Vector2(611,341+i*73), actions[i]))
    _build_profile()
    _build_pages()
    var version_bg = ColorRect.new()
    version_bg.color = Color("09110de0")
    version_bg.size = Vector2(266,30)
    version_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(version_bg)
    _label(_stack(canvas, Vector2(7,4), Vector2(250,24)), "FRAIHA Xadrez V0.24 · TESTE", 16)
    var footer = ColorRect.new()
    footer.color = Color("06100ce6")
    footer.position = Vector2(0,867)
    footer.size = Vector2(385,74)
    footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(footer)
    var crown = TextureRect.new()
    crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    crown.texture = _slice(FOREST, Rect2(748,7,153,89))
    crown.position = Vector2(19,882)
    crown.size = Vector2(43,45)
    crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(crown)
    var footer_text = _stack(canvas, Vector2(82,877), Vector2(291,55))
    _label(footer_text, "FRAIHA XADREZ", 18)
    _label(footer_text, "Feito por jogadores, para jogadores.", 14, MUTED)
    var signature = _label(_stack(canvas, Vector2(1342,879), Vector2(307,50)), "Versão 0.24 · Ligas e temas\nMaringá · PR · Brasil", 15)
    signature.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    signature.add_theme_constant_override("outline_size", 4)
    signature.add_theme_color_override("font_outline_color", Color("09110dee"))

func _build_profile():
    _frame(canvas, Vector2(1254,24), Vector2(396,178))
    var profile = _stack(canvas, Vector2(1254,24), Vector2(396,178), Vector4(18,13,18,13), 4)
    profile_button = TextureButton.new()
    profile_button.name = "ProfileButton"
    profile_button.custom_minimum_size = Vector2(0,106)
    profile_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    profile_button.focus_mode = Control.FOCUS_ALL
    profile.add_child(profile_button)
    var portrait = TextureRect.new()
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    portrait.texture = AVATAR
    portrait.position = Vector2(0,2)
    portrait.size = Vector2(88,88)
    portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    profile_button.add_child(portrait)
    var words = _stack(profile_button, Vector2(94,0), Vector2(266,106), Vector4.ZERO, 2)
    profile_name = _label(words, player_name, 20)
    var current = LeagueCatalog.entry(league_profile.data.current_league,league_profile.data)
    _label(words, "%s · %d / 100 PL" % [current.display_name,league_profile.data.lp], 14, GOLD)
    _progress(words,league_profile.data.lp,8)
    _label(words, "Perfil local · progressão em preparação", 11, MUTED)
    profile_button.pressed.connect(func(): show_page("profile"))
    profile_button.mouse_entered.connect(func(): profile_name.modulate = GOLD)
    profile_button.mouse_exited.connect(func(): profile_name.modulate = Color.WHITE)
    var quote = _label(profile, "“O xadrez é a ginástica da inteligência.”\n— Blaise Pascal", 13)
    quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

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
    _build_ranking()
    var about = _new_page("about", "FRAIHA XADREZ", "ESTRATÉGIA PARA IR MAIS LONGE")
    _body(about, "Um tabuleiro, muitas histórias.\n\nFRAIHA Xadrez combina o jogo clássico com um mundo em pixel art. Planeje, aprenda e compartilhe boas partidas.\n\nFeito por jogadores, para jogadores.\nMaringá · Paraná · Brasil")
    var profile = _new_page("profile", "SEU LUGAR NO TABULEIRO", "PERFIL DO JOGADOR")
    _body(profile, "Escolha como quer aparecer nesta Home. O nome fica salvo neste computador. Contas e estatísticas online virão depois.")
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
    _label(profile, "O perfil desta build é independente do jogo atual.", 16, GOLD)
    var settings = _new_page("settings", "DO SEU JEITO", "CONFIGURAÇÕES")
    volume_label = _label(settings, "", 19, GOLD)
    var slider = HSlider.new()
    slider.name = "MasterVolume"
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
        var status = _label(content,"DISPONÍVEL" if entry.unlocked else "BLOQUEADA",10,MUTED)
        status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
    _button(panel,6,"VOLTAR À HOME","ESC também volta",Vector2(35,548),back,Vector2(410,64))
    _button(panel,0,"PEÇAS CLÁSSICAS","Usar o conjunto original",Vector2(483,548),func(): piece_set_requested.emit("classic"),Vector2(390,64))
    var note = _label(panel,"Prévia local. Sem partidas ranqueadas, ganho de PL ou desbloqueios automáticos nesta build.",14,MUTED)
    note.position = Vector2(895,568)
    note.size = Vector2(510,44)

func _select_league(id: String):
    selected_league = id
    var entry = LeagueCatalog.entry(id,league_profile.data)
    league_detail_title.text = "LIGA " + entry.display_name.to_upper() + "  ·  0–100 PL"
    league_detail_badge.texture = ThemeCatalog.badge_texture(id)
    var theme: String = entry.environment_theme
    var available = id in ["madeira","ferro"]
    var description = "Floresta, equilíbrio e o começo da sua jornada.\nRecompensas: cenário natural, tabuleiro e peças de madeira." if id == "madeira" else "Fortaleza, montanhas e forjas.\nRecompensas: arena de pedra, tabuleiro de aço e peças de ferro."
    if not available: description = "Recompensas visuais em desenvolvimento.\nSeu emblema já faz parte da jornada."
    league_details.text = ("Disponível" if entry.unlocked else "Bloqueada")+"\n"+description+"\n\nPL e progressão competitiva ainda não são atribuídos."
    var textures = ThemeCatalog.piece_textures(theme) if available else {}
    league_scene_preview.texture = ThemeCatalog.texture(ThemeCatalog.get_theme(theme).arena_path) if available else null
    for i in range(league_preview_pieces.size()):
        league_preview_pieces[i].texture = textures.get("w"+ThemeCatalog.PIECE_ORDER[i])
    preview_caption.text = "CENÁRIO E PEÇAS · "+entry.display_name.to_upper() if available else "VISUAIS EM DESENVOLVIMENTO"
    league_preview_button.visible = available
    for key in league_buttons:
        league_buttons[key].modulate = Color.WHITE if key == id else Color(0.78,0.82,0.79)

func _preview_league():
    if selected_league not in ["madeira","ferro"]: return
    theme_preview_requested.emit(LeagueCatalog.theme_for(selected_league))
    open_home()

func _layout():
    var dimensions = get_viewport().get_visible_rect().size
    var factor = maxf(dimensions.x / DESIGN.x, dimensions.y / DESIGN.y)
    # All elements share this transform. If cover would cut a control, preserve
    # the complete composition over one solid deep-green surround instead.
    var origin = (dimensions - DESIGN * factor) / 2.0
    var safe = Rect2(origin + Vector2(6,4) * factor, Vector2(1644,925) * factor)
    if not Rect2(Vector2.ZERO, dimensions).encloses(safe):
        factor = minf(dimensions.x / DESIGN.x, dimensions.y / DESIGN.y)
    canvas.scale = Vector2.ONE * factor
    canvas.position = (dimensions - DESIGN*factor) / 2.0

func show_page(id: String):
    if not pages.has(id): return
    page = id
    for key in pages:
        pages[key].visible = key == id
    if page_scrolls.has(id): page_scrolls[id].scroll_vertical = 0
    if is_instance_valid(display_label): _refresh_display_label()
    if id == "ranking": _select_league(selected_league)

func apply_theme(texture: Texture2D):
    if texture != null:
        canvas.get_node("ForestArtwork").texture = texture

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
    AudioServer.set_bus_volume_db(0,linear_to_db(maxf(volume,0.0001)))
    AudioServer.set_bus_mute(0, volume <= 0.0)
    volume_label.text = "VOLUME GERAL  ·  %d%%" % round(value)
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
    volume = clampf(float(config.get_value("audio","volume",0.8)),0,1)
    fullscreen = bool(config.get_value("video","fullscreen",false))

func _save_preferences():
    var config = ConfigFile.new()
    config.set_value("profile","name",player_name)
    config.set_value("audio","volume",volume)
    config.set_value("video","fullscreen",fullscreen)
    config.save(PREFS)
