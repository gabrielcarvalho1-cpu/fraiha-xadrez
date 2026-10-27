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
signal peer_avatar_ready(uid: String)   # R150 · chegou a foto de outro jogador (amigo, mesa, adversário)
signal cosmetics_changed   # R31: ícone/título/moldura/avatar mudaram (a conta sincroniza com o servidor)

const BoardColors = preload("res://cosmetics/board_colors.gd")   # R139
const ConteudoExtra = preload("res://web_content/conteudo_extra.gd")   # R137
const DESIGN = Vector2(1672, 941)
const FRAME_MARGIN = 0.0
const EDGE_CROP = 1.035
const APP_VERSION = "0.38"
# Home oficial (Fase 8.2): mesma composição com painéis, conta, versão e Ranqueado já desenhados na arte.
## R89 · as artes da Home do PC (≈30 MB de textura) não são mais constantes: no celular em pé elas nem são
## carregadas (e são soltas quando a Home deitada sai da tela). Os nomes continuam os mesmos para o resto do código.
const FOREST_PATH := "res://ui_v022/assets/home_forest_v9.png"
const FOREST_WIDE_PATH := "res://ui_v022/assets/home_forest_v9_wide.png"
const FOREST_LEGACY_PATH := "res://ui_v022/assets/home_forest.png"
const BUTTON_ATLAS_PATH := "res://ui_v022/assets/menu_atlas.png"
var _desk_tex := {}
func _desk(path: String) -> Texture2D:
    if not _desk_tex.has(path): _desk_tex[path] = load(path)
    return _desk_tex[path]
var FOREST: Texture2D:
    get: return _desk(FOREST_PATH)   # R64: botões do menu (ícones e textos) da nova referência do dono (tools/home_ref_v9.py)
#   # R47: arte de REFERÊNCIA do dono (tools/home_ref_v8.py): menu em 3 linhas grandes + grade 2×3 + CONFIGURAÇÕES/SAIR; só o que é vivo foi apagado   # R36: arte de REFERÊNCIA aprovada pelo dono (tools/home_ref_v7.py): menu com pilares e tochas, 11 linhas com textos; só o que é vivo foi apagado
## R32 · linhas do menu na arte v3 (y, altura da moldura) — saída de tools/home_menu_10rows.py
## R36 · linhas do menu na arte v7 (y da borda dourada de cima, altura até a de baixo) — medidas na referência
# R43: menu da arte em 92% (tools/home_r43_art.py): x' = 554 + (x-530)*0,92 ; y' = 292 + (y-288)*0,92
const MENU_ROWS := [Vector2(325.1, 42.8), Vector2(372.0, 42.8), Vector2(420.3, 50.6), Vector2(478.8, 42.8), Vector2(524.8, 42.8), Vector2(571.7, 42.3), Vector2(617.7, 42.8), Vector2(663.7, 42.8), Vector2(710.6, 41.9), Vector2(756.6, 41.9), Vector2(801.7, 41.9)]
const MENU_X := 621.16      # borda esquerda das linhas na arte v7 (R43: menu 92%)
const MENU_W := 420.44      # até a borda direita (R43: menu 92%)
const MENU_SCALE := 0.74   # R35: escala das linhas (o conteúdo encolhe por igual a partir de x=628)
const MENU_TEXT_X := 705.8  # onde começam os textos das linhas na arte v7 (R43: menu 92%)
## R47 · Home da referência do dono (arte v8). Mesma ordem de botões de sempre (títulos/ações abaixo);
## cada um ganha o retângulo do botão DESENHADO na arte e os textos no lugar/medida da referência.
## Textos: [título, Rect2(x, topo das maiúsculas, largura da tinta, altura das maiúsculas), fonte] e,
## nas 3 linhas grandes, o subtítulo [texto, Rect2(x, topo, largura, 0)].
## R64 · botões da arte v9 (medidos na referência do dono). Os TEXTOS dos botões estão na arte, iguais à referência.
const PC_MENU := [Rect2(607,339,435,71), Rect2(607,417,435,68), Rect2(605,491,440,71), Rect2(601,662,218,59), Rect2(601,598,218,56), Rect2(830,598,217,56), Rect2(601,729,218,61), Rect2(603,803,216,59), Rect2(830,729,217,61), Rect2(830,662,217,59), Rect2(830,803,212,59)]
const REF_TEXT_IN_ART := true
const PC_TITLE := [Rect2(699,358,296,15), Rect2(700,431,149,15), Rect2(707,505,232,19), Rect2(661,678,120,13), Rect2(661,618,97,13), Rect2(899,619,46,13), Rect2(671,742,55,13), Rect2(674,824,114,13), Rect2(899,742,131,13), Rect2(899,678,133,13), Rect2(903,824,32,13)]
const PC_SUB := {0: ["Treine e evolua seu jogo", Rect2(700,381,184,0)], 1: ["Partida casual · fila automática", Rect2(702,455,220,0)], 2: ["Compita e conquiste seu lugar", Rect2(707,532,239,0)]}
const PC_COVER := Rect2(598,322,452,548)   # miolo do menu entre os pilares (páginas internas)
var FOREST_V2: Texture2D:
    get: return _desk(FOREST_PATH)
var FOREST_WIDE: Texture2D:
    get: return _desk(FOREST_WIDE_PATH)   # R64   # R43: laterais completadas (tools/home_wide_r43.py)
const WIDE_PAD := 84.0
const FOREST_SIDE_L := "res://ui_v022/assets/home_forest_v9_side_l.png"   # R152 · 360 px de folhagem + 90 px de emenda
const FOREST_SIDE_R := "res://ui_v022/assets/home_forest_v9_side_r.png"
const SIDE_OVERLAP := 90.0
# Arte anterior: continua sendo a fonte das molduras das páginas internas (_frame) e dos temas que a usam.
var FOREST_LEGACY: Texture2D:
    get: return _desk(FOREST_LEGACY_PATH)
var BUTTON_ATLAS: Texture2D:
    get: return _desk(BUTTON_ATLAS_PATH)
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
var about_body: RichTextLabel   # R142 · rich: MODOS DE JOGO com tópicos (XADREZ · XEQUE · MARCHA REAL) em dourado
var volume := 0.8
var music_volume := 0.65
var premove_enabled := true
var premove_button: BaseButton
var premium = null   # FRAIHA PREMIUM (Monetização V1, simulação)
var monetization_state = null   # flags dev_mock_* (simulação)
var entitlements = null         # direitos (servidor + simulação) — única leitura para a interface
var avatar_gallery = null       # profile/avatar_gallery.gd (página Perfil, PC)
var avatar_detail := {}         # área de detalhe do avatar em foco
var gallery_count: Label
var inspected_avatar := ""
var inspected_badge := "auto"   # R32: ícone em foco na aba ÍCONES do Perfil
var profile_tab := "avatars"    # "avatars" | "icons" | "frames" | "emotes"
var badge_gallery = null        # profile/badge_gallery.gd
var frame_gallery = null        # R168 · profile/frame_gallery.gd (aba MOLDURAS)
var emote_gallery = null        # R176.8 · profile/emote_gallery.gd (aba EMOTES)
var title_gallery = null        # R176.9 · profile/title_gallery.gd (aba TÍTULOS)
var inspected_title := "auto"
var inspected_emote := ""
var inspected_frame := ""
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
var trophy_button: Button        # R96 · RANKING
var gchat_button: Button         # R96 · CHAT GLOBAL
var leaderboard_ui
var ranking_art     # R198
var legal_ui                      # R97 · TERMOS E PRIVACIDADE / EXCLUIR CONTA
var global_chat_ui
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
    # R185 · MÚSICA/EFEITOS mudos e volumes salvos valem desde a abertura do jogo (antes só eram aplicados ao montar a
    # tela de CONFIGURAÇÕES: o botão mostrava "Música: NÃO" e a música tocava mesmo assim)
    var mb := AudioServer.get_bus_index("Music")
    AudioServer.set_bus_volume_db(mb, linear_to_db(maxf(music_volume, 0.0001)))
    AudioServer.set_bus_mute(mb, music_volume <= 0.0 or music_muted)
    var eb := AudioServer.get_bus_index("Effects")
    AudioServer.set_bus_volume_db(eb, linear_to_db(maxf(volume, 0.0001)))
    AudioServer.set_bus_mute(eb, volume <= 0.0 or effects_muted)
    league_profile.load_profile()
    ranked.load_local()
    avatar_store = load("res://profile/avatar_store.gd").new()
    avatar_store.name = "AvatarStore"
    add_child(avatar_store)
    avatar_store.texture_ready.connect(func(k):
        if String(k).begins_with(PEER_PREFIX):   # R150 · foto de OUTRO jogador: só avisa quem está mostrando
            peer_avatar_ready.emit(String(k).substr(PEER_PREFIX.length()))
            return
        _focus_current_look()   # R54 · foto chegou da conta: o detalhe do Perfil mostra a foto
        _refresh_avatars())
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

## R89 · recortes das artes do PC (molduras, botões, brilho dos botões): lembrados para soltar/voltar a arte
var _desk_atlases := {}       # AtlasTexture -> caminho da arte
var desk_art_awake := true
func _track_desk(t: AtlasTexture, texture: Texture2D):
    if texture != null and texture.resource_path in [FOREST_PATH, FOREST_WIDE_PATH, FOREST_LEGACY_PATH, BUTTON_ATLAS_PATH]:
        _desk_atlases[t] = texture.resource_path

## R89 · celular: solta as artes da Home do PC quando ela não está na tela (em pé, páginas, partidas) e
## carrega de novo quando a Home deitada aparece. No PC fica sempre acordada.
## R154 · celular deitado: a moldura nova do cartão de perfil (a do PC) também — sem ela aparecia o cartão
## antigo da arte, com a barrinha num lugar e "Madeira · 0/100 PL" escrito em cima dela. Só com a Home deitada na tela.
func _mobile_profile_frame():
    if not is_instance_valid(canvas) or not preload("res://ui_v022/mobile_layout.gd").active(get_viewport()): return
    var pb = canvas.get_node_or_null("RefProfileButton")
    if pb == null: return
    var fr = pb.get_node_or_null("RefProfileFrame")
    var un = pb.get_node_or_null("RefProfileUnder")
    var on: bool = desk_art_awake
    if fr != null and (fr.texture != null) != on: fr.texture = load(PROFILE_FRAME_PATH) if on else null
    if un != null and (un.texture != null) != on: un.texture = load(PROFILE_UNDER_PATH) if on else null

func set_desk_art(on: bool):
    if on == desk_art_awake: return
    desk_art_awake = on
    var art = canvas.get_node_or_null("ForestArtwork") if is_instance_valid(canvas) else null
    if not on:
        if art != null: art.texture = null
        for t in _desk_atlases: (t as AtlasTexture).atlas = null
        _desk_tex.clear()
    else:
        for t in _desk_atlases: (t as AtlasTexture).atlas = _desk(String(_desk_atlases[t]))
        if art != null: art.texture = _desk_theme_tex if _desk_theme_tex != null else FOREST
    _mobile_profile_frame()
    if is_instance_valid(presentation_frame): presentation_frame.queue_redraw()
    var fx = canvas.get_node_or_null("HomeFx") if is_instance_valid(canvas) else null
    if fx != null and fx.has_method("set_awake"): fx.set_awake(on)
var _desk_theme_tex: Texture2D = null

func _slice(texture: Texture2D, region: Rect2) -> AtlasTexture:
    var t = AtlasTexture.new()
    _track_desk(t, texture)
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
    button.set_meta("subtitle", subtitle)
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
    presentation_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # R64: laterais sem serrilhado
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
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # R64: botões/textos da arte sem serrilhado em qualquer escala
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_SCALE
    art.size = DESIGN
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(art)
    # R36: a arte de referência já traz o gato, os viajantes, a placa da conta etc. — sem camada de detalhes
    # nem recorte da placa por cima (eles eram da arte v2/v6 e ficariam fora do lugar).
    # Espírito das águas sobre o lago (abaixo da cachoeira, à esquerda da placa), animado.
    var spirit = preload("res://ui_v022/water_spirit.gd").new()
    spirit.position = Vector2(1258, 642)
    spirit.size = Vector2(112, 112)
    # R44 · tochas, água, passarinhos e o rabinho da gatinha (por baixo do espírito e dos painéis)
    var fx = preload("res://ui_v022/home_fx.gd").new()
    # R197 · folhas balançando e névoa da cachoeira também no PC
    fx.leaf_rects = [Rect2(0, 0, 620, 140), Rect2(430, 100, 170, 600), Rect2(1040, 0, 632, 330), Rect2(1080, 560, 592, 381), Rect2(0, 380, 130, 320)]
    fx.mists = [[Vector2(1410, 520), 60.0], [Vector2(1190, 650), 50.0], [Vector2(1230, 690), 50.0], [Vector2(1350, 590), 30.0]]
    canvas.add_child(fx)
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
        var item = _button(main, icons[i], titles[i], subtitles[i], Vector2(MENU_X, row.x), actions[i], Vector2(MENU_W, row.y))
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
    desk_league_label = _label(words, "%s · %d / 100 PL" % [current.display_name,league_profile.data.lp], 14, GOLD)
    desk_league_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _progress(words,league_profile.data.lp,8)
    desk_league_bar = words.get_child(words.get_child_count() - 1)
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
func _ornate_panel(parent: Node, pos: Vector2, dimensions: Vector2, fill := Color(0.061, 0.084, 0.132,0.95)) -> Control:
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
        icon.draw_circle(c, 21.0, Color("1c2435"))
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
    under.bg_color = Color("111725")
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
    _build_side_art()
    _build_ranked()
    _build_ranking()
    _build_about_page()
    _build_history_page()
    # R52b · PERFIL DO JOGADOR: painel/modal próprio na referência nova (ui_kit/pages/perfil_bg.png, 1774 x 887),
    # centralizado por cima da Home escurecida (fade em show_page). Abas, cartões, detalhe, nome, estatísticas
    # e textos são do jogo; molduras, barra de rolagem e os 3 botões de baixo são da arte.
    var profile_panel := RefPage.modal(canvas, "perfil_bg", PROFILE_REF, DESIGN)
    profile_panel.name = "ProfilePage"
    pages["profile"] = profile_panel
    RefPage.hotspot(profile_panel, Rect2(89, 99, 210, 58), back, "ProfileBack")
    # GALERIA (centro): todos os avatares; bloqueados em cinza com o requisito.
    gallery_count = RefPage.text(profile_panel, "", Rect2(488, 194, 344, 30), 21, Color("f0cf7a"), true)
    gallery_count.name = "GalleryCount"
    var gscroll = ScrollContainer.new()
    gscroll.name = "AvatarGalleryScroll"
    gscroll.position = Vector2(340, 232)
    gscroll.size = Vector2(662, 598)
    gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    gscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # a barra visível é a da arte
    profile_panel.add_child(gscroll)
    preload("res://ui_v022/touch_scroll.gd").attach(gscroll)
    avatar_gallery = load("res://profile/avatar_gallery.gd").new()
    avatar_gallery.name = "AvatarGallery"
    gscroll.add_child(avatar_gallery)
    avatar_gallery.setup(self, 4, Vector2(152, 190))
    for c in ["h_separation", "v_separation"]: avatar_gallery.add_theme_constant_override(c, 14)
    avatar_gallery.inspected.connect(_inspect_avatar)
    # R32: ÍCONES separados dos avatares — aba própria, mesma área, botão APLICAR ÍCONE no detalhe.
    var bscroll = ScrollContainer.new()
    bscroll.name = "BadgeGalleryScroll"
    bscroll.position = gscroll.position
    bscroll.size = gscroll.size
    bscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    bscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    bscroll.visible = false
    profile_panel.add_child(bscroll)
    preload("res://ui_v022/touch_scroll.gd").attach(bscroll)
    badge_gallery = load("res://profile/badge_gallery.gd").new()
    badge_gallery.name = "BadgeGallery"
    bscroll.add_child(badge_gallery)
    badge_gallery.setup(self, 4, Vector2(152, 190))
    for c in ["h_separation", "v_separation"]: badge_gallery.add_theme_constant_override(c, 14)
    badge_gallery.inspected.connect(_inspect_badge)
    # R168 · MOLDURAS: terceira aba, mesma área, botão APLICAR MOLDURA no detalhe.
    var fscroll = ScrollContainer.new()
    fscroll.name = "FrameGalleryScroll"
    fscroll.position = gscroll.position
    fscroll.size = gscroll.size
    fscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    fscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    fscroll.visible = false
    profile_panel.add_child(fscroll)
    preload("res://ui_v022/touch_scroll.gd").attach(fscroll)
    frame_gallery = load("res://profile/frame_gallery.gd").new()
    frame_gallery.name = "FrameGallery"
    fscroll.add_child(frame_gallery)
    frame_gallery.setup(self, 4, Vector2(152, 190))
    for c in ["h_separation", "v_separation"]: frame_gallery.add_theme_constant_override(c, 14)
    frame_gallery.inspected.connect(_inspect_frame)
    # R176.8 · EMOTES: quarta aba (coleção do chat da partida: grátis, comprados e os da Loja)
    var escroll = ScrollContainer.new()
    escroll.name = "EmoteGalleryScroll"
    escroll.position = gscroll.position
    escroll.size = gscroll.size
    escroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    escroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    escroll.visible = false
    profile_panel.add_child(escroll)
    preload("res://ui_v022/touch_scroll.gd").attach(escroll)
    emote_gallery = load("res://profile/emote_gallery.gd").new()
    emote_gallery.name = "EmoteGallery"
    escroll.add_child(emote_gallery)
    emote_gallery.setup(self, 4, Vector2(152, 190))
    for c in ["h_separation", "v_separation"]: emote_gallery.add_theme_constant_override(c, 14)
    emote_gallery.inspected.connect(_inspect_emote)
    # R176.9 · TÍTULOS: quinta aba (texto sob o nome, com cor e brilho próprios)
    var tscroll = ScrollContainer.new()
    tscroll.name = "TitleGalleryScroll"
    tscroll.position = gscroll.position
    tscroll.size = gscroll.size
    tscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    tscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    tscroll.visible = false
    profile_panel.add_child(tscroll)
    preload("res://ui_v022/touch_scroll.gd").attach(tscroll)
    title_gallery = load("res://profile/title_gallery.gd").new()
    title_gallery.name = "TitleGallery"
    tscroll.add_child(title_gallery)
    title_gallery.setup(self, 3, Vector2(208, 150))
    for c in ["h_separation", "v_separation"]: title_gallery.add_theme_constant_override(c, 14)
    title_gallery.inspected.connect(_inspect_title)
    gallery_scrolls = {"avatars": gscroll, "icons": bscroll, "frames": fscroll, "emotes": escroll, "titles": tscroll}
    # barra de rolagem da arte (trilho azul + alça dourada), funcional para as cinco galerias
    for sc in [gscroll, bscroll, fscroll, escroll, tscroll]:
        var bar := _art_scrollbar(profile_panel, sc, "perfil_bg", PF_BAR, PF_BAR_GRAB, PF_BAR_TRACK, PF_BAR_UP, PF_BAR_DOWN, 204, "GalleryBar")
        var scr: ScrollContainer = sc
        for n in bar: n.visible = scr.visible
        scr.visibility_changed.connect(func():
            for n in bar: n.visible = scr.visible)
    var tabs = Control.new()
    tabs.name = "ProfileTabs"
    tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
    profile_panel.add_child(tabs)
    var ti := 0
    for pair in [["avatars", "AVATARES", "pf_ico_avatares"], ["icons", "ÍCONES", "pf_ico_icones"], ["frames", "MOLDURAS", ""], ["emotes", "EMOTES", "emote"], ["titles", "TÍTULOS", "title"]]:
        var tab_id: String = pair[0]
        var tr := Rect2(90, 214 + ti * 74, 228, 66)   # R176.9 · 5 abas (TÍTULOS entrou)
        ti += 1
        var tart := NinePatchRect.new()
        tart.name = "TabArt"
        tart.texture = RefPage.tex("pf_tab")
        for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]: tart.set(m, 16)
        tart.position = tr.position
        tart.size = tr.size
        tart.mouse_filter = Control.MOUSE_FILTER_IGNORE
        tart.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        tabs.add_child(tart)
        if pair[2] == "emote":
            var efx = preload("res://social/emote_fx.gd").make("emote_boa_jogada", 44)
            efx.name = "TabEmoteIcon"
            efx.playing = false
            efx.position = Vector2(tr.position.x + 18, tr.position.y + 11)
            tabs.add_child(efx)
        elif pair[2] == "title":
            var tg = preload("res://monetization/premium_art.gd").Glyph.new("scroll", 46, Color("f6d27a"))
            tg.name = "TabTitleIcon"
            tg.position = Vector2(tr.position.x + 18, tr.position.y + 10)
            tabs.add_child(tg)
        elif pair[2] != "": RefPage.image(tabs, RefPage.tex(pair[2]), Rect2(tr.position.x + 20, tr.position.y + 10, 42, 46))
        else:
            var fi := TextureRect.new()
            fi.name = "TabFrameIcon"
            fi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            fi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            fi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
            fi.mouse_filter = Control.MOUSE_FILTER_IGNORE
            fi.texture = load("res://monetization/frames/elo_ouro.png")
            fi.position = Vector2(tr.position.x + 14, tr.position.y + 6)
            fi.size = Vector2(54, 54)
            tabs.add_child(fi)
        var tl := RefPage.text(tabs, pair[1], Rect2(tr.position.x + 74, tr.position.y, 146, tr.size.y), 20 if tab_id == "frames" else 23, Color("f1e6c8"), true, HORIZONTAL_ALIGNMENT_LEFT)
        tl.add_theme_font_override("font", FONT_CINZEL)
        var tb := RefPage.hotspot(tabs, tr, func(): set_profile_tab(tab_id), "Tab_" + tab_id)
        tb.name = {"icons": "ProfileTabIcons", "frames": "ProfileTabFrames", "emotes": "ProfileTabEmotes", "titles": "ProfileTabTitles"}.get(tab_id, "ProfileTabAvatars")
        tb.set_meta("art", tart)
        profile_tabs[tab_id] = tb
    for id in avatar_gallery.cards:
        avatar_choices[id] = avatar_gallery.cards[id]
        avatar_gallery.cards[id].name = "AvatarCard_" + String(id)
    # Foto própria: escolher arquivo → enquadrar → salvar (512x512). Remover volta ao avatar.
    # Os 3 botões de baixo já estão desenhados na arte: aqui só as áreas de clique.
    var change_photo := RefPage.hotspot(profile_panel, Rect2(1070, 775, 194, 58), pick_photo, "ChangePhoto")
    change_photo.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    var remove_photo := RefPage.hotspot(profile_panel, Rect2(1279, 775, 193, 58), request_remove_photo, "RemovePhoto")   # R176 · com confirmação
    remove_photo.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    # R31: ícone, título, moldura, universo e peças exclusivos (Fundador / Club).
    var personalize := RefPage.hotspot(profile_panel, Rect2(1487, 775, 203, 58), func(): open_premium("personalize"), "OpenPersonalize")
    personalize.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    personalize.tooltip_text = "Ícone, título, moldura, tabuleiro e peças"
    # avisos (bloqueado, aplicado…) na coluna da esquerda, abaixo das abas
    avatar_note = RefPage.text(profile_panel, "", Rect2(104, 592, 200, 170), 17, MUTED, false)   # R176.8 · abaixo das 4 abas
    avatar_note.name = "AvatarNote"
    avatar_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    avatar_note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    # DETALHE (direita, topo): avatar em foco (círculo com o anel da arte), nome, origem, status e APLICAR.
    avatar_detail = _build_avatar_detail(profile_panel, Rect2(1066, 190, 620, 188))
    var dbox: Panel = avatar_detail.box
    dbox.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # a moldura é a da arte
    var pic: TextureRect = avatar_detail.pic
    pic.position = Vector2(32, 26)
    pic.size = Vector2(138, 138)
    var circle := ShaderMaterial.new()
    circle.shader = Shader.new()
    # R168 · o círculo é medido pelo retângulo do retrato (não pela UV): arte retangular (ex.: Arqueira) não vaza mais
    circle.shader.code = "shader_type canvas_item;\nuniform bool gray = false;\nuniform vec2 box = vec2(138.0);\nvarying vec2 lp;\nvoid vertex(){ lp = VERTEX; }\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float d = distance(lp / box, vec2(0.5)); vec3 rgb = c.rgb; if (gray) { float l = dot(rgb, vec3(0.3, 0.59, 0.11)); rgb = vec3(l) * 0.75; } COLOR = vec4(rgb, c.a * (1.0 - smoothstep(0.485, 0.5, d))); }"
    circle.set_shader_parameter("box", pic.size)
    pic.set_meta("circle", circle)
    pic.material = circle
    var ring := TextureRect.new()
    ring.name = "DetailRing"
    ring.texture = RefPage.tex("pf_anel")
    ring.position = Vector2(100.5, 94.5) - Vector2(79.5, 79.5)
    ring.size = Vector2(159, 159)
    ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
    dbox.add_child(ring)
    avatar_detail["ring"] = ring
    var words: Control = avatar_detail.title.get_parent().get_parent()
    words.position = Vector2(200, 18)
    words.size = Vector2(410, 100)
    avatar_detail.title.add_theme_font_size_override("font_size", 34)
    var apply: Button = avatar_detail.apply
    apply.position = Vector2(357, 121)
    apply.size = Vector2(234, 52)
    for st in ["normal", "hover", "pressed", "focus", "disabled"]:
        var ab := StyleBoxTexture.new()
        ab.texture = RefPage.tex("pf_btn_aplicar")
        ab.texture_margin_left = 14; ab.texture_margin_right = 14; ab.texture_margin_top = 14; ab.texture_margin_bottom = 14
        ab.modulate_color = {"hover": Color(1.15, 1.12, 1.05), "pressed": Color(0.88, 0.88, 0.88), "disabled": Color(0.5, 0.55, 0.52)}.get(st, Color.WHITE)
        apply.add_theme_stylebox_override(st, ab)
    apply.add_theme_font_override("font", Kit.SERIF_BOLD)
    apply.add_theme_font_size_override("font_size", 20)
    for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: apply.add_theme_color_override(c, Color("f6e7bf"))
    apply.add_theme_color_override("font_disabled_color", Color("b7c4b4"))
    apply.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
    apply.add_theme_constant_override("outline_size", 3)
    # NOME PÚBLICO (conta) / nome local (sem conta) — abaixo do detalhe
    var right_scroll = ScrollContainer.new()
    right_scroll.name = "ProfileInfoScroll"
    right_scroll.position = Vector2(1068, 386)
    right_scroll.size = Vector2(624, 166)
    right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    profile_panel.add_child(right_scroll)
    preload("res://ui_v022/touch_scroll.gd").attach(right_scroll)
    var right_holder = MarginContainer.new()
    right_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_holder.add_theme_constant_override("margin_right", 6)
    right_scroll.add_child(right_holder)
    var profile = VBoxContainer.new()
    profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    profile.add_theme_constant_override("separation", 6)
    right_holder.add_child(profile)
    # Selo Fundador (Pacote Fundador): emblema + título; só aparece para quem tem o pacote.
    founder_row = HBoxContainer.new()
    founder_row.name = "FounderRow"
    founder_row.add_theme_constant_override("separation", 12)
    profile.add_child(founder_row)
    var seal = TextureRect.new()
    seal.name = "FounderSeal"
    seal.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # R138 · ícone nítido
    founder_seal = seal
    seal.texture = FOUNDER_BADGE
    seal.custom_minimum_size = Vector2(56, 56)
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
    nickname_editor.confirm = ask   # R151 · "tem certeza?" com as regras do nome (30 dias)
    nickname_editor.always_enabled = true   # R151 · TROCAR NOME sempre aceso; o toque explica o que falta
    if nickname_editor.save_button != null: nickname_editor.save_button.disabled = false
    _style_name_editor(nickname_editor)
    # Sem conta: nome local só para a partida contra o computador / tela inicial.
    local_name_box = VBoxContainer.new()
    local_name_box.name = "LocalNameBox"
    local_name_box.add_theme_constant_override("separation", 6)
    profile.add_child(local_name_box)
    var lt := _label(local_name_box,"NOME LOCAL (SEM CONTA)",20,GOLD)
    lt.add_theme_font_override("font", FONT_CINZEL)
    var name_input = LineEdit.new()
    name_input.name = "PlayerName"
    name_input.custom_minimum_size.y = 50
    name_input.max_length = 20
    name_input.text = player_name
    name_input.placeholder_text = "Seu nome"
    name_input.add_theme_font_size_override("font_size",22)
    _style_name_field(name_input)
    local_name_box.add_child(name_input)
    name_input.text_changed.connect(func(value):
        player_name = value.strip_edges()
        if player_name.is_empty(): player_name = "Jogador"
        profile_name.text = player_name
        refresh_founder()
        _save_preferences()
    )
    _refresh_name_boxes()
    # ESTATÍSTICAS por ritmo, nas 4 células da arte (os ícones já estão na arte)
    var cells := [Rect2(1116, 562, 246, 100), Rect2(1422, 562, 262, 100), Rect2(1116, 672, 246, 92), Rect2(1422, 672, 262, 92)]
    var mi := 0
    for mode in Ranked.MODES:
        if mi >= cells.size(): break
        var cr: Rect2 = cells[mi]
        mi += 1
        var lines: PackedStringArray = String(ranked.summary(mode)).split("\n")
        var head: String = lines[0] if lines.size() > 0 else ""
        var cut := head.find(" · ")
        var title := head.left(cut).to_upper() if cut > 0 else head.to_upper()
        var first := head.substr(cut + 3) if cut > 0 else ""
        var t := RefPage.text(profile_panel, title, Rect2(cr.position.x, cr.position.y, cr.size.x, 24), 17, Color("f3c95f"), true, HORIZONTAL_ALIGNMENT_LEFT)
        t.name = "Stats_" + String(mode)
        var rest: Array = [first]
        for k in range(1, lines.size()):
            var ln: String = lines[k]
            var lc := ln.rfind(" · ")
            if k == 1 and lc > 0:   # "0 vitórias · 0 derrotas · 0 empates" / "0 partidas" (como na referência)
                rest.append(ln.left(lc))
                rest.append(ln.substr(lc + 3))
            else:
                rest.append(ln)
        var body := RefPage.text(profile_panel, "\n".join(PackedStringArray(rest)), Rect2(cr.position.x, cr.position.y + 24, cr.size.x, cr.size.y - 24), 14, Color("e7e0cc"), false, HORIZONTAL_ALIGNMENT_LEFT)
        body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
        body.size.y = 72.0 if cr.position.y < 600 else 68.0
        body.add_theme_constant_override("line_spacing", -3)
    set_profile_tab("avatars")
    _build_settings_page()

## CONFIGURAÇÕES (R29): painel próprio, centralizado e do mesmo sistema das páginas largas
## (moldura FRAIHA, título dourado, VOLTAR À HOME no rodapé). Uma coluna que cabe inteira em 1600x900
## sem rolar; no celular a mesma coluna é emprestada pelo mobile_hub (page_scrolls).
## R51 · CONFIGURAÇÕES no PC: a página é a imagem de referência do dono (ui_kit/pages/config_bg.png);
## o jogo põe por cima os valores vivos (volumes, pré-move, versão), os sliders e as áreas de clique.
const CONFIG_REF := Vector2(1448, 1234)   # R52: referência nova (painel já recortado) · R145: + linha TABULEIRO E PEÇAS (148 px)
const PROFILE_REF := Vector2(1774, 887)   # R52b: referência nova do PERFIL (painel já recortado)
const PF_BAR := Rect2(1014, 232, 20, 546)
const PF_BAR_GRAB := Rect2(1014, 232, 20, 124)
const PF_BAR_TRACK := Rect2(1014, 360, 20, 418)
const PF_BAR_UP := Rect2(1004, 204, 40, 30)
const PF_BAR_DOWN := Rect2(1004, 778, 40, 44)

## R52b · campo e botão do nome na arte da referência (campo azul-escuro, SALVAR NOME azul)
func _style_name_field(e: LineEdit):
    var fb := StyleBoxTexture.new()
    fb.texture = RefPage.tex("pf_field")
    fb.texture_margin_left = 12; fb.texture_margin_right = 12; fb.texture_margin_top = 12; fb.texture_margin_bottom = 12
    fb.content_margin_left = 20; fb.content_margin_right = 14
    for st in ["normal", "focus", "read_only"]: e.add_theme_stylebox_override(st, fb)
    e.add_theme_font_override("font", Kit.SERIF_BOLD)
    e.add_theme_color_override("font_color", Color("f1e6c8"))

func _style_name_editor(ed):
    if ed == null: return
    if ed.get("title") is Label:
        ed.title.add_theme_font_override("font", FONT_CINZEL)
        ed.title.add_theme_font_size_override("font_size", 23)
        ed.title.text = "✦  SEU NOME PÚBLICO" if not ed.title.text.begins_with("✦") else ed.title.text
    if ed.get("input") is LineEdit:
        _style_name_field(ed.input)
        ed.input.custom_minimum_size.y = 50
        ed.input.add_theme_font_size_override("font_size", 22)
    if ed.get("save_button") is Button:
        var b: Button = ed.save_button
        b.custom_minimum_size = Vector2(178, 50)
        for st in ["normal", "hover", "pressed", "focus", "disabled"]:
            var sb := StyleBoxTexture.new()
            sb.texture = RefPage.tex("pf_btn_salvar")
            sb.texture_margin_left = 12; sb.texture_margin_right = 12; sb.texture_margin_top = 12; sb.texture_margin_bottom = 12
            sb.modulate_color = {"hover": Color(1.15, 1.12, 1.05), "pressed": Color(0.88, 0.88, 0.88), "disabled": Color(0.5, 0.52, 0.55)}.get(st, Color.WHITE)
            b.add_theme_stylebox_override(st, sb)
        b.add_theme_font_override("font", Kit.SERIF_BOLD)
        b.add_theme_font_size_override("font_size", 19)
        for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(c, Color("f6e7bf"))
func _build_settings_page():
    # R52 · painel/modal próprio: centralizado por cima da Home escurecida (fade em show_page)
    var panel := RefPage.modal(canvas, "config_bg_r176", CONFIG_REF, DESIGN)   # R176.8 · 4 placas (2x2)
    panel.name = "SettingsPage"
    # FRAIHA PREMIUM (Fundador + Club): a arte já desenha a entrada; o botão do jogo fica por cima, invisível
    var premium_entry = preload("res://monetization/premium_entry.gd").new()
    premium_entry.pressed.connect(func(): open_premium())
    panel.add_child(premium_entry)
    premium_entry.position = Vector2(126, 222)
    premium_entry.size = Vector2(1196, 188)
    premium_entry.self_modulate = Color(1, 1, 1, 0)
    music_volume_label = RefPage.text(panel, "", Rect2(232, 496, 700, 44), 30, Color("f1e6c8"), true, HORIZONTAL_ALIGNMENT_LEFT)
    music_volume_label.add_theme_font_override("font", FONT_CINZEL)
    var music_slider = _ref_slider(panel, "MusicVolume", Rect2(238, 532, 1056, 60))
    music_slider.value = round(music_volume*100)
    music_slider.value_changed.connect(_set_music_volume)
    _set_music_volume(music_slider.value,false)
    volume_label = RefPage.text(panel, "", Rect2(232, 610, 700, 44), 30, Color("f1e6c8"), true, HORIZONTAL_ALIGNMENT_LEFT)
    volume_label.add_theme_font_override("font", FONT_CINZEL)
    var slider = _ref_slider(panel, "EffectsVolume", Rect2(238, 648, 1056, 60))
    slider.value = round(volume*100)
    slider.value_changed.connect(_set_volume)
    _set_volume(slider.value, false)
    # R176.8 · PARTIDA: quatro placas iguais em 2x2 (tools/config_plates_r176.py) — PRÉ-MOVE, TABULEIRO E PEÇAS,
    # EMOTES e TERMOS E CONTA (antes a chave dos emotes e os termos ficavam soltos num canto)
    var cells := [Rect2(126, 782, 591, 130), Rect2(731, 782, 591, 130), Rect2(126, 930, 591, 130), Rect2(731, 930, 591, 130)]
    premove_button = RefPage.hotspot(panel, cells[0], _toggle_premove, "PremoveToggle")
    premove_button.set_meta("ref_labels", _settings_plate(panel, cells[0], RefPage.tex("config_ico_premove"), "", ""))
    _refresh_premove_button()
    var bc_btn := RefPage.hotspot(panel, cells[1], open_board_colors, "SettingsBoardColors")
    _settings_plate(panel, cells[1], RefPage.tex("about_ico_perso"), "Tabuleiro e Peças", "Cores das casas e peças")
    bc_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    var EmotePrefs = preload("res://social/emote_prefs.gd")
    var em_btn := RefPage.hotspot(panel, cells[2], func(): pass, "SettingsEmotes")
    em_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    var em_ic := Control.new()
    em_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
    em_ic.position = cells[2].position + Vector2(44, 20)
    em_ic.size = Vector2(90, 90)
    em_ic.draw.connect(func(): EmotePrefs.draw_icon(em_ic, Rect2(Vector2.ZERO, em_ic.size), Color("f5cf72")))
    panel.add_child(em_ic)
    var el: Array = _settings_plate(panel, cells[2], null, "", "")
    var paint_em := func():
        el[0].text = "Emotes: " + ("Ligados" if EmotePrefs.enabled() else "Desligados")
        el[1].text = "Faixas ao lado da foto" if EmotePrefs.enabled() else "Clique para ligar"
        _fit_plate_title(el[0])
    paint_em.call()
    em_btn.pressed.connect(func():
        EmotePrefs.toggle()
        paint_em.call())
    var lg_btn := RefPage.hotspot(panel, cells[3], func(): open_legal("termos"), "SettingsLegal")
    lg_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    _settings_plate(panel, cells[3], RefPage.tex("about_ico_projeto"), "Termos e Conta", "Privacidade · excluir conta")
    var note := Label.new()
    note.name = "SettingsNote"
    note.text = "Preferências salvas automaticamente. O botão de som da tela inicial silencia tudo."
    note.visible = false
    panel.add_child(note)
    RefPage.hotspot(panel, Rect2(132, 1080, 668, 98), back, "SettingsBack")
    var ver := RefPage.text(panel, "FRAIHA Xadrez · versão %s" % APP_VERSION, Rect2(900, 1128, 422, 40), 21, Color("e3dccb"), false, HORIZONTAL_ALIGNMENT_RIGHT)
    ver.name = "SettingsVersion"
    pages["settings"] = panel

## R176.8 · conteúdo de uma placa das Configurações (ícone + título dourado + linha de baixo), em px da arte.
func _settings_plate(panel: Control, r: Rect2, icon: Texture2D, title: String, sub: String) -> Array:
    if icon != null:
        var ic := RefPage.image(panel, icon, Rect2(r.position + Vector2(40, 18), Vector2(98, 94)))
        ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        ic.size = Vector2(98, 94)
    var tw := r.size.x - 160.0 - 104.0
    var t := RefPage.text(panel, title, Rect2(r.position + Vector2(160, 18), Vector2(tw, 50)), 36, Color("f5cf72"), true, HORIZONTAL_ALIGNMENT_LEFT)
    t.add_theme_font_override("font", FONT_CINZEL)
    t.clip_text = true
    t.set_meta("fit_w", tw)
    _fit_plate_title(t)
    var u := RefPage.text(panel, sub, Rect2(r.position + Vector2(162, 68), Vector2(tw, 38)), 24, Color("efe6cf"), true, HORIZONTAL_ALIGNMENT_LEFT, false)
    u.clip_text = true
    return [t, u]

## título da placa: a fonte encolhe até o texto caber (até 36 px da arte)
func _fit_plate_title(t: Label) -> void:
    if not t.has_meta("fit_w"): return
    var w: float = t.get_meta("fit_w")
    var px := 36
    while px > 18 and FONT_CINZEL.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > w - 4.0: px -= 1
    t.add_theme_font_size_override("font_size", px)

## Slider sobre o trilho desenhado na arte: preenchimento dourado e o botão esmeralda recortados da referência.
func _ref_slider(parent: Control, node_name: String, rect: Rect2) -> HSlider:
    var slider := HSlider.new()
    slider.name = node_name
    slider.position = rect.position
    slider.size = rect.size
    slider.min_value = 0
    slider.max_value = 100
    slider.step = 1
    slider.focus_mode = Control.FOCUS_NONE
    # trilho da arte: a parte dourada (39 px, com as bordas) cobre o trilho; o botão esmeralda vai por cima
    var track := StyleBoxEmpty.new()
    track.content_margin_top = 19.5
    track.content_margin_bottom = 19.5
    slider.add_theme_stylebox_override("slider", track)
    var fill := StyleBoxTexture.new()
    fill.texture = RefPage.tex("slider_fill")
    fill.content_margin_top = 19.5
    fill.content_margin_bottom = 19.5
    fill.expand_margin_left = -4
    for st in ["grabber_area", "grabber_area_highlight"]: slider.add_theme_stylebox_override(st, fill)
    var knob := RefPage.tex("slider_knob")
    slider.add_theme_icon_override("grabber", knob)
    slider.add_theme_icon_override("grabber_highlight", knob)
    slider.add_theme_constant_override("center_grabber", 1)
    parent.add_child(slider)
    return slider

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
    track.bg_color = Color("0f1625")
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

## PC: escada de bots pelas ligas — R51: a página é a imagem de referência do dono (ui_kit/pages/bots_bg.png);
## o jogo desenha por cima, nos cartões da arte, o estado de cada bot e os botões.
const RefPage = preload("res://ui_kit/ref_page.gd")
const Kit = preload("res://ui_kit/kit.gd")
const BOT_CARDS_R1 := [[100, 332], [347, 581], [596, 828], [842, 1075], [1090, 1322], [1336, 1572]]   # R52: referência nova
const BOT_CARDS_R2 := [[100, 380], [395, 680], [695, 977], [993, 1277], [1292, 1572]]
const BOT_CARD_Y := [Vector2(215, 517), Vector2(531, 807)]
var bot_ref_page: Control
var bot_ref_cards: Control

## Elementos fora do canvas (botões de som/tela cheia, chip da conta) somem enquanto uma página de referência cobre a tela.
var _ref_hidden: Array = []
func _sync_ref_full(on: bool):
    if on:
        for n in [sound_button, fullscreen_button, trophy_button, gchat_button]:
            if n is CanvasItem and is_instance_valid(n) and n.visible and not n.is_ancestor_of(canvas) and not canvas.is_ancestor_of(n):
                n.visible = false
                _ref_hidden.append(n)
    else:
        for n in _ref_hidden:
            if is_instance_valid(n): n.visible = true
        _ref_hidden.clear()

func _build_bot_ladder_page():
    # R52 · painel/modal próprio: centralizado por cima da Home escurecida (fade em show_page)
    var panel := RefPage.modal(canvas, "bots_bg", DESIGN, DESIGN)
    panel.name = "BotLadderPage"
    pages["bot"] = panel
    bot_ref_page = panel
    RefPage.hotspot(panel, Rect2(118, 826, 537, 80), back, "BotBack")
    storage_note = RefPage.text(panel, "", Rect2(788, 845, 740, 40), 19, Color("efe6d2"), false, HORIZONTAL_ALIGNMENT_LEFT)
    bot_progress.changed.connect(_refresh_storage_note)
    bot_progress.changed.connect(_refresh_bot_ref_cards)
    _refresh_storage_note()
    _refresh_bot_ref_cards()

func _refresh_bot_ref_cards():
    if not is_instance_valid(bot_ref_page): return
    if is_instance_valid(bot_ref_cards): bot_ref_cards.queue_free()
    bot_ref_cards = Control.new()
    bot_ref_cards.name = "Cards"
    bot_ref_cards.size = DESIGN
    bot_ref_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bot_ref_page.add_child(bot_ref_cards)
    var bots: Array = BotLadder.bots()
    for i in bots.size():
        var b: Dictionary = bots[i]
        var id := String(b.id)
        var st: String = bot_progress.status(id) if bot_progress != null else ("available" if i == 0 else "locked")
        var top := i < 6
        var xr: Array = BOT_CARDS_R1[i] if top else BOT_CARDS_R2[i - 6]
        var x0 := float(xr[0])
        var x1 := float(xr[1])
        var cx := (x0 + x1) / 2.0
        var cy: Vector2 = BOT_CARD_Y[0] if top else BOT_CARD_Y[1]
        var y_name := 357.0 if top else 661.0
        if st == "available":
            # destaque sutil (mesmo da liga escolhida): fio dourado suave que se desfaz para dentro
            var hl := Panel.new()
            var sf := StyleBoxFlat.new()
            sf.draw_center = false
            sf.border_color = Color(0.98, 0.86, 0.55, 0.95)
            sf.set_border_width_all(5)
            sf.border_blend = true
            sf.set_corner_radius_all(3)
            sf.set_expand_margin_all(1)
            hl.add_theme_stylebox_override("panel", sf)
            hl.position = Vector2(x0 + 1, cy.x + 1)
            hl.size = Vector2(x1 - x0 - 1, cy.y - cy.x - 1)
            hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
            hl.name = "BotHighlight"
            bot_ref_cards.add_child(hl)
        var locked := st == "locked"
        RefPage.text(bot_ref_cards, String(b.name), Rect2(x0 + 10, y_name - 17, x1 - x0 - 20, 34), 24, Color("f6cf6d") if not locked else Color("cbb98a"), true)
        RefPage.text(bot_ref_cards, String(b.get("title", "")), Rect2(x0 + 10, y_name + 11, x1 - x0 - 20, 28), 17, Color("ece3cc") if not locked else Color("b8b3a3"))
        var sy := y_name + 56.0 if top else y_name + 57.0
        match st:
            "defeated": RefPage.icon_text(bot_ref_cards, RefPage.tex("ico_check"), "DERROTADO", Vector2(cx, sy), 19, Color("6fe07c"), 20)
            "available": RefPage.icon_text(bot_ref_cards, RefPage.tex("ico_espadas_ouro"), "DISPONÍVEL", Vector2(cx, sy), 19, Color("f6cf6d"), 22)
            _: RefPage.icon_text(bot_ref_cards, RefPage.tex("ico_cadeado"), "BLOQUEADO", Vector2(cx, sy), 19, Color("b3ad9c"), 24)
        var reward: String = "Prêmio: " + load("res://bot/bot_ladder_ui.gd").reward_text(b.get("reward", {}), true)
        RefPage.text(bot_ref_cards, reward, Rect2(x0 + 10, sy + 16 if top else sy + 11, x1 - x0 - 20, 28), 16, Color("ece3cc") if not locked else Color("b8b3a3"))
        var by := 459.0 if top else 755.0
        var bh := 48.0 if top else 44.0
        var art: String = {"defeated": "btn_jogar_de_novo", "available": "btn_desafiar", "locked": "btn_bloqueado"}[st]
        var lbl: String = {"defeated": "JOGAR DE NOVO", "available": "DESAFIAR", "locked": "BLOQUEADO"}[st]
        var col: Color = {"defeated": Color("f3d27e"), "available": Color("ffe7a6"), "locked": Color("8d8f86")}[st]
        var bid := id
        var btn := RefPage.art_button(bot_ref_cards, art, lbl, Rect2(x0 + 12, by, x1 - x0 - 24, bh), 19, col, func(): _choose_difficulty(bid))
        btn.name = "Challenge_" + id
        btn.disabled = locked

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

## R150 · FOTO DOS OUTROS JOGADORES. O servidor manda avatar_url (foto pública do Storage) junto com o perfil
## público (amigos, busca, convites, mensagens, mesa, adversário). Antes ninguém via a foto dos outros: só o
## avatar do catálogo. Cache próprio (user://avatars/p_<user_id>.webp, 160 px) separado da foto da conta
## deste aparelho; URL nova (foto trocada) = baixa de novo. Enquanto baixa, mostra o avatar do catálogo.
const PEER_PREFIX := "p_"
const PEER_PHOTO_SIZE := 160
func peer_photo(uid: String, url: String) -> Texture2D:
    if avatar_store == null or uid.is_empty() or not url.begins_with("http"): return null
    if account != null and account.has_profile() and uid == String(account.user_id): return custom_avatar()
    var key := PEER_PREFIX + uid
    if avatar_store.needs_fetch(key, url): avatar_store.fetch(key, url, PEER_PHOTO_SIZE)
    return avatar_store.texture_for(key)   # cópia antiga (se houver) até a nova chegar

## Avatar de outro jogador a partir do perfil público: foto (se tiver) → avatar do catálogo → Guerreiro.
func avatar_texture_for(info: Dictionary) -> Texture2D:
    var uid := String(info.get("user_id", info.get("uid", info.get("userId", ""))))
    var url = info.get("avatar_url")
    if url is String and not url.is_empty():
        var photo := peer_photo(uid, url)
        if photo != null: return photo
    var av := String(info.get("avatar_id", info.get("avatar", "")))
    var t: Texture2D = avatar_texture(av) if not av.is_empty() else null
    return t if t != null else avatar_texture("warrior")

## R65 · os avatares do catálogo (profile/avatars) já trazem uma moldura própria desenhada na borda; dentro da
## moldura do cartão da Home isso virava "moldura dentro da moldura" e a foto parecia não preencher o vão.
## Aqui a borda desenhada do avatar é recortada (a foto enviada pelo jogador e os medalhões ficam como estão).
const AVATAR_ART_INSET := 26.0 / 512.0        # moldura desenhada nos avatares de recompensa e peões
const AVATAR_ART_INSET_WIDE := 36.0 / 512.0   # Club e Fundador (moldura mais larga)
func slot_avatar_texture() -> Texture2D:
    var t := avatar_texture()
    if t == null or custom_avatar() != null: return t
    var id := avatar_id
    if id in ["warrior", "archer", "mage", "paladin"] or not AvatarCatalog.has_art(id): return t
    var inset: float = AVATAR_ART_INSET_WIDE if (id == AvatarCatalog.FOUNDER or AvatarCatalog.is_club_avatar(id)) else AVATAR_ART_INSET
    var sz := t.get_size()
    var at := AtlasTexture.new()
    at.atlas = t
    at.region = Rect2(sz * inset, sz * (1.0 - 2.0 * inset))
    return at

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
    # R55 · a arte da Arqueira/Mago traz moldura quadrada própria (filete e flores douradas): recortada fora,
    # senão os cantos aparecem dentro do círculo do Perfil e ficam duas molduras nos cartões.
    var inset: float = half * 0.065
    return _slice(atlas,Rect2((0.0 if id == "archer" else half) + inset,inset,half - 2.0 * inset,atlas.get_height() - 2.0 * inset))

## Avatar liberado? Iniciais sempre; recompensas da escada pelo progresso dos bots; o do Fundador pelo
## Pacote Fundador (entitlements: servidor is_founder ou simulação de dev).
func avatar_unlocked(id: String) -> bool:
    if id in AvatarCatalog.FREE_NEW: return true   # R163 · gratuitos novos
    if AvatarCatalog.is_legend_avatar(id): return is_legend()
    if AvatarCatalog.is_founder_avatar(id): return is_founder()
    if AvatarCatalog.is_club_avatar(id): return club_active()
    if AvatarCatalog.is_owned_avatar(id): return id in Cosmetics.shop_owned   # R163 · Loja de Coroas / Passe (para sempre)
    return bot_progress == null or bot_progress.avatar_unlocked(id)

func avatar_lock_hint(id: String) -> String:
    if AvatarCatalog.is_legend_avatar(id): return "Exclusivo do Fundador Lendário"
    if AvatarCatalog.is_founder_avatar(id): return "Exclusivo do Pacote Fundador"
    if AvatarCatalog.is_club_avatar(id): return "Exclusivo do Club FRAIHA"
    if id in AvatarCatalog.SHOP:
        var it: Dictionary = preload("res://economy/crown_store_catalog.gd").item(id)
        return "Compre na Loja de Coroas (%d Coroas)" % int(it.get("price", 0))
    if id in AvatarCatalog.PASS_FREE: return "Prêmio do Passe da Temporada (nível 25)"
    if id in AvatarCatalog.PASS_CLUB: return "Prêmio do Passe Club (nível 25)"
    return String(bot_progress.unlock_hint(id)) if bot_progress != null else ""

func is_founder() -> bool:
    return entitlements != null and entitlements.founder()

## R103 · Fundador Lendário (só direito REAL do servidor).
func is_legend() -> bool:
    return entitlements != null and bool(entitlements.real.is_founder) and String(entitlements.real.get("founder_tier", "")) == "legend"

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
    var states = {"normal": [Color("192642"), Color("b8913f")], "hover": [Color("263a62"), Color("f0c45c")], "pressed": [Color("0e1729"), Color("f0c45c")], "focus": [Color("263a62"), Color("f0c45c")]}
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
## Botão cuja imagem inteira (moldura, ícone e texto) vem da referência.
func _ref_image_button(art: String, sz: Vector2) -> Button:
    var b := Button.new()
    b.custom_minimum_size = sz
    b.focus_mode = Control.FOCUS_NONE
    var st := StyleBoxTexture.new()
    st.texture = RefPage.tex(art)
    b.add_theme_stylebox_override("normal", st)
    var hi: StyleBoxTexture = st.duplicate()
    hi.modulate_color = Color(1.15, 1.12, 1.05)
    for n in ["hover", "pressed", "focus"]: b.add_theme_stylebox_override(n, hi)
    return b

func _build_avatar_detail(parent: Control, r: Rect2) -> Dictionary:
    var box = Panel.new()
    box.name = "AvatarDetail"
    box.position = r.position
    box.size = r.size
    var sb := StyleBoxTexture.new()
    sb.texture = RefPage.tex("pf_detail")
    sb.texture_margin_left = 16; sb.texture_margin_right = 16; sb.texture_margin_top = 16; sb.texture_margin_bottom = 16
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
    # R168 · os textos ficam ACIMA do botão APLICAR (antes o título quebrava em 2 linhas e empurrava o resto para trás dele)
    var words = _stack(box, Vector2(r.size.y + 4, 12), Vector2(r.size.x - r.size.y - 16, r.size.y - 12 - 60), Vector4.ZERO, 2)
    words.get_parent().clip_contents = true
    var title = _label(words, "", 24, GOLD)
    title.add_theme_font_override("font", FONT_CINZEL)
    title.add_theme_font_size_override("font_size", 28)
    title.autowrap_mode = TextServer.AUTOWRAP_OFF
    title.clip_text = true
    var origin = _label(words, "", 16, CREAM)
    var status = _label(words, "", 16, MUTED)
    var brief = _label(words, "", 13, MUTED)
    for l in [origin, status]:
        l.autowrap_mode = TextServer.AUTOWRAP_OFF
        l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    # R168 · aba MOLDURAS: retrato com a moldura no lugar do círculo
    var frame_slot := Control.new()
    frame_slot.name = "DetailFrame"
    frame_slot.position = Vector2(6, 2)
    frame_slot.size = Vector2(r.size.y - 4, r.size.y - 4)
    frame_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    frame_slot.visible = false
    box.add_child(frame_slot)
    # R32: aplicar é explícito (tocar no cartão só inspeciona)
    var apply = _hud_text_button("APLICAR AVATAR", Vector2(230,42))
    var dim := StyleBoxTexture.new()
    dim.texture = RefPage.tex("pf_btn_dim")
    dim.texture_margin_left = 8; dim.texture_margin_right = 8; dim.texture_margin_top = 8; dim.texture_margin_bottom = 8
    for st in ["disabled"]: apply.add_theme_stylebox_override(st, dim)
    apply.name = "ApplyInspected"
    apply.position = Vector2(r.size.x - 244, r.size.y - 54)
    apply.size = Vector2(230,42)
    apply.mouse_filter = Control.MOUSE_FILTER_STOP
    apply.pressed.connect(request_apply_inspected)   # R176 · pergunta antes de trocar
    box.add_child(apply)
    return {"box": box, "pic": pic, "title": title, "origin": origin, "status": status, "brief": brief, "apply": apply, "frame_slot": frame_slot}

## R168 · título do detalhe numa linha só: diminui a letra até caber
func _fit_detail_title():
    var t: Label = avatar_detail.title
    var w: float = t.get_parent().size.x if t.get_parent().size.x > 0.0 else 360.0
    var f: Font = FONT_CINZEL
    var px := 28
    while px > 16 and f.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > w - 4: px -= 1
    t.add_theme_font_size_override("font_size", px)

## R54 · o detalhe do Perfil volta para o visual EM USO (avatar aplicado ou a foto do jogador): ao abrir o Perfil e
## sempre que o visual muda (foto enviada/removida, avatar vindo da conta). Tocar num cartão continua só inspecionando.
func _focus_current_look():
    inspected_avatar = ""
    if avatar_gallery != null: avatar_gallery.focus_id = ""

func _inspect_avatar(id: String):
    inspected_avatar = id
    _refresh_avatar_detail()

func _inspect_badge(id: String):
    inspected_badge = id
    _refresh_avatar_detail()

func _inspect_frame(id: String):
    inspected_frame = id
    _refresh_avatar_detail()

func set_profile_tab(tab: String):
    profile_tab = tab
    for k in gallery_scrolls: gallery_scrolls[k].visible = k == tab
    for k in profile_tabs:
        var tb: Control = profile_tabs[k]
        if tb.has_meta("art"): tb.get_meta("art").texture = RefPage.tex("pf_tab_sel" if k == tab else "pf_tab")
        else: tb.modulate = Color.WHITE if k == tab else Color(0.62, 0.66, 0.62)
    if tab == "icons": inspected_badge = cosmetic_pref("badge")
    if tab == "frames": inspected_frame = cosmetic_pref("frame")
    if tab == "titles" and title_gallery != null:
        inspected_title = cosmetic_pref("title")
        title_gallery.focus_id = inspected_title
        title_gallery.update_states()
    if tab == "emotes" and emote_gallery != null:
        if inspected_emote.is_empty(): inspected_emote = String(emote_gallery.all_ids()[0])
        emote_gallery.focus_id = inspected_emote
        emote_gallery.update_states()
    if frame_gallery != null:
        frame_gallery.focus_id = inspected_frame
        frame_gallery.update_states()
    if badge_gallery != null:
        badge_gallery.focus_id = inspected_badge
        badge_gallery.update_states()
    _refresh_avatars()

## R176 · APLICAR com confirmação: "Você deseja mesmo aplicar …?" SIM / NÃO. Bloqueado ou já em uso: sem pergunta
## (apply_inspected mostra o motivo / não muda nada).
func request_apply_inspected():
    if profile_tab == "titles" and title_gallery != null:   # R176.9
        var tid := inspected_title
        var tst: String = title_gallery.state_of(tid)
        if tst == "locked":
            if Cosmetics.requirement("title", tid) == "shop": crowns_client().open_store("title")
            elif Cosmetics.requirement("title", tid) == "pass": crowns_client().open_pass()   # R178
            else: open_premium("personalize")
            return
        if tst == "selected": return
        preload("res://ui_kit/confirm_box.gd").ask_change(self, "o título", title_gallery.display_name(tid), func(): apply_inspected())
        return
    if profile_tab == "emotes":   # R176.8 · emote não se aplica: bloqueado abre a Loja de Coroas
        if emote_gallery != null and emote_gallery.state_of(inspected_emote) == "locked": crowns_client().open_store("emote")
        elif emote_gallery != null and emote_gallery.state_of(inspected_emote) == "pass": crowns_client().open_pass()
        return
    var what := "o avatar"
    var id := inspected_avatar if not inspected_avatar.is_empty() else avatar_id
    var nm := ""
    var current := false
    var ok := true
    if profile_tab == "icons":
        what = "o ícone"
        id = inspected_badge
        nm = preload("res://profile/badge_gallery.gd").display_name(id)
        current = id == cosmetic_pref("badge")
        ok = id == "auto" or Cosmetics.allowed("badge", id, is_founder(), club_active(), is_legend())
    elif profile_tab == "frames":
        what = "a moldura"
        id = inspected_frame if not inspected_frame.is_empty() else "auto"
        nm = preload("res://profile/frame_gallery.gd").display_name(id)
        current = id == cosmetic_pref("frame")
        ok = id == "auto" or Cosmetics.allowed("frame", id, is_founder(), club_active(), is_legend())
    else:
        nm = AvatarCatalog.display_name(id)
        current = id == avatar_id and custom_avatar() == null
        ok = avatar_unlocked(id) and AvatarCatalog.has_art(id)
    if current or not ok:
        apply_inspected()
        return
    preload("res://ui_kit/confirm_box.gd").ask_change(self, what, nm, func(): apply_inspected())

## R32 · botão APLICAR da área de detalhe: aplica o avatar ou o ícone em foco.
func apply_inspected() -> bool:
    if profile_tab == "emotes": return false
    if profile_tab == "titles":
        var ok := set_cosmetic("title", inspected_title)
        title_gallery.update_states()
        _refresh_avatar_detail()
        return ok
    if profile_tab == "icons": return apply_badge(inspected_badge)
    if profile_tab == "frames": return apply_frame(inspected_frame)
    return apply_avatar(inspected_avatar if not inspected_avatar.is_empty() else avatar_id)

func apply_badge(bid: String) -> bool:
    if true:
        if not set_cosmetic("badge", bid):
            _avatar_message("Bloqueado · " + Cosmetics.lock_hint("badge", bid) + ".", true)
            return false
        _avatar_message("Ícone aplicado: " + preload("res://profile/badge_gallery.gd").display_name(bid) + ".", false)
        return true
    return false

## R168 · aplica a moldura do retrato (aba MOLDURAS)
func apply_frame(fid: String) -> bool:
    if fid.is_empty(): fid = "auto"
    if not set_cosmetic("frame", fid):
        _avatar_message("Bloqueado · " + Cosmetics.lock_hint("frame", fid) + ".", true)
        return false
    _avatar_message("Moldura aplicada: " + preload("res://profile/frame_gallery.gd").display_name(fid) + ".", false)
    _refresh_avatars()
    return true

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
    _show_detail_frame("")
    if profile_tab != "titles":
        var otag = avatar_detail.pic.get_parent().get_node_or_null("DetailTitleTag")
        if otag != null:
            otag.get_parent().remove_child(otag)
            otag.queue_free()
    if profile_tab != "emotes":
        var efx = avatar_detail.pic.get_parent().get_node_or_null("DetailEmoteFx")
        if efx != null:
            efx.get_parent().remove_child(efx)
            efx.queue_free()
        avatar_detail.apply.visible = true
    if profile_tab == "icons" and badge_gallery != null:
        _refresh_badge_detail()
        _fit_detail_title()
        return
    if profile_tab == "frames" and frame_gallery != null:
        _refresh_frame_detail()
        _fit_detail_title()
        return
    if profile_tab == "emotes" and emote_gallery != null:
        _refresh_emote_detail()
        _fit_detail_title()
        return
    if profile_tab == "titles" and title_gallery != null:
        _refresh_title_detail()
        _fit_detail_title()
        return
    _refresh_avatar_detail_inner()
    _fit_detail_title()

func _refresh_avatar_detail_inner():
    var photo := custom_avatar() if inspected_avatar.is_empty() else null
    if photo != null:
        avatar_detail.pic.texture = photo
        _detail_material(false)
        _show_detail_frame(current_frame(), photo)
        avatar_detail.title.text = "SUA FOTO"
        avatar_detail.origin.text = "Foto enviada por você"
        avatar_detail.status.text = "EM USO no seu perfil"
        avatar_detail.status.add_theme_color_override("font_color", Color("49d17a"))
        avatar_detail.brief.text = ""
        if avatar_detail.has("apply"):
            avatar_detail.apply.text = "EM USO"
            avatar_detail.apply.disabled = true
        return
    var id: String = inspected_avatar if not inspected_avatar.is_empty() else avatar_id
    var e: Dictionary = AvatarCatalog.entry(id)
    var st: String = avatar_gallery.state_of(id)
    avatar_detail.pic.texture = avatar_texture(id) if AvatarCatalog.has_art(id) else null
    _detail_material(st == "locked")
    # R169 · o avatar aparece QUADRADO dentro da moldura que o jogador usa (o círculo dourado saiu)
    _show_detail_frame(current_frame(), avatar_detail.pic.texture, st == "locked")
    avatar_detail.title.text = String(e.get("name", id)).to_upper()
    var src := String(e.get("source", ""))
    avatar_detail.origin.text = "Avatar inicial do FRAIHA" if src == "initial" else (avatar_lock_hint(id) if src in ["founder", "club", "shop", "pass"] else "Recompensa: 1ª vitória contra o " + String(BotLadder.bot(src).get("name", "bot")))
    match st:
        "locked":
            avatar_detail.status.text = "BLOQUEADO"
            avatar_detail.status.add_theme_color_override("font_color", Color("e89a7a"))
        "selected":
            avatar_detail.status.text = "EM USO no seu perfil"
            avatar_detail.status.add_theme_color_override("font_color", Color("49d17a"))
        "no_art_unlocked":
            avatar_detail.status.text = "CONQUISTADO · arte em breve"
            avatar_detail.status.add_theme_color_override("font_color", GOLD)
        _:
            avatar_detail.status.text = "CONQUISTADO"
            avatar_detail.status.add_theme_color_override("font_color", GOLD)
    avatar_detail.brief.text = "" if AvatarCatalog.has_art(id) else "Arte em produção."
    if avatar_detail.has("apply"):
        var b: Button = avatar_detail.apply
        b.text = "EM USO" if st == "selected" else ("BLOQUEADO" if st in ["locked", "no_art_unlocked"] else "APLICAR AVATAR")
        b.disabled = st != "unlocked"

## retrato do detalhe: recortado em círculo (anel da arte) e em cinza quando bloqueado
func _detail_material(locked: bool):
    var pic: TextureRect = avatar_detail.pic
    if pic.has_meta("circle"):
        var m: ShaderMaterial = pic.get_meta("circle")
        m.set_shader_parameter("gray", locked)
        pic.material = m
    else:
        pic.material = avatar_gallery.gray_material() if locked else null

func _refresh_badge_detail():
    var id: String = inspected_badge
    var st: String = badge_gallery.state_of(id)
    var shown: String = Cosmetics.effective("badge", id, is_founder(), club_active()) if id == "auto" else id
    avatar_detail.pic.texture = Cosmetics.badge_texture(shown, false)
    _detail_material(st == "locked")
    avatar_detail.title.text = badge_gallery.display_name(id).to_upper()
    var req := Cosmetics.requirement("badge", id) if id != "auto" else ""
    avatar_detail.origin.text = "Selo ao lado do seu nome" if req.is_empty() else ("Exclusivo do Pacote Fundador" if req == "founder" else "Exclusivo do Club FRAIHA")
    match st:
        "locked":
            avatar_detail.status.text = "BLOQUEADO"
            avatar_detail.status.add_theme_color_override("font_color", Color("e89a7a"))
        "selected":
            avatar_detail.status.text = "EM USO"
            avatar_detail.status.add_theme_color_override("font_color", Color("49d17a"))
        _:
            avatar_detail.status.text = "DISPONÍVEL"
            avatar_detail.status.add_theme_color_override("font_color", GOLD)
    avatar_detail.brief.text = "Usa o melhor selo que você tem." if id == "auto" else ""
    var b: Button = avatar_detail.apply
    b.text = "EM USO" if st == "selected" else ("BLOQUEADO" if st == "locked" else "APLICAR ÍCONE")
    b.disabled = st != "unlocked"

## R176.9 · aba TÍTULOS: o detalhe mostra o SEU NOME com o título embaixo (como os outros vão ver)
func _inspect_title(id: String):
    inspected_title = id
    _refresh_avatar_detail()

func _refresh_title_detail():
    var TG = preload("res://profile/title_gallery.gd")
    var id: String = inspected_title
    var st: String = title_gallery.state_of(id)
    var shown: String = title_gallery.shown(id)
    avatar_detail.pic.texture = avatar_texture()
    _detail_material(st == "locked")
    avatar_detail.pic.visible = true
    if avatar_detail.has("ring"): avatar_detail.ring.visible = true
    var holder: Control = avatar_detail.pic.get_parent()
    var tag = holder.get_node_or_null("DetailTitleTag")
    if tag == null:
        tag = preload("res://profile/title_tag.gd").make(shown, 20, HORIZONTAL_ALIGNMENT_LEFT)
        tag.name = "DetailTitleTag"
        holder.add_child(tag)
    tag.set_title(shown, 20)
    tag.modulate = Color(0.55, 0.55, 0.55) if st == "locked" else Color.WHITE
    var tp: Vector2 = avatar_detail.title.get_global_position() - holder.get_global_position()
    tag.position = Vector2(tp.x - 2, tp.y + 34)
    tag.size = Vector2(holder.size.x - tp.x - 12, 34)
    avatar_detail.title.text = String(player_name).to_upper()
    var origin := "Aparece embaixo do seu nome para todos"
    if id == "auto": origin = "Usa o melhor título que você tem"
    elif id == "": origin = "Nenhum título embaixo do nome"
    elif st == "locked": origin = title_gallery.hint(id)
    avatar_detail.origin.text = ""
    avatar_detail.status.text = "EM USO" if st == "selected" else ("BLOQUEADO" if st == "locked" else "LIBERADO")
    avatar_detail.status.add_theme_color_override("font_color", Color("49d17a") if st != "locked" else Color("e89a7a"))
    avatar_detail.brief.text = origin
    var b: Button = avatar_detail.apply
    b.visible = true
    if st == "locked":
        b.text = "VER NA LOJA" if Cosmetics.requirement("title", id) == "shop" else ("VER O PASSE" if Cosmetics.requirement("title", id) == "pass" else "CONHECER")
        b.disabled = false
    else:
        b.text = "EM USO" if st == "selected" else "USAR TÍTULO"
        b.disabled = st == "selected"

## R176.8 · aba EMOTES: tocar inspeciona; o detalhe mostra o emote animado e onde conseguir
func _inspect_emote(id: String):
    inspected_emote = id
    _refresh_avatar_detail()

func _refresh_emote_detail():
    var EG = preload("res://profile/emote_gallery.gd")
    var id: String = inspected_emote if not inspected_emote.is_empty() else String(EG.all_ids()[0])
    var st: String = emote_gallery.state_of(id)
    avatar_detail.pic.texture = null
    _detail_material(false)
    # R176.8c · emote sem o círculo dos avatares: o desenho fica solto, no lugar do retrato
    avatar_detail.pic.visible = false
    if avatar_detail.has("ring"): avatar_detail.ring.visible = false
    var holder: Control = avatar_detail.pic.get_parent()
    var old = holder.get_node_or_null("DetailEmoteFx")
    if old == null or String(old.emote_id) != id:
        if old != null:
            holder.remove_child(old)
            old.queue_free()
        var side: float = minf(avatar_detail.pic.size.x, avatar_detail.pic.size.y) * 0.95
        var fx = preload("res://social/emote_fx.gd").make(id, side)
        fx.name = "DetailEmoteFx"
        fx.position = avatar_detail.pic.position + (avatar_detail.pic.size - fx.size) / 2.0
        holder.add_child(fx)
        old = fx
    var lk: bool = st in ["locked", "pass"]
    old.modulate = Color(0.5, 0.5, 0.5, 0.9) if lk else Color.WHITE
    avatar_detail.title.text = EG.text_of(id).to_upper()
    var tr := EG.pass_track(id)
    var origin := "Grátis para todos"
    if st == "owned": origin = "Seu para sempre"
    elif st == "locked": origin = "Na Loja de Coroas · %d coroas" % EG.price_of(id)
    elif st == "pass": origin = "Passe da Temporada · nível 10" + (" (faixa Club)" if tr == "club" else " (faixa grátis)")
    avatar_detail.origin.text = origin
    avatar_detail.status.text = "BLOQUEADO" if lk else "LIBERADO"
    avatar_detail.status.add_theme_color_override("font_color", Color("e89a7a") if lk else Color("49d17a"))
    avatar_detail.brief.text = "Use no chat da partida (botão EMOTES)."
    var b: Button = avatar_detail.apply
    b.text = "VER NA LOJA" if st == "locked" else "VER O PASSE"
    b.disabled = not lk
    b.visible = lk   # R176.8c · liberado: sem botão (o texto ao lado já diz LIBERADO)

## R168 · detalhe da aba MOLDURAS
func _refresh_frame_detail():
    var FG = preload("res://profile/frame_gallery.gd")
    var id: String = inspected_frame if not inspected_frame.is_empty() else cosmetic_pref("frame")
    var st: String = frame_gallery.state_of(id)
    _show_detail_frame(frame_gallery.shown(id), null, st == "locked")
    avatar_detail.title.text = FG.display_name(id).to_upper()
    var req := Cosmetics.requirement("frame", id) if id != "auto" else ""
    avatar_detail.origin.text = ("Moldura em volta do seu retrato" if req.is_empty() else Cosmetics.lock_hint("frame", id))
    if id == "liga": avatar_detail.origin.text = "Muda sozinha com a sua liga"
    match st:
        "locked":
            avatar_detail.status.text = "BLOQUEADO"
            avatar_detail.status.add_theme_color_override("font_color", Color("e89a7a"))
        "selected":
            avatar_detail.status.text = "EM USO"
            avatar_detail.status.add_theme_color_override("font_color", Color("49d17a"))
        _:
            avatar_detail.status.text = "DISPONÍVEL"
            avatar_detail.status.add_theme_color_override("font_color", GOLD)
    avatar_detail.brief.text = "Usa a melhor moldura que você tem." if id == "auto" else ""
    var b: Button = avatar_detail.apply
    b.text = "EM USO" if st == "selected" else ("BLOQUEADO" if st == "locked" else "APLICAR MOLDURA")
    b.disabled = st != "unlocked"

## R169 · retrato QUADRADO com a moldura `fid` (Avatares e Molduras) ou o círculo com o anel (Ícones, fid vazio).
## tex: o que vai dentro (null = avatar/foto em uso); locked: cinza.
func _show_detail_frame(fid: String, tex: Texture2D = null, locked := false):
    if not avatar_detail.has("frame_slot"): return
    var slot: Control = avatar_detail.frame_slot
    var on := not fid.is_empty()
    slot.visible = on
    avatar_detail.pic.visible = not on
    if avatar_detail.has("ring"): avatar_detail.ring.visible = not on
    if not on: return
    if String(slot.get_meta("fid", "")) != fid:
        for c in slot.get_children():
            slot.remove_child(c)
            c.queue_free()
        var pv: Control = preload("res://profile/frame_gallery.gd").preview(self, fid, slot.size.x)
        pv.name = "Preview"
        slot.add_child(pv)
        slot.set_meta("fid", fid)
    var pic = slot.get_node_or_null("Preview/FramePic")
    if pic != null:
        pic.texture = tex if tex != null else avatar_texture()
        pic.material = avatar_gallery.gray_material() if locked and avatar_gallery != null else null
    slot.modulate = Color(0.75, 0.75, 0.75) if locked else Color.WHITE

func _refresh_avatars():
    if is_instance_valid(profile_portrait): profile_portrait.texture = slot_avatar_texture() if ref_mode else avatar_texture()
    if is_instance_valid(profile_portrait): attach_league_frame(profile_portrait)
    if ref_mode and not ref_profile.is_empty(): _use_profile(true)
    _refresh_ref_account()
    if avatar_gallery != null:
        avatar_gallery.update_states()
        gallery_count.text = "%d de %d avatares conquistados" % [avatar_gallery.count_unlocked(), avatar_gallery.cards.size()]
    if badge_gallery != null:
        badge_gallery.update_states()
        if profile_tab == "icons": gallery_count.text = "Ícone em uso: " + badge_gallery.display_name(cosmetic_pref("badge"))
    if frame_gallery != null:
        frame_gallery.update_states()
        if profile_tab == "frames": gallery_count.text = "%d de %d molduras liberadas" % [frame_gallery.count_unlocked(), frame_gallery.cards.size() - 1]
    if title_gallery != null:
        title_gallery.update_states()
        if profile_tab == "titles": gallery_count.text = "%d de %d títulos liberados" % [title_gallery.count_unlocked(), title_gallery.cards.size() - 2]
    if emote_gallery != null:
        emote_gallery.update_states()
        if profile_tab == "emotes": gallery_count.text = "%d de %d emotes liberados" % [emote_gallery.count_unlocked(), emote_gallery.cards.size()]
    _refresh_avatar_detail()
    if get_parent().has_method("refresh_player_card"): get_parent().refresh_player_card()

# ---------- R32 · HISTÓRICO DE PARTIDAS (todas as partidas terminadas + análise) ----------
var history_list: VBoxContainer = null
var history_filter := "all"
var history_filter_buttons := {}
const HISTORY_FILTERS := [["all", "TODAS"], ["bot", "COMPUTADOR"], ["casual", "ONLINE"], ["ranked", "RANQUEADAS"], ["local", "LOCAL"], ["marcha", "MARCHA REAL"], ["xeque", "XEQUE"]]

## R51 · HISTÓRICO no PC: a página é a imagem de referência do dono (ui_kit/pages/hist_bg.png, desenhada em
## coordenadas da referência e reduzida para o painel), com as abas e as linhas montadas com peças da própria arte.
const HIST_REF := Vector2(1672, 941)   # R52: referência nova (painel já recortado)
## R51b · páginas na arte de referência: só moldura + miolo, entre a faixa do logo e o rodapé da tela.
const PAGE_TOP := 302.0
const PAGE_W := 1380.0
const HIST_TABS := [[67, 289], [301, 532], [544, 717], [729, 956], [968, 1144], [1156, 1374], [1386, 1603]]
const HIST_ICONS := {"all": "ico_todas", "bot": "ico_computador", "casual": "ico_online", "ranked": "ico_ranqueada", "local": "ico_local", "marcha": "ico_marcha", "xeque": "ico_xeque"}
var hist_tab_art := {}

func _build_history_page():
    # R52 · painel/modal próprio: centralizado por cima da Home escurecida (fade em show_page)
    var panel := RefPage.modal(canvas, "hist_bg", HIST_REF, DESIGN)
    panel.name = "HistoryPage"
    pages["history"] = panel
    var filters := Control.new()
    filters.name = "HistoryFilters"
    filters.size = HIST_REF
    filters.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(filters)
    for i in HISTORY_FILTERS.size():
        var f: Array = HISTORY_FILTERS[i]
        var fid: String = f[0]
        var xr: Array = HIST_TABS[i]
        var r := Rect2(xr[0] - 2, 204, xr[1] - xr[0] + 5, 75)
        var art := NinePatchRect.new()
        art.texture = RefPage.tex("hist_tab")
        for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]: art.set(m, 18)
        art.position = r.position
        art.size = r.size
        art.mouse_filter = Control.MOUSE_FILTER_IGNORE
        art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        filters.add_child(art)
        hist_tab_art[fid] = art
        var ic: Texture2D = RefPage.tex(HIST_ICONS[fid])
        var iw := 38.0 * ic.get_size().x / ic.get_size().y if ic != null else 0.0
        iw = minf(iw, 52.0)
        # ícone + texto centralizados juntos na aba (sem encostar)
        var label_t := String(f[1])
        var tw: float = filters.get_theme_default_font().get_string_size(label_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
        var gx: float = xr[0] + ((xr[1] - xr[0]) - (iw + 12.0 + tw)) / 2.0
        gx = maxf(gx, xr[0] + 16.0)
        RefPage.image(filters, ic, Rect2(gx, 222, iw, 38))
        RefPage.text(filters, label_t, Rect2(gx + iw + 12.0, 218, xr[1] - gx - iw - 22.0, 46), 20, Color("f1e6c8"), false, HORIZONTAL_ALIGNMENT_LEFT)
        var b := RefPage.hotspot(filters, r, func():
            history_filter = fid
            refresh_history(), "HistoryFilter_" + fid)
        history_filter_buttons[fid] = b
    var scroll = ScrollContainer.new()
    scroll.name = "HistoryScroll"
    scroll.position = Vector2(68, 296)
    scroll.size = Vector2(1506, 512)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
    scroll.clip_contents = true   # a barra visível é a da arte (abaixo)
    panel.add_child(scroll)
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    _history_scrollbar(panel, scroll)
    history_list = VBoxContainer.new()
    history_list.name = "HistoryList"
    history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    history_list.add_theme_constant_override("separation", 8)
    scroll.add_child(history_list)
    RefPage.hotspot(panel, Rect2(85, 816, 418, 62), back, "HistoryBack")

## R51c · A barra de rolagem da direita é a própria arte (trilho azul, alça de marfim e setas douradas),
## agora funcional: trilho e alça são recortes da hist_bg; arrastar, clicar no trilho e nas setas rola a lista,
## e rolar a lista (roda/arrasto) move a alça. Lista curta: a alça fica parada no topo, como na referência.
const HIST_BAR := Rect2(1586, 318, 22, 458)        # trilho: abaixo da seta de cima até antes da seta de baixo
const HIST_BAR_GRAB := Rect2(1586, 318, 22, 106)   # alça de marfim com as pontas douradas
const HIST_BAR_TRACK := Rect2(1586, 425, 22, 352)  # trilho azul liso (ponta arredondada embaixo)
const HIST_BAR_UP := Rect2(1574, 286, 46, 32)
const HIST_BAR_DOWN := Rect2(1574, 776, 46, 32)
func _history_scrollbar(panel: Control, scroll: ScrollContainer) -> void:
    var parts := _art_scrollbar(panel, scroll, "hist_bg", HIST_BAR, HIST_BAR_GRAB, HIST_BAR_TRACK, HIST_BAR_UP, HIST_BAR_DOWN, 104, "HistoryBar")
    parts[1].name = "HistoryBarUp"
    parts[2].name = "HistoryBarDown"

## R51c/R52b · barra de rolagem que É a arte (trilho e alça recortados do fundo da página), funcional:
## arrastar a alça, clicar no trilho e nas setas rola a lista; rolar a lista (roda/arrasto) move a alça.
## Lista curta: a alça fica parada no topo, como na referência. Devolve [barra, seta de cima, seta de baixo].
func _art_scrollbar(panel: Control, scroll: ScrollContainer, bg: String, bar_r: Rect2, grab_r: Rect2, track_r: Rect2, up_r: Rect2, down_r: Rect2, step: int, bar_name: String) -> Array:
    var tex := RefPage.tex(bg)
    var bar := VScrollBar.new()
    bar.name = bar_name
    bar.position = bar_r.position
    bar.size = bar_r.size
    bar.custom_minimum_size = Vector2(bar_r.size.x, 0)
    bar.focus_mode = Control.FOCUS_NONE
    bar.step = 0
    var track := StyleBoxTexture.new()
    track.texture = tex
    track.region_rect = track_r
    track.texture_margin_top = 4
    track.texture_margin_bottom = 12
    for st in ["scroll", "scroll_focus"]: bar.add_theme_stylebox_override(st, track)
    for k in [["grabber", Color.WHITE], ["grabber_highlight", Color(1.12, 1.08, 1.0)], ["grabber_pressed", Color(0.9, 0.88, 0.85)]]:
        var g := StyleBoxTexture.new()
        g.texture = tex
        g.region_rect = grab_r
        g.texture_margin_top = 14
        g.texture_margin_bottom = 14
        g.modulate_color = k[1]
        bar.add_theme_stylebox_override(k[0], g)
    var empty_icon := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
    for ic in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
        bar.add_theme_icon_override(ic, empty_icon)
    panel.add_child(bar)
    var inner := scroll.get_v_scroll_bar()
    var syncing := [false]
    var sync := func():
        syncing[0] = true
        var fits: bool = inner.max_value <= inner.page + 0.5
        bar.set_meta("fits", fits)
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE if fits else Control.MOUSE_FILTER_STOP
        if fits:   # nada para rolar: alça no tamanho e lugar da arte
            bar.max_value = bar_r.size.y
            bar.page = grab_r.size.y
            bar.value = 0
        else:
            bar.max_value = inner.max_value
            bar.page = inner.page
            bar.value = scroll.scroll_vertical
        syncing[0] = false
    inner.changed.connect(sync)
    inner.value_changed.connect(func(_v): sync.call())
    bar.value_changed.connect(func(v):
        if not syncing[0] and not bar.get_meta("fits", false): scroll.scroll_vertical = int(round(v)))
    sync.call()
    var up := RefPage.hotspot(panel, up_r, func(): scroll.scroll_vertical -= step, bar_name + "Up")
    var down := RefPage.hotspot(panel, down_r, func(): scroll.scroll_vertical += step, bar_name + "Down")
    return [bar, up, down]

func refresh_history():
    if history_list == null: return
    for k in hist_tab_art:
        hist_tab_art[k].texture = RefPage.tex("hist_tab_sel" if k == history_filter else "hist_tab")
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
        if not compact and not hist_tab_art.is_empty():
            empty.add_theme_font_size_override("font_size", 24)
            empty.custom_minimum_size = Vector2(1500, 0)
            empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _history_row(e: Dictionary, compact: bool, st, mh) -> Control:
    if not compact and not hist_tab_art.is_empty(): return _history_row_ref(e, st, mh)
    var MH = preload("res://analysis/match_history.gd")
    var box = PanelContainer.new()
    box.name = "HistoryRow"
    var sb = StyleBoxFlat.new()
    sb.bg_color = Color(0.042, 0.075, 0.141, 0.92)
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

## Linha do histórico na arte da referência (coordenadas da referência; a página é reduzida inteira).
func _history_row_ref(e: Dictionary, st, mh) -> Control:
    # R52 · linha da referência nova (1506 x 96): escudo, faixa e moldura vêm da arte; o resto é do jogo
    var MH = preload("res://analysis/match_history.gd")
    var mode := String(e.get("mode", ""))
    var res := String(e.get("result", ""))
    var row := Control.new()
    row.name = "HistoryRow"
    row.custom_minimum_size = Vector2(1506, 96)
    row.mouse_filter = Control.MOUSE_FILTER_PASS
    var lost: bool = res in ["loss", "abandon"] and mode != "local"
    var art := RefPage.image(row, RefPage.tex("hist_row_loss" if lost else "hist_row_win"), Rect2(0, 0, 1506, 96))
    art.stretch_mode = TextureRect.STRETCH_SCALE
    if res == "draw" or mode == "local": art.modulate = Color(0.86, 0.86, 0.78)
    var res_txt: String = String(MH.result_name(res, mode)).to_upper()
    var col: Color = Color("6fe07a") if res == "win" else (Color("ff5b5b") if lost else Color("f3d27e"))
    RefPage.text(row, res_txt, Rect2(120, 16, 300, 42), 29, col, false, HORIZONTAL_ALIGNMENT_LEFT)
    if mode == "bot":
        var pc_ic := TextureRect.new()   # (com RefPage.image a imagem nascia no tamanho da textura e cobria o texto)
        pc_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        pc_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        pc_ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        pc_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
        pc_ic.texture = RefPage.tex("ico_computador")
        pc_ic.position = Vector2(120, 59)
        pc_ic.size = Vector2(28, 24)
        row.add_child(pc_ic)
        _hist_fit(RefPage.text(row, "CONTRA COMPUTADOR", Rect2(156, 52, 214, 36), 16, Color("efe6cf"), false, HORIZONTAL_ALIGNMENT_LEFT))
    else:
        _hist_fit(RefPage.text(row, MH.mode_name(mode).to_upper(), Rect2(120, 52, 250, 36), 22, Color("efe6cf"), false, HORIZONTAL_ALIGNMENT_LEFT))
    RefPage.image(row, RefPage.tex(String(HIST_ICONS.get(mode, "ico_todas"))), Rect2(384, 16, 50, 46))
    var opp := String(e.get("opponent", ""))
    var d := Time.get_datetime_dict_from_unix_time(int(e.get("finished_at", e.get("started_at", 0))))
    var chess: bool = String(e.get("mode_id", MH.CHESS_MODE_ID)) == MH.CHESS_MODE_ID
    # R169 · nomes longos (mesas de 4 da Marcha/Xeque) diminuem e terminam em "…" antes da próxima coluna
    var name_l := RefPage.text(row, ("vs  " + opp) if not opp.is_empty() and mode != "local" else MH.mode_name(mode), Rect2(460, 14, 270, 42), 26, Color("f1e6c8"), false, HORIZONTAL_ALIGNMENT_LEFT)
    _hist_fit(name_l, 20)
    name_l.tooltip_text = opp
    RefPage.text(row, "%02d/%02d/%d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute], Rect2(460, 52, 270, 34), 21, Color("e7ddc4"), false, HORIZONTAL_ALIGNMENT_LEFT)
    var info := ""
    if chess:
        var white := String(e.get("color", "w")) != "b"
        RefPage.image(row, RefPage.tex("ico_peao_branco" if white else "ico_peao_preto"), Rect2(742, 20, 48, 58))
        info = "%d lances   ·   %s" % [int(e.get("plies", 0)), "Brancas" if white else "Pretas"]
    else:
        var data: Dictionary = e.get("data", {}) if e.get("data") is Dictionary else {}
        if String(e.get("mode_id", "")) == "xeque":
            info = "%d rodadas   ·   %dº de %d" % [int(data.get("rounds", e.get("plies", 0))), int(e.get("placement", 0)), int(e.get("players", 4))]
        else:
            var cr: Array = data.get("crowned", [0, 0])
            info = "%d jogadas   ·   coroados %d x %d" % [int(e.get("plies", 0)), int(cr[0]) if cr.size() > 0 else 0, int(cr[1]) if cr.size() > 1 else 0]
    var rec = mh.record_of(e) if mh != null and chess else null
    var an: Dictionary = st.analysis_entry_for(rec) if chess and st != null and st.has_method("analysis_entry_for") else {}
    var can_review: bool = chess and not an.is_empty() and st.analysis_history != null and st.analysis_history.has_report(an)
    # R169 · a informação termina ANTES do botão ANALISAR DE NOVO (antes passava por baixo dele)
    var info_x := 806.0 if chess else 744.0
    var info_end := 1028.0 if can_review else 1262.0
    if not an.is_empty():
        RefPage.text(row, info, Rect2(info_x, 12, info_end - info_x, 38), 21, Color("efe6cf"), false, HORIZONTAL_ALIGNMENT_LEFT)
        _hist_fit(RefPage.text(row, "precisão %d%%" % int(round(float(an.get("accuracy", 0.0)))), Rect2(info_x, 50, info_end - info_x, 34), 19, Color("bfe8a8"), false, HORIZONTAL_ALIGNMENT_LEFT))
    else:
        _hist_fit(RefPage.text(row, info, Rect2(info_x, 28, info_end - info_x, 42), 21, Color("efe6cf"), false, HORIZONTAL_ALIGNMENT_LEFT))
    # botão da arte (moldura + lupa): o texto e o clique são do jogo
    var btn_r := Rect2(1273, 15, 215, 67)
    var txt_r := Rect2(1334, 15, 150, 67)
    if not chess:
        RefPage.text(row, "SEM ANÁLISE", txt_r, 17, Color("8c8a7e"), true)
        return row
    var main := RefPage.hotspot(row, btn_r, func():
        if can_review: st.open_history_report(an)
        elif rec != null: st.open_analysis_for(rec), "HistoryReview" if can_review else "HistoryAnalyze")
    main.disabled = not can_review and (rec == null or rec.moves.size() < 2)
    if not can_review: main.tooltip_text = "Usa uma análise da cota do dia (Club: ilimitado)"
    RefPage.text(row, "REVER\nANÁLISE" if can_review else "ANALISAR", txt_r, 17 if can_review else 24, Color("8c8a7e") if main.disabled else Color("f6d27a"), true)
    if can_review:
        var az := RefPage.art_button(row, "btn_jogar_de_novo", "ANALISAR DE NOVO", Rect2(1040, 22, 218, 52), 16, Color("f3d27e"), func(): if rec != null: st.open_analysis_for(rec))
        az.name = "HistoryAnalyze"
        az.disabled = rec == null or rec.moves.size() < 2
    return row

## R169 · texto da linha do histórico diminui até caber na própria coluna (nunca invade a vizinha)
func _hist_fit(l: Label, min_px := 12):
    l.clip_text = true
    var box: Vector2 = l.get_meta("box", l.size)
    var f: Font = l.get_theme_font("font")
    var px := l.get_theme_font_size("font_size")
    while px > min_px and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > box.x - 4.0: px -= 1
    l.add_theme_font_size_override("font_size", px)
    if f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > box.x - 4.0:
        var t := l.text
        while t.length() > 1 and f.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > box.x - 4.0: t = t.substr(0, t.length() - 1)
        l.text = t.strip_edges().trim_suffix(",") + "…"
    # a caixa não cresce com o texto: o rótulo vai para dentro de um recorte do tamanho da coluna
    var par := l.get_parent()
    var clip := Control.new()
    clip.clip_contents = true
    clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip.position = l.position
    clip.size = box
    par.add_child(clip)
    l.reparent(clip, false)
    l.position = Vector2.ZERO
    l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    l.size = box

func _hist_btn_font(b: Button, px: int):
    b.add_theme_font_override("font", Kit.SERIF_BOLD)
    b.add_theme_font_size_override("font_size", px)
    for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(c, Color("f6d27a"))
    b.add_theme_color_override("font_disabled_color", Color("8c8a7e"))
    b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
    b.add_theme_constant_override("outline_size", 3)

## R51 · CONHEÇA O FRAIHA no PC: a página é a imagem de referência do dono (ui_kit/pages/about_bg.png),
## desenhada em coordenadas da referência; o menu da esquerda e o conteúdo do tópico são do jogo.
const ABOUT_REF := Vector2(1772, 888)   # R52: referência nova (painel já recortado)
const ABOUT_NAV := [[220, 286], [296, 360], [371, 436], [445, 510], [521, 585], [595, 661]]
var about_nav_labels: Array = []
const ABOUT_ICONS := ["about_ico_projeto", "about_ico_como", "about_ico_ligas", "about_ico_modos", "about_ico_perso", "about_ico_comunidade"]
var about_nav_art: Array = []
var about_icon: TextureRect
var about_lead: Label
var about_topic := 0
var about_discord: Button   # R141 · COMUNIDADE E SUPORTE: link do Discord clicável
var about_instagram: Button   # R176 · e o Instagram ao lado
var about_support: Button     # R176.8 · FALAR COM O SUPORTE (ticket)
## R53 · tópicos do CONHEÇA O FRAIHA (fonte única: PC e celular)
const ABOUT_TOPICS := [["O PROJETO","Um tabuleiro, muitas histórias.\n\nFRAIHA Xadrez é xadrez online e grátis, direto no navegador do PC ou do celular, num reino medieval em pixel art. Treine contra 11 bots, jogue com pessoas de verdade, suba de liga no Ranked e reveja suas partidas na análise.\n\nAlém do xadrez, tem dois jogos próprios para jogar com os amigos: XEQUE e MARCHA REAL. Feito por jogadores, para jogadores."],["COMO JOGAR","Clique em uma peça e depois em uma casa marcada, ou arraste a peça.\n\nESC abre a confirmação para abandonar. O jogo ocupa a tela inteira (no PC, Alt+Enter alterna janela/tela cheia). Ao jogar de pretas, suas peças ficam na parte inferior do tabuleiro."],["SISTEMA DE LIGAS","Madeira, Ferro, Bronze, Prata, Ouro, Platina, Esmeralda, Diamante, Mestre, Grande Mestre e Challenger.\n\nCada ritmo do Ranked (3, 5, 10 e 20 min) tem liga e PL próprios, e a cada 100 PL você sobe de liga. Embaixo a vitória vale mais (Madeira +20); subindo, cada ponto custa mais (Grande Mestre ±6). O adversário é escolhido pelo seu nível de verdade: quem joga acima da própria liga sobe mais rápido. Empate rende PL contra alguém mais forte.\n\nQuando a fila está vazia, você pode enfrentar oponentes de IA (com o selo IA): valem metade dos PL e não entram no placar.\n\nO Challenger é só para os melhores de cada ritmo: complete o Grande Mestre e dispute uma vaga. A maior liga alcançada libera brasão, moldura e cor de tabuleiro para sempre."],["MODOS DE JOGO","## XADREZ\n• Desafio das Ligas: 11 bots com Stockfish, do BOT MADEIRA ao BOT CHALLENGER. Cada vitória libera o próximo e uma recompensa.\n• Online: escolha 3, 5, 10 ou 20 min e jogue na hora. Não vale PL.\n• Ranqueado: com a sua conta, dispute PL em quatro ritmos.\n## XEQUE\nCartas e blefe para 4. Baixe cartas viradas dizendo que são a peça que a mesa pede. Desconfiou? Aperte XEQUE!\n## MARCHA REAL\nEm dupla, levem os 8 peões até o Salão do Trono jogando cartas."],["PERSONALIZAÇÃO","Escolha seu avatar no Perfil. Novos avatares são liberados vencendo os bots do Desafio das Ligas.\n\nEm TABULEIRO E PEÇAS (Configurações ou Ligas) escolha as cores das casas (várias grátis; cada liga conquistada no Ranked libera a cor dela) e as peças: Marfim e ardósia ou as Peças clássicas."],["COMUNIDADE E SUPORTE","Venha jogar com a gente no Discord: desafios, Torneio da Semana, novidades e salas de voz. Siga também o Instagram @fraihaxadrez.\n\nProblema, dúvida, sugestão ou pagamento? Use FALAR COM O SUPORTE: a resposta aparece aqui no jogo."]]

func _build_about_page():
    var topics: Array = ABOUT_TOPICS
    # R52 · painel/modal próprio: centralizado por cima da Home escurecida (fade em show_page)
    var panel := RefPage.modal(canvas, "about_bg", ABOUT_REF, DESIGN)
    panel.name = "AboutPage"
    pages["about"] = panel
    about_icon = RefPage.image(panel, null, Rect2(626, 248, 92, 94))
    about_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # R176.8 · ícones novos (arte lisa)
    about_title = RefPage.text(panel, "", Rect2(766, 250, 660, 74), 50, Color("f5cf6a"), true, HORIZONTAL_ALIGNMENT_LEFT)
    about_title.add_theme_font_override("font", FONT_CINZEL)
    about_lead = RefPage.text(panel, "", Rect2(620, 384, 720, 56), 34, Color("efe6cf"), true, HORIZONTAL_ALIGNMENT_LEFT, false)
    about_lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    about_lead.clip_text = false
    about_body = RichTextLabel.new()
    about_body.bbcode_enabled = true
    about_body.scroll_active = false
    about_body.fit_content = false
    about_body.position = Vector2(620, 470)
    about_body.size = Vector2(720, 276)
    about_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
    about_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    about_body.add_theme_font_override("normal_font", Kit.SERIF)
    about_body.add_theme_font_override("bold_font", Kit.SERIF_BOLD)
    about_body.add_theme_color_override("default_color", Color("efe6cf"))
    about_body.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
    about_body.add_theme_constant_override("outline_size", 3)
    about_body.add_theme_constant_override("line_separation", 5)
    panel.add_child(about_body)
    about_nav_art.clear()
    about_nav_labels.clear()
    for i in range(topics.size()):
        var topic: Array = topics[i]
        var yr: Array = ABOUT_NAV[i]
        var r := Rect2(121, yr[0] - 2, 433, yr[1] - yr[0] + 4)
        var art := NinePatchRect.new()
        art.texture = RefPage.tex("about_btn")
        for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]: art.set(m, 18)
        art.patch_margin_right = 70   # a seta › da arte fica inteira
        art.position = r.position
        art.size = r.size
        art.mouse_filter = Control.MOUSE_FILTER_IGNORE
        art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        panel.add_child(art)
        about_nav_art.append(art)
        var ic: Texture2D = RefPage.tex(ABOUT_ICONS[i])
        var ih := 58.0   # R176.8 · ícones da referência do dono (256 px, fundo transparente)
        var iw := minf(62.0, ih * ic.get_size().x / ic.get_size().y) if ic != null else 0.0
        var icr := Rect2(178 - iw / 2.0, r.position.y + (r.size.y - ih) / 2.0, iw, ih)
        var icn := RefPage.image(panel, ic, icr)
        icn.size = icr.size   # a imagem (256 px) não pode empurrar o retângulo
        icn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        var tl := RefPage.text(panel, String(topic[0]), Rect2(226, r.position.y, 276, r.size.y), 21, Color("f1e6c8"), true, HORIZONTAL_ALIGNMENT_LEFT)
        tl.add_theme_font_override("font", FONT_CINZEL)
        for px in [21, 20, 19, 18, 17]:   # nome longo encolhe para não passar da seta
            tl.add_theme_font_size_override("font_size", px)
            if FONT_CINZEL.get_string_size(tl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= 270.0: break
        about_nav_labels.append(tl)
        var idx := i
        RefPage.hotspot(panel, r, func(): _show_about_topic(topics, idx), "AboutTopic%d" % i)
    RefPage.hotspot(panel, Rect2(122, 685, 430, 82), back, "AboutBack")
    # R141 · COMUNIDADE E SUPORTE: botão de verdade para o Discord (o link no texto não era clicável)
    about_discord = discord_button(panel, Rect2(620, 628, 400, 54), 24)
    about_discord.name = "AboutDiscord"
    about_instagram = instagram_button(panel, Rect2(1036, 628, 270, 54), 24)   # R176
    about_instagram.name = "AboutInstagram"
    about_support = support_button(panel, Rect2(620, 694, 686, 54), 24)   # R176.8 · ticket direto para o Admin
    about_support.name = "AboutSupport"
    _show_about_topic(topics, 0)

## R141 · botão ENTRAR NO DISCORD (PC e celular): dourado sobre azul-marinho, abre a pergunta da COMUNIDADE
func discord_button(parent: Control, r: Rect2, px: int) -> Button:
    return link_button(parent, r, px, "ENTRAR NO DISCORD  ›", open_community)

## R176.8 · FALAR COM O SUPORTE: abre a tela de tickets (a mensagem cai no Admin → Suporte)
func support_button(parent: Control, r: Rect2, px: int) -> Button:
    return link_button(parent, r, px, "FALAR COM O SUPORTE  ›", open_support)

var support_ui = null
func open_support():
    if not is_instance_valid(support_ui):
        support_ui = load("res://social/support_ui.gd").new()
        add_child(support_ui)
        support_ui.setup(self, account)
    support_ui.show_support()

## R176 · SEGUIR NO INSTAGRAM (mesmo estilo do botão do Discord): abre direto o @fraihaxadrez
func instagram_button(parent: Control, r: Rect2, px: int) -> Button:
    return link_button(parent, r, px, "INSTAGRAM  ›", InstagramLink.open)

func link_button(parent: Control, r: Rect2, px: int, text: String, action: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.position = r.position
    b.size = r.size
    b.focus_mode = Control.FOCUS_NONE
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    for st in [["normal", Color("13254a"), 1.0], ["hover", Color("1d3768"), 1.0], ["pressed", Color("0d1a36"), 1.0]]:
        var sb := StyleBoxFlat.new()
        sb.bg_color = st[1]
        sb.border_color = Color("e8b242")
        sb.set_border_width_all(maxi(2, int(round(px / 9.0))))
        sb.set_corner_radius_all(maxi(4, int(round(px / 4.0))))
        sb.shadow_color = Color(0, 0, 0, 0.45)
        sb.shadow_size = 4
        b.add_theme_stylebox_override(st[0], sb)
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    b.add_theme_font_override("font", FONT_CINZEL)
    b.add_theme_font_size_override("font_size", px)
    for c in ["font_color", "font_focus_color"]: b.add_theme_color_override(c, Color("f5cf6a"))
    for c in ["font_hover_color", "font_pressed_color"]: b.add_theme_color_override(c, Color("fff0b8"))
    b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
    b.add_theme_constant_override("outline_size", 3)
    b.pressed.connect(action)
    parent.add_child(b)
    return b

## R142 · texto dos tópicos em BBCode: linha "## NOME" vira um subtítulo dourado (MODOS DE JOGO: XADREZ · XEQUE · MARCHA REAL)
static func about_bbcode(t: String) -> String:
    var out := PackedStringArray()
    for line in t.replace("[", "[lb]").split("\n"):
        if line.begins_with("## "):
            if not out.is_empty(): out.append("[font_size=10] [/font_size]")   # respiro entre os tópicos
            out.append("[color=#f3c55a][b]%s[/b][/color]" % line.substr(3))
        else: out.append(line)
    return "\n".join(out)

func _show_about_topic(topics: Array, i: int):
    var topic: Array = topics[i]
    about_title.text = String(topic[0])
    # R141 · título longo (COMUNIDADE E SUPORTE) encolhia para fora da moldura: diminui até caber
    for px in [50, 46, 42, 38, 34]:
        about_title.add_theme_font_size_override("font_size", px)
        if FONT_CINZEL.get_string_size(about_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= 560.0: break
    var parts: PackedStringArray = String(topic[1]).split("\n\n", false, 1)
    # frase de abertura (curta) em destaque, como na referência; texto longo fica todo no corpo
    var lead_ok := parts.size() > 1 and parts[0].length() <= 60
    about_lead.text = parts[0] if lead_ok else ""
    var plain: String = parts[1] if lead_ok else String(topic[1])
    about_body.text = about_bbcode(plain)
    about_body.position.y = 470.0 if lead_ok else 384.0
    var discord: bool = String(topic[0]) == "COMUNIDADE E SUPORTE"
    if is_instance_valid(about_discord): about_discord.visible = discord
    if is_instance_valid(about_instagram): about_instagram.visible = discord
    if is_instance_valid(about_support): about_support.visible = discord
    var avail: float = (676.0 if discord else 746.0) - about_body.position.y
    about_body.size.y = avail
    # texto longo: diminui a fonte até caber no quadro (nada passa da moldura)
    # R141 · mede com a própria fonte (get_line_count() do Label ainda trazia o tamanho anterior e o texto passava da moldura)
    for px in [27, 25, 23, 21, 19]:
        about_body.add_theme_font_size_override("normal_font_size", px)
        about_body.add_theme_font_size_override("bold_font_size", px + 2)
        # R142 · altura real do texto (RichTextLabel mede na hora, com subtítulos e quebras)
        if about_body.get_content_height() <= avail - 6.0: break
    var big := RefPage.tex(ABOUT_ICONS[i])   # R93 · o "_big" era cópia idêntica
    about_icon.texture = big
    about_topic = i
    for k in about_nav_art.size():
        about_nav_art[k].texture = RefPage.tex("about_btn_sel" if k == i else "about_btn")
        if k < about_nav_labels.size(): about_nav_labels[k].add_theme_color_override("font_color", Color("f6d46e") if k == i else Color("f1e6c8"))

func _progress(parent: Node, value: int, height: int = 14):
    var bar = ProgressBar.new()
    bar.max_value = 100
    bar.value = value
    bar.show_percentage = false
    bar.custom_minimum_size.y = height
    var fill = StyleBoxFlat.new()
    fill.bg_color = GOLD
    var background = StyleBoxFlat.new()
    background.bg_color = Color("2e394f")
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

## R51d · LIGAS: painel próprio desenhado pela referência nova do dono (tools/ui_ref/ligas_v2.png → ui_kit/pages/
## ligas_bg.png, fundo transparente: nenhum pedaço do cenário). Abre por cima da Home escurecida, com fade, centrado.
## O jogo desenha por cima o nome/liga/PL, o estado de cada liga, a liga escolhida (brasão, título, estado,
## descrição), a prévia (cenário + peças) e o destaque sutil do cartão escolhido.
const FONT_CINZEL = preload("res://account/fonts/Cinzel-Bold.woff")   # versaletes (títulos das referências)
const LIGA_TILES := [[107, 233], [240, 365], [373, 498], [506, 632], [640, 765], [773, 899], [907, 1032], [1040, 1166], [1174, 1298], [1306, 1432], [1440, 1571]]
const LIGA_TILE_Y := Vector2(250, 447)
var ranking_header: Label
var ranking_fill: ColorRect
var league_sel_frame: Panel
var league_chip: Label
var league_desc: Label
## R51e · PEÇAS CLÁSSICAS: o botão liga/desliga o conjunto clássico e mostra o estado (antes não dava retorno)
var current_piece_set := ""
var classic_sub: Label
var classic_frame: Panel
var classic_btn: Control

func _build_ranking():
    var panel := RefPage.full_page(canvas, "ligas_bg", DESIGN, 0.92, 0.72)
    panel.name = "RankingPage"
    panel.set_meta("ref_full", true)
    panel.set_meta("modal", true)
    pages.ranking = panel
    ranking_header = RefPage.text(panel, "", Rect2(566, 112, 940, 56), 36, Color("f3d89a"), true, HORIZONTAL_ALIGNMENT_LEFT)
    ranking_header.name = "RankingHeader"
    ranking_fill = ColorRect.new()
    ranking_fill.color = Color("d9a948")
    ranking_fill.position = Vector2(153, 176)
    ranking_fill.size = Vector2(0, 16)
    ranking_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(ranking_fill)
    # destaque da liga escolhida: sutil — fio dourado suave, brilho leve e o miolo um pouco mais claro
    league_sel_frame = Panel.new()
    var sf := StyleBoxFlat.new()
    # (sem sombra: a sombra do StyleBoxFlat pinta o miolo inteiro e deixa o brasão lavado)
    sf.bg_color = Color(0, 0, 0, 0)
    sf.draw_center = false
    sf.border_color = Color(0.98, 0.86, 0.55, 0.95)
    sf.set_border_width_all(5)
    sf.border_blend = true          # o fio dourado se desfaz para dentro: brilho leve só na borda
    sf.set_corner_radius_all(3)
    sf.set_expand_margin_all(1)
    league_sel_frame.add_theme_stylebox_override("panel", sf)
    league_sel_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(league_sel_frame)
    var entries: Array = LeagueCatalog.entries(league_profile.data)
    for i in entries.size():
        var entry = entries[i]
        var id: String = entry.league_id
        var xr: Array = LIGA_TILES[i]
        var button := RefPage.hotspot(panel, Rect2(xr[0], LIGA_TILE_Y.x, xr[1] - xr[0], LIGA_TILE_Y.y - LIGA_TILE_Y.x), func(): _select_league(id), "League_" + id)
        for st in ["hover", "pressed"]: button.add_theme_stylebox_override(st, StyleBoxEmpty.new())
        button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        button.tooltip_text = entry.display_name + " · 0–100 PL"
        var status := RefPage.text(panel, "", Rect2(xr[0], 413, xr[1] - xr[0], 24), 14, Color("d8cdb2"), false)
        status.name = "LeagueStatus_" + id
        league_status_labels[id] = status
        league_buttons[id] = button
    league_detail_badge = RefPage.image(panel, null, Rect2(111, 412, 227, 436))   # R137: menor e centrado entre a moldura dourada da esquerda e o texto (as asas da Challenger passavam das duas)
    league_detail_badge.name = "LeagueDetailBadge"
    league_detail_title = RefPage.text(panel, "", Rect2(352, 478, 540, 56), 40, Color("f5cf72"), true, HORIZONTAL_ALIGNMENT_LEFT)
    league_detail_title.add_theme_font_override("font", FONT_CINZEL)
    league_chip = RefPage.text(panel, "", Rect2(376, 541, 146, 29), 20, Color("efe6cf"), true)
    league_desc = RefPage.text(panel, "", Rect2(358, 588, 528, 104), 21, Color("efe6cf"), false, HORIZONTAL_ALIGNMENT_LEFT)
    league_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    league_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    league_desc.clip_text = false
    league_desc.add_theme_constant_override("line_spacing", 6)
    # texto completo (estado + descrição + nota) continua num rótulo do jogo (testes e leitores de tela)
    league_details = Label.new()
    league_details.visible = false
    panel.add_child(league_details)
    preview_caption = RefPage.text(panel, "", Rect2(944, 472, 628, 40), 28, Color("f3d27e"), true)
    preview_caption.add_theme_font_override("font", FONT_CINZEL)
    league_scene_preview = TextureRect.new()
    league_scene_preview.position = Vector2(958, 528)
    league_scene_preview.size = Vector2(334, 249)
    league_scene_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    league_scene_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    league_scene_preview.clip_contents = true
    league_scene_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    panel.add_child(league_scene_preview)
    # R37.3 · passar o mouse no cenário: zoom suave no tabuleiro (ver melhor a arte); tirar: volta
    league_scene_preview.mouse_filter = Control.MOUSE_FILTER_STOP
    league_scene_preview.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    league_scene_preview.mouse_entered.connect(func(): _zoom_preview(true))
    league_scene_preview.mouse_exited.connect(func(): _zoom_preview(false))
    for i in range(6):
        var cx := 1314.0 + (i % 3) * 78.0
        var cy := 540.0 + (i / 3) * 116.0
        var piece := RefPage.image(panel, null, Rect2(cx + 4, cy, 74, 110), false)
        league_preview_pieces.append(piece)
    league_preview_button = _button(panel,2,"TESTAR UNIVERSO","Prévia de desenvolvimento · sem alterar PL",Vector2(968,700),_preview_league,Vector2(334,60))
    league_preview_button.visible = DEV_PREVIEW_BUTTON
    RefPage.hotspot(panel, Rect2(97, 808, 471, 80), back, "RankingBack")
    # R139 · o botão PEÇAS CLÁSSICAS da arte vira TABULEIRO E PEÇAS (cores das casas e das peças; as clássicas
    # estão lá dentro): uma placa da cor do botão cobre o título pintado
    classic_btn = RefPage.hotspot(panel, Rect2(597, 808, 444, 80), open_board_colors, "ClassicPieces")
    classic_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    # o fundo do próprio botão (uma faixa vazia da arte, esticada) cobre o título antigo: sem retângulo aparente
    var cover := TextureRect.new()
    cover.name = "BoardColorsTitleCover"
    var strip := AtlasTexture.new()
    strip.atlas = RefPage.tex("ligas_bg")
    strip.region = Rect2(700, 813, 6, 70)
    cover.texture = strip
    cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    cover.stretch_mode = TextureRect.STRETCH_SCALE
    cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    cover.position = Vector2(690, 813)
    cover.size = Vector2(296, 70)
    cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(cover)
    # R139 · o aviso pintado ("a maior liga alcançada libera cenário e peças") ganha o texto novo
    var info_cover := ColorRect.new()
    info_cover.name = "LeagueInfoCover"
    info_cover.color = Color(0.008, 0.043, 0.11)
    info_cover.position = Vector2(1130, 824)
    info_cover.size = Vector2(432, 58)
    info_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(info_cover)
    for li in 2:
        var info := Label.new()
        info.name = "LeagueInfoText%d" % li
        info.text = ["Ligas conquistadas no Ranked. Cada ritmo tem PL próprio;", "a liga libera brasão, moldura e a cor de tabuleiro dela."][li]
        info.add_theme_font_size_override("font_size", 15)
        info.add_theme_color_override("font_color", Color("d9d2bf"))
        info.clip_text = true
        info.mouse_filter = Control.MOUSE_FILTER_IGNORE
        info.position = Vector2(1134, 826 + li * 26)
        info.size = Vector2(428, 26)
        panel.add_child(info)
    var bct := RefPage.text(panel, "TABULEIRO E PEÇAS", Rect2(682, 812, 312, 38), 26, Color("f5cf72"), true)
    bct.name = "BoardColorsTitle"
    bct.add_theme_font_override("font", FONT_CINZEL)
    classic_sub = RefPage.text(panel, "Cores das casas e das peças", Rect2(682, 849, 312, 30), 20, Color("efe6cf"), false)
    classic_sub.name = "ClassicPiecesSub"
    classic_frame = Panel.new()
    classic_frame.add_theme_stylebox_override("panel", league_sel_frame.get_theme_stylebox("panel"))
    classic_frame.position = Vector2(603, 813)
    classic_frame.size = Vector2(432, 70)
    classic_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    classic_frame.visible = false
    panel.add_child(classic_frame)
    _refresh_classic_state()
    set_ranked_unlock(ranked_unlock_index)

func _toggle_classic_pieces():
    # clássicas em uso → volta às peças da liga ("" = acompanha o cenário); senão, liga as clássicas
    var want := "" if current_piece_set == "classic" else "classic"
    # R176 · pergunta antes de trocar as peças
    preload("res://ui_kit/confirm_box.gd").ask_change(self, "as peças", "PEÇAS CLÁSSICAS" if want == "classic" else "PEÇAS DA SUA LIGA", func(): _apply_classic_pieces(want))

func _apply_classic_pieces(want: String):
    piece_set_requested.emit(want)
    if want == "classic": current_piece_set = "classic"   # sem o gerenciador (testes), o estado segue o clique
    elif current_piece_set == "classic": current_piece_set = ""
    _refresh_classic_state()

## chamado pelo gerenciador de temas sempre que cenário/peças mudam (stage.gd)
func on_theme_changed(_theme_id: String, piece_set_id: String):
    current_piece_set = piece_set_id
    _refresh_classic_state()

func _refresh_classic_state():
    # R139 · o botão agora abre TABULEIRO E PEÇAS: o texto é fixo
    if not is_instance_valid(classic_sub): return
    classic_sub.text = "Cores das casas e das peças"

func _refresh_ranking_header():
    if not is_instance_valid(ranking_header): return
    var d: Dictionary = league_profile.data
    var cur = LeagueCatalog.entry(d.current_league, d)
    ranking_header.text = "%s — %s   ·   %d / 100 PL" % [player_name, cur.display_name, int(d.lp)]
    ranking_fill.size.x = 1365.0 * clampf(float(d.lp) / 100.0, 0.0, 1.0)

var review_all := false   # R37.3 · conferência visual (theme_manager.review_all): todas as ligas para olhar
func league_unlocked(id: String) -> bool:
    return review_all or LeagueCatalog.index_of(id) <= ranked_unlock_index

func set_ranked_unlock(index: int):
    ranked_unlock_index = index
    for key in league_status_labels:
        if is_instance_valid(league_status_labels[key]):
            league_status_labels[key].text = ("CONFERIR" if review_all and LeagueCatalog.index_of(key) > ranked_unlock_index else "DISPONÍVEL") if league_unlocked(key) else "BLOQUEADA"
            league_status_labels[key].add_theme_color_override("font_color", Color("d8cdb2") if league_unlocked(key) else Color("8f8a7e"))

var _preview_tween: Tween
const PREVIEW_ZOOM := 2.1
func _zoom_preview(on: bool):
    if not is_instance_valid(league_scene_preview): return
    league_scene_preview.pivot_offset = league_scene_preview.size / 2.0
    league_scene_preview.z_index = 20 if on else 0
    if _preview_tween != null and _preview_tween.is_valid(): _preview_tween.kill()
    _preview_tween = create_tween()
    _preview_tween.tween_property(league_scene_preview, "scale", Vector2.ONE * (PREVIEW_ZOOM if on else 1.0), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## R137 · nome longo (Challenger, Grande Mestre) e descrição de 4 linhas: diminui a letra até caber, sem cortar
## o "0–100 PL" nem passar da linha de baixo
func _fit_league_texts():
    var tf: Font = league_detail_title.get_theme_font("font")
    var px := 40
    while px > 26 and tf.get_string_size(league_detail_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > league_detail_title.size.x - 4: px -= 1
    league_detail_title.add_theme_font_size_override("font_size", px)
    var dpx := 21
    while true:
        league_desc.add_theme_font_size_override("font_size", dpx)
        if dpx <= 16 or league_desc.get_line_count() <= 3: break   # até a linha dourada cabem 3 linhas
        dpx -= 1

## R139 · quadro RECOMPENSAS da página das Ligas (PC): brasão · moldura no avatar · cor do tabuleiro
var league_rewards: Control = null
func _show_league_rewards(id: String, nome: String):
    var panel: Control = league_scene_preview.get_parent()
    if not is_instance_valid(league_rewards):
        league_rewards = Control.new()
        league_rewards.name = "LeagueRewards"
        league_rewards.mouse_filter = Control.MOUSE_FILTER_IGNORE
        league_rewards.position = Vector2(950, 520)
        league_rewards.size = Vector2(616, 252)
        panel.add_child(league_rewards)
        # fundo liso por cima das caixas pintadas do antigo "Cenário e Peças"
        var under := ColorRect.new()
        under.name = "LeagueRewardsUnder"
        under.color = Color(0.012, 0.05, 0.11)
        under.position = Vector2(940, 512)
        under.size = Vector2(636, 266)
        under.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.add_child(under)
        panel.move_child(under, league_rewards.get_index())
    for c in league_rewards.get_children(): c.queue_free()
    var cw := 616.0 / 3.0
    var pic := 150.0
    var items := [["BRASÃO", "badge"], ["MOLDURA NO AVATAR", "frame"], ["TABULEIRO " + nome.to_upper() if id != "madeira" else "TABULEIRO PADRÃO", "board"]]
    for i in 3:
        # R167 · os 3 mais para baixo (a moldura de arte passa por cima do retrato e pegava o título "Recompensas")
        var box := Rect2(Vector2(i * cw + (cw - pic) / 2.0, 34), Vector2(pic, pic))
        var kind: String = items[i][1]
        if kind == "badge":
            var t := TextureRect.new()
            t.name = "RewardBadge"
            t.texture = ThemeCatalog.badge_texture(id)
            t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
            t.mouse_filter = Control.MOUSE_FILTER_IGNORE
            t.position = box.position
            t.size = box.size
            league_rewards.add_child(t)
        elif kind == "frame":
            var holder := Control.new()
            holder.name = "RewardFrame"
            holder.position = box.position + Vector2(26, 30)
            holder.size = box.size - Vector2(52, 52)
            holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
            league_rewards.add_child(holder)
            var av := TextureRect.new()
            av.texture = avatar_texture()
            av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
            av.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
            av.set_anchors_preset(Control.PRESET_FULL_RECT)
            av.offset_left = 4; av.offset_top = 4; av.offset_right = -4; av.offset_bottom = -4
            av.mouse_filter = Control.MOUSE_FILTER_IGNORE
            holder.add_child(av)
            var lf = preload("res://profile/league_frame.gd").new()
            lf.league_id = id
            holder.add_child(lf)
        else:
            var bt := TextureRect.new()
            bt.name = "RewardBoard"
            var at := AtlasTexture.new()
            at.atlas = BoardColors.casas()
            at.region = Rect2(0, 0, 320, 320)
            bt.texture = at
            bt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            bt.stretch_mode = TextureRect.STRETCH_SCALE
            bt.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
            bt.material = BoardColors.board_material(id) if BoardColors.board(id)[0] == id else null
            bt.position = box.position + Vector2(10, 10)
            bt.size = box.size - Vector2(20, 20)
            bt.mouse_filter = Control.MOUSE_FILTER_IGNORE
            league_rewards.add_child(bt)
            var line := Panel.new()
            var st := StyleBoxFlat.new()
            st.draw_center = false
            st.border_color = Color("c99a45")
            st.set_border_width_all(2)
            line.add_theme_stylebox_override("panel", st)
            line.position = bt.position - Vector2(2, 2)
            line.size = bt.size + Vector2(4, 4)
            line.mouse_filter = Control.MOUSE_FILTER_IGNORE
            league_rewards.add_child(line)
        var cap := Label.new()
        cap.text = String(items[i][0])
        cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        cap.vertical_alignment = VERTICAL_ALIGNMENT_TOP
        cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        cap.add_theme_font_override("font", FONT_CINZEL)
        cap.add_theme_font_size_override("font_size", 19)
        cap.add_theme_color_override("font_color", Color("efe6cf"))
        cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
        cap.add_theme_constant_override("outline_size", 3)
        cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
        cap.position = Vector2(i * cw + 6, pic + 40)
        cap.custom_minimum_size = Vector2(cw - 12, 0)
        cap.size = Vector2(cw - 12, 60)
        league_rewards.add_child(cap)

## R137 · o conteúdo extra (Web) chegou: redesenha a prévia da liga aberta na página das Ligas
func refresh_league_preview():
    if is_instance_valid(league_detail_title) and not selected_league.is_empty(): _select_league(selected_league, false)

## R139 · recompensas de cada liga (no lugar de cenário/tabuleiro/peças próprios)
const LEAGUE_MOTTO := {"madeira": "Floresta, equilíbrio e o começo da sua jornada.", "ferro": "Fortaleza, disciplina e as primeiras batalhas.",
    "bronze": "Conquista, prestígio e novos horizontes.", "prata": "Elegância, conhecimento e novos desafios.", "ouro": "Maestria, poder e grandes vitórias.",
    "platina": "Precisão fria e jogadas refinadas.", "esmeralda": "Raízes antigas e estratégia que cresce.", "diamante": "Brilho raro de quem não erra.",
    "mestre": "Domínio do jogo e respeito do reino.", "grande_mestre": "A elite do reino.", "challenger": "O topo: poucos chegam aqui."}
func league_rewards_text(id: String) -> String:
    var motto := String(LEAGUE_MOTTO.get(id, ""))
    if id == "madeira": return motto + "\nRecompensas: brasão da Madeira, moldura de liga no avatar e o tabuleiro padrão."
    var nome := String(BoardColors.board(id)[1]) if BoardColors.board(id)[0] == id else id.capitalize()
    return motto + "\nRecompensas: brasão e moldura de liga no avatar e a cor de tabuleiro " + nome + "."

## R136 · tema que está valendo nas partidas (o lobby é sempre Madeira; ver apply_theme)
var current_league_theme := "wood"
var _theme_confirmed := false
func _select_league(id: String, _apply_theme_now := true, done := Callable()):
    # R139 · PADRÃO ÚNICO: escolher uma liga só mostra os detalhes e as recompensas dela (brasão, moldura de liga
    # no avatar e a cor de tabuleiro da liga); o visual da partida é sempre o da Madeira (cores em TABULEIRO E PEÇAS)
    selected_league = id
    var unlocked = league_unlocked(id)
    if done.is_valid(): done.call()
    # R136 · no celular a página das Ligas do PC não é montada (a do celular se redesenha sozinha): sem ela, nada a atualizar
    if not is_instance_valid(league_detail_title): return
    var entry = LeagueCatalog.entry(id,league_profile.data)
    league_detail_title.text = "LIGA " + entry.display_name.to_upper() + "  ·  0–100 PL"
    if is_instance_valid(league_chip): league_detail_title.text = "Liga " + entry.display_name + "  ·  0–100 PL"
    league_detail_badge.texture = ThemeCatalog.badge_texture(id)
    var theme: String = entry.environment_theme
    var available = ThemeCatalog.THEME_DATA.has(theme)
    var description := league_rewards_text(id)
    league_details.text = ("Disponível" if unlocked else LOCKED_TEXT)+"\n"+description+"\n\nConquiste esta liga no Ranked: cada ritmo tem PL próprio e a promoção acontece a cada 100 PL."
    if is_instance_valid(league_chip):
        league_chip.text = "Disponível" if unlocked else "Bloqueada"
        league_chip.add_theme_color_override("font_color", Color("efe6cf") if unlocked else Color("b9b2a0"))
        league_desc.text = description
        _fit_league_texts()
        _refresh_ranking_header()
        var i := LeagueCatalog.index_of(id)
        if i >= 0 and i < LIGA_TILES.size():
            var xr: Array = LIGA_TILES[i]
            league_sel_frame.position = Vector2(float(xr[0]) + 1, LIGA_TILE_Y.x + 1)
            league_sel_frame.size = Vector2(float(xr[1] - xr[0]) - 1, LIGA_TILE_Y.y - LIGA_TILE_Y.x - 1)
    # R139 · no lugar de "Cenário e Peças": RECOMPENSAS da liga (brasão, moldura no avatar e cor do tabuleiro)
    league_scene_preview.visible = false
    for pc in league_preview_pieces: pc.visible = false
    preview_caption.text = ("Recompensas  ·  " + entry.display_name) if is_instance_valid(league_chip) else "RECOMPENSAS · " + entry.display_name.to_upper()
    _show_league_rewards(id, entry.display_name)
    league_preview_button.visible = false   # R139 · sem cenários de liga
    if not is_instance_valid(league_chip):
        for key in league_buttons:
            league_buttons[key].modulate = Color.WHITE if key == id else Color(0.78,0.82,0.79)

func _preview_league():
    if not ThemeCatalog.THEME_DATA.has(LeagueCatalog.theme_for(selected_league)): return
    if not league_unlocked(selected_league): return
    theme_preview_requested.emit(LeagueCatalog.theme_for(selected_league))
    open_home()

func _layout():
    if is_instance_valid(mobile_ui):
        # R86 · celular DEITADO na Home: a mesma Home nova do PC (arte, botões e perfil); em pé e nas
        # outras páginas continua a tela do celular.
        var desk_home: bool = mobile_ui.desk_home_on()
        set_desk_art(desk_home)   # R89 · artes do PC só quando a Home deitada está na tela
        _mobile_profile_frame()
        mobile_ui.visible = not desk_home
        canvas.visible = desk_home
        presentation_frame.visible = desk_home
        if not desk_home:
            _wide_home(false)
            mobile_ui.layout()
            return
    var dimensions = get_viewport().get_visible_rect().size
    # R153 · HOME DEITADA no celular largo: o menu ocupa a altura da tela e o resto vai para as laterais
    var wide: bool = is_instance_valid(mobile_ui) and dimensions.x / maxf(1.0, dimensions.y) > WIDE_MIN_RATIO
    _wide_home(wide)
    if wide:
        _layout_wide(dimensions)
        presentation_frame.queue_redraw()
        return
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

## R153 · HOME DEITADA (celular deitado, tela mais larga que 1,85:1). Antes a composição inteira (16:9) cabia
## na altura e sobravam as laterais (borda espelhada / folhagem). Agora a faixa do MENU (dos pilares até o SAIR)
## ocupa a altura toda — botões ~50% maiores — e o fundo cobre a tela inteira. O que fica fora dessa faixa
## (SEJA MEMBRO, ícones, logo, cartão de perfil, conta, COMUNIDADE) vai para as laterais: os botões de verdade
## são movidos e a moldura da arte vai junto (recortes com borda suave, tools/home_wide_r153.py).
const WIDE_MIN_RATIO := 1.85
const WIDE_BAND := Vector2(312, 905)   # y de cima/baixo da faixa do menu na arte (1672x941)
const WIDE_PATCHES := {   # recorte (mesmos números de tools/home_wide_r153.py) e nós que andam junto
    "club": [Rect2(10, 4, 354, 84), ["ClubHomeEntry"]],
    "icons": [Rect2(356, 6, 146, 82), ["SoundButton", "FullscreenButton", "TrophyTopButton", "ChatTopButton", "CrownsTopButton", "MailTopButton", "SupportTopButton"]],
    "logo": [Rect2(470, 0, 732, 312), ["NewsTicker"]],
    "profile": [Rect2(1210, 18, 446, 232), ["RefProfileButton", "ProfilePanel", "ProfileStack"]],
    "account": [Rect2(20, 832, 354, 100), ["AccountCard", "AccountPanel", "RefAccountAvatar", "RefAccountAvatarFrameHost"]],
    "community": [Rect2(1388, 856, 262, 64), ["CommunityButton"]],
    "signs": [Rect2(1378, 576, 226, 268), []],   # R184e · placas JOGUE/APRENDA… (a arte cortava na borda direita)
}
var _wide_on := false
var _wide_orig := {}          # nó -> posição original (para voltar ao normal)
var _wide_layer: Control      # recortes da arte, entre a arte e os botões
var _wide_patch := {}

func _wide_home(on: bool):
    if on == _wide_on: return
    _wide_on = on
    if not on:
        for n in _wide_orig.keys():
            if is_instance_valid(n):
                n.position = _wide_orig[n][0]
                n.scale = _wide_orig[n][1]
        _wide_orig.clear()
        var pb0 = canvas.get_node_or_null("RefProfileButton")
        var un0 = pb0.get_node_or_null("RefProfileUnder") if pb0 != null else null
        if un0 != null: un0.visible = true
        if is_instance_valid(_wide_layer): _wide_layer.queue_free()
        _wide_layer = null
        _wide_patch.clear()
        return
    _wide_layer = Control.new()
    _wide_layer.name = "WideHomePatches"
    _wide_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(_wide_layer)
    var art = canvas.get_node_or_null("ForestArtwork")
    canvas.move_child(_wide_layer, (art.get_index() + 1) if art != null else 0)
    # o cartão de perfil usa a moldura nova (a mesma do PC) por cima; o "remendo" do fundo não vai junto
    var pb = canvas.get_node_or_null("RefProfileButton")
    var un = pb.get_node_or_null("RefProfileUnder") if pb != null else null
    if un != null: un.visible = false
    for key in WIDE_PATCHES:
        if key == "community" or key == "profile": continue
        var t := TextureRect.new()
        t.name = "Wide_" + key
        t.texture = load("res://ui_v022/assets/home_wide_%s.png" % key)
        t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        t.stretch_mode = TextureRect.STRETCH_SCALE
        t.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _wide_layer.add_child(t)
        if key == "signs": t.z_index = 1   # R184e · por cima do espírito das águas (que passa na frente da arte)
        _wide_patch[key] = t

const WIDE_MENU_X := Vector2(540, 1120)   # pilares do menu na arte: nada das laterais passa daqui
func _layout_wide(dims: Vector2):
    var band_h: float = WIDE_BAND.y - WIDE_BAND.x
    var s: float = maxf(dims.y / band_h, dims.x / DESIGN.x)
    canvas.scale = Vector2.ONE * s
    canvas.position = Vector2((dims.x - DESIGN.x * s) / 2.0, (dims.y - band_h * s) / 2.0 - WIDE_BAND.x * s)
    var v := Rect2(-canvas.position / s, dims / s)          # parte da arte que aparece (coordenadas da arte)
    var m := 12.0
    var left_w: float = WIDE_MENU_X.x - v.position.x - m * 2.0
    var right_w: float = v.end.x - WIDE_MENU_X.y - m * 2.0
    var kl: float = clampf(left_w / 356.0, 0.5, 1.0)         # tela menos larga: as laterais encolhem um pouco
    var kr: float = clampf(right_w / 446.0, 0.5, 1.0)
    # R178f · os 7 ícones (som … suporte) ocupam 490 px na arte: encolhem para caber na coluna (não invadem o menu)
    var ki: float = minf(kl, left_w / 490.0)
    var place := {
        "club": [v.position + Vector2(m, m), kl],
        "icons": [v.position + Vector2(m, m + 90.0 * kl), ki],
        "account": [Vector2(v.position.x + m, v.end.y - (100.0 + m) * kl), kl],
        "profile": [Vector2(v.end.x - 446.0 * kr - m, v.position.y + m), kr],
        "community": [Vector2(v.end.x - (262.0 + m) * kr - m * 0.5, v.end.y - (64.0 + m) * kr - m * 0.5), kr],
        # R184e · placas: só andam quando a borda direita da tela corta a arte; ficam coladas à direita, mesma altura
        "signs": [Vector2(minf(1378.0, v.end.x - 228.0), 576.0), 1.0],
    }
    for key in place:
        var src: Rect2 = WIDE_PATCHES[key][0]
        var at: Vector2 = place[key][0]
        var k: float = place[key][1]
        # R199 · iPhone (sem tela cheia): o botão TELA CHEIA some; os ícones seguintes andam uma casa para a esquerda
        # e a moldura vazia dele na arte não aparece (antes ficava um quadrado preto)
        var fs_gone: bool = key == "icons" and is_instance_valid(fullscreen_button) and not fullscreen_button.visible
        var after_fs := false
        for nm in WIDE_PATCHES[key][1]:
            var n = canvas.get_node_or_null(nm)
            if n == null: continue
            if not _wide_orig.has(n): _wide_orig[n] = [n.position, n.scale]
            n.scale = (_wide_orig[n][1] as Vector2) * k
            n.position = at + ((_wide_orig[n][0] as Vector2) - src.position) * k
            if fs_gone and after_fs: n.position.x -= 72.0 * k
            if nm == "FullscreenButton": after_fs = true
        if _wide_patch.has(key):
            _wide_patch[key].position = at
            _wide_patch[key].size = src.size * k
            if fs_gone:
                var at2 := AtlasTexture.new()
                at2.atlas = load("res://ui_v022/assets/home_wide_icons.png")
                at2.region = Rect2(0, 0, 74, 82)
                _wide_patch[key].texture = at2
                _wide_patch[key].size = Vector2(74, 82) * k
            elif _wide_patch[key].texture is AtlasTexture:
                _wide_patch[key].texture = load("res://ui_v022/assets/home_wide_icons.png")
    # logo: no meio do espaço livre da coluna da esquerda (entre os ícones e a conta), do tamanho que couber
    var lsrc: Rect2 = WIDE_PATCHES["logo"][0]
    var top: float = v.position.y + m + 90.0 * kl + 84.0 * ki
    # R178 · o cartão do PASSE vai embaixo dos ícones, e o logo desce junto
    var pcard = canvas.get_node_or_null("PassHomeCard")
    if pcard != null:
        if not _wide_orig.has(pcard): _wide_orig[pcard] = [pcard.position, pcard.scale]
        pcard.scale = Vector2.ONE * kl
        pcard.position = Vector2(v.position.x + m, top + 4.0 * kl)
        top += (PASS_CARD_PC.size.y + 12.0) * kl
    var wab = canvas.get_node_or_null("WhatsAppButton")   # R180 · WhatsApp embaixo do PASSE
    if wab != null:
        if not _wide_orig.has(wab): _wide_orig[wab] = [wab.position, wab.scale]
        wab.scale = Vector2.ONE * kl
        var solo: bool = canvas.get_node_or_null("AppDownloadButton") == null
        wab.position = Vector2(v.position.x + m + ((PASS_CARD_PC.size.x - WA_PC.size.x) * 0.5 if solo else 0.0) * kl, top)
    var adb = canvas.get_node_or_null("AppDownloadButton")   # R184 · BAIXAR O APP embaixo do WhatsApp
    if adb != null:
        if not _wide_orig.has(adb): _wide_orig[adb] = [adb.position, adb.scale]
        adb.scale = Vector2.ONE * kl
        adb.position = Vector2(v.position.x + m + (APP_PC.position.x - WA_PC.position.x) * kl, top)   # R196 · lado a lado
    if wab != null or adb != null: top += (WA_PC.size.y + 10.0) * kl
    var bottom: float = v.end.y - (100.0 + m * 2.0) * kl
    var k2: float = minf(left_w / lsrc.size.x, (bottom - top) / lsrc.size.y)
    var lsz: Vector2 = lsrc.size * maxf(0.2, k2)
    _wide_patch["logo"].size = lsz
    _wide_patch["logo"].position = Vector2(v.position.x + m + (left_w - lsz.x) / 2.0, top + (bottom - top - lsz.y) / 2.0)
    _wide_patch["logo"].visible = k2 > 0.22

func _draw_presentation_frame():
    if not desk_art_awake: return   # R89
    # Sobras fora da composição: a própria arte, ampliada para cobrir a tela e escurecida
    # (cor sempre derivada da arte atual, nunca cinza neutro). Nada disso recebe clique.
    var artwork = Rect2(canvas.position, DESIGN * canvas.scale)
    var full = Rect2(Vector2.ZERO, presentation_frame.size)
    if artwork.encloses(full.grow(-0.5)): return
    var art = canvas.get_node_or_null("ForestArtwork")
    var tex: Texture2D = art.texture if art != null else null
    if tex == null:
        presentation_frame.draw_rect(full, Color("151a25"))
        return
    var cover = maxf(full.size.x / DESIGN.x, full.size.y / DESIGN.y) * 1.04
    var cover_rect = Rect2((full.size - DESIGN * cover) / 2.0, DESIGN * cover)
    if _is_ref_art(tex):
        # R43 · modo janela: a cena continua dos dois lados (home_forest_v7_wide.png = 84 px de cada
        # lado completados + o meio idêntico à arte oficial), alinhada pixel a pixel com a arte.
        # Se a janela for ainda mais larga, o resto é a mesma cena ampliada e escurecida.
        # R88 · tela mais larga ainda (celular deitado): em vez de uma cópia ampliada da cena atrás (aparecia
        # tudo duplicado), a borda da própria arte continua ESPELHADA e escurece para fora.
        var u = canvas.scale.x
        var wr := Rect2(artwork.position - Vector2(WIDE_PAD * u, 0), FOREST_WIDE.get_size() * u)
        presentation_frame.draw_rect(full, Color("0f1625"))
        presentation_frame.draw_texture_rect(FOREST_WIDE, wr, false)
        for side in 2:
            var gap: float = wr.position.x if side == 0 else full.size.x - wr.end.x
            if gap < 0.5: continue
            # R152 · celular deitado bem largo: a cena CONTINUA com folhagem pixel art emendada na borda
            # (tools/home_side_ext_r152.py) em vez da borda espelhada (parecia a tela duplicada) e das faixas pretas.
            var ext: Texture2D = _desk(FOREST_SIDE_L if side == 0 else FOREST_SIDE_R)
            var ew: float = (ext.get_width() - SIDE_OVERLAP) * u
            var er := Rect2(wr.position.x - ew, wr.position.y, ext.get_width() * u, wr.size.y) if side == 0 else Rect2(wr.end.x - SIDE_OVERLAP * u, wr.position.y, ext.get_width() * u, wr.size.y)
            presentation_frame.draw_texture_rect(ext, er, false)
            var rest: float = gap - ew
            if rest < 0.5: continue
            # mais larga ainda (raro): o que sobra escurece aos poucos para fora, sem emenda
            var x0: float = er.position.x if side == 0 else er.end.x
            var n := 12
            for i in n:
                var a := pow(float(i + 1) / n, 1.2) * 0.9
                var w := rest / n
                var x := x0 - (i + 1) * w if side == 0 else x0 + i * w
                presentation_frame.draw_rect(Rect2(x, 0, w + 0.5, full.size.y), Color(0.043, 0.057, 0.085, a))
        return
    # Sobras da tela (fora da tela cheia): panorama de folhagem em pixel art, levemente escurecido.
    var foliage: Texture2D = load("res://ui_v022/assets/home_side_foliage.png")   # R87 · não fica presa na memória do celular
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
    close_status_editor()   # R55 · o editor do status é só da Home
    if pages_pending and id != "main":
        pages_pending = false
        _build_pages()
    if not pages.has(id): return
    page = id
    for key in pages:
        pages[key].visible = key == id
    # R51 · páginas na arte de referência cobrem a tela toda: ficam por cima de tudo do canvas (Club, som, perfil…)
    if pages[id].has_meta("ref_full"):
        canvas.move_child(pages[id], canvas.get_child_count() - 1)
    _sync_ref_full(pages[id].has_meta("ref_full"))
    _sync_menu_cover()
    if page_scrolls.has(id): page_scrolls[id].scroll_vertical = 0
    if id == "ranking": _select_league(selected_league, false)
    # R51d/R52 · painéis/modais abrem com fade suave (Home escurecida atrás)
    if pages[id].has_meta("modal"):
        var rp: Control = pages[id]
        rp.modulate.a = 0.0
        create_tween().tween_property(rp, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
    if id == "profile":
        _focus_current_look()
        _refresh_avatars()
    elif avatar_gallery != null and avatar_gallery.has_method("unload_art"): avatar_gallery.unload_art()   # R89
    if id == "history": refresh_history()
    if is_instance_valid(mobile_ui): mobile_ui.show_page(id)
    _sync_side_art(id)

func apply_theme(texture: Texture2D, theme_id: String = "wood"):
    # R134 · a TELA INICIAL é sempre a da Madeira (lobby completo); a liga muda só a PARTIDA (tabuleiro, peças, cenário)
    var league_theme := theme_id
    current_league_theme = league_theme
    texture = FOREST
    theme_id = "wood"
    if texture != null and texture.resource_path == FOREST_LEGACY_PATH: texture = FOREST   # temas que usavam a Home da floresta passam a usar a arte oficial
    if texture != null:
        _desk_theme_tex = texture if texture.resource_path != FOREST_PATH else null
        canvas.get_node("ForestArtwork").texture = texture if desk_art_awake else null
        var details = canvas.get_node_or_null("ForestDetails")
        if details != null: details.visible = _is_ref_art(texture)
        var spirit = canvas.get_node_or_null("WaterSpirit")
        if spirit != null: spirit.visible = _is_ref_art(texture)
        var fx = canvas.get_node_or_null("HomeFx")
        if fx != null: fx.visible = _is_ref_art(texture)
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
        selected_league = ThemeCatalog.get_theme(league_theme).get("unlock_league","madeira")
        if selected_league == "wood" or selected_league == "": selected_league = "madeira"

func back():
    show_page("bot" if page == "bot_side" else "main")

## R52d · ESCOLHA SEU LADO na arte da referência (ui_kit/pages/lado_bg.png, 1122 x 1402): painel/modal
## centralizado por cima do jogo escurecido, com fade, no PC e no celular (fica por cima da tela do celular
## também). Títulos e botões são da arte; o adversário é do jogo. Os botões fazem o mesmo que os da página
## antiga (que continua montada por baixo, oculta, para o celular e os testes).
const SIDE_REF := Vector2(1122, 1402)
var side_art: Control
var side_panel: Control
var side_opponent: Label

func _build_side_art():
    side_art = Control.new()
    side_art.name = "SideChoiceArt"
    side_art.mouse_filter = Control.MOUSE_FILTER_STOP
    side_art.visible = false
    root.add_child(side_art)
    var dim := ColorRect.new()
    dim.name = "SideDim"
    dim.color = Color(0.029, 0.034, 0.043, 0.72)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    side_art.add_child(dim)
    side_panel = Control.new()
    side_panel.name = "SidePanel"
    side_panel.size = SIDE_REF
    side_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    side_art.add_child(side_panel)
    RefPage.image(side_panel, RefPage.tex("lado_bg"), Rect2(Vector2.ZERO, SIDE_REF)).stretch_mode = TextureRect.STRETCH_SCALE
    side_opponent = RefPage.text(side_panel, "", Rect2(250, 432, 622, 56), 38, Color("f1e6c8"), true)
    side_opponent.name = "SideOpponent"
    side_opponent.add_theme_font_override("font", Kit.SERIF_BOLD)
    for spec in [["SideWhite", Rect2(204, 522, 714, 166), "w"], ["SideBlack", Rect2(204, 714, 714, 166), "b"], ["SideRandom", Rect2(204, 904, 714, 166), "random"]]:
        var col: String = spec[2]
        var hb := RefPage.hotspot(side_panel, spec[1], func(): play_bot_requested.emit(selected_difficulty, col), spec[0])
        hb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    var bb := RefPage.hotspot(side_panel, Rect2(172, 1140, 778, 144), back, "SideBack")
    bb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    get_viewport().size_changed.connect(_layout_side_art)

func _layout_side_art():
    if not is_instance_valid(side_art) or not side_art.visible: return
    var vs := get_viewport().get_visible_rect().size
    side_art.position = Vector2.ZERO
    side_art.size = vs
    side_art.get_node("SideDim").size = vs
    var k := minf(vs.x * 0.92 / SIDE_REF.x, vs.y * 0.94 / SIDE_REF.y)
    side_panel.scale = Vector2.ONE * k
    side_panel.position = ((vs - SIDE_REF * k) / 2.0).round()

func _sync_side_art(id: String):
    if not is_instance_valid(side_art): return
    var on := id == "bot_side"
    var was := side_art.visible
    side_art.visible = on
    if not on: return
    root.move_child(side_art, root.get_child_count() - 1)
    var t := difficulty_label.text if is_instance_valid(difficulty_label) else ""
    side_opponent.text = t
    for px in [38, 34, 30, 27]:   # nome longo (BOT GRANDE MESTRE) encolhe para caber
        side_opponent.add_theme_font_size_override("font_size", px)
        if Kit.SERIF_BOLD.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= side_opponent.size.x - 12.0: break
    if is_instance_valid(pages.get("bot_side")): pages["bot_side"].visible = false
    _layout_side_art()
    if not was:
        side_art.modulate.a = 0.0
        create_tween().tween_property(side_art, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)

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
    if is_instance_valid(volume_label): volume_label.text = ("Efeitos Sonoros  •  %d%%" if volume_label.has_meta("ref") or volume_label.get_parent().name == "SettingsPage" else "EFEITOS SONOROS  ·  %d%%") % round(value)
    if save:
        _save_preferences()
        _osd().show_volume("effects", value)

func _set_music_volume(value: float, save := true):
    music_volume = value/100.0
    var bus = AudioServer.get_bus_index("Music")
    AudioServer.set_bus_volume_db(bus,linear_to_db(maxf(music_volume,0.0001)))
    AudioServer.set_bus_mute(bus,music_volume <= 0.0 or music_muted)
    if is_instance_valid(music_volume_label): music_volume_label.text = ("Música  •  %d%%" if music_volume_label.get_parent().name == "SettingsPage" else "MÚSICA  ·  %d%%") % round(value)
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

## R88 · volume pelo controle deslizante dos modos (0..1). 0 = mudo; subir tira o mudo. Fica salvo.
func set_mode_volume(kind: String, v: float):
    v = clampf(v, 0.0, 1.0)
    if kind == "music":
        music_muted = v <= 0.0
        if v > 0.0: music_volume = v
        _set_music_volume(v * 100.0 if v > 0.0 else music_volume * 100.0, false)
        AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)
    else:
        effects_muted = v <= 0.0
        if v > 0.0: volume = v
        _set_volume(v * 100.0 if v > 0.0 else volume * 100.0, false)
        AudioServer.set_bus_mute(AudioServer.get_bus_index("Effects"), effects_muted)
    _save_preferences()
    _refresh_sound_button()

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
        if ref_mode: fullscreen_button.set_frame(TOP_FRAME_PC, 14.0)   # R122 · moldura azul
        else: fullscreen_button.set_over_art(false)
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
    if _wide_on and is_instance_valid(canvas): _layout_wide(get_viewport().get_visible_rect().size)   # R199

## Web: SAIR volta para o site — o subtítulo desenhado na arte ("Até a próxima partida!") é coberto
## com o mesmo verde do botão e recebe "Voltar para o site".
func _build_web_quit_caption():
    # R37.2 · pedido do dono: o SAIR fica só com a palavra (sem legenda por cima nem sombra).
    var last0 := menu_buttons.size() - 1
    if OS.has_feature("web") and last0 >= 0: menu_buttons[last0].tooltip_text = "Voltar para o site fraihaxadrez.com"

## R96 · botão do topo da Home (troféu / balão) no mesmo estilo do som e da tela cheia.
func make_top_button(glyph: String, tip: String, action: Callable, side := 62.0) -> Button:
    var b = preload("res://ui_v022/hud_button.gd").make(glyph)
    b.name = glyph.capitalize() + "TopButton"
    b.size = Vector2(side, side)
    b.custom_minimum_size = Vector2(side, side)
    b.tooltip_text = tip
    b.pressed.connect(action)
    b.set_frame(TOP_FRAME_CEL if side != 62.0 else TOP_FRAME_PC, 14.0)   # R113 · moldura dos botões de som / tela cheia
    return b

## R122 · COMUNIDADE: botão largo (duas pessoas + "COMUNIDADE") na moldura dos botões do topo; abre o Discord.
const CommunityLink := preload("res://social/community_link.gd")
const PassHomeCard := preload("res://economy/pass_home_card.gd")   # R178
const WhatsAppButton := preload("res://ui_kit/whatsapp_button.gd")   # R180
const WA_PC := Rect2(14, 186, 170, 46)   # R180 · embaixo do cartão do PASSE · R196: arte do dono (1000x270), lado a lado com o BAIXAR O APP
const APP_PC := Rect2(190, 186, 170, 46)   # R196 · BAIXAR O APP à direita do WhatsApp, mesmo tamanho
const PASS_CARD_PC := Rect2(14, 94, 346, 85)   # R178e · proporção da arte do botão (2036x502)   # R178 · embaixo da placa CLUB (topo esquerdo)
func make_community_button(sz: Vector2, frame: Texture2D, font_px: int) -> Button:
    var b: Button = preload("res://ui_v022/hud_button.gd").make("community", "COMUNIDADE")
    b.name = "CommunityButton"
    b.icon_box = sz.y * 0.9
    b.size = sz
    b.custom_minimum_size = sz
    b.tooltip_text = CommunityLink.TIP
    b.clip_text = true
    b.add_theme_font_override("font", FONT_CINZEL)
    b.add_theme_font_size_override("font_size", font_px)
    b.add_theme_color_override("font_color", Color("f4ce7f"))
    b.set_frame(frame, 14.0 if frame == TOP_FRAME_PC else 16.0)
    b.pressed.connect(open_community)   # R124 · pergunta antes de abrir o Discord
    return b

## R176 · INSTAGRAM (@fraihaxadrez): fica dentro da COMUNIDADE (open_community) e em CONHEÇA O FRAIHA
const InstagramLink := preload("res://social/instagram_link.gd")

## R113 · moldura dos botões do topo, recortada da arte da Home (PC: som em 363,17; celular: som em 730,45)
const TOP_FRAME_PC := preload("res://ui_v022/assets/r113/moldura_botao_topo_pc_azul.png")   # R122 · miolo azul
const TOP_FRAME_CEL := preload("res://ui_v022/assets/r113/moldura_botao_topo_cel_azul.png")   # R122 · miolo azul

## R112 · COROAS: um controlador só (estado do servidor, botões de saldo, painel e aviso "+N COROAS").
var crowns = null
func crowns_client():
    if crowns == null:
        crowns = load("res://economy/crowns_client.gd").new()
        add_child(crowns)
        if account != null: crowns.setup(self, account)
    return crowns

## R96 · RANKING (XADREZ por fila, XEQUE, MARCHA REAL) e CHAT GLOBAL — painéis por cima da Home.
## R162 · MENSAGENS (envelope ao lado da coroa). O número vem do social_ui (stage liga o sinal unread_changed).
var mail_buttons: Array = []
var unread_messages := 0
func make_mail_button(side := 62.0) -> Button:
    var b: Button = make_top_button("mail", "Mensagens", open_messages, side)
    b.name = "MailTopButton"
    b.badge = unread_messages
    mail_buttons.append(b)
    return b

func set_unread(n: int):
    unread_messages = n
    for b in mail_buttons:
        if is_instance_valid(b):
            b.badge = n
            b.tooltip_text = "Mensagens" if n <= 0 else ("%d mensagem nova" % n if n == 1 else "%d mensagens novas" % n)

func open_messages():
    var st = get_parent()
    if st != null and st.has_method("_open_messages"): st._open_messages()

## R161 · NOVIDADES (outdoor embaixo da logo + tela com abas)
var news_feed = null
var news_ui = null
func news():
    if not is_instance_valid(news_feed):
        news_feed = load("res://ui_v022/news_feed.gd").new()
        add_child(news_feed)
    return news_feed

func open_news(tab := ""):
    if not is_instance_valid(news_ui):
        news_ui = load("res://ui_v022/news_ui.gd").new()
        add_child(news_ui)
        news_ui.setup(self, news())
    if is_instance_valid(global_chat_ui): global_chat_ui.close()
    news_ui.show_news(tab)

func make_news_ticker(font_px: int, top_col: Color, bottom_col: Color) -> Button:
    var t: Button = load("res://ui_v022/news_ticker.gd").new()
    t.setup(news(), font_px, top_col, bottom_col)
    t.pressed.connect(func(): open_news())
    return t

func open_leaderboard():
    # R198 · PC (tela deitada): o RANKING com a ARTE do dono
    if preload("res://ui_v022/ranking_art.gd").available() and not preload("res://ui_v022/mobile_layout.gd").active(get_viewport()):
        if not is_instance_valid(ranking_art):
            ranking_art = preload("res://ui_v022/ranking_art.gd").new()
            add_child(ranking_art)
            ranking_art.setup(self, account)
        ranking_art.show_ranking()
        return
    if not is_instance_valid(leaderboard_ui):
        leaderboard_ui = load("res://ui_v022/leaderboard_ui.gd").new()
        add_child(leaderboard_ui)
        leaderboard_ui.setup(self, account)
    if is_instance_valid(global_chat_ui): global_chat_ui.close()
    leaderboard_ui.show_ranking()

## R97 · TERMOS DE USO, PRIVACIDADE e EXCLUIR CONTA (aba inicial: "termos" | "privacidade" | "excluir").
## R104 · aviso importante na moldura do jogo (ex.: CONTA SUSPENSA).
var notice_modal = null
func show_notice(title: String, text: String):
    if not is_instance_valid(notice_modal):
        notice_modal = load("res://ui_v022/notice_modal.gd").new()
        add_child(notice_modal)
        notice_modal.setup(self, title)
    notice_modal.show_notice(title, text)

## R124 · pergunta antes de sair do jogo (ex.: COMUNIDADE abre o Discord numa aba nova)
func ask(title: String, text: String, yes_text: String, no_text: String, action: Callable, no_action := Callable()):
    if not is_instance_valid(notice_modal):
        notice_modal = load("res://ui_v022/notice_modal.gd").new()
        add_child(notice_modal)
        notice_modal.setup(self, title)
    notice_modal.ask(title, text, yes_text, no_text, action, no_action)

func open_community():
    # R176.2 · COMUNIDADE reúne o Discord e o Instagram (o Instagram saiu da tela do jogo)
    # R198 · a ARTE do dono (textos e botões na imagem): DISCORD · INSTAGRAM · AGORA NÃO
    if ResourceLoader.exists("res://ui_kit/art/community_dialog.png"):
        if get_tree().root.get_node_or_null("CommunityDialog") != null: return
        preload("res://ui_kit/art_dialog.gd").open(self, "res://ui_kit/art/community_dialog.png", [
            [Rect2(23, 365, 440, 127), CommunityLink.open],
            [Rect2(473, 365, 458, 127), InstagramLink.open],
            [Rect2(945, 365, 447, 127), null]], "CommunityDialog")
        return
    if not is_instance_valid(notice_modal):
        notice_modal = load("res://ui_v022/notice_modal.gd").new()
        add_child(notice_modal)
        notice_modal.setup(self, "COMUNIDADE")
    notice_modal.ask_two("COMUNIDADE", "DISCORD: desafios, torneios e suporte.\nINSTAGRAM: @fraihaxadrez\n\nO app escolhido abre fora do jogo.",
        "DISCORD", CommunityLink.open, "INSTAGRAM", InstagramLink.open, "AGORA NÃO")

func open_legal(tab := "termos"):
    if not is_instance_valid(legal_ui):
        legal_ui = load("res://ui_v022/legal_ui.gd").new()
        add_child(legal_ui)
        legal_ui.setup(self, account)
    legal_ui.show_legal(tab)

func open_global_chat():
    if not is_instance_valid(global_chat_ui):
        global_chat_ui = load("res://ui_v022/global_chat_ui.gd").new()
        add_child(global_chat_ui)
        global_chat_ui.setup(self, account)
    if is_instance_valid(leaderboard_ui): leaderboard_ui.close()
    global_chat_ui.show_chat()

## R96 · ícone de som da Home desligado = som geral mudo OU música e efeitos no zero.
func home_sound_off() -> bool:
    return sound_muted or (music_muted and effects_muted)

## R96 · botão de som da Home: abre o painel com MÚSICA e EFEITOS deslizantes (antes só mutava).
## Se o som geral estava mudo (preferência antiga do botão), liga de novo para as barras valerem.
func open_home_volume(btn: Control):
    if sound_muted: set_sound_muted(false)
    var r := Rect2(get_viewport().get_visible_rect().size.x - 80, 10, 60, 60)
    if is_instance_valid(btn):
        var xf := btn.get_global_transform_with_canvas()
        r = Rect2(xf.origin, btn.size * xf.get_scale())
    preload("res://ui_v022/mode_sound.gd").volume_popup(self, "both", r)

func _refresh_sound_button():
    if is_instance_valid(mobile_ui) and mobile_ui.has_method("refresh_sound"): mobile_ui.refresh_sound()
    if not is_instance_valid(sound_button): return
    sound_button.glyph = "sound_off" if home_sound_off() else "sound_on"
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
    if not await preload("res://web_content/conteudo_extra.gd").ensure("XEQUE"): return   # R115
    if xeque == null:
        xeque = load("res://xeque/xeque_ui.gd").new()
        xeque.setup(self, get_parent())
        get_parent().add_child(xeque)
        xeque.closed.connect(func(): _cover_home(false))
    _cover_home(true)
    xeque.open()

func open_marcha():
    if not await preload("res://web_content/conteudo_extra.gd").ensure("MARCHA REAL"): return   # R115
    if marcha == null:
        marcha = load("res://marcha/marcha_ui.gd").new()
        marcha.setup(self, get_parent())
        get_parent().add_child(marcha)
        marcha.closed.connect(func(): _cover_home(false))
    _cover_home(true)
    marcha.open()

## R81 · com a MARCHA ou o XEQUE aberto (tela cheia por cima), a Home de baixo some de verdade: antes ela continuava
## sendo desenhada e animada escondida atrás (≈ metade do trabalho de cada quadro), o que pesava no celular.
var _home_covered := false
var _home_was_visible := true
var _forest_was_visible := true
func _cover_home(on: bool):
    if on == _home_covered: return
    _home_covered = on
    var forest = get_parent().get_node_or_null("ForestExtensions")
    if on:
        _home_was_visible = root.visible
        root.visible = false
        if forest != null:
            _forest_was_visible = forest.visible
            forest.visible = false
    else:
        root.visible = _home_was_visible
        if forest != null: forest.visible = _forest_was_visible

## Club ativo (real OU simulação) → atualiza a fita da Home e o cartão do jogador.
## Selo Fundador: cartão da Home (ao lado do nome), Perfil e cartão do celular.
func refresh_founder():
    if ref_mode: _fit_ref_name()   # R55 · o nome muda (conta, edição): reajusta o tamanho
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
    if is_instance_valid(ref_title_label):
        ref_title_label.text = Cosmetics.title_text(title) if not title.is_empty() else ""
        var tc := Cosmetics.title_color(title)   # R176.9 · cor própria do título + brilho da mesma cor
        ref_title_label.add_theme_color_override("font_color", tc)
        ref_title_label.add_theme_color_override("font_outline_color", Color(tc.r, tc.g, tc.b, 0.35))
        ref_title_label.add_theme_constant_override("outline_size", 6)
        ref_title_label.visible = not title.is_empty() and ref_mode
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
        ref_founder_badge.visible = false   # R138 · o cartão da Home não mostra mais o ícone (ficava colado no brasão da liga e borrado); ele segue no Perfil e na partida
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
    if premove_button.has_meta("ref_labels"):
        var labs: Array = premove_button.get_meta("ref_labels")
        labs[0].text = "Pré-move: " + ("Ligado" if premove_enabled else "Desligado")
        labs[1].text = sub
        if labs[0] is Label: _fit_plate_title(labs[0])
        return
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
    board_color_pref = String(config.get_value("board","casas",BoardColors.MADEIRA))
    piece_color_pref = String(config.get_value("board","pecas",BoardColors.ORIGINAL))
    effective_board_color()
    effective_piece_color()

## R139 · TABULEIRO E PEÇAS: cores escolhidas (cosmetics/board_colors.gd). O que estiver bloqueado (liga ainda não
## conquistada, Club vencido…) cai para o padrão sem apagar a escolha.
signal board_colors_changed
var board_color_pref := "madeira"
var piece_color_pref := "original"
func effective_board_color() -> String:
    BoardColors.current_board = board_color_pref if BoardColors.board_unlocked(board_color_pref, self) else BoardColors.MADEIRA
    return BoardColors.current_board
func effective_piece_color() -> String:
    BoardColors.current_pieces = piece_color_pref if BoardColors.pieces_unlocked(piece_color_pref, self) else BoardColors.ORIGINAL
    return BoardColors.current_pieces
func set_board_colors(board_id: String, piece_id: String):
    if not board_id.is_empty() and BoardColors.board_unlocked(board_id, self): board_color_pref = board_id
    if not piece_id.is_empty() and BoardColors.pieces_unlocked(piece_id, self): piece_color_pref = piece_id
    _save_preferences()
    effective_board_color()
    effective_piece_color()
    board_colors_changed.emit()

var board_colors_ui = null
func open_board_colors():
    if not is_instance_valid(board_colors_ui):
        board_colors_ui = load("res://ui_v022/board_colors_ui.gd").new()
        add_child(board_colors_ui)
        board_colors_ui.setup(self)
    board_colors_ui.open()

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
    config.set_value("board","casas",board_color_pref)
    config.set_value("board","pecas",piece_color_pref)
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
    # R168 · moldura de ARTE: o buraco dela encaixa no retrato de verdade (o host da Home é 4 px maior que o retrato
    # por causa da moldura Club desenhada; com a arte sobrava uma fresta azul em cima e embaixo)
    var inset: float = float(portrait.get_meta("art_inset", 0.0)) if preload("res://monetization/club_frame.gd").is_art(fr) else 0.0
    frame.fill_parent = false
    frame.set_anchors_preset(Control.PRESET_FULL_RECT)
    frame.offset_left = inset
    frame.offset_top = inset
    frame.offset_right = -inset
    frame.offset_bottom = -inset
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
    return Cosmetics.effective("title", title_pref, is_founder(), club_active(), is_legend())

func current_frame() -> String:
    _sync_highest_league()
    return Cosmetics.effective("frame", frame_pref, is_founder(), club_active())

## R166 · molduras de ELO: liberadas pela maior liga já alcançada (dado do Ranked que a Home já tem)
func _sync_highest_league():
    if league_profile == null: return
    var d = league_profile.data
    var hid := String(d.get("highest_league", d.get("current_league", "madeira")))
    Cosmetics.highest_league = maxi(LeagueCatalog.index_of(hid), LeagueCatalog.index_of(String(d.get("current_league", "madeira"))))

func current_badge_texture(small := true) -> Texture2D:
    return Cosmetics.badge_texture(current_badge(), small)

## kind: "badge" | "title" | "frame". id "auto" volta ao automático. Bloqueado → false (nada muda).
func set_cosmetic(kind: String, id: String) -> bool:
    _sync_highest_league()
    var options: Array = Cosmetics.BADGES if kind == "badge" else (Cosmetics.TITLES if kind == "title" else Cosmetics.FRAMES)
    if id != "auto" and id not in options: return false
    if id != "auto" and not Cosmetics.allowed(kind, id, is_founder(), club_active(), is_legend()): return false
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
    return {"avatar_id": av, "badge": Cosmetics.effective("badge", badge_pref, f, c), "title": Cosmetics.effective("title", title_pref, f, c, is_legend()), "frame": Cosmetics.effective("frame", frame_pref, f, c)}

# ---------- Home "referência" (arte oficial com moldura, perfil, conta, versão e Ranqueado desenhados) ----------
# Na arte FOREST_V2 os painéis e botões já estão desenhados; aqui só entra o conteúdo vivo
# (retrato, nickname, liga/PL, barra, insígnia, texto da conta) e as áreas de clique.
# R55 · PAINEL DE PERFIL da Home (PC): moldura nova do dono (tools/home_profile_art.py) sobre o painel antigo.
# Medidas em px da arte da Home (1672x941): referência 1774x887 escalada para PROFILE_FRAME_RECT.
## R55.4 · só a Home do PC usa estas artes: carregadas ao montar o painel no PC, nunca no celular.
const PROFILE_FRAME_PATH := "res://ui_v022/art/home_profile_frame.png"
const PROFILE_UNDER_PATH := "res://ui_v022/art/home_profile_under.png"   # a Home sem o painel antigo
const PROFILE_UNDER_SIZE := Vector2(476, 252)
const PROFILE_UNDER_POS := Vector2(1196, 6)
const PROFILE_FRAME_RECT := Rect2(1198, 19.5, 470, 235)
const PROFILE_BODY := Rect2(1214, 36.5, 438, 200)     # área clicável (corpo da moldura, sem os ornamentos de fora)
const PROFILE_PORTRAIT := Rect2(1253.5, 77, 87, 83)   # R168: medido no print (o vão vai de y 77 a 159; antes sobrava azul em cima e embaixo) · R65: o retrato preenche todo o vão da moldura (medido em home_profile_frame.png: 1254.2,77.8 · 85.9×77.4)
const PROFILE_NAME := Rect2(1410, 64, 150, 40)
const PROFILE_LEAGUE := Rect2(1360, 102, 196, 30)
const PROFILE_BAR := Rect2(1365.6, 135.8, 180, 12.6)   # R176.8 · enche o trilho da arte (sem a linha azul em cima)
const PROFILE_BADGE := Rect2(1561, 82, 60, 76)
const PROFILE_STATUS := Rect2(1290, 172, 284, 46)
const PROFILE_STATUS_EDIT := Rect2(1580, 178, 22, 22)
const PROFILE_NAME_FONT := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const PROFILE_LEAGUE_FONT := preload("res://ui_kit/fonts/Alegreya-Bold.woff")
const PROFILE_STATUS_FONT := preload("res://ui_kit/fonts/Alegreya-Medium.woff")
const STATUS_DEFAULT := "“O xadrez é a ginástica da inteligência.”"
const STATUS_DEFAULT_AUTHOR := "— Blaise Pascal"
var ref_status_label: Label
var ref_status_author: Label
var ref_status_edit: Button
var status_editor: Control
var status_input: LineEdit
var status_count: Label
var status_note: Label

const REF_MENU_RECT = Rect2(616.56,319.6,430.56,529.0)   # R36/R43: miolo do menu da arte v7 (entre os pilares, menu 92%)
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

var ref_league_label: Label
var ref_title_label: Label   # R169 · título (Loja de Coroas / Fundador / Club) embaixo da barra de PL no cartão da Home
var ref_league_fill: ColorRect
var desk_league_label: Label
var desk_league_bar: Control

## Liga/PL do cartão da Home = a do RANKED da conta (servidor), no ritmo em que o jogador está melhor
## (maior liga; empate → mais PL). O perfil local nunca ganha PL; sem conta continua Madeira 0.
## Antes o cartão lia só o perfil local e ficava "Madeira · 0 / 100 PL" mesmo depois de subir de liga.
static func best_ranked_standing(ranked) -> Dictionary:
    var best := {}
    if not ranked is Dictionary: return best
    for mode in ranked:
        var st = ranked[mode]
        if not st is Dictionary: continue
        var lg := clampi(int(st.get("league", 0)), 0, LeagueCatalog.IDS.size() - 1)
        var pl := clampi(int(st.get("pl", 0)), 0, 100)
        if best.is_empty() or lg > int(best.league) or (lg == int(best.league) and pl > int(best.pl)):
            best = {"league": lg, "pl": pl, "mode": String(mode), "highest": clampi(int(st.get("highest_league", lg)), lg, LeagueCatalog.IDS.size() - 1)}
    return best

func apply_ranked_standing(ranked):
    var best := best_ranked_standing(ranked)
    var d: Dictionary = league_profile.data
    var lid: String = LeagueCatalog.IDS[int(best.league)] if not best.is_empty() else "madeira"
    var lp: int = int(best.pl) if not best.is_empty() else 0
    var hid: String = LeagueCatalog.IDS[int(best.highest)] if not best.is_empty() else "madeira"
    if String(d.current_league) == lid and int(d.lp) == lp and String(d.get("highest_league", "")) == hid: return
    # Só em memória (o arquivo local não recebe PL do servidor).
    d.current_league = lid
    d.lp = lp
    d.highest_league = hid
    _refresh_league_widgets()

func _refresh_league_widgets():
    var d: Dictionary = league_profile.data
    var cur = LeagueCatalog.entry(d.current_league, d)
    var txt := "%s · %d / 100 PL" % [cur.display_name, int(d.lp)]
    var k := clampf(float(d.lp) / 100.0, 0.0, 1.0)
    if is_instance_valid(ref_league_label): ref_league_label.text = txt
    if is_instance_valid(ref_league_fill): ref_league_fill.size.x = PROFILE_BAR.size.x * k
    if is_instance_valid(desk_league_label): desk_league_label.text = txt
    if is_instance_valid(desk_league_bar) and desk_league_bar.has_method("set_value"): desk_league_bar.set_value(float(d.lp))
    elif is_instance_valid(desk_league_bar) and "value" in desk_league_bar: desk_league_bar.value = float(d.lp)
    if not desk_profile.is_empty() and is_instance_valid(desk_profile.portrait): attach_league_frame(desk_profile.portrait)
    _use_profile(ref_mode)
    if is_instance_valid(mobile_ui) and mobile_ui.has_method("queue_redraw_cards"): mobile_ui.queue_redraw_cards()

## R55 · moldura nova + remendo (a Home sem o painel antigo) + STATUS do jogador com lápis para editar.
func _build_profile_frame(pbtn: Control):
    var desk: bool = not preload("res://ui_v022/mobile_layout.gd").active(get_viewport())   # R55.4
    var under := TextureRect.new()
    under.name = "RefProfileUnder"
    if desk: under.texture = load(PROFILE_UNDER_PATH)
    under.position = PROFILE_UNDER_POS - pbtn.position
    under.size = PROFILE_UNDER_SIZE
    under.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(under)
    var frame := TextureRect.new()
    frame.name = "RefProfileFrame"
    if desk: frame.texture = load(PROFILE_FRAME_PATH)
    frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    frame.stretch_mode = TextureRect.STRETCH_SCALE
    frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    frame.position = PROFILE_FRAME_RECT.position - pbtn.position
    frame.size = PROFILE_FRAME_RECT.size
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(frame)
    ref_status_label = Label.new()
    ref_status_label.name = "RefProfileStatus"
    ref_status_label.add_theme_font_override("font", PROFILE_STATUS_FONT)
    ref_status_label.add_theme_font_size_override("font_size", 16)
    ref_status_label.add_theme_color_override("font_color", Color("f1e6cc"))
    ref_status_label.add_theme_color_override("font_outline_color", Color(0.043, 0.052, 0.071, 0.9))
    ref_status_label.add_theme_constant_override("outline_size", 3)
    ref_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ref_status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    ref_status_label.position = PROFILE_STATUS.position - pbtn.position
    ref_status_label.size = PROFILE_STATUS.size
    ref_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(ref_status_label)
    ref_status_author = Label.new()
    ref_status_author.name = "RefProfileStatusAuthor"
    ref_status_author.text = STATUS_DEFAULT_AUTHOR
    ref_status_author.add_theme_font_override("font", PROFILE_STATUS_FONT)
    ref_status_author.add_theme_font_size_override("font_size", 16)
    ref_status_author.add_theme_color_override("font_color", Color("f1e6cc"))
    ref_status_author.add_theme_color_override("font_outline_color", Color(0.043, 0.052, 0.071, 0.9))
    ref_status_author.add_theme_constant_override("outline_size", 3)
    ref_status_author.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    ref_status_author.position = Vector2(PROFILE_STATUS.position.x, PROFILE_STATUS.position.y + 22) - pbtn.position
    ref_status_author.size = Vector2(PROFILE_STATUS.size.x - 6, 22)
    ref_status_author.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(ref_status_author)
    # lápis: editar o status (não abre o Perfil)
    ref_status_edit = Button.new()
    ref_status_edit.name = "RefStatusEdit"
    ref_status_edit.tooltip_text = "Editar status"
    ref_status_edit.focus_mode = Control.FOCUS_NONE
    ref_status_edit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    ref_status_edit.position = PROFILE_STATUS_EDIT.position - pbtn.position
    ref_status_edit.size = PROFILE_STATUS_EDIT.size
    for st in ["normal", "hover", "pressed", "focus", "disabled"]:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.070, 0.102, 0.168, 0.0 if st == "normal" else 0.75)
        sb.set_corner_radius_all(4)
        ref_status_edit.add_theme_stylebox_override(st, sb)
    ref_status_edit.draw.connect(func(): _draw_pencil(ref_status_edit))
    ref_status_edit.mouse_entered.connect(ref_status_edit.queue_redraw)
    ref_status_edit.mouse_exited.connect(ref_status_edit.queue_redraw)
    ref_status_edit.pressed.connect(open_status_editor)
    pbtn.add_child(ref_status_edit)
    refresh_profile_status()

## Lápis dourado desenhado (sem fonte de ícones).
func _draw_pencil(b: Control):
    var col := Color("ffe39a") if b.is_hovered() else Color("e7c46e")
    var r := Rect2(Vector2.ZERO, b.size).grow(-3)
    var a := r.position + Vector2(r.size.x * 0.18, r.size.y * 0.82)
    var z := r.position + Vector2(r.size.x * 0.84, r.size.y * 0.16)
    var d := (z - a).normalized()
    var n := Vector2(-d.y, d.x) * r.size.x * 0.13
    var tip := a - d * r.size.x * 0.12
    b.draw_colored_polygon(PackedVector2Array([a + n, z + n, z - n, a - n]), col)
    b.draw_colored_polygon(PackedVector2Array([a + n, a - n, tip]), Color("f6e9c8"))
    b.draw_line(z + n * 1.1 - d * r.size.x * 0.16, z - n * 1.1 - d * r.size.x * 0.16, Color(0.12, 0.08, 0.03), 1.5)

## Quebra o status em no máximo 2 linhas na largura do painel. Devolve [texto com \\n, tamanho da letra].
func _wrap_status(text: String) -> Array:
    var f: Font = PROFILE_STATUS_FONT
    var room: float = PROFILE_STATUS.size.x - 8.0
    for fs in [16, 15, 14, 13]:
        var lines := _wrap_words(text, f, fs, room)
        if lines.size() <= 2: return ["\n".join(lines), fs]
    var l2 := _wrap_words(text, f, 13, room)
    var second := String(l2[1])
    while second.length() > 1 and f.get_string_size(second + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > room: second = second.left(-1)
    return [String(l2[0]) + "\n" + second.strip_edges() + "…", 13]

static func _wrap_words(text: String, f: Font, fs: int, room: float) -> Array:
    var lines: Array = []
    var cur := ""
    for w in text.split(" ", false):
        var tryline := w if cur.is_empty() else cur + " " + w
        if f.get_string_size(tryline, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= room or cur.is_empty():
            cur = tryline
            # palavra sozinha maior que a linha (sem espaços): corta em pedaços
            while f.get_string_size(cur, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room and cur.length() > 1:
                var cut := cur.length() - 1
                while cut > 1 and f.get_string_size(cur.left(cut), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room: cut -= 1
                lines.append(cur.left(cut))
                cur = cur.substr(cut)
        else:
            lines.append(cur)
            cur = w
    if not cur.is_empty(): lines.append(cur)
    return lines

## R55 · nome do painel: grande como na referência; nomes compridos diminuem até caber (sem "…").
func _fit_ref_name():
    if ref_profile.is_empty(): return
    var nl: Label = ref_profile.name
    var f: Font = PROFILE_NAME_FONT
    var fs := 30
    while fs > 16 and f.get_string_size(nl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > PROFILE_NAME.size.x - 4: fs -= 1
    nl.add_theme_font_size_override("font_size", fs)
    var h := ceilf(f.get_height(fs)) + 2.0          # a linha inteira precisa caber na caixa (senão o Label a esconde)
    nl.custom_minimum_size.y = h
    nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    nl.position = Vector2(PROFILE_NAME.position.x, PROFILE_NAME.get_center().y - h / 2.0) - PROFILE_BODY.position
    nl.size = Vector2(PROFILE_NAME.size.x, h)

func profile_status_text() -> String:
    if account != null and account.has_method("profile_status"): return String(account.profile_status())
    return ""

func refresh_profile_status():
    if not is_instance_valid(ref_status_label): return
    var st := profile_status_text()
    if st.is_empty():
        ref_status_label.text = STATUS_DEFAULT
        ref_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        ref_status_author.visible = true
        ref_status_label.add_theme_font_size_override("font_size", 16)
    else:
        ref_status_author.visible = false
        # até 2 linhas, quebrando nas palavras; a letra diminui um pouco e, se ainda não couber, "…" no fim
        var fit := _wrap_status("“%s”" % st)
        ref_status_label.text = fit[0]
        ref_status_label.add_theme_font_size_override("font_size", fit[1])
    ref_status_edit.visible = ref_mode
    ref_status_label.visible = not _status_editing   # R64: editando, o campo fica no lugar da frase
    if _status_editing: ref_status_author.visible = false

# ---------- R64 · edição do STATUS no PRÓPRIO painel (só o lápis; sem janela) ----------
## O lápis troca a frase por um campo de texto no mesmo lugar, mesma letra. ENTER salva, ESC cancela,
## clicar fora salva (se mudou). Contador pequeno no lugar do autor. Limite: account_service.STATUS_MAX (40).
func open_status_editor():
    if status_editor == null: _build_status_editor()
    var logged: bool = account != null and account.has_profile()
    var cur := profile_status_text()
    # frase antiga acima do limite novo: aparece inteira (sem corte silencioso); o campo só deixa encurtar
    status_input.max_length = maxi(_status_max(), cur.length())
    status_input.text = cur
    status_input.editable = logged
    _status_editing = true
    ref_status_label.visible = false
    ref_status_author.visible = false
    status_note.text = "" if logged else "Entre na sua conta para salvar."
    status_note.add_theme_color_override("font_color", Color("ff9d86"))
    _status_count()
    status_editor.show()
    if logged:
        status_input.grab_focus()
        status_input.caret_column = status_input.text.length()

func close_status_editor():
    if status_editor == null or not status_editor.visible: return
    _status_editing = false
    status_editor.hide()
    if status_input.has_focus(): status_input.release_focus()
    refresh_profile_status()

var _status_editing := false

func _status_max() -> int:
    return int(account.STATUS_MAX) if account != null else 40

func status_can_save() -> bool:
    return account != null and account.has_profile() and status_input != null and status_input.text.length() <= _status_max()

func _status_count():
    if status_count == null: return
    var n: int = status_input.text.length()
    var lim := _status_max()
    if status_input.max_length > lim and n < status_input.max_length:   # frase antiga longa: só encolhe
        var cc := status_input.caret_column                              # (trocar max_length volta o cursor ao início)
        status_input.max_length = maxi(lim, n)
        status_input.caret_column = cc
    status_count.text = "%d/%d" % [n, lim]
    status_count.add_theme_color_override("font_color", Color("ff9d86") if n > lim else Color(0.95, 0.9, 0.8, 0.7))
    if n > lim:
        status_note.text = "encurte para salvar"
    elif status_note.text == "encurte para salvar":
        status_note.text = ""

func save_status():
    if account == null or not account.has_profile(): return
    var t: String = account.clean_status(status_input.text)
    if t.length() > _status_max():
        _status_count()
        return
    if t == profile_status_text():
        close_status_editor()
        return
    if account.set_status(t):
        status_input.editable = false
        status_note.text = "salvando…"
        status_note.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8, 0.7))
    else:
        status_note.text = "sem conexão"
        status_note.add_theme_color_override("font_color", Color("ff9d86"))

func _on_status_saved(_st: String):
    if status_editor != null and status_editor.visible:
        status_input.editable = true
        _status_editing = false
        status_editor.hide()
    refresh_profile_status()

func _on_status_failed(_code: String, message: String):
    if status_editor == null or not status_editor.visible: return
    status_input.editable = account != null and account.has_profile()
    status_note.text = message if not message.is_empty() else "não foi possível salvar"
    status_note.add_theme_color_override("font_color", Color("ff9d86"))

func _build_status_editor():
    var host: Control = ref_status_label.get_parent()
    status_editor = Control.new()
    status_editor.name = "StatusEditor"
    status_editor.position = ref_status_label.position
    status_editor.size = PROFILE_STATUS.size
    status_editor.mouse_filter = Control.MOUSE_FILTER_IGNORE
    host.add_child(status_editor)
    status_input = LineEdit.new()
    status_input.name = "StatusInput"
    status_input.max_length = _status_max()
    status_input.placeholder_text = "Escreva sua frase"
    status_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
    status_input.add_theme_font_override("font", PROFILE_STATUS_FONT)
    status_input.add_theme_font_size_override("font_size", 16)
    status_input.add_theme_color_override("font_color", Color("f1e6cc"))
    status_input.add_theme_color_override("font_placeholder_color", Color(0.95, 0.9, 0.8, 0.45))
    status_input.add_theme_color_override("caret_color", Color("f4ce7f"))
    status_input.add_theme_color_override("selection_color", Color(0.85, 0.66, 0.25, 0.35))
    status_input.add_theme_color_override("font_outline_color", Color(0.043, 0.052, 0.071, 0.9))
    status_input.add_theme_constant_override("outline_size", 3)
    for st in ["normal", "focus", "read_only"]:
        status_input.add_theme_stylebox_override(st, StyleBoxEmpty.new())   # sem caixa: a frase vira o campo
    status_input.position = Vector2(0, -3)
    status_input.size = Vector2(PROFILE_STATUS.size.x, 26)
    status_input.context_menu_enabled = false
    status_input.text_changed.connect(func(_t): _status_count())
    status_input.text_submitted.connect(func(_t): save_status())
    status_input.focus_exited.connect(func(): if _status_editing and status_input.editable: save_status())
    status_editor.add_child(status_input)
    status_note = Label.new()
    status_note.name = "StatusNote"
    status_note.add_theme_font_size_override("font_size", 12)
    status_note.add_theme_color_override("font_outline_color", Color(0.043, 0.052, 0.071, 0.9))
    status_note.add_theme_constant_override("outline_size", 3)
    status_note.position = Vector2(4, 24)
    status_note.size = Vector2(PROFILE_STATUS.size.x - 60, 18)
    status_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
    status_editor.add_child(status_note)
    status_count = Label.new()
    status_count.name = "StatusCount"
    status_count.add_theme_font_size_override("font_size", 12)
    status_count.add_theme_color_override("font_outline_color", Color(0.043, 0.052, 0.071, 0.9))
    status_count.add_theme_constant_override("outline_size", 3)
    status_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    status_count.position = Vector2(PROFILE_STATUS.size.x - 60, 24)
    status_count.size = Vector2(54, 18)
    status_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
    status_editor.add_child(status_count)
    status_editor.hide()

## R64 · clicar/tocar fora do campo da frase termina a edição (salva se mudou).
func _input(e):
    if not _status_editing or status_input == null: return
    var down: bool = (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed)
    if down and not status_input.get_global_rect().has_point(e.position) \
            and not (is_instance_valid(ref_status_edit) and ref_status_edit.get_global_rect().has_point(e.position)):
        if status_input.has_focus(): status_input.release_focus()
        else: close_status_editor()

func _unhandled_key_input(e):
    if status_editor != null and status_editor.visible and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
        close_status_editor()
        get_viewport().set_input_as_handled()

func _is_ref_art(texture: Texture2D) -> bool:
    if texture == null: return ref_mode    # R89: arte do PC solta (celular) — mantém o estado atual
    return texture.resource_path == FOREST_PATH

func _build_reference_chrome():
    # Perfil
    var pbtn = TextureButton.new()
    pbtn.name = "RefProfileButton"
    pbtn.ignore_texture_size = true
    pbtn.position = PROFILE_BODY.position   # R55: painel novo (moldura do dono) por cima do antigo
    pbtn.size = PROFILE_BODY.size
    pbtn.focus_mode = Control.FOCUS_ALL
    pbtn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    pbtn.tooltip_text = "Perfil"
    canvas.add_child(pbtn)
    ref_nodes.append(pbtn)
    _build_profile_frame(pbtn)
    # CLUB FRAIHA: fita pendurada no cartão de perfil (entrada própria, fora de Configurações).
    # Canto superior esquerdo do HUD (antes ficava pendurado no cartão de perfil e invadia as páginas).
    club_entry = preload("res://monetization/club_home_entry.gd").new()
    club_entry.over_art = true   # R36: a placa é da arte v7
    club_entry.position = Vector2(22, 16)
    club_entry.size = Vector2(330, 62)
    club_entry.pressed.connect(func(): open_premium())   # R63 · SEJA MEMBRO → FRAIHA PREMIUM
    canvas.add_child(club_entry)
    ref_nodes.append(club_entry)
    refresh_club()
    sound_button = preload("res://ui_v022/hud_button.gd").make("sound_on")
    sound_button.name = "SoundButton"
    sound_button.size = Vector2(62, 62)
    sound_button.position = Vector2(364, 16)
    sound_button.pressed.connect(func(): open_home_volume(sound_button))   # R96 · painel MÚSICA / EFEITOS
    canvas.add_child(sound_button)
    # R96 · RANKING (troféu) e CHAT GLOBAL (balão), ao lado do som e da tela cheia
    trophy_button = make_top_button("trophy", "Ranking", open_leaderboard)
    trophy_button.position = Vector2(504, 16)
    canvas.add_child(trophy_button)
    gchat_button = make_top_button("chat", "Chat global", open_global_chat)
    gchat_button.position = Vector2(574, 16)
    canvas.add_child(gchat_button)
    # R112 · COROAS: saldo ao lado do chat (toque abre o painel)
    var crown_chip: Button = crowns_client().make_chip(62.0, 62.0)   # R122 · quadrado como os outros
    crown_chip.set_frame(TOP_FRAME_PC, 14.0)
    crown_chip.position = Vector2(644, 16)
    canvas.add_child(crown_chip)
    # R162 · MENSAGENS: envelope ao lado da coroa, com a bolinha das não lidas; abre a caixa de mensagens
    var mail := make_mail_button(62.0)
    mail.position = Vector2(714, 16)
    canvas.add_child(mail)
    # R176.8c · SUPORTE: fone ao lado do envelope (abre a tela de tickets)
    var sup := make_top_button("support", "Falar com o suporte", open_support)
    sup.name = "SupportTopButton"
    sup.position = Vector2(784, 16)
    canvas.add_child(sup)
    # R122 · COMUNIDADE (Discord): canto de baixo à direita, espelhando o cartão ENTRAR / CRIAR CONTA
    # R196 · a ARTE do dono (placa COMUNIDADE pronta) no lugar do botão desenhado
    var community: Button = preload("res://ui_kit/art_plate_button.gd").make("res://ui_kit/art/community_plate.png", "CommunityButton", Vector2(262, 64))
    community.tooltip_text = CommunityLink.TIP
    community.pressed.connect(open_community)   # R124 · pergunta antes de abrir o Discord
    community.position = Vector2(1388, 856)
    canvas.add_child(community)
    # R178 · PASSE DA TEMPORADA bem à vista: cartão dourado no topo esquerdo, embaixo do CLUB (toque abre o Passe)
    var pass_card := PassHomeCard.new()
    pass_card.setup(self, "card")
    pass_card.neon = true   # R196 · neon roxo acendendo e apagando
    pass_card.position = Vector2(PASS_CARD_PC.position)
    pass_card.size = PASS_CARD_PC.size
    canvas.add_child(pass_card)
    # R180 · BETA: WhatsApp do dono embaixo do PASSE (dúvidas e bugs)
    var wa := WhatsAppButton.new()
    wa.art = true   # R196 · a arte do dono
    wa.position = WA_PC.position
    wa.size = WA_PC.size
    canvas.add_child(wa)
    # R184 · BAIXAR O APP (site no PC): logo abaixo do WhatsApp, mesmo tamanho
    var AppBtn = load("res://ui_kit/app_download_button.gd")
    if AppBtn.should_show():
        var ab: Button = AppBtn.new()
        ab.name = "AppDownloadButton"
        ab.art = true   # R196 · a arte do dono, ao lado do WhatsApp e do mesmo tamanho
        ab.position = APP_PC.position
        ab.size = APP_PC.size
        canvas.add_child(ab)
    else:
        wa.position.x = PASS_CARD_PC.position.x + (PASS_CARD_PC.size.x - WA_PC.size.x) * 0.5   # sozinho: no meio
    # R161 · OUTDOOR: a faixa "ESTRATÉGIA PARA IR MAIS LONGE" vira a frase do Admin e abre NOVIDADES
    var ticker := make_news_ticker(19, Color("010612"), Color("030b1c"))
    ticker.position = Vector2(631, 273)
    ticker.size = Vector2(390, 29)
    canvas.add_child(ticker)
    _refresh_sound_button()
    var clip = Control.new()
    clip.name = "RefPortraitClip"
    clip.clip_contents = true
    clip.position = PROFILE_PORTRAIT.position - pbtn.position   # R55: miolo da moldura do retrato (arte nova)
    clip.size = PROFILE_PORTRAIT.size
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
    club_host.set_meta("art_inset", 6.0)   # R168 · arte cobre 2 px da borda do retrato: nada de fresta
    ref_profile_club_host = club_host
    attach_club_frame(club_host)
    var name_label = _label(pbtn, player_name, 30, Color("f8ebc8"))
    name_label.name = "RefProfileName"
    name_label.add_theme_font_override("font", PROFILE_NAME_FONT)
    name_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.01, 0.9))
    name_label.add_theme_constant_override("outline_size", 4)
    _single_line(name_label)
    name_label.position = PROFILE_NAME.position - pbtn.position
    name_label.size = PROFILE_NAME.size
    var current = LeagueCatalog.entry(league_profile.data.current_league,league_profile.data)
    var league = _label(pbtn, "%s · %d / 100 PL" % [current.display_name,league_profile.data.lp], 21, Color("f3dba0"))
    league.add_theme_font_override("font", PROFILE_LEAGUE_FONT)
    league.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.01, 0.85))
    league.add_theme_constant_override("outline_size", 3)
    ref_league_label = league
    _single_line(league)
    league.position = PROFILE_LEAGUE.position - pbtn.position
    league.size = PROFILE_LEAGUE.size
    ref_title_label = Label.new()
    ref_title_label.name = "RefTitle"
    ref_title_label.add_theme_font_override("font", PROFILE_LEAGUE_FONT)
    ref_title_label.add_theme_font_size_override("font_size", 15)
    ref_title_label.add_theme_color_override("font_color", Color("f6d27a"))
    ref_title_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.01, 0.85))
    ref_title_label.add_theme_constant_override("outline_size", 3)
    ref_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ref_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    ref_title_label.clip_text = true
    ref_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ref_title_label.position = Vector2(PROFILE_BAR.position.x - 6, PROFILE_BAR.end.y + 1) - pbtn.position
    ref_title_label.size = Vector2(PROFILE_BAR.size.x + 12, 20)
    ref_title_label.visible = false
    pbtn.add_child(ref_title_label)
    var fill = ColorRect.new()
    fill.color = Color("f2bd3c")
    fill.position = PROFILE_BAR.position - pbtn.position   # R55: dentro do trilho da barra da arte nova
    fill.size = Vector2(PROFILE_BAR.size.x * clampf(league_profile.data.lp / 100.0, 0.0, 1.0), PROFILE_BAR.size.y)
    var shine = ColorRect.new()                              # brilho de cima do ouro (como na referência)
    shine.color = Color(1.0, 0.93, 0.62, 0.75)
    shine.position = Vector2.ZERO
    shine.size = Vector2(0, PROFILE_BAR.size.y * 0.32)
    shine.set_anchors_preset(Control.PRESET_TOP_WIDE)
    shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
    fill.add_child(shine)
    ref_league_fill = fill
    fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(fill)
    # Insígnia da liga: a arte já traz a da Madeira; outras ligas cobrem com a insígnia viva.
    ref_badge_plate = Panel.new()
    var plate = StyleBoxFlat.new()
    plate.bg_color = Color(0.000, 0.060, 0.181)
    plate.set_corner_radius_all(6)
    ref_badge_plate.add_theme_stylebox_override("panel", plate)
    ref_badge_plate.position = PROFILE_BADGE.position - pbtn.position
    ref_badge_plate.size = PROFILE_BADGE.size
    ref_badge_plate.visible = false   # R55: a arte nova não traz insígnia pintada (a viva vale para todas as ligas)
    ref_badge_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pbtn.add_child(ref_badge_plate)
    ref_badge = TextureRect.new()
    ref_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    ref_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    ref_badge.position = PROFILE_BADGE.position - pbtn.position
    ref_badge.size = PROFILE_BADGE.size
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
    ref_account_avatar.position = Vector2(39.5,844.5)   # R36: centro do medalhão da arte v7 · R176.8: enche o círculo até o dourado
    ref_account_avatar.size = Vector2(71,71)
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
    cover.bg_color = Color(0.042, 0.084, 0.168)
    cover.set_corner_radius_all(4)
    ref_menu_cover.add_theme_stylebox_override("panel", cover)
    ref_menu_cover.position = PC_COVER.position
    ref_menu_cover.size = PC_COVER.size
    ref_menu_cover.clip_contents = false
    ref_menu_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(ref_menu_cover)
    canvas.move_child(ref_menu_cover, canvas.get_node("MainMenu").get_index())
    ref_nodes.append(ref_menu_cover)
    # R47: na arte v8 o Ranqueado não tem louros sobre a borda — nada a recompor nas páginas internas.
    # Botões do menu: ao passar o mouse / foco o PRÓPRIO botão da arte reluz (mesmos pixels,
    # somando luz nas partes douradas). Nada de caixa por cima nem texto extra.
    var glow_material = ShaderMaterial.new()
    glow_material.shader = preload("res://ui_v022/home_button_glow.gdshader")
    for i in menu_buttons.size():
        var button: TextureButton = menu_buttons[i]
        var ranked = title_of(button) == "JOGAR RANQUEADO"
        var offset = Vector2(-3, -3)
        var region = Rect2(PC_MENU[i].position + offset, PC_MENU[i].size + Vector2(6, 6))
        var atlas = AtlasTexture.new()
        atlas.atlas = FOREST
        _track_desk(atlas, FOREST)
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
        # R44.1: os textos NÃO ficam mais na arte (serrilhavam ao reduzir): o jogo escreve com a fonte
        # do jogo, nítida em qualquer tamanho de tela. Mesma coluna, mesmo tamanho em todas as linhas.
        _ref_caption(button, i)

## R47 · textos do botão no lugar e na medida do texto da referência (ui_v022/ref_text.gd).
func _ref_caption(button: TextureButton, i: int):
    var cap := Control.new()
    cap.name = "RefCaption"
    cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    cap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    button.add_child(cap)
    var RefText = preload("res://ui_v022/ref_text.gd")
    var origin: Vector2 = PC_MENU[i].position
    var big: bool = PC_SUB.has(i)
    var ranked: bool = i == 2
    var tr: Rect2 = PC_TITLE[i]
    var t = RefText.make(String(button.get_meta("title", "")), Rect2(tr.position - origin, tr.size), "default" if big else "squeeze", Color("ffd36e") if ranked else Color("f6f1e4"))
    t.name = "RefTitle"
    t.bold = 1 if big else 0
    if not big: t.outline_size = 2
    cap.add_child(t)
    if big:
        var sr: Rect2 = PC_SUB[i][1]
        var st = RefText.make(String(PC_SUB[i][0]), Rect2(sr.position - origin, Vector2(sr.size.x, 0)), "default", Color("f1ede2"))
        st.name = "RefSubtitle"
        st.outline_size = 2
        cap.add_child(st)
    cap.hide()

func _sync_chrome():
    var ref = _is_ref_art(canvas.get_node("ForestArtwork").texture)
    ref_mode = ref
    # R36: na arte v7 os quadrados de som / tela cheia já estão desenhados (o botão só põe o ícone)
    # R122 · agora com a moldura azul por cima (igual ao troféu, chat, coroas e comunidade)
    for b in [sound_button, fullscreen_button]:
        if not is_instance_valid(b): continue
        if ref: b.set_frame(TOP_FRAME_PC, 14.0)
        else:
            b.framed = false
            b.set_over_art(false)
    if is_instance_valid(presentation_frame): presentation_frame.queue_redraw()
    for n in ref_nodes: n.visible = ref
    close_status_editor()   # R55
    if is_instance_valid(ref_status_edit): ref_status_edit.visible = ref
    for name in ["ProfilePanel","AccountPanel"]:
        var n = canvas.get_node_or_null(name)
        if n != null: n.visible = not ref
    var plaque = canvas.get_node_or_null("RefAccountPlaque")
    if plaque != null: plaque.visible = ref
    if not desk_profile.is_empty(): desk_profile.stack.visible = not ref
    for n in ranked_extras: n.visible = not ref
    # Botões: na arte de referência o botão já está desenhado; o nosso vira área de clique transparente.
    for i in menu_buttons.size():
        var button: TextureButton = menu_buttons[i]
        # R47: na arte de referência cada botão fica sobre o botão desenhado; nos temas antigos, a coluna v7
        if not button.has_meta("legacy_rect"): button.set_meta("legacy_rect", Rect2(button.position, button.size))
        var lr: Rect2 = button.get_meta("legacy_rect")
        var rr: Rect2 = PC_MENU[i] if ref else lr
        button.position = rr.position
        button.custom_minimum_size = Vector2(0, rr.size.y)
        button.size = rr.size
        if not button.has_meta("atlas_texture"): button.set_meta("atlas_texture", button.texture_normal)
        var tex = null if ref else button.get_meta("atlas_texture")
        button.texture_normal = tex
        button.texture_hover = tex
        button.texture_pressed = tex
        button.texture_disabled = tex
        if button.get_child_count() > 0 and button.get_child(0) is MarginContainer: button.get_child(0).visible = not ref
        var rcap = button.get_node_or_null("RefCaption")
        if rcap != null: rcap.visible = ref and not REF_TEXT_IN_ART   # R64: texto já está na arte
        if ref_hovers.has(button) and not ref: ref_hovers[button].hide()
    # Cartão da conta: arte traz moldura, medalhão e seta; ficam só os textos vivos.
    if is_instance_valid(account_card):
        account_card.position = Vector2(38,846) if ref else Vector2(26,860)
        account_card.size = Vector2(322,72) if ref else Vector2(326,62)
        account_card.get_node("AccountIcon").visible = not ref
        var words = account_card_title.get_parent().get_parent()
        words.position = Vector2(95,10) if ref else Vector2(70,8)
        words.size = Vector2(196,60) if ref else Vector2(214,48)
        account_card_title.add_theme_font_size_override("font_size", 22 if ref else 18)   # R47: medida da referência
        account_card_subtitle.add_theme_font_size_override("font_size", 18 if ref else 13)
        account_card_subtitle.add_theme_color_override("font_color", Color("f2efe6") if ref else MUTED)
        for l in [account_card_title, account_card_subtitle]:   # 1 linha visível: a altura acompanha a fonte
            l.custom_minimum_size.y = ceilf(l.get_theme_font_size("font_size") * 1.42)
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
    profile_portrait.texture = slot_avatar_texture() if ref else avatar_texture()
    if ref: _fit_ref_name()
    refresh_founder.call_deferred()
    if ref:
        if is_instance_valid(ref_profile_club_host): attach_club_frame(ref_profile_club_host)
        # retratos quadrados preenchem a moldura; o medalhão redondo (Guerreiro) fica centralizado
        profile_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if avatar_id == "warrior" else TextureRect.STRETCH_KEEP_ASPECT_COVERED
        var league_id = String(league_profile.data.current_league)
        var madeira = league_id in ["madeira", "wood"]
        ref_badge.texture = ThemeCatalog.badge_texture("madeira" if madeira else league_id)   # R55: todas as ligas, ao vivo
        ref_badge.visible = true
        ref_badge_plate.visible = false
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
    # R36: na arte v7 a placa da conta faz parte do cenário; numa página interna os textos vivos
    # continuam nela (sem eles a placa ficaria vazia), a não ser na arte antiga/temas.
    var wide: bool = not home and pages.has(page) and pages[page] is Control and (pages[page] as Control).position.x < 400.0
    var keep := home or (ref_mode and not wide)
    for n in [account_card, ref_account_avatar, ref_account_frame_host]:
        if is_instance_valid(n):
            n.modulate.a = 1.0 if keep else 0.0
            n.z_index = 1   # por cima do fundo das páginas internas (a placa é da arte)
    if is_instance_valid(account_card): account_card.mouse_filter = Control.MOUSE_FILTER_STOP if keep else Control.MOUSE_FILTER_IGNORE
    var acct = canvas.get_node_or_null("AccountPanel")
    if acct != null: acct.modulate.a = 1.0 if home else 0.0
    var quit_cap = canvas.get_node_or_null("WebQuitCaption")
    if quit_cap != null: quit_cap.visible = ref_mode and home


# ---------- Conta ligada ao Home: nome público e foto (0004) ----------
func bind_account(acc):
    account = acc
    if bot_progress != null: bot_progress.setup(acc)
    if crowns != null and crowns.account == null: crowns.setup(self, acc)   # R112
    else: crowns_client()
    if nickname_editor != null and nickname_editor.account == null: nickname_editor.setup(acc, 18)
    acc.changed.connect(_on_account_changed)
    if acc.has_signal("status_saved"):   # R55 · status do perfil
        acc.status_saved.connect(_on_status_saved)
        acc.status_failed.connect(_on_status_failed)
    acc.avatar_saved.connect(func(url):
        _server_avatar_url = String(url)
        # A cópia local é exatamente a foto que acabou de ser enviada: marca a URL para não baixar de novo.
        if avatar_store != null and not String(url).is_empty() and avatar_store.has_local(avatar_key()): avatar_store.set_cached_url(avatar_key(), String(url))
        _avatar_message("Foto enviada para a sua conta." if not String(url).is_empty() else "Foto removida da conta.", false)
        _refresh_avatars())
    acc.avatar_failed.connect(func(_code, msg):
        _avatar_message("A foto ficou salva neste aparelho, mas a conta não a recebeu: " + msg, true))
    acc.entitlements_changed.connect(func(data): if entitlements != null: entitlements.apply_server(data))
    # R39 · saiu da conta (ou trocou): as vantagens da conta anterior não ficam nesta sessão
    acc.changed.connect(func(): if entitlements != null and entitlements.real_known and not acc.has_profile(): entitlements.clear_server())
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
    if av in AvatarCatalog.ids() and AvatarCatalog.has_art(av):
        avatar_id = av
        _focus_current_look()
    if not String(data.get("badge", "")).is_empty(): badge_pref = String(data.badge)
    if not String(data.get("title", "")).is_empty(): title_pref = String(data.title)
    if String(data.get("frame", "liga")) != "liga": frame_pref = String(data.frame)
    _save_preferences()
    refresh_club()

var _server_avatar_url := ""   # última URL informada pelo servidor nesta sessão (por conta)
var _avatar_resent := {}       # contas para as quais a foto local já foi reenviada nesta sessão

func _on_account_changed():
    refresh_profile_status()
    _refresh_name_boxes()
    refresh_online_button()
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

## R48 · JOGAR ONLINE reflete o servidor: com o Casual fechado pelo Admin (todos os ritmos ou a fila inteira),
## o subtítulo vira "Temporariamente indisponível" (PC e celular). O clique continua abrindo a tela, que
## mostra CASUAL TEMPORARIAMENTE INDISPONÍVEL sem nenhum ritmo para entrar; o servidor também recusa.
const ONLINE_OFF_TEXT := "Temporariamente indisponível"
func casual_available() -> bool:
    return account == null or not account.has_method("casual_available") or account.casual_available()

func refresh_online_button():
    var on := casual_available()
    for b in menu_buttons:
        if title_of(b) != "JOGAR ONLINE": continue
        var sub := "Partida casual · fila automática" if on else ONLINE_OFF_TEXT
        var rs = b.find_child("RefSubtitle", true, false)
        if rs != null:
            rs.color = Color("f1ede2") if on else Color("ffb08f")
            rs.set_text(sub)
        var rt = b.find_child("RefTitle", true, false)
        if rt != null:
            rt.modulate = Color.WHITE if on else Color(1, 1, 1, 0.6)
        var labels = b.find_children("*", "Label", true, false)
        if labels.size() >= 2: labels[1].text = String(b.get_meta("subtitle", "")) if on else ONLINE_OFF_TEXT
    if is_instance_valid(mobile_ui) and mobile_ui.has_method("refresh_online"): mobile_ui.refresh_online(on)

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
    avatar_editor.set_frame(current_frame(), String(league_profile.data.current_league) if league_profile != null else "madeira")   # R169
    var err: String = avatar_editor.open_with(bytes)
    if not err.is_empty(): _avatar_message(err, true)

func _on_photo_saved(image: Image, bytes: PackedByteArray):
    avatar_store.save_local(avatar_key(), image)
    _focus_current_look()
    _refresh_avatars()
    if account != null and account.has_profile():
        if account.upload_avatar(bytes): _avatar_message("Foto salva. Enviando para a sua conta…", false)
        else: _avatar_message("Foto salva neste aparelho. Conecte-se para enviá-la à conta.", false)
    else:
        _avatar_message("Foto salva neste aparelho. Entre na conta para usá-la em todo lugar.", false)

## R176 · REMOVER FOTO pergunta antes (sem foto: nada a perguntar)
func request_remove_photo():
    if custom_avatar() == null:
        remove_custom_avatar()
        return
    preload("res://ui_kit/confirm_box.gd").ask(self, "REMOVER SUA FOTO?", "Você deseja mesmo remover a sua foto do perfil?\nO avatar escolhido volta a aparecer.", "SIM, REMOVER", func(): remove_custom_avatar())

func remove_custom_avatar():
    avatar_store.clear_local(avatar_key())
    if account != null and account.has_profile(): account.clear_avatar()
    _focus_current_look()
    _refresh_avatars()
    _avatar_message("Foto removida. Avatar padrão de volta.", false)

func _avatar_message(text: String, is_error: bool):
    if is_instance_valid(avatar_note):
        avatar_note.text = text
        avatar_note.add_theme_color_override("font_color", Color("ff9d86") if is_error else MUTED)
    if is_instance_valid(mobile_ui) and mobile_ui.has_method("avatar_message"): mobile_ui.avatar_message(text, is_error)
