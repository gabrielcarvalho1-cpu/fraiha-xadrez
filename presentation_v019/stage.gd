extends Node2D
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
var mobile_actions: VBoxContainer
var mobile_status: Label
var mobile_promotion: PanelContainer

func _enter_tree():
    MobileLayout.configure_window(get_window())

func _ready():
    get_tree().auto_accept_quit = false
    bot_controller = preload("res://bot/controller.gd").new()
    bot_controller.name = "BotController"
    add_child(bot_controller)
    _build_navigation()
    get_viewport().size_changed.connect(_layout)
    hub.play_local_requested.connect(_start_local)
    hub.play_online_requested.connect(_open_online)
    hub.play_bot_requested.connect(_start_bot)
    hub.quit_requested.connect(request_quit)
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
    if hub.has_signal("theme_preview_requested"):
        hub.theme_preview_requested.connect(theme_manager.apply_theme)
    if hub.has_signal("piece_set_requested"):
        hub.piece_set_requested.connect(theme_manager.apply_piece_set)
    _layout()
    open_home()

func _build_navigation():
    var overlay = CanvasLayer.new()
    overlay.name = "Navigation"
    overlay.layer = 40
    add_child(overlay)
    home_button = Button.new()
    home_button.name = "HomeButton"
    home_button.text = "← TELA INICIAL  ·  ESC"
    home_button.size = Vector2(248, 46)
    home_button.add_theme_font_size_override("font_size", 18)
    home_button.pressed.connect(return_to_home)
    overlay.add_child(home_button)
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
    overlay.add_child(navigation_dialog)
    _build_mobile_controls(overlay)

func _build_mobile_controls(overlay: CanvasLayer):
    mobile_actions = VBoxContainer.new()
    mobile_actions.add_theme_constant_override("separation", 8)
    overlay.add_child(mobile_actions)
    for caption in ["Reiniciar", "Música", "Tela cheia"]:
        var button = Button.new()
        button.text = caption
        button.custom_minimum_size.y = 44
        button.add_theme_font_size_override("font_size", 17)
        mobile_actions.add_child(button)
        if caption == "Reiniciar":
            button.pressed.connect(func():
                game._new_game()
                game.queue_redraw())
        elif caption == "Música":
            button.pressed.connect(func(): get_node("GameAudio").toggle_music())
        else:
            button.pressed.connect(toggle_fullscreen)
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

func _process(_delta):
    if not is_instance_valid(mobile_status): return
    var mobile = MobileLayout.active(get_viewport())
    var playing = mode in ["local", "online", "bot"]
    mobile_actions.visible = mobile and playing
    mobile_status.visible = mobile and mode in ["local", "bot"]
    mobile_status.text = game.status
    mobile_promotion.visible = mobile and playing and game.promotion_pending and (game.online == null or game.promotion_color == game.online.color)

func _clear_selection():
    game.cancel_drag()
    game.selected = Vector2i(-1, -1)
    game.legal_moves.clear()
    game.queue_redraw()

func _refresh_input():
    var audio = get_node_or_null("GameAudio")
    if audio != null: audio.refresh_music()
    var playing = mode in ["local", "online", "bot"]
    bot_controller.set_paused(not pending_navigation.is_empty())
    bot_info.visible = mode == "bot"
    game.set_process_unhandled_input(playing and pending_navigation.is_empty())
    home_button.visible = mode != "home"
    home_button.disabled = not pending_navigation.is_empty()
    refresh_player_card()

func refresh_player_card():
    if not is_instance_valid(player_card): return
    player_card.visible = mode in ["local","online","bot"]
    player_portrait.texture = hub.avatar_texture()
    hub.attach_league_frame(player_portrait)
    player_caption.text = hub.player_name + "\n" + ("Pretas" if game.board_flipped() else "Brancas")
    if mode == "local": player_caption.text = hub.player_name + "\nPartida local"

func _start_local():
    bot_controller.stop()
    hub.hide_hub()
    online.cancel_connection()
    online.start_local()
    bot_controller.start_local(game)
    mode = "local"
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

func _start_bot(difficulty: String, side: String):
    bot_controller.stop()
    online.cancel_connection()
    hub.hide_hub()
    mode = "bot"
    game.show()
    bot_controller.start(game,difficulty,side)
    var level_name = {"easy":"FÁCIL","medium":"MÉDIO","hard":"DIFÍCIL","expert":"EXPERT"}.get(difficulty,"FÁCIL")
    bot_info.text = "BOT %s  ·  VOCÊ: %s" % [level_name, "BRANCAS" if bot_controller.human_color == "w" else "PRETAS"]
    _clear_selection()
    _refresh_input()

func _room_joined():
    mode = "online"
    game.show()
    _refresh_input()

func _room_left():
    if pending_navigation == "quit":
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
    var needs_confirmation = destination == "quit" or online.joined or mode in ["online","bot"] or (mode == "local" and game.move_count > 0)
    pending_navigation = destination
    navigation_confirmed = false
    _refresh_input()
    if not needs_confirmation:
        _confirm_navigation()
        return
    navigation_dialog.ok_button_text = "Confirmar"
    if mode == "bot":
        navigation_dialog.dialog_text = "Deseja abandonar a partida?"
        navigation_dialog.ok_button_text = "Sair para Home" if destination == "home" else "Sair do jogo"
    elif online.joined or mode == "online":
        navigation_dialog.dialog_text = "Sair da sala encerra sua participação nesta partida. Continuar?"
    elif mode == "local" and game.move_count > 0:
        navigation_dialog.dialog_text = "A partida local será encerrada. Voltar à tela inicial?" if destination == "home" else "A partida local será encerrada. Sair do jogo?"
    else:
        navigation_dialog.dialog_text = "Sair do FRAIHA Xadrez?"
    navigation_dialog.cancel_button_text = "Continuar jogando" if mode in ["local", "online"] else "Cancelar"
    if mode == "bot": navigation_dialog.cancel_button_text = "Continuar partida"
    var dialog_size = Vector2i(480, 160)
    if MobileLayout.active(get_viewport()):
        dialog_size = Vector2i(minf(480, MobileLayout.safe_rect(get_viewport()).size.x-32), 200)
    navigation_dialog.popup_centered(dialog_size)

func _cancel_navigation():
    navigation_dialog.hide()
    pending_navigation = ""
    navigation_confirmed = false
    _refresh_input()

func _confirm_navigation():
    navigation_dialog.hide()
    navigation_confirmed = true
    if online.joined or mode == "online":
        # The existing client resigns and waits for the server before leaving.
        online.leave_room()
        return
    online.cancel_connection()
    bot_controller.stop()
    if pending_navigation == "quit":
        get_tree().quit()
    else:
        game._new_game()
        open_home()

func _input(event):
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.alt_pressed and event.keycode == KEY_ENTER:
        toggle_fullscreen()
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
    var size = get_viewport_rect().size
    var mobile = MobileLayout.active(get_viewport())
    game.mobile_presentation = mobile
    if is_instance_valid(home_button):
        home_button.text = "← TELA INICIAL  ·  ESC"
        home_button.size = Vector2(248, 46)
        home_button.position = Vector2(20, size.y - 66)
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
        var safe = MobileLayout.safe_rect(get_viewport())
        var board_pixels = maxf(160.0, minf(safe.size.y - 44.0, safe.size.x - 360.0))
        factor = board_pixels / game.BOARD
        game.scale = Vector2.ONE * factor
        game.position = safe.get_center() - board_center * factor
        var side_width = (safe.size.x-board_pixels)/2.0-24.0
        var right_x = safe.get_center().x+board_pixels/2.0+16.0
        home_button.text = "← Início"
        home_button.position = Vector2(right_x, safe.end.y-52)
        home_button.size = Vector2(side_width, 44)
        player_card.position = Vector2(right_x, safe.position.y+16)
        player_card.size = Vector2(side_width, 52)
        player_portrait.custom_minimum_size = Vector2(44,44)
        player_caption.custom_minimum_size.x = maxf(90, side_width-53)
        player_caption.add_theme_font_size_override("font_size", 16)
        mobile_actions.position = Vector2(right_x, safe.position.y+88)
        mobile_actions.size = Vector2(side_width, 148)
        mobile_status.position = safe.position+Vector2(12, 112)
        mobile_status.size = Vector2(side_width, 144)
        bot_info.position = safe.position+Vector2(12, 16)
        bot_info.size = Vector2(side_width, 76)
        bot_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        bot_info.add_theme_font_size_override("font_size", 17)
        mobile_promotion.size = Vector2(maxf(326, board_pixels), 132)
        mobile_promotion.position = safe.get_center()-mobile_promotion.size/2.0
        navigation_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        navigation_dialog.get_label().add_theme_font_size_override("font_size", 18)
        for button in [navigation_dialog.get_ok_button(), navigation_dialog.get_cancel_button()]:
            button.custom_minimum_size.y = 44
            button.add_theme_font_size_override("font_size", 17)
    else:
        player_caption.add_theme_font_size_override("font_size", 17)
        bot_info.autowrap_mode = TextServer.AUTOWRAP_OFF
        bot_info.add_theme_font_size_override("font_size", 20)
    # The outpaint has its own board center; align its terrain while covering every edge.
    var texture_size = forest.texture.get_size()
    var art_center = texture_size * Vector2(802.0/1672.0, 445.5/941.0)
    var cover = max(max(size.x/2.0/art_center.x, size.x/2.0/(texture_size.x-art_center.x)), max(size.y/2.0/art_center.y, size.y/2.0/(texture_size.y-art_center.y)))
    forest.scale = Vector2.ONE * cover
    forest.position = size/2.0 + (texture_size/2.0-art_center)*cover
    game.update_presentation(Rect2(-game.position / factor, size / factor))
    if is_instance_valid(theme_manager): theme_manager.layout()

func toggle_fullscreen():
    var window = get_window()
    if OS.has_feature("web"):
        window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
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
        window.mode = Window.MODE_FULLSCREEN
    game.queue_redraw()
