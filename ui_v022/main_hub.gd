extends CanvasLayer
## Reference-led artwork, individually sliced interactive sprites, live text.
signal play_local_requested
signal play_online_requested
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
var root: Control
var canvas: Control
var pages := {}
var page := "main"
var menu_buttons: Array[TextureButton] = []
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

func _text(parent: Node, value: String, pos: Vector2, box: Vector2, font_size: int, color: Color = CREAM) -> Label:
    var label = Label.new()
    label.text = value
    label.position = pos
    label.size = box
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0,0,0,0.9))
    label.add_theme_constant_override("shadow_offset_y", 1)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

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
    button.ignore_texture_size = true
    button.stretch_mode = TextureButton.STRETCH_SCALE
    button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    button.position = pos
    button.size = dimensions
    button.focus_mode = Control.FOCUS_ALL
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    button.tooltip_text = title
    button.name = "MenuButton" + str(row)
    parent.add_child(button)
    var title_label = _text(button, title, Vector2(105,11), Vector2(dimensions.x-150,23), 18)
    title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _text(button, subtitle, Vector2(105,35), Vector2(dimensions.x-150,21), 15, MUTED)
    button.pressed.connect(callback)
    button.mouse_entered.connect(func(): _highlight(button, true))
    button.mouse_exited.connect(func(): _highlight(button, button.has_focus()))
    button.focus_entered.connect(func(): _highlight(button, true))
    button.focus_exited.connect(func(): _highlight(button, false))
    button.button_down.connect(func(): button.self_modulate = Color(0.78,0.85,0.74))
    button.button_up.connect(func(): _highlight(button, true))
    return button

func _highlight(button: TextureButton, active: bool):
    button.self_modulate = Color(1.22,1.24,1.12) if active else Color.WHITE

func _build():
    root = Control.new()
    root.name = "HomeRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    var backdrop = TextureRect.new()
    backdrop.texture = FOREST
    backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(backdrop)
    canvas = Control.new()
    canvas.name = "ReferenceComposition"
    canvas.size = DESIGN
    canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(canvas)
    # Keep artwork and controls in one design coordinate system on every aspect.
    var art = TextureRect.new()
    art.texture = FOREST
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
    version_bg.size = Vector2(246,30)
    version_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(version_bg)
    _text(canvas, "FRAIHA Xadrez V0.22 · TESTE", Vector2(7,4), Vector2(235,23), 16)
    var footer = ColorRect.new()
    footer.color = Color("06100ce6")
    footer.position = Vector2(0,867)
    footer.size = Vector2(370,74)
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
    _text(canvas, "FRAIHA XADREZ", Vector2(82,879), Vector2(268,25), 18)
    _text(canvas, "Feito por jogadores, para jogadores.", Vector2(82,907), Vector2(280,22), 15, MUTED)
    var signature = _text(canvas, "Versão 0.22 · Home de teste\nMaringá · PR · Brasil", Vector2(1342,879), Vector2(307,48), 15)
    signature.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    signature.add_theme_constant_override("outline_size", 4)
    signature.add_theme_color_override("font_outline_color", Color("09110dee"))

func _build_profile():
    _frame(canvas, Vector2(1254,24), Vector2(396,178))
    profile_button = TextureButton.new()
    profile_button.name = "ProfileButton"
    profile_button.position = Vector2(1269,38)
    profile_button.size = Vector2(365,90)
    profile_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    profile_button.focus_mode = Control.FOCUS_ALL
    canvas.add_child(profile_button)
    var portrait = TextureRect.new()
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    portrait.texture = AVATAR
    portrait.position = Vector2(0,-5)
    portrait.size = Vector2(88,88)
    portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    profile_button.add_child(portrait)
    profile_name = _text(profile_button, player_name, Vector2(90,4), Vector2(230,32), 24)
    _text(profile_button, "Perfil local", Vector2(90,40), Vector2(220,23), 16, GOLD)
    _text(profile_button, "Ligas e histórico em preparação", Vector2(90,65), Vector2(255,20), 14, MUTED)
    profile_button.pressed.connect(func(): show_page("profile"))
    profile_button.mouse_entered.connect(func(): profile_name.modulate = GOLD)
    profile_button.mouse_exited.connect(func(): profile_name.modulate = Color.WHITE)
    var quote = _text(canvas, "“O xadrez é a ginástica da inteligência.”\n— Blaise Pascal", Vector2(1278,145), Vector2(345,45), 15)
    quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _new_page(id: String, title: String, eyebrow: String) -> Control:
    var panel = Control.new()
    panel.name = id.capitalize() + "Page"
    panel.position = Vector2(611,341)
    panel.size = Vector2(450,505)
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    canvas.add_child(panel)
    # The environmental art already supplies the ornate outer frame.
    _text(panel, eyebrow, Vector2(27,20), Vector2(396,24), 13, GOLD)
    _text(panel, title, Vector2(27,55), Vector2(400,40), 26)
    _button(panel, 6, "VOLTAR À HOME", "ESC também volta", Vector2(0,439), func(): show_page("main"))
    pages[id] = panel
    return panel

func _body(parent: Control, value: String, y: float, height: float = 190):
    var l = _text(parent, value, Vector2(27,y), Vector2(394,height), 19, MUTED)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_constant_override("line_spacing", 6)
    return l

func _build_pages():
    var bot = _new_page("bot", "SEU PRÓXIMO DESAFIO", "JOGAR CONTRA O BOT")
    _body(bot, "O modo de treino está em preparação.\n\nNesta versão, você já pode jogar com outra pessoa no mesmo computador ou encontrar um amigo online.", 119)
    _button(bot, 0, "JOGAR LOCAL", "Comece uma partida a dois", Vector2(0,343), func(): play_local_requested.emit())
    var ranking = _new_page("ranking", "CADA JOGADA CONTA", "LIGAS E RANKING")
    _body(ranking, "As ligas e o ranking chegarão em uma próxima etapa.\n\nEsta build não calcula elo, vitórias ou posições competitivas. Aproveite as partidas casuais e conheça a nova Home.", 119, 235)
    var about = _new_page("about", "FRAIHA XADREZ", "ESTRATÉGIA PARA IR MAIS LONGE")
    _body(about, "Um tabuleiro, muitas histórias.\n\nFRAIHA Xadrez combina o jogo clássico com um mundo em pixel art. Planeje, aprenda e compartilhe boas partidas.\n\nFeito por jogadores, para jogadores.\nMaringá · Paraná · Brasil", 116, 285)
    var profile = _new_page("profile", "SEU LUGAR NO TABULEIRO", "PERFIL DO JOGADOR")
    _body(profile, "Escolha como quer aparecer nesta Home. O nome fica salvo neste computador. Contas e estatísticas online virão depois.", 114, 135)
    var name_input = LineEdit.new()
    name_input.name = "PlayerName"
    name_input.position = Vector2(27,268)
    name_input.size = Vector2(396,48)
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
    _text(profile, "O perfil desta build é independente do jogo atual.", Vector2(27,338), Vector2(396,52), 16, GOLD).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var settings = _new_page("settings", "DO SEU JEITO", "CONFIGURAÇÕES")
    volume_label = _text(settings, "", Vector2(27,122), Vector2(396,28),20,GOLD)
    var slider = HSlider.new()
    slider.name = "MasterVolume"
    slider.position = Vector2(27,169)
    slider.size = Vector2(394,35)
    slider.min_value = 0
    slider.max_value = 100
    slider.step = 1
    slider.value = round(volume*100)
    settings.add_child(slider)
    slider.value_changed.connect(_set_volume)
    _set_volume(slider.value, false)
    _button(settings, 1, "TELA CHEIA", "Alternar janela / tela cheia", Vector2(0,244), _toggle_fullscreen)
    display_label = _text(settings, "", Vector2(27,329), Vector2(396,30),17,MUTED)
    _text(settings, "As preferências são salvas automaticamente.\nAlt + Enter também alterna a tela.", Vector2(27,373), Vector2(396,52),16,MUTED)
    _refresh_display_label()

func _layout():
    var dimensions = get_viewport().get_visible_rect().size
    var factor = minf(dimensions.x / DESIGN.x, dimensions.y / DESIGN.y)
    canvas.scale = Vector2.ONE * factor
    canvas.position = (dimensions - DESIGN*factor) / 2.0

func show_page(id: String):
    if not pages.has(id): return
    page = id
    for key in pages:
        pages[key].visible = key == id
    if is_instance_valid(display_label): _refresh_display_label()

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
