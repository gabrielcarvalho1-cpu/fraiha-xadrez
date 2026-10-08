extends Node2D
const FairPlay = preload("res://analysis/fair_play.gd")
const MobileLayout = preload("res://ui_v022/mobile_layout.gd")
# Only this presentation root handles the screen dimensions. Game coordinates stay intact.
@onready var game: Node2D = $World
@onready var forest: Sprite2D = $ForestExtensions
@onready var online: CanvasLayer = $Online
@onready var hub: CanvasLayer = $MainHub
var windowed_size := Vector2i(1280, 720)
var windowed_position := Vector2i.ZERO
var windowed_mode := Window.MODE_WINDOWED
var mode := "home"
var pending_navigation := ""
var navigation_confirmed := false
var home_button: Button
var navigation_dialog: ConfirmationDialog
var bot_controller: Node
var bot_info: Label
var theme_manager: Node
var player_card: HBoxContainer
var player_portrait: TextureRect
var player_caption: Label
var mobile_actions: BoxContainer
var mobile_restart: Button
var bot_level_name := "FÁCIL"
# HUD da partida no desktop (o mobile mantém seus próprios controles).
const HudButton = preload("res://ui_v022/hud_button.gd")
var fullscreen_button: Button
var medieval_modal
var match_plaque: Control
var material_hud: Control        # R38.3 · pontos e peças capturadas (bot, online, ranqueada, local)
var desk_panel: PanelContainer
var desk_person: HBoxContainer
var desk_portrait: TextureRect
var desk_name: Label
var desk_side: Label
var desk_gear: Button
var desk_music: Button       # R37.3
var _desk_snd := []           # R52e · último estado (música, efeitos) desenhado nos botões da mesa
var desk_fx: Button
var desk_fullscreen: Button   # R43 · tela cheia também na partida
var mobile_fullscreen: Button
var mobile_music: Button
var mobile_fx: Button
const ModeSound := preload("res://ui_v022/mode_sound.gd")
var board_skin = null   # R49 · ranked/board_skin.gd
var mobile_hud = null   # R53 · ranked/mobile_match_hud.gd

func mobile_hud_on() -> bool:
    return mobile_hud != null and mobile_hud.on
var bot_view = null     # R51 · dados dos cartões do Ranked na partida contra o computador (bot/bot_view.gd)
var _bot_forced_wood := ""   # R51 · tema salvo do jogador enquanto a partida contra o bot usa a Madeira
var desk_restart: Button
var desk_mark: Button          # MARCAR PARA REVISAR (sem engine; só guarda o lance)
var desk_analyze: Button       # ANALISAR PARTIDA (só depois do fim)
var mobile_mark: Button
var mobile_analyze: Button
var recorder                   # analysis/match_recorder.gd
var result_overlay             # presentation_v019/game_result_overlay.gd (VITÓRIA / DERROTA)
var analysis_engine            # analysis/engine.gd
var reward_modal               # bot/reward_modal.gd
var analysis_access            # analysis/analysis_access.gd
var analysis_ui = null
var training_ui = null
var analysis_history           # analysis/analysis_history.gd
var match_history              # analysis/match_history.gd (R32: todas as partidas terminadas)
var bot_side_name := "BRANCAS"
var mobile_status: Label
var mobile_promotion: PanelContainer
var account
var party_chat                   # R37.3 · social/party_chat.gd
var profile_popup                # R37 · social/profile_popup.gd (cartão de perfil durante a partida)
var account_ui
var account_chip: Button
var ranked
var ranked_ui
var casual
var casual_ui
var match_chat
var social_ui
var invite_ui
var voice                      # R45 · FRAIHA Voice (voice/fraiha_voice.gd): voz só em PvP humano online
var desk_voice: Control
var mobile_voice: Control
var _voice_poll := 0.0

func _enter_tree():
    MobileLayout.configure_window(get_window())

func _ready():
    get_tree().auto_accept_quit = false
    bot_controller = preload("res://bot/controller.gd").new()
    bot_controller.name = "BotController"
    bot_controller.guard = func() -> bool: return FairPlay.engine_blocked(self, "bot")
    add_child(bot_controller)
    voice = preload("res://voice/fraiha_voice.gd").new()
    add_child(voice)
    _build_backdrop()
    _build_navigation()
    get_viewport().size_changed.connect(_layout)
    hub.play_local_requested.connect(_start_local)
    # JOGAR ONLINE = Casual com fila automática. As salas por código (_open_online) seguem internas.
    hub.play_online_requested.connect(_open_casual)
    hub.play_bot_requested.connect(_start_bot)
    hub.quit_requested.connect(request_quit)
    _setup_screen_mode()
    # Pré-move (Configurações): vale contra o computador, Online e Ranqueado.
    game.premove_enabled = hub.premove_enabled
    hub.premove_changed.connect(func(on):
        game.premove_enabled = on
        if not on: game.clear_premove())
    online.room_joined.connect(_room_joined)
    online.room_left.connect(_room_left)
    online.connection_failed.connect(_connection_failed)
    theme_manager = preload("res://cosmetics/theme_manager.gd").new()
    theme_manager.name = "ThemeManager"
    add_child(theme_manager)
    theme_manager.setup(self)
    var audio = preload("res://audio_v025/game_audio.gd").new()
    audio.name = "GameAudio"
    add_child(audio)
    if theme_manager.review_requested():
        theme_manager.review_all = true
        hub.review_all = true
        print("CONFERÊNCIA VISUAL: todas as ligas abertas só para olhar (nada é salvo)")
    if hub.has_signal("theme_preview_requested"):
        hub.theme_preview_requested.connect(theme_manager.choose_theme)
    if hub.has_signal("piece_set_requested"):
        hub.piece_set_requested.connect(theme_manager.choose_piece_set)
    if hub.has_method("on_theme_changed"):
        theme_manager.theme_changed.connect(hub.on_theme_changed)
        hub.on_theme_changed(theme_manager.active_theme, theme_manager.active_piece_set)
    _setup_account()
    # Vida sutil no cenário (fogo, água, vaga-lumes, pássaros); só apresentação.
    var ambient = preload("res://presentation_v019/ambient_life.gd").new()
    ambient.name = "AmbientLife"
    forest.add_child(ambient)
    # R49 · pele do tabuleiro Ranked Madeira (arte de referência; só aparência)
    bot_view = preload("res://bot/bot_view.gd").new(self, bot_controller)
    board_skin = preload("res://ranked/board_skin.gd").new()
    add_child(board_skin)
    board_skin.setup(self)
    # R53 · HUD da partida no celular (em pé e deitado) no visual das referências aprovadas
    mobile_hud = preload("res://ranked/mobile_match_hud.gd").new()
    add_child(mobile_hud)
    mobile_hud.setup(self)
    _layout()
    open_home()

func _build_backdrop():
    # Onde nada é desenhado aparecia o cinza padrão do Godot. Agora: verde-escuro + folhagem
    # em pixel art recortada da própria arte da floresta, em mosaico espelhado (sem emendas).
    RenderingServer.set_default_clear_color(Color("0b1a10"))
    var layer := CanvasLayer.new()
    layer.name = "LeafBackdrop"
    layer.layer = -5
    add_child(layer)
    var rect := TextureRect.new()
    rect.texture = preload("res://ui_v022/assets/home_side_foliage.png")
    rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    rect.modulate = Color(0.55, 0.62, 0.55)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(rect)

func _build_navigation():
    var overlay = CanvasLayer.new()
    overlay.name = "Navigation"
    overlay.layer = 40
    add_child(overlay)
    home_button = HudButton.make("home", "INÍCIO", "ESC")
    home_button.name = "HomeButton"
    home_button.tooltip_text = "Voltar à tela inicial (Esc)"
    home_button.size = Vector2(196, 54)
    home_button.pressed.connect(return_to_home)
    overlay.add_child(home_button)
    # Sem botão de TELA CHEIA: o jogo sempre ocupa a tela toda (desktop: exclusiva desde o início;
    # Web: viewport inteira; tela cheia pelo botão ao lado do som — ver _setup_screen_mode).
    match_plaque = preload("res://presentation_v019/match_plaque.gd").new()
    match_plaque.name = "MatchPlaque"
    overlay.add_child(match_plaque)
    material_hud = preload("res://presentation_v019/material_hud.gd").new()
    material_hud.game = game
    overlay.add_child(material_hud)
    _build_desk_panel(overlay)
    bot_info = Label.new()
    bot_info.name = "BotInfo"
    bot_info.add_theme_font_size_override("font_size", 20)
    bot_info.add_theme_color_override("font_color", Color("efcf83"))
    bot_info.add_theme_color_override("font_outline_color", Color("102018"))
    bot_info.add_theme_constant_override("outline_size", 5)
    bot_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    bot_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(bot_info)
    player_card = HBoxContainer.new()
    player_card.add_theme_constant_override("separation",9)
    player_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(player_card)
    player_portrait = TextureRect.new()
    player_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    player_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    player_portrait.custom_minimum_size = Vector2(58,58)
    player_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    player_card.add_child(player_portrait)
    player_caption = Label.new()
    player_caption.add_theme_font_size_override("font_size",17)
    player_caption.add_theme_constant_override("outline_size",5)
    player_caption.add_theme_color_override("font_outline_color",Color("101510"))
    player_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    player_caption.custom_minimum_size.x = 142
    player_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
    player_card.add_child(player_caption)
    navigation_dialog = ConfirmationDialog.new()
    navigation_dialog.name = "LeaveConfirmation"
    navigation_dialog.title = "FRAIHA XADREZ"
    navigation_dialog.ok_button_text = "Confirmar"
    navigation_dialog.cancel_button_text = "Continuar jogando"
    navigation_dialog.confirmed.connect(_confirm_navigation)
    navigation_dialog.canceled.connect(_cancel_navigation)
    navigation_dialog.theme = _medieval_dialog_theme()
    navigation_dialog.exclusive = false
    medieval_modal = preload("res://presentation_v019/medieval_modal.gd").new()
    medieval_modal.name = "MedievalModal"
    overlay.add_child(navigation_dialog)
    var modal_layer := CanvasLayer.new()
    modal_layer.layer = 70
    add_child(modal_layer)
    modal_layer.add_child(medieval_modal)
    medieval_modal.setup(navigation_dialog, func(): return mode)
    _build_mobile_controls(overlay)

func _build_desk_panel(overlay: CanvasLayer):
    # Canto superior direito: jogador (retrato maior + nome + cor) e ferramentas da partida.
    desk_panel = PanelContainer.new()
    desk_panel.name = "MatchPlayerPanel"
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.06, 0.13, 0.09, 0.93)
    style.border_color = Color("b99555")
    style.set_border_width_all(2)
    style.set_corner_radius_all(10)
    style.shadow_color = Color(0, 0, 0, 0.5)
    style.shadow_size = 8
    style.shadow_offset = Vector2(0, 3)
    for side in ["left", "right"]: style.set("content_margin_" + side, 12)
    for side in ["top", "bottom"]: style.set("content_margin_" + side, 9)
    desk_panel.add_theme_stylebox_override("panel", style)
    overlay.add_child(desk_panel)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    desk_panel.add_child(row)
    desk_person = HBoxContainer.new()
    desk_person.add_theme_constant_override("separation", 12)
    desk_person.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(desk_person)
    desk_portrait = TextureRect.new()
    desk_portrait.name = "DeskPortrait"
    desk_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    desk_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    desk_portrait.custom_minimum_size = Vector2(74, 74)
    desk_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    desk_person.add_child(desk_portrait)
    var words := VBoxContainer.new()
    words.alignment = BoxContainer.ALIGNMENT_CENTER
    words.add_theme_constant_override("separation", 2)
    words.custom_minimum_size.x = 170
    desk_person.add_child(words)
    desk_name = Label.new()
    desk_name.name = "DeskName"
    desk_name.add_theme_font_size_override("font_size", 22)
    desk_name.add_theme_color_override("font_color", Color("f4ce7f"))
    desk_name.add_theme_color_override("font_outline_color", Color("0b150f"))
    desk_name.add_theme_constant_override("outline_size", 4)
    desk_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    desk_name.clip_text = true
    desk_name.custom_minimum_size = Vector2(170, 30)
    words.add_child(desk_name)
    desk_side = Label.new()
    desk_side.name = "DeskSide"
    desk_side.add_theme_font_size_override("font_size", 16)
    desk_side.add_theme_color_override("font_color", Color("e8dcc0"))
    words.add_child(desk_side)
    var line := ColorRect.new()
    line.custom_minimum_size = Vector2(1.5, 58)
    line.color = Color(0.957, 0.808, 0.498, 0.35)
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    desk_person.add_child(line)
    var tools := HBoxContainer.new()
    tools.alignment = BoxContainer.ALIGNMENT_CENTER
    tools.add_theme_constant_override("separation", 8)
    row.add_child(tools)
    # R45 · FRAIHA Voice: microfone + estado (só aparece em Casual/Ranked/amigo online, no navegador)
    desk_voice = preload("res://voice/voice_control.gd").new()
    tools.add_child(desk_voice)
    desk_voice.setup(voice)
    desk_restart = HudButton.make("restart")
    desk_restart.name = "RestartButton"
    desk_restart.tooltip_text = "Reiniciar partida"
    desk_restart.custom_minimum_size = Vector2(54, 54)
    desk_restart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    desk_restart.pressed.connect(func(): game.restart_match())
    tools.add_child(desk_restart)
    desk_mark = HudButton.make("bookmark")
    desk_mark.name = "MarkButton"
    desk_mark.tooltip_text = "Marcar para revisar (sem engine): guarda este lance para a análise depois da partida"
    desk_mark.custom_minimum_size = Vector2(54, 54)
    desk_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    desk_mark.pressed.connect(mark_for_review)
    tools.add_child(desk_mark)
    desk_analyze = HudButton.make("magnifier", "ANALISAR PARTIDA")
    desk_analyze.name = "AnalyzeButton"
    desk_analyze.tooltip_text = "Analisar partida"
    desk_analyze.custom_minimum_size = Vector2(240, 54)
    desk_analyze.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    desk_analyze.pressed.connect(open_analysis)
    tools.add_child(desk_analyze)
    desk_gear = HudButton.make("gear")
    desk_gear.name = "GearButton"
    desk_gear.tooltip_text = "Opções da partida"
    desk_gear.custom_minimum_size = Vector2(54, 54)
    desk_gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    desk_gear.pressed.connect(func(): game.toggle_settings())
    tools.add_child(desk_gear)
    # R37.3 · MÚSICA e EFEITOS também na partida de xadrez (bots, casual, ranked): desligam só um dos dois
    for kind in ["music", "fx"]:
        var sb := HudButton.make("sound_on")
        sb.name = "DeskMusic" if kind == "music" else "DeskEffects"
        sb.glyph = ""
        sb.tooltip_text = "Música: ligar / desligar" if kind == "music" else "Efeitos sonoros: ligar / desligar"
        sb.custom_minimum_size = Vector2(54, 54)
        sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        sb.pressed.connect(func():
            if kind == "music": ModeSound.toggle_music(hub)
            else: ModeSound.toggle_effects(hub)
            sb.queue_redraw())
        sb.draw.connect(func():
            var off: bool = ModeSound.music_muted(hub) if kind == "music" else ModeSound.effects_muted(hub)
            var r := Rect2(Vector2.ZERO, sb.size).grow(-8)
            ModeSound.glyph(sb, r, kind, off, Color("f4ce7f")))
        tools.add_child(sb)
        if kind == "music": desk_music = sb
        else: desk_fx = sb
    # R43 · TELA CHEIA também durante a partida (bots, casual, ranked): o mesmo botão da Home.
    desk_fullscreen = HudButton.make("fullscreen")
    desk_fullscreen.name = "DeskFullscreen"
    desk_fullscreen.tooltip_text = "Tela cheia"
    desk_fullscreen.custom_minimum_size = Vector2(54, 54)
    desk_fullscreen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    desk_fullscreen.pressed.connect(func(): if screen_mode != null: screen_mode.toggle())
    tools.add_child(desk_fullscreen)

## Visual medieval da confirmação (sair/abandonar): painel verde, moldura dourada, título
## em Cinzel e botões verde/ouro. Só aparência; as ações continuam as mesmas.
func _medieval_dialog_theme() -> Theme:
    var th := Theme.new()
    var gold := Color("c99a45")
    var frame := StyleBoxFlat.new()
    frame.bg_color = Color("0c1f14")
    frame.border_color = gold
    frame.set_border_width_all(3)
    frame.border_width_top = 44
    frame.set_corner_radius_all(8)
    frame.expand_margin_top = 44
    frame.expand_margin_left = 3
    frame.expand_margin_right = 3
    frame.expand_margin_bottom = 3
    frame.shadow_color = Color(0, 0, 0, 0.55)
    frame.shadow_size = 14
    th.set_stylebox("embedded_border", "Window", frame)
    th.set_stylebox("embedded_unfocused_border", "Window", frame)
    th.set_font("title_font", "Window", preload("res://account/login_art.gd").FONT_BOLD)
    th.set_font_size("title_font_size", "Window", 26)
    th.set_color("title_color", "Window", Color("1a0f02"))
    th.set_constant("title_height", "Window", 40)
    var body := StyleBoxFlat.new()
    body.bg_color = Color("0c1f14")
    body.border_color = Color(0.79, 0.6, 0.27, 0.35)
    body.set_border_width_all(1)
    for side in ["left", "right", "top", "bottom"]: body.set("content_margin_" + side, 18)
    th.set_stylebox("panel", "AcceptDialog", body)
    th.set_color("font_color", "Label", Color("f1e4c2"))
    th.set_font_size("font_size", "Label", 24)
    var btn := StyleBoxFlat.new()
    btn.bg_color = Color("1f5a2e")
    btn.border_color = Color("f1d58a")
    btn.set_border_width_all(2)
    btn.set_corner_radius_all(4)
    btn.content_margin_left = 14
    btn.content_margin_right = 14
    btn.content_margin_top = 8
    btn.content_margin_bottom = 8
    btn.shadow_color = Color(0, 0, 0, 0.4)
    btn.shadow_size = 3
    var lit := btn.duplicate()
    lit.bg_color = Color("2d7a40")
    lit.border_color = Color("fff0b8")
    var down := btn.duplicate()
    down.bg_color = Color("153f20")
    th.set_stylebox("normal", "Button", btn)
    th.set_stylebox("hover", "Button", lit)
    th.set_stylebox("pressed", "Button", down)
    th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
    th.set_font("font", "Button", preload("res://account/login_art.gd").FONT_BOLD)
    th.set_font_size("font_size", "Button", 21)
    th.set_color("font_color", "Button", Color("f4e8c8"))
    th.set_color("font_hover_color", "Button", Color("fff4c8"))
    return th

func _sync_fullscreen_glyph():
    if not is_instance_valid(fullscreen_button): return
    var on = get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
    fullscreen_button.glyph = "exit_fullscreen" if on else "fullscreen"
    fullscreen_button.tooltip_text = ("Sair da tela cheia" if on else "Tela cheia") + " (Alt+Enter)"
    fullscreen_button.queue_redraw()

func _refresh_desk_hud():
    if not is_instance_valid(desk_panel): return
    var mobile = MobileLayout.active(get_viewport())
    var in_match = mode in ["local", "online", "bot", "ranked", "casual"] and game.visible
    navigation_dialog.min_size = Vector2i.ZERO if mobile else Vector2i(620, 230)
    game.external_hud = not mobile
    match_plaque.visible = mode == "bot" and not mobile
    if is_instance_valid(material_hud): material_hud.visible = in_match
    if match_plaque.visible:
        var king = game.piece_textures.get("wK" if bot_side_name == "BRANCAS" else "bK")
        match_plaque.set_info(bot_controller.bot_id if not String(bot_controller.bot_id).is_empty() else bot_controller.difficulty, bot_level_name, bot_side_name, king)
    desk_panel.visible = in_match and not mobile
    desk_person.visible = mode in ["local", "online", "bot"]
    desk_restart.visible = mode in ["local", "online", "bot"] and game.game_started
    _refresh_analysis_buttons()
    if desk_person.visible:
        desk_portrait.texture = hub.avatar_texture()
        hub.attach_league_frame(desk_portrait)
        desk_name.text = hub.player_name
        var side = "Pretas" if game.board_flipped() else "Brancas"
        desk_side.text = "Partida local" if mode == "local" else "Você joga de " + side
    _layout_desk_hud()

func _layout_desk_hud():
    if not is_instance_valid(desk_panel) or MobileLayout.active(get_viewport()): return
    if board_skin != null and board_skin.on: return   # R49: a pele já pôs cada botão no lugar da arte
    var size = get_viewport_rect().size
    home_button.position = Vector2(24, 20)
    home_button.size = Vector2(196, 54)
    if match_plaque.visible:
        match_plaque.position = Vector2((size.x - match_plaque.size.x) / 2.0, 16)
    # ANALISAR PARTIDA com texto só quando cabe entre a placa central e a borda direita;
    # senão vira ícone (com tooltip). O cartão nunca sai da tela.
    if is_instance_valid(desk_analyze) and desk_analyze.visible:
        _set_analyze_compact(false)
        desk_panel.reset_size()
        var limit_left: float = (size.x + match_plaque.size.x) / 2.0 + 16.0 if match_plaque.visible else home_button.position.x + home_button.size.x + 16.0
        if size.x - 24.0 - desk_panel.get_combined_minimum_size().x < limit_left:
            _set_analyze_compact(true)
    _layout_material_desktop()
    desk_panel.reset_size()
    desk_panel.size = desk_panel.get_combined_minimum_size()
    desk_panel.position = Vector2(maxf(8.0, size.x - 24 - desk_panel.size.x), 16)
    # O painel de opções (desenhado pelo tabuleiro) abre logo abaixo deste cartão.
    if desk_panel.visible and game.scale.x > 0.0:
        var anchor = Vector2(size.x - 24, 16 + desk_panel.size.y + 10)
        game.place_settings_panel((anchor - game.position) / game.scale.x)

func _set_analyze_compact(compact: bool):
    if not is_instance_valid(desk_analyze): return
    var want_text := "" if compact else "ANALISAR PARTIDA"
    if desk_analyze.text == want_text: return
    desk_analyze.text = want_text
    desk_analyze.icon_only = compact
    desk_analyze.custom_minimum_size = Vector2(54 if compact else 240, 54)
    desk_analyze._margins()

func _setup_account():
    account = preload("res://account/account_service.gd").new()
    account.name = "Account"
    add_child(account)
    account_ui = preload("res://account/account_ui.gd").new()
    account_ui.name = "AccountUI"
    add_child(account_ui)
    account_ui.setup(account)
    voice.setup(account)
    voice.changed.connect(_on_voice_changed)
    hub.bind_account(account)
    # R37 · cartão de perfil ao passar o mouse no avatar (Ranked, Casual, Marcha, Xeque)
    profile_popup = preload("res://social/profile_popup.gd").new()
    add_child(profile_popup)
    profile_popup.bind(account)
    # R37.3 · chat das mesas com amigo (XEQUE e MARCHA REAL online)
    party_chat = preload("res://social/party_chat.gd").new()
    add_child(party_chat)
    party_chat.setup(account)
    _setup_analysis()
    account_ui.ready_for_ranked.connect(_open_ranked)
    ranked = preload("res://ranked/ranked_controller.gd").new()
    ranked.name = "RankedController"
    add_child(ranked)
    ranked.setup(account, game)
    ranked_ui = preload("res://ranked/ranked_ui.gd").new()
    ranked_ui.name = "RankedUI"
    add_child(ranked_ui)
    ranked_ui.hub = hub
    ranked_ui.setup(account, ranked)
    ranked_ui.back_requested.connect(open_home)
    ranked_ui.play_requested.connect(_back_to_ranked_lobby)
    ranked.found.connect(_ranked_found)
    ranked.finished.connect(_on_online_result)   # R42.1 · fim da partida = resultado OFICIAL do servidor
    casual = preload("res://ranked/ranked_controller.gd").new()
    casual.name = "CasualController"
    casual.kind = "casual"
    add_child(casual)
    casual.setup(account, game)
    casual_ui = preload("res://ranked/ranked_ui.gd").new()
    casual_ui.name = "CasualUI"
    casual_ui.kind = "casual"
    add_child(casual_ui)
    casual_ui.hub = hub   # R41 · retratos/selos na faixa e no "adversário encontrado" (antes só o Ranked tinha)
    casual_ui.setup(account, casual)
    casual_ui.back_requested.connect(open_home)
    # Abas CASUAL / RANQUEADA da tela de escolha de ritmo.
    casual_ui.switch_requested.connect(func(k): if k == "ranked":
        _open_ranked()
        if ranked_ui.panel_open(): casual_ui.close_panel())
    ranked_ui.switch_requested.connect(func(k): if k == "casual":
        ranked_ui.close_panel()
        _open_casual())
    casual_ui.play_requested.connect(_back_to_casual_lobby)
    casual.found.connect(_casual_found)
    casual.finished.connect(_on_online_result)
    match_chat = preload("res://social/match_chat.gd").new()
    match_chat.name = "MatchChat"
    add_child(match_chat)
    match_chat.setup(account)
    match_chat.layout_needed.connect(_layout)
    var toggle: Button = match_chat.toggle_button
    toggle.custom_minimum_size.y = 44
    toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    toggle.add_theme_font_size_override("font_size", 15)
    mobile_actions.add_child(toggle)
    account_ui.closed.connect(_refresh_account_chip)
    account.changed.connect(_refresh_account_chip)
    hub.ranked_requested.connect(_open_ranked)
    hub.account_requested.connect(func(): account_ui.open())
    hub.friends_requested.connect(_open_friends)
    social_ui = preload("res://social/social_ui.gd").new()
    social_ui.name = "SocialUI"
    add_child(social_ui)
    social_ui.setup(account, hub.avatar_texture)
    # R35.1 · JOGAR ONLINE (casual) → CONVIDAR AMIGO: lista de amigos e escolha do ritmo (Ranqueado não tem)
    casual_ui.invite_requested.connect(func(): social_ui.open_invite_picker("chess"))
    account.changed.connect(func(): if social_ui.is_open() and not account.has_profile() and not account.account_pending(): social_ui.hide_ui())
    invite_ui = preload("res://social/invite_ui.gd").new()
    invite_ui.name = "InviteUI"
    add_child(invite_ui)
    # Convite nunca aparece por cima de uma partida online em andamento.
    invite_ui.setup(account, hub.avatar_texture, func(): return party_in_match() or (mode in ["online", "ranked", "casual"] and ((mode != "ranked" or ranked.in_match()) and (mode != "casual" or casual.in_match()))))
    # R35 · MARCHA REAL / XEQUE online com amigo: o servidor manda party_* e a tela do modo joga
    account.server_message.connect(_on_party_message)
    account_chip = Button.new()
    account_chip.name = "AccountChip"
    account_chip.add_theme_font_size_override("font_size", 20)
    account_chip.size = Vector2(420, 46)
    account_chip.pressed.connect(func(): account_ui.open())
    get_node("Navigation").add_child(account_chip)
    _refresh_account_chip()
    # Tela inicial sem sessão: oferece entrar/criar conta (convidado continua possível).
    if account.configured() and not account.signed_in() and account.refresh_token.is_empty() and not account.redirect_pending:
        account_ui.open("login")

func _refresh_account_chip():
    if not is_instance_valid(account_chip): return
    _sync_theme_unlocks()
    var caption = "CONVIDADO · ENTRAR / CRIAR CONTA"
    if account.has_profile():
        if account.after_login == "ranked":
            account.after_login = ""
            _open_ranked.call_deferred()
        caption = "CONTA: " + account.nickname()
        hub.player_name = account.nickname()
        if is_instance_valid(hub.profile_name): hub.profile_name.text = account.nickname()
    elif account.signed_in():
        caption = "CONTA: conectando…" if not account.needs_nickname else "CONTA: escolher nome"
        # Primeiro login (inclusive Google): pede o nome público antes de tudo.
        if account.needs_nickname and account.server_ready and not account_ui.is_open():
            account_ui.open("nickname")
    hub.account_caption = caption
    account_chip.text = caption
    # Desktop: o cartão ornamentado da Home (canto inferior esquerdo) substitui o botão simples.
    account_chip.visible = false
    if account.has_profile(): hub.set_account_card(account.nickname(), "MINHA CONTA", true)
    elif account.signed_in(): hub.set_account_card("CONTA", "Escolher nome" if account.needs_nickname else "Conectando…", true)
    else: hub.set_account_card("CONVIDADO", "ENTRAR / CRIAR CONTA", false)
    if is_instance_valid(hub.mobile_ui) and hub.mobile_ui.current_page == "main" and hub.is_home_visible():
        hub.mobile_ui.show_page("main")

## Temas/peças: libera até a maior liga já alcançada (highest_league) entre os 4 modos Ranked.
func _sync_theme_unlocks():
    var index := 0
    var confirmed := false
    if account.has_profile():
        confirmed = true
        if account.ranked is Dictionary:
            for m in account.ranked:
                var s = account.ranked[m]
                if s is Dictionary: index = maxi(index, int(s.get("highest_league", 0)))
    elif account.signed_in():
        confirmed = account.server_ready and account.needs_nickname # conta nova
    else:
        confirmed = account.refresh_token.is_empty() and not account.redirect_pending # convidado
    hub.set_ranked_unlock(index)
    hub.apply_ranked_standing(account.ranked if account.has_profile() else {})   # cartão da Home = liga/PL do Ranked
    if is_instance_valid(theme_manager): theme_manager.sync_unlocks(index, confirmed)

func _open_ranked():
    if account.has_profile():
        bot_controller.stop()
        online.cancel_connection()
        hub.hide_hub()
        mode = "ranked_lobby"
        game.hide()
        _clear_selection()
        ranked_ui.open_modes()
        _refresh_input()
        return
    account_ui.open("", "Crie uma conta ou entre para jogar partidas ranqueadas.", true)

func _open_friends():
    # Área de Amigos: só para contas. Conta ainda conectando abre em "Conectando…" (não pede login).
    if account.has_profile() or (account.account_pending() and not (account.server_ready and account.needs_nickname)):
        social_ui.open()
        return
    if account.signed_in() and account.needs_nickname:
        account_ui.open("nickname", "Escolha seu nome de jogador para usar Amigos.")
        return
    account_ui.open("", "Entre ou crie uma conta para usar Amigos.")

func _open_casual():
    bot_controller.stop()
    online.cancel_connection()
    hub.hide_hub()
    mode = "casual_lobby"
    game.hide()
    _clear_selection()
    account.ensure_online()
    casual_ui.open_modes()
    _refresh_input()

func _casual_found(_msg: Dictionary):
    if social_ui != null and social_ui.is_open(): social_ui.hide_ui()   # partida por convite: sai de Amigos
    if account_ui.is_open(): account_ui.hide_ui()
    bot_controller.stop()
    online.cancel_connection()
    if ranked != null: ranked.detach()
    hub.hide_hub()
    mode = "casual"
    casual.attach()
    if recorder != null: recorder.begin("casual", casual.human_color, hub.player_name, String(casual.opponent.get("nickname", "Adversário")), String(casual.match_id))
    game.show()
    _clear_selection()
    casual_ui.hud.show()
    match_chat.bind(casual)
    _refresh_input()
    _layout()

func _back_to_casual_lobby():
    match_chat.unbind()
    casual.detach()
    casual_ui.hud.hide()
    game.hide()
    mode = "casual_lobby"
    _refresh_input()

func _ranked_found(_msg: Dictionary):
    if casual != null: casual.detach()
    bot_controller.stop()
    hub.hide_hub()
    mode = "ranked"
    ranked.attach()
    if recorder != null: recorder.begin("ranked", ranked.human_color, hub.player_name, String(ranked.opponent.get("nickname", "Adversário")), String(ranked.match_id))
    game.show()
    _clear_selection()
    ranked_ui.hud.show()
    match_chat.bind(ranked)
    _refresh_input()
    _layout()

func _back_to_ranked_lobby():
    match_chat.unbind()
    ranked.detach()
    ranked_ui.hud.hide()
    game.hide()
    mode = "ranked_lobby"
    _refresh_input()

func _build_mobile_controls(overlay: CanvasLayer):
    mobile_actions = BoxContainer.new()
    mobile_actions.vertical = true
    mobile_actions.add_theme_constant_override("separation", 8)
    overlay.add_child(mobile_actions)
    for caption in ["Reiniciar", "Marcar", "Analisar", "Música", "Efeitos", "Tela cheia"]:
        var button = Button.new()
        button.text = caption
        button.custom_minimum_size.y = 44
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.add_theme_font_size_override("font_size", 15)
        mobile_actions.add_child(button)
        if caption == "Marcar":
            mobile_mark = button
            button.text = "Marcar p/ revisar"
            button.pressed.connect(mark_for_review)
        if caption == "Analisar":
            mobile_analyze = button
            button.text = "Analisar partida"
            button.pressed.connect(open_analysis)
        if caption == "Reiniciar":
            mobile_restart = button
            button.pressed.connect(func():
                if mode == "ranked":
                    ranked_ui._confirm_resign()
                    return
                if mode == "casual":
                    casual_ui._confirm_resign()
                    return
                if mode == "bot" and ((board_skin != null and board_skin.on) or mobile_hud_on()) and bot_controller.in_match():
                    ranked_ui._confirm_resign()
                    return
                game._new_game()
                game.queue_redraw())
        elif caption == "Música":
            # R37.3 · MÚSICA e EFEITOS separados (a mesma preferência do jogo inteiro)
            button.pressed.connect(func(): ModeSound.toggle_music(hub))
            mobile_music = button
        elif caption == "Efeitos":
            button.pressed.connect(func(): ModeSound.toggle_effects(hub))
            mobile_fx = button
        elif caption == "Tela cheia":
            button.pressed.connect(func(): if screen_mode != null: screen_mode.toggle())
            mobile_fullscreen = button
    mobile_voice = preload("res://voice/voice_control.gd").new()
    mobile_actions.add_child(mobile_voice)
    mobile_voice.setup(voice, true)
    mobile_status = Label.new()
    mobile_status.add_theme_font_size_override("font_size", 20)
    mobile_status.add_theme_color_override("font_color", Color("efcf83"))
    mobile_status.add_theme_color_override("font_outline_color", Color("102018"))
    mobile_status.add_theme_constant_override("outline_size", 5)
    mobile_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    mobile_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(mobile_status)
    mobile_promotion = PanelContainer.new()
    mobile_promotion.z_index = 100
    mobile_promotion.hide()
    overlay.add_child(mobile_promotion)
    var margin = MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 12)
    mobile_promotion.add_child(margin)
    var column = VBoxContainer.new()
    column.add_theme_constant_override("separation", 12)
    margin.add_child(column)
    var title = Label.new()
    title.text = "PROMOÇÃO DO PEÃO"
    title.add_theme_font_size_override("font_size", 18)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(title)
    var choices = HBoxContainer.new()
    choices.add_theme_constant_override("separation", 6)
    column.add_child(choices)
    var kinds = ["Q", "R", "B", "N"]
    var captions = ["Dama", "Torre", "Bispo", "Cavalo"]
    for index in range(4):
        var choice = Button.new()
        choice.text = captions[index]
        choice.custom_minimum_size = Vector2(70, 64)
        choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        choice.add_theme_font_size_override("font_size", 16)
        choice.pressed.connect(game._finish_promotion.bind(kinds[index]))
        choices.add_child(choice)

func _process(delta):
    _voice_poll -= delta
    if _voice_poll <= 0.0:   # R45 · voz segue a partida (entra/sai sozinha do contexto, nunca o contrário)
        _voice_poll = 0.25
        _sync_voice()
    if is_instance_valid(medieval_modal) and (medieval_modal.visible or navigation_dialog.visible): _sync_modal()
    if not is_instance_valid(mobile_status): return
    var mobile = MobileLayout.active(get_viewport())
    var playing = mode in ["local", "online", "bot", "ranked", "casual"]
    mobile_actions.visible = mobile and playing and not mobile_hud_on()   # R53: com o HUD novo, as ações vão para AÇÕES
    if is_instance_valid(mobile_music):
        mobile_music.text = "Música: " + ("NÃO" if ModeSound.music_muted(hub) else "SIM")
        mobile_fx.text = "Efeitos: " + ("NÃO" if ModeSound.effects_muted(hub) else "SIM")
    if is_instance_valid(desk_music) and desk_panel.visible:
        # R52e · só redesenha quando o estado de som muda (antes: todo quadro, recriando os ícones na GPU)
        var snd := [ModeSound.music_muted(hub), ModeSound.effects_muted(hub)]
        if snd != _desk_snd:
            _desk_snd = snd
            desk_music.queue_redraw()
            desk_fx.queue_redraw()
    _sync_fullscreen_buttons()
    # Online has its own server-side rematch; a local reset would desync the room.
    mobile_restart.visible = mode != "online" and not (mode == "ranked" and not ranked.in_match()) and not (mode == "casual" and not casual.in_match())
    mobile_restart.text = "Desistir" if mode in ["ranked", "casual"] else "Reiniciar"
    _refresh_analysis_buttons()
    if match_chat != null:
        var want_chat = mobile and mode in ["ranked", "casual"] and match_chat.active()
        if match_chat.toggle_button.visible != want_chat:
            match_chat.toggle_button.visible = want_chat
            _layout.call_deferred()
    mobile_status.visible = mobile and mode in ["local", "bot"] and not (board_skin != null and board_skin.on) and not mobile_hud_on()   # R51: com a pele, o relógio aceso mostra a vez
    var short_status = _mobile_status_text()
    if mobile_status.text != short_status: mobile_status.text = short_status
    mobile_promotion.visible = mobile and playing and game.promotion_pending and (game.online == null or game.promotion_color == game.online.color)

func _mobile_status_text() -> String:
    var text: String = game.status
    if text.contains("SUA VEZ"):
        return ("XEQUE! " if text.begins_with("XEQUE") else "") + "SUA VEZ"
    if text.contains("PENSANDO"):
        return "BOT PENSANDO…"
    return text

func _badge_style(accent: Color) -> StyleBoxFlat:
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.05, 0.08, 0.07, 0.82)
    style.border_color = accent
    style.set_border_width_all(1)
    style.set_corner_radius_all(6)
    style.content_margin_left = 10
    style.content_margin_right = 10
    style.content_margin_top = 4
    style.content_margin_bottom = 4
    return style

func _touch_button_style(button: Button):
    if button.has_meta("touch_style"): return
    button.set_meta("touch_style", true)
    var style = _badge_style(Color("84754b"))
    style.bg_color = Color(0.06, 0.11, 0.09, 0.9)
    button.add_theme_stylebox_override("normal", style)
    var active = style.duplicate()
    active.bg_color = Color("26382b")
    active.border_color = Color("e5c37c")
    for state in ["pressed", "hover", "focus"]: button.add_theme_stylebox_override(state, active)
    button.add_theme_color_override("font_color", Color("efe3c4"))

func _refresh_bot_caption():
    if MobileLayout.active(get_viewport()):
        bot_info.text = (bot_level_name if bot_level_name.begins_with("BOT ") else "BOT · %s" % bot_level_name) if mode == "bot" else "PARTIDA LOCAL"
    else:
        bot_info.text = "%s  ·  VOCÊ: %s" % [bot_level_name if bot_level_name.begins_with("BOT ") else "BOT " + bot_level_name, bot_side_name]

func _clear_selection():
    game.cancel_drag()
    game.selected = Vector2i(-1, -1)
    game.legal_moves.clear()
    game.queue_redraw()

## R51 · contra o computador o layout é o do Ranked Madeira para todos: tema Madeira durante a partida
## (sem gravar como escolha do jogador); ao sair, volta o tema que ele usa.
func _bot_theme_guard():
    if theme_manager == null: return
    if mode == "bot" and _bot_forced_wood.is_empty():
        _bot_forced_wood = String(theme_manager.active_theme)
        if _bot_forced_wood != "wood": theme_manager.apply_theme("wood", false)
    elif mode != "bot" and not _bot_forced_wood.is_empty():
        var back := _bot_forced_wood
        _bot_forced_wood = ""
        if back != "wood" and String(theme_manager.active_theme) == "wood": theme_manager.apply_theme(back, false)

## R51 · DESISTIR na partida contra o computador (botão do layout do Ranked).
func resign_bot():
    if mode == "bot": bot_controller.resign()

func _refresh_input():
    var audio = get_node_or_null("GameAudio")
    if audio != null: audio.refresh_music()
    var playing = mode in ["local", "online", "bot", "ranked", "casual"]
    bot_controller.set_paused(not pending_navigation.is_empty())
    if ranked != null:
        ranked.set_paused(not pending_navigation.is_empty())
        ranked_ui.hud.visible = mode == "ranked" or (mode == "bot" and ((board_skin != null and board_skin.wanted()) or (mobile_hud != null and mobile_hud.wanted())))
    if casual != null:
        casual.set_paused(not pending_navigation.is_empty())
        casual_ui.hud.visible = mode == "casual"
    bot_info.visible = MobileLayout.active(get_viewport()) and mode in ["bot", "local"] and not (mobile_hud != null and mobile_hud.wanted())
    _bot_theme_guard()
    _refresh_bot_caption()
    game.set_process_unhandled_input(playing and pending_navigation.is_empty())
    # On mobile the online menu has its own full-width back button.
    home_button.visible = mode != "home" and not (mode == "online_menu" and MobileLayout.active(get_viewport())) and not (mobile_hud != null and mobile_hud.wanted())
    _refresh_account_chip()
    home_button.disabled = not pending_navigation.is_empty()
    refresh_player_card()
    _refresh_desk_hud()

func refresh_player_card():
    if not is_instance_valid(player_card): return
    player_card.visible = mode in ["local","online","bot"] and MobileLayout.active(get_viewport()) and not (mobile_hud != null and mobile_hud.wanted())
    player_portrait.texture = hub.avatar_texture()
    hub.attach_league_frame(player_portrait)
    var side = "Pretas" if game.board_flipped() else "Brancas"
    if MobileLayout.active(get_viewport()):
        player_caption.text = hub.player_name + "\nVocê: " + side
        if mode == "local": player_caption.text = hub.player_name + "\nLocal · 2 jogadores"
    else:
        player_caption.text = hub.player_name + "\n" + side
        if mode == "local": player_caption.text = hub.player_name + "\nPartida local"

func _start_local():
    bot_controller.stop()
    hub.hide_hub()
    online.cancel_connection()
    online.start_local()
    bot_controller.start_local(game)
    mode = "local"
    if recorder != null: recorder.begin("local", "", hub.player_name, "Partida local")
    game.show()
    _clear_selection()
    _refresh_input()

func _open_online():
    bot_controller.stop()
    hub.hide_hub()
    mode = "online_menu"
    game.hide()
    online.open_online_menu()
    _clear_selection()
    _refresh_input()

var last_bot_side := "w"
func _start_bot(difficulty: String, side: String):
    last_bot_side = side
    if reward_modal != null: reward_modal.close()
    bot_controller.stop()
    online.cancel_connection()
    hub.hide_hub()
    mode = "bot"
    game.show()
    bot_controller.start(game,difficulty,side)
    var ladder_bot: Dictionary = preload("res://bot/bot_ladder.gd").bot(difficulty)
    bot_level_name = String(ladder_bot.get("name", "")) if not ladder_bot.is_empty() else {"easy":"FÁCIL","medium":"MÉDIO","hard":"DIFÍCIL","expert":"EXPERT"}.get(difficulty,"FÁCIL")
    bot_side_name = "BRANCAS" if bot_controller.human_color == "w" else "PRETAS"
    if recorder != null: recorder.begin("bot", bot_controller.human_color, hub.player_name, bot_level_name if not ladder_bot.is_empty() else "Computador · " + bot_level_name)
    _refresh_bot_caption()
    _clear_selection()
    _refresh_input()

func _room_joined():
    mode = "online"
    game.show()
    _refresh_input()

func _room_left():
    if pending_navigation == "quit":
        if OS.has_feature("web"):
            # Web: SAIR = sair da tela cheia e voltar para o site (get_tree().quit() só congelava a aba).
            pending_navigation = ""
            navigation_confirmed = false
            screen_mode.leave_to_site()
            return
        get_tree().quit()
    else:
        open_home()

func _connection_failed():
    if navigation_confirmed:
        online.finish_leave()
        return
    if not pending_navigation.is_empty():
        _cancel_navigation()
    mode = "online_menu"
    game.hide()
    _clear_selection()
    _refresh_input()

func open_home():
    bot_controller.stop()
    if ranked != null:
        if ranked.searching: ranked.cancel_queue()
        ranked.detach()
        ranked_ui.close_panel()
        ranked_ui.hud.hide()
    if match_chat != null: match_chat.unbind()
    if social_ui != null and social_ui.is_open(): social_ui.hide_ui()
    if casual != null:
        if casual.searching: casual.cancel_queue()
        casual.detach()
        casual_ui.close_panel()
        casual_ui.hud.hide()
    pending_navigation = ""
    navigation_confirmed = false
    navigation_dialog.hide()
    mode = "home"
    online.menu.hide()
    online.hud.hide()
    game.game_started = false
    game.settings_open = false
    game.hide()
    _clear_selection()
    hub.open_home()
    _refresh_input()

func return_to_home():
    if not pending_navigation.is_empty():
        return
    if mode == "home":
        hub.back()
        return
    _request_navigation("home")

func request_quit():
    if pending_navigation.is_empty():
        _request_navigation("quit")

func _request_navigation(destination: String):
    _clear_selection()
    # Returning from an empty board or a pending connection is lossless.
    var needs_confirmation = destination == "quit" or online.joined or mode == "online" or (mode == "bot" and not game.game_over) or (mode == "local" and game.move_count > 0) or (mode == "ranked" and ranked.in_match()) or (mode == "casual" and casual.in_match())
    pending_navigation = destination
    navigation_confirmed = false
    _refresh_input()
    if not needs_confirmation:
        _confirm_navigation()
        return
    navigation_dialog.ok_button_text = "Confirmar"
    if mode == "ranked" and ranked.in_match():
        navigation_dialog.dialog_text = "Sair agora conta como DESISTÊNCIA (derrota) nesta modalidade Ranked."
        navigation_dialog.ok_button_text = "Desistir e sair"
    elif mode == "casual" and casual.in_match():
        navigation_dialog.dialog_text = "Sair agora conta como DESISTÊNCIA nesta partida Casual (sem alterar PL)."
        navigation_dialog.ok_button_text = "Desistir e sair"
    elif mode == "bot":
        navigation_dialog.dialog_text = "Deseja abandonar a partida?"
        navigation_dialog.ok_button_text = "Sair para Home" if destination == "home" else "Sair do jogo"
    elif online.joined or mode == "online":
        navigation_dialog.dialog_text = "Sair da sala encerra sua participação nesta partida. Continuar?"
    elif mode == "local" and game.move_count > 0:
        navigation_dialog.dialog_text = "A partida local será encerrada. Voltar à tela inicial?" if destination == "home" else "A partida local será encerrada. Sair do jogo?"
    else:
        navigation_dialog.dialog_text = "Voltar para o site fraihaxadrez.com?" if OS.has_feature("web") and destination == "quit" else "Sair do FRAIHA Xadrez?"
    navigation_dialog.cancel_button_text = "Continuar jogando" if mode in ["local", "online"] else "Cancelar"
    if mode == "bot": navigation_dialog.cancel_button_text = "Continuar partida"
    var dialog_size = Vector2i(480, 160)
    if MobileLayout.active(get_viewport()):
        dialog_size = Vector2i(minf(480, MobileLayout.safe_rect(get_viewport()).size.x-32), 200)
    navigation_dialog.popup_centered(dialog_size)
    _sync_modal()

func _sync_modal():
    if is_instance_valid(medieval_modal):
        medieval_modal.sync(not MobileLayout.active(get_viewport()), get_viewport_rect().size)

func _cancel_navigation():
    navigation_dialog.hide()
    _sync_modal()
    pending_navigation = ""
    navigation_confirmed = false
    _refresh_input()

func _confirm_navigation():
    navigation_dialog.hide()
    _sync_modal()
    navigation_confirmed = true
    if online.joined or mode == "online":
        # The existing client resigns and waits for the server before leaving.
        online.leave_room()
        return
    online.cancel_connection()
    bot_controller.stop()
    if mode == "ranked" and ranked.in_match(): ranked.resign()
    if mode == "casual" and casual.in_match(): casual.resign()
    if pending_navigation == "quit":
        if OS.has_feature("web"):
            # Web: SAIR = sair da tela cheia e voltar para o site (get_tree().quit() só congelava a aba).
            pending_navigation = ""
            navigation_confirmed = false
            screen_mode.leave_to_site()
            return
        get_tree().quit()
    else:
        game._new_game()
        open_home()

## Tela cheia (R29.2): ui_v022/fullscreen_control.gd — botão ao lado do som, Esc sai da tela cheia
## naturalmente (sem travar a tecla), 1 pedido automático só no 1º clique/toque e nunca mais depois que o
## jogador sai. Esc com a tela cheia ativa (ou que acabou de tirá-la) não navega: ver EscGuard.
var screen_mode

## R43 · botões de tela cheia da partida (desktop e celular) seguem o estado real; somem sem a API (iPhone).
func _sync_fullscreen_buttons():
    var ok: bool = screen_mode != null and screen_mode.supported()
    var on: bool = ok and screen_mode.on_cached()
    if is_instance_valid(desk_fullscreen):
        desk_fullscreen.visible = ok
        var g := "exit_fullscreen" if on else "fullscreen"
        if desk_fullscreen.glyph != g:
            desk_fullscreen.glyph = g
            desk_fullscreen.tooltip_text = "Sair da tela cheia" if on else "Tela cheia"
            desk_fullscreen.queue_redraw()
    if is_instance_valid(mobile_fullscreen):
        mobile_fullscreen.visible = ok
        mobile_fullscreen.text = "Sair da tela cheia" if on else "Tela cheia"

func _setup_screen_mode():
    screen_mode = preload("res://ui_v022/fullscreen_control.gd").new()
    screen_mode.name = "ScreenMode"
    screen_mode.stage = self
    add_child(screen_mode)
    hub.attach_screen_mode(screen_mode)
    # Guarda do Esc: último filho da raiz = primeiro a receber _input (antes de páginas, overlays e diálogos).
    var guard = EscGuard.new()
    guard.name = "EscGuard"
    guard.screen_mode = screen_mode
    get_tree().root.add_child.call_deferred(guard)

class EscGuard extends Node:
    var screen_mode
    func _input(event):
        if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and screen_mode != null and screen_mode.esc_belongs_to_fullscreen():
            # Esc em tela cheia = só sair da tela cheia (o navegador já faz; garante caso a tecla chegue ao jogo).
            if not event.echo: screen_mode.exit()
            get_viewport().set_input_as_handled()

func _input(event):
    # R42.2: tela cheia SÓ pelo botão de expandir (sem pedido automático no 1º clique).
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.alt_pressed and event.keycode == KEY_ENTER and not OS.has_feature("web"):
        toggle_fullscreen()   # atalho de desktop (sem botão e sem preferência salva)
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_ESCAPE:
        if navigation_dialog.visible:
            _cancel_navigation()
        else:
            return_to_home()
        get_viewport().set_input_as_handled()

func _notification(what):
    if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(navigation_dialog):
        request_quit()

func _layout():
    if board_skin != null: board_skin.before_layout()
    if mobile_hud != null: mobile_hud.before_layout()
    var size = get_viewport_rect().size
    var mobile = MobileLayout.active(get_viewport())
    game.mobile_presentation = mobile
    if is_instance_valid(home_button) and not mobile:
        home_button.text = "INÍCIO"
        home_button.hint = "ESC"
        home_button.glyph = "home"
        home_button.icon_box = 54.0
        home_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        home_button.icon_only = false
        home_button._margins()
        home_button.add_theme_font_size_override("font_size", 18)
    if is_instance_valid(account_chip):
        account_chip.position = Vector2(20, size.y - 62)
    if is_instance_valid(bot_info):
        bot_info.position = Vector2(size.x/2.0-250,16)
        bot_info.size = Vector2(500,38)
    if is_instance_valid(player_card):
        player_card.position = Vector2(size.x-230,80)
        player_portrait.custom_minimum_size = Vector2(58,58)
        player_caption.custom_minimum_size.x = 142
    var factor = min(size.y / 1024.0, size.x / 1024.0)
    game.scale = Vector2.ONE * factor
    var board_center = game.ORIGIN + Vector2.ONE * game.BOARD / 2.0
    game.position = size / 2.0 - board_center * factor
    if mobile:
        _layout_mobile(board_center)
        factor = game.scale.x
    else:
        player_caption.add_theme_font_size_override("font_size", 17)
        bot_info.autowrap_mode = TextServer.AUTOWRAP_OFF
        bot_info.add_theme_font_size_override("font_size", 20)
        bot_info.remove_theme_stylebox_override("normal")
        bot_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    # The outpaint has its own board center; align its terrain while covering every edge.
    var texture_size = forest.texture.get_size()
    var art_center = texture_size * Vector2(802.0/1672.0, 445.5/941.0)
    var cover = max(max(size.x/2.0/art_center.x, size.x/2.0/(texture_size.x-art_center.x)), max(size.y/2.0/art_center.y, size.y/2.0/(texture_size.y-art_center.y)))
    forest.scale = Vector2.ONE * cover
    forest.position = size/2.0 + (texture_size/2.0-art_center)*cover
    if mobile:
        # The wood board is painted in the artwork: keep it glued to the playable grid.
        var art_scale = maxf(cover, game.scale.x * WOOD_ART_BOARD_RATIO)
        forest.scale = Vector2.ONE * art_scale
        forest.position = game.position + board_center*game.scale.x + (texture_size/2.0-art_center)*art_scale
    game.update_presentation(Rect2(-game.position / factor, size / factor))
    if is_instance_valid(theme_manager): theme_manager.layout()
    if ranked_ui != null and not mobile:
        var board_rect = Rect2(game.position + game.ORIGIN * game.scale.x, Vector2.ONE * game.BOARD * game.scale.x)
        for ui in [ranked_ui, casual_ui]:
            if ui != null: ui.layout_hud(board_rect, false, false, get_viewport_rect(), Rect2(), Rect2())
        if match_chat != null: match_chat.layout(board_rect, false, get_viewport_rect())
    if not mobile: _layout_material_desktop()
    _refresh_desk_hud()
    if board_skin != null: board_skin.after_layout()
    if mobile_hud != null: mobile_hud.after_layout()

## R38.3 · faixas de pontos/capturas no desktop: à direita do tabuleiro (adversário em cima, você embaixo);
## na ranqueada/online ficam coladas nas faixas de nome e relógio. Tela estreita: lado esquerdo.
const MATERIAL_H := 52.0
func _layout_material_desktop():
    if not is_instance_valid(material_hud): return
    if board_skin != null and board_skin.on: return   # R49: a pele põe o material nos cartões da arte
    var board := Rect2(game.position + game.ORIGIN * game.scale.x, Vector2.ONE * game.BOARD * game.scale.x)
    var vs := get_viewport_rect().size
    var strips := mode in ["ranked", "casual"]
    var w := 460.0
    var x := board.end.x + 28.0
    if x + w > vs.x - 8.0: x = maxf(8.0, board.position.x - w - 28.0)
    var top_y := board.position.y + (106.0 if strips else 0.0)
    var bottom_y := board.end.y - MATERIAL_H - (106.0 if strips else 0.0)
    material_hud.compact = false
    material_hud.top_rect = Rect2(x, top_y, w, MATERIAL_H)
    material_hud.bottom_rect = Rect2(x, bottom_y, w, MATERIAL_H)
    material_hud.queue_redraw()

# Painted wood board: 600 grid units span ~522 texture pixels (calibrated at 1920x1080).
const WOOD_ART_BOARD_RATIO := (540.0/445.5) / (1080.0/1024.0)

func _layout_mobile(board_center: Vector2):
    var safe = MobileLayout.safe_rect(get_viewport())
    var portrait = MobileLayout.is_portrait(get_viewport())
    var online_play = mode == "online"
    # The playable grid is 600 units; decorative rims extend 20 units per side.
    var rim = 640.0/600.0
    var gap = 8.0
    _refresh_bot_caption()
    refresh_player_card()
    for label in [bot_info, mobile_status]:
        label.autowrap_mode = TextServer.AUTOWRAP_OFF
        label.clip_text = true
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.add_theme_constant_override("outline_size", 3)
    bot_info.add_theme_font_size_override("font_size", 14)
    bot_info.add_theme_color_override("font_color", Color("e8dcc0"))
    bot_info.add_theme_stylebox_override("normal", _badge_style(Color("5d6b58")))
    mobile_status.add_theme_font_size_override("font_size", 16)
    mobile_status.add_theme_stylebox_override("normal", _badge_style(Color("e5c37c")))
    mobile_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    player_portrait.custom_minimum_size = Vector2(40,40)
    player_caption.add_theme_font_size_override("font_size", 14)
    player_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
    player_caption.clip_text = true
    home_button.text = "INÍCIO"
    # Mobile mantém o botão como antes (só texto, centralizado).
    home_button.hint = ""
    home_button.glyph = ""
    home_button.icon_box = 16.0
    home_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
    home_button.call_deferred("_margins")
    home_button.add_theme_font_size_override("font_size", 15)
    for button in [home_button] + mobile_actions.get_children():
        if button is Button: _touch_button_style(button)   # R45: a coluna também tem o controle de voz (não é Button)
    player_caption.add_theme_stylebox_override("normal", _badge_style(Color("5d6b58")))
    var board_pixels: float
    if portrait:
        # Column: badges, board (full width), player, controls.
        var ranked_play = mode in ["ranked", "casual"]
        var top_h = 128.0 if online_play else (44.0 if ranked_play else 34.0)
        var player_h = 48.0
        var controls_h = 44.0
        var mat_h = 32.0      # R38.3 · faixa de capturas acima e abaixo do tabuleiro
        var available = safe.size.y - top_h - player_h - controls_h - gap*4.0 - mat_h*2.0
        var board_total = minf(safe.size.x, available)
        board_pixels = maxf(160.0, board_total/rim)
        board_total = board_pixels*rim
        var column_h = top_h + gap + mat_h + board_total + mat_h + gap + player_h
        var top = safe.position.y + maxf(0.0, (safe.size.y - controls_h - gap - column_h)/2.0)
        var board_top = top + top_h + gap + mat_h
        var board_mid = Vector2(safe.get_center().x, board_top + board_total/2.0)
        game.scale = Vector2.ONE * (board_pixels/game.BOARD)
        game.position = board_mid - board_center*game.scale.x
        var half = (safe.size.x - gap)/2.0
        bot_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        bot_info.position = Vector2(safe.position.x, top)
        bot_info.size = Vector2(half, top_h)
        mobile_status.position = Vector2(safe.position.x + half + gap, top)
        mobile_status.size = Vector2(half, top_h)
        var player_y = board_top + board_total + mat_h + gap + 4.0
        if is_instance_valid(material_hud):
            material_hud.compact = true
            material_hud.top_rect = Rect2(safe.position.x, board_top - mat_h, safe.size.x, mat_h - 2.0)
            material_hud.bottom_rect = Rect2(safe.position.x, board_top + board_total + 2.0, safe.size.x, mat_h - 2.0)
            material_hud.queue_redraw()
        player_card.position = Vector2(safe.position.x, player_y)
        player_card.size = Vector2(safe.size.x, player_h)
        # Adversário acima do tabuleiro, você abaixo (relógios compactos).
        for ui in [ranked_ui, casual_ui]:
            if ui != null: ui.layout_hud(Rect2(), true, true, safe, Rect2(safe.position.x, top, safe.size.x, top_h), Rect2(safe.position.x, player_y, safe.size.x, player_h))
        player_caption.custom_minimum_size.x = maxf(90.0, safe.size.x - 52.0)
        var controls_y = safe.end.y - controls_h
        var home_w = maxf(92.0, safe.size.x*0.26)
        home_button.position = Vector2(safe.position.x, controls_y)
        home_button.size = Vector2(home_w, controls_h)
        mobile_actions.vertical = false
        mobile_actions.add_theme_constant_override("separation", 6)
        mobile_actions.position = Vector2(safe.position.x + home_w + 6.0, controls_y)
        mobile_actions.size = Vector2(safe.size.x - home_w - 6.0, controls_h)
    else:
        # Row: status column, board (full height), player/controls column.
        board_pixels = maxf(160.0, minf(safe.size.y, safe.size.x - 300.0)/rim)
        var board_total = board_pixels*rim
        game.scale = Vector2.ONE * (board_pixels/game.BOARD)
        game.position = safe.get_center() - board_center*game.scale.x
        var side_width = maxf(120.0, (safe.size.x - board_total)/2.0 - 12.0)
        var right_x = safe.get_center().x + board_total/2.0 + 12.0
        bot_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        bot_info.position = safe.position
        bot_info.size = Vector2(side_width, 32)
        mobile_status.position = safe.position + Vector2(0, 40)
        mobile_status.size = Vector2(side_width, 36)
        player_card.position = Vector2(right_x, safe.position.y)
        player_card.size = Vector2(side_width, 44)
        player_caption.custom_minimum_size.x = maxf(70.0, side_width - 50.0)
        mobile_actions.vertical = true
        mobile_actions.add_theme_constant_override("separation", 6)
        mobile_actions.position = Vector2(right_x, safe.position.y + 54)
        var shown = mobile_actions.get_children().filter(func(b): return b.visible).size()
        mobile_actions.size = Vector2(side_width, maxf(138.0, shown * 46.0))
        home_button.position = Vector2(right_x, safe.end.y - 44)
        home_button.size = Vector2(side_width, 44)
        var left_x = safe.position.x
        if is_instance_valid(material_hud):
            material_hud.compact = true
            material_hud.top_rect = Rect2(left_x, safe.position.y + 84.0, side_width, 34.0)
            material_hud.bottom_rect = Rect2(left_x, safe.end.y - 50.0 - 8.0 - 34.0, side_width, 34.0)
            material_hud.queue_redraw()
        for ui in [ranked_ui, casual_ui]:
            if ui != null: ui.layout_hud(Rect2(), true, false, safe, Rect2(left_x, safe.position.y, side_width, 50), Rect2(left_x, safe.end.y - 50, side_width, 50))
    var crowded = portrait and mobile_actions.get_children().filter(func(b): return b.visible).size() > 3
    for button in mobile_actions.get_children():
        if not (button is Button): continue
        button.custom_minimum_size.y = 44 if portrait else 40
        # Linha única no retrato: com o botão Chat, todos encolhem por igual sem sair da tela.
        button.clip_text = crowded
        button.custom_minimum_size.x = 0
        button.add_theme_font_size_override("font_size", 13 if crowded else 15)
        for state in ["normal", "pressed", "hover", "focus"]:
            var box = button.get_theme_stylebox(state)
            if box is StyleBoxFlat and button.has_theme_stylebox_override(state):
                box.content_margin_left = 4 if crowded else 10
                box.content_margin_right = 4 if crowded else 10
        if button.has_meta("short_text"): button.text = button.get_meta("short_text") if crowded else button.get_meta("full_text")
    if portrait:
        if crowded:
            home_button.size.x = 76.0
            mobile_actions.position.x = safe.position.x + 82.0
        # O tamanho do container foi limitado ao mínimo antigo; reaplica depois de encolher os botões.
        mobile_actions.reset_size()
        mobile_actions.size = Vector2(safe.end.x - mobile_actions.position.x, 44.0)
    if match_chat != null: match_chat.layout(Rect2(), true, safe)
    mobile_promotion.size = Vector2(minf(safe.size.x, maxf(326.0, board_pixels)), 132)
    mobile_promotion.position = game.position + board_center*game.scale.x - mobile_promotion.size/2.0
    navigation_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    navigation_dialog.get_label().add_theme_font_size_override("font_size", 17)
    for button in [navigation_dialog.get_ok_button(), navigation_dialog.get_cancel_button()]:
        button.custom_minimum_size.y = 44
        button.add_theme_font_size_override("font_size", 13)

func toggle_fullscreen():
    _sync_fullscreen_glyph.call_deferred()
    var window = get_window()
    if OS.has_feature("web"):
        # Web: nada de alternar Window.mode por atalho (sair da tela cheia = Esc do navegador; voltar = 1º clique).
        return
    if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
        window.mode = Window.MODE_WINDOWED
        window.size = windowed_size
        window.position = windowed_position
        if windowed_mode == Window.MODE_MAXIMIZED:
            window.mode = Window.MODE_MAXIMIZED
    else:
        windowed_size = window.size
        windowed_position = window.position
        windowed_mode = window.mode
        # Desktop: tela cheia EXCLUSIVA. A não exclusiva do Windows deixa uma linha de 1 px (cor de fundo) tremendo no topo.
        window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
    game.queue_redraw()


# ---------- Análise pós-partida (FAIR PLAY: engine só depois do fim) ----------
func _setup_analysis():
    recorder = preload("res://analysis/match_recorder.gd").new()
    recorder.name = "MatchRecorder"
    add_child(recorder)
    recorder.setup(self)
    recorder.finished.connect(_on_match_finished)
    result_overlay = preload("res://presentation_v019/game_result_overlay.gd").new()
    add_child(result_overlay)
    analysis_engine = preload("res://analysis/engine.gd").new("analysis")
    analysis_engine.name = "AnalysisEngine"
    analysis_engine.guard = func() -> bool: return FairPlay.engine_blocked(self, "analysis")
    add_child(analysis_engine)
    analysis_access = preload("res://analysis/analysis_access.gd").new()
    analysis_access.name = "AnalysisAccess"
    add_child(analysis_access)
    analysis_access.setup(account, hub.entitlements)
    analysis_history = preload("res://analysis/analysis_history.gd").new()
    analysis_history.name = "AnalysisHistory"
    add_child(analysis_history)
    match_history = preload("res://analysis/match_history.gd").new()
    match_history.name = "MatchHistory"
    add_child(match_history)
    reward_modal = preload("res://bot/reward_modal.gd").new()
    reward_modal.name = "BotRewardModal"
    reward_modal.avatar_for = func(id): return hub.avatar_texture(id)
    add_child(reward_modal)
    reward_modal.advance_requested.connect(func(next_id): _start_bot(next_id, last_bot_side))
    reward_modal.replay_requested.connect(func(bid): _start_bot(bid, last_bot_side))
    reward_modal.home_requested.connect(open_home)
    if hub.bot_progress != null:
        # Painel pós-partida em TODA vitória confirmada (1ª vitória com recompensa; revanche sem recompensa).
        # Conta: só depois da resposta do servidor (R28). Sempre espera a animação de VITÓRIA terminar.
        hub.bot_progress.victory_confirmed.connect(func(bid, fresh, rw): _after_result_overlay(func(): reward_modal.show_progress(bid, rw, fresh)))
        hub.bot_progress.notice.connect(func(t):
            print("BOT PROGRESS: ", t)
            _after_result_overlay(func(): reward_modal.show_error(t)))

## Executa `action` quando a animação de VITÓRIA/DERROTA sair da tela (ou já, se não estiver aberta).
func _after_result_overlay(action: Callable):
    # espera a animação de VITÓRIA terminar (inclusive o fade de saída) antes de abrir o painel
    if result_overlay != null and (result_overlay.is_showing() or result_overlay.visible):
        await result_overlay.dismissed
    action.call()

## MARCAR PARA REVISAR: só grava o índice do lance. Nenhuma engine roda aqui.
func mark_for_review():
    if recorder == null or recorder.current() == null: return
    recorder.mark_for_review()
    var n: int = recorder.current().marked.size()
    if is_instance_valid(desk_mark): desk_mark.tooltip_text = "Marcado para revisar (%d)" % n
    if is_instance_valid(mobile_mark): mobile_mark.text = "Marcado (%d)" % n

func analysis_available() -> bool:
    if recorder == null: return false
    var rec = recorder.current()
    if rec == null: return false
    return preload("res://analysis/fair_play.gd").can_analyze(rec, self) and rec.moves.size() >= 2

func _refresh_analysis_buttons():
    var mobile = MobileLayout.active(get_viewport())
    var playing = mode in ["local", "online", "bot", "ranked", "casual"] and game.game_started and not game.game_over
    var human_mode = mode in ["ranked", "casual", "online", "local"]
    var can_mark = playing and recorder != null and recorder.current() != null and not recorder.current().finished
    var can_analyze = analysis_available()
    if is_instance_valid(desk_mark): desk_mark.visible = can_mark and not mobile
    if is_instance_valid(desk_analyze):
        desk_analyze.visible = can_analyze and not mobile
        if can_analyze and analysis_access != null:
            desk_analyze.tooltip_text = "Analisar partida · " + analysis_access.status_line()
    if is_instance_valid(mobile_mark): mobile_mark.visible = can_mark and mobile
    if is_instance_valid(mobile_analyze): mobile_analyze.visible = can_analyze and mobile
    if human_mode and playing and is_instance_valid(desk_analyze): desk_analyze.visible = false   # nunca durante partida humana
    if not mobile: _layout_desk_hud.call_deferred()   # a largura do cartão muda quando ANALISAR aparece

func _on_online_result(msg: Dictionary):
    if voice != null: voice.exit_match("match_end")   # R45 · fim oficial da partida: sai da voz
    if bool(msg.get("unknown", false)): return   # R53 · servidor não tinha mais o resultado: nada a gravar
    # Resultado do Ranked traz a liga/PL novos: a Home (cartão do jogador) e os temas liberados atualizam na hora.
    if msg.get("stats") is Dictionary and String(msg.get("mode", "")).begins_with("ranked_") and account.ranked is Dictionary:
        account.ranked[String(msg.mode)] = msg.stats
        _sync_theme_unlocks()
    if recorder == null: return
    recorder.finish_online(String(msg.get("match_id", "")), String(msg.get("outcome", "")), String(msg.get("reason_text", msg.get("reason", ""))))

## Fim de partida: usa o RESULTADO REAL do registro (vencedor comparado com a cor do jogador —
## nunca só "brancas"/"pretas"). Partida local (dois humanos) e empates não abrem a tela.
func _on_match_finished(record):
    if match_history != null: match_history.add(record)
    if record == null or result_overlay == null: return
    if String(record.human_color).is_empty(): return
    var res := String(record.result)
    if res == "win": result_overlay.show_result("victory")
    elif res == "loss": result_overlay.show_result("defeat")
    # Desafio das Ligas: 1ª vitória (xeque-mate no bot) → progresso + recompensa (servidor valida na conta).
    if res == "win" and String(record.mode) == "bot" and not String(bot_controller.bot_id).is_empty() and "MATE" in String(record.result_reason) and String(record.start_fen).is_empty():
        if hub.bot_progress != null: hub.bot_progress.report_victory(String(bot_controller.bot_id), String(record.human_color), PackedStringArray(record.moves))

func _ensure_analysis_ui():
    if analysis_ui == null:
        analysis_ui = preload("res://analysis/analysis_ui.gd").new(analysis_engine, analysis_access, hub)
        add_child(analysis_ui)
        analysis_ui.train_requested.connect(open_training)
        analysis_ui.analyzer.finished.connect(func(rep): if analysis_history != null: analysis_history.record(analysis_ui.record, rep, account))

func open_analysis():
    if not analysis_available(): return
    _ensure_analysis_ui()
    analysis_ui.open_for(recorder.current())

## R32 · HISTÓRICO DE PARTIDAS: análise de uma partida guardada (usa a cota; Club = ilimitado).
func open_analysis_for(rec) -> bool:
    if rec == null or not preload("res://analysis/fair_play.gd").can_analyze(rec, self) or rec.moves.size() < 2: return false
    _ensure_analysis_ui()
    analysis_ui.open_for(rec)
    return true

## Entrada do histórico de análises (relatório completo) desta partida, se ela já foi analisada.
func analysis_entry_for(rec) -> Dictionary:
    if analysis_history == null or rec == null: return {}
    for e in analysis_history.entries:
        if int(e.get("played_at", -1)) == int(rec.started_at) and String(e.get("mode", "")) == String(rec.mode): return e
    return {}

## CLUB · HISTÓRICO DETALHADO: reabre uma análise guardada (sem gastar cota nem rodar a engine).
func open_history_report(entry: Dictionary) -> bool:
    if analysis_history == null: return false
    var full: Dictionary = analysis_history.load_report(entry)
    if full.is_empty(): return false
    _ensure_analysis_ui()
    analysis_ui.open_report(full.record, full.report)
    return true

## CLUB · TREINE MEUS ERROS / TREINO PERSONALIZADO com posições de várias partidas.
func open_training_moves(moves: Array) -> bool:
    if moves.is_empty(): return false
    if training_ui == null:
        training_ui = preload("res://analysis/training_ui.gd").new(analysis_engine)
        add_child(training_ui)
    training_ui.open_exercises(moves)
    return true

func open_training(report: Dictionary):
    if training_ui == null:
        training_ui = preload("res://analysis/training_ui.gd").new(analysis_engine)
        add_child(training_ui)
    training_ui.open_for(report)


# ---------- R45 · FRAIHA Voice: qual partida PvP humana está ativa agora (o modo informa; voz só segue) ----------
func voice_context() -> Dictionary:
    if mode == "ranked" and ranked != null and ranked.in_match(): return {"kind": "ranked", "match_id": String(ranked.match_id)}
    if mode == "casual" and casual != null and casual.in_match(): return {"kind": "casual", "match_id": String(casual.match_id)}
    for g in ["marcha", "xeque"]:
        var ui = _party_ui(g)
        if ui == null or not bool(ui.get("online")) or String(ui.get("mode")) != "game" or not ui.is_open(): continue
        var humans := 0
        for p in ui.get("players"):
            if p is Dictionary and String(p.get("user_id", "")) != "" and not bool(p.get("left", false)): humans += 1
        if humans >= 2: return {"kind": g, "match_id": String(ui.get("room_id"))}
    return {}

func _sync_voice():
    if voice == null: return
    var c := voice_context()
    if c.is_empty() or String(c.match_id).is_empty():
        if voice.in_match() or voice.active(): voice.exit_match("left_match")
    else:
        voice.enter_match(String(c.kind), String(c.match_id))

var _voice_last_error := ""
func _on_voice_changed():
    var err: String = voice.message if voice.state == "ERROR" else ""
    var fresh := err != "" and err != _voice_last_error
    _voice_last_error = err
    for g in ["marcha", "xeque"]:
        var ui = _party_ui(g)
        if ui == null or not ui.is_open(): continue
        if fresh and bool(ui.get("online")) and ui.has_method("_flash"): ui._flash(err)   # erro de voz visível no celular em pé
        if ui.has_method("_redraw"): ui._redraw()

# ---------- R35 · MARCHA REAL / XEQUE online com amigo (mesa de 4 com bots, servidor autoridade) ----------
func _party_ui(game: String):
    if hub == null: return null
    return hub.get("marcha") if game == "marcha" else hub.get("xeque")

func party_in_match() -> bool:
    for game in ["marcha", "xeque"]:
        var ui = _party_ui(game)
        if ui != null and bool(ui.get("online")) and String(ui.get("mode")) == "game" and ui.is_open(): return true
    return false

func _on_party_message(msg: Dictionary):
    var type := String(msg.get("type", ""))
    if not type.begins_with("party_"): return
    match type:
        "party_start":
            var game := String(msg.get("game", ""))
            if not game in ["marcha", "xeque"]: return
            if social_ui != null and social_ui.is_open(): social_ui.hide_ui()   # partida por convite: sai de Amigos
            if account_ui.is_open(): account_ui.hide_ui()
            var other = _party_ui("xeque" if game == "marcha" else "marcha")
            if other != null and other.is_open(): other.close()
            var ui = _party_ui(game)
            if ui == null or not ui.is_open():
                if game == "marcha": hub.open_marcha()
                else: hub.open_xeque()
                ui = _party_ui(game)
            if ui != null: ui.start_online(msg)
        "party_event", "party_error":
            for game in ["marcha", "xeque"]:
                var ui = _party_ui(game)
                if ui != null and bool(ui.get("online")): ui.on_party_message(msg)
        "party_none":
            for game in ["marcha", "xeque"]:
                var ui = _party_ui(game)
                if ui != null and bool(ui.get("online")): ui.online_lost("A partida online terminou (o servidor reiniciou ou ela expirou).")
