extends Node2D
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
    navigation_dialog = ConfirmationDialog.new()
    navigation_dialog.name = "LeaveConfirmation"
    navigation_dialog.title = "FRAIHA XADREZ"
    navigation_dialog.ok_button_text = "Confirmar"
    navigation_dialog.cancel_button_text = "Continuar jogando"
    navigation_dialog.confirmed.connect(_confirm_navigation)
    navigation_dialog.canceled.connect(_cancel_navigation)
    overlay.add_child(navigation_dialog)

func _clear_selection():
    game.cancel_drag()
    game.selected = Vector2i(-1, -1)
    game.legal_moves.clear()
    game.queue_redraw()

func _refresh_input():
    var playing = mode in ["local", "online", "bot"]
    bot_controller.set_paused(not pending_navigation.is_empty())
    bot_info.visible = mode == "bot"
    game.set_process_unhandled_input(playing and pending_navigation.is_empty())
    home_button.visible = mode != "home"
    home_button.disabled = not pending_navigation.is_empty()

func _start_local():
    bot_controller.stop()
    hub.hide_hub()
    online.cancel_connection()
    online.start_local()
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
    bot_info.text = "BOT %s  ·  VOCÊ: %s" % ["MÉDIO" if difficulty == "medium" else "FÁCIL", "BRANCAS" if bot_controller.human_color == "w" else "PRETAS"]
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
    navigation_dialog.popup_centered(Vector2i(480, 160))

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
    if is_instance_valid(home_button):
        home_button.position = Vector2(20, size.y - 66)
    if is_instance_valid(bot_info):
        bot_info.position = Vector2(size.x/2.0-250,16)
        bot_info.size = Vector2(500,38)
    var factor = min(size.y / 1024.0, size.x / 1024.0)
    game.scale = Vector2.ONE * factor
    var board_center = game.ORIGIN + Vector2.ONE * game.BOARD / 2.0
    game.position = size / 2.0 - board_center * factor
    # The outpaint has its own board center; align its terrain while covering every edge.
    var texture_size = forest.texture.get_size()
    var art_center = texture_size * Vector2(802.0/1672.0, 445.5/941.0)
    var cover = max(max(size.x/2.0/art_center.x, size.x/2.0/(texture_size.x-art_center.x)), max(size.y/2.0/art_center.y, size.y/2.0/(texture_size.y-art_center.y)))
    forest.scale = Vector2.ONE * cover
    forest.position = size/2.0 + (texture_size/2.0-art_center)*cover
    game.update_presentation(Rect2(-game.position / factor, size / factor))

func toggle_fullscreen():
    var window = get_window()
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
