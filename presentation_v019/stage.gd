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
var mobile_actions: BoxContainer
var mobile_restart: Button
var bot_level_name := "FÁCIL"
var bot_side_name := "BRANCAS"
var mobile_status: Label
var mobile_promotion: PanelContainer
var account
var account_ui
var account_chip: Button
var ranked
var ranked_ui
var casual
var casual_ui
var match_chat
var social_ui
var invite_ui

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
    # JOGAR ONLINE = Casual com fila automática. As salas por código (_open_online) seguem internas.
    hub.play_online_requested.connect(_open_casual)
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
    _setup_account()
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

func _setup_account():
    account = preload("res://account/account_service.gd").new()
    account.name = "Account"
    add_child(account)
    account_ui = preload("res://account/account_ui.gd").new()
    account_ui.name = "AccountUI"
    add_child(account_ui)
    account_ui.setup(account)
    account_ui.ready_for_ranked.connect(_open_ranked)
    ranked = preload("res://ranked/ranked_controller.gd").new()
    ranked.name = "RankedController"
    add_child(ranked)
    ranked.setup(account, game)
    ranked_ui = preload("res://ranked/ranked_ui.gd").new()
    ranked_ui.name = "RankedUI"
    add_child(ranked_ui)
    ranked_ui.setup(account, ranked)
    ranked_ui.back_requested.connect(open_home)
    ranked_ui.play_requested.connect(_back_to_ranked_lobby)
    ranked.found.connect(_ranked_found)
    casual = preload("res://ranked/ranked_controller.gd").new()
    casual.name = "CasualController"
    casual.kind = "casual"
    add_child(casual)
    casual.setup(account, game)
    casual_ui = preload("res://ranked/ranked_ui.gd").new()
    casual_ui.name = "CasualUI"
    casual_ui.kind = "casual"
    add_child(casual_ui)
    casual_ui.setup(account, casual)
    casual_ui.back_requested.connect(open_home)
    casual_ui.play_requested.connect(_back_to_casual_lobby)
    casual.found.connect(_casual_found)
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
    account.changed.connect(func(): if social_ui.is_open() and not account.has_profile() and not account.account_pending(): social_ui.hide_ui())
    invite_ui = preload("res://social/invite_ui.gd").new()
    invite_ui.name = "InviteUI"
    add_child(invite_ui)
    # Convite nunca aparece por cima de uma partida online em andamento.
    invite_ui.setup(account, hub.avatar_texture, func(): return mode in ["online", "ranked", "casual"] and ((mode != "ranked" or ranked.in_match()) and (mode != "casual" or casual.in_match())))
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
    for caption in ["Reiniciar", "Música", "Tela cheia"]:
        var button = Button.new()
        button.text = caption
        button.custom_minimum_size.y = 44
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.add_theme_font_size_override("font_size", 15)
        mobile_actions.add_child(button)
        if caption == "Reiniciar":
            mobile_restart = button
            button.pressed.connect(func():
                if mode == "ranked":
                    ranked_ui._confirm_resign()
                    return
                if mode == "casual":
                    casual_ui._confirm_resign()
                    return
                game._new_game()
                game.queue_redraw())
        elif caption == "Música":
            button.set_meta("full_text", caption)
            button.set_meta("short_text", "Som")
            button.pressed.connect(func(): get_node("GameAudio").toggle_music())
        else:
            button.set_meta("full_text", caption)
            button.set_meta("short_text", "Tela")
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
    var playing = mode in ["local", "online", "bot", "ranked", "casual"]
    mobile_actions.visible = mobile and playing
    # Online has its own server-side rematch; a local reset would desync the room.
    mobile_restart.visible = mode != "online" and not (mode == "ranked" and not ranked.in_match()) and not (mode == "casual" and not casual.in_match())
    mobile_restart.text = "Desistir" if mode in ["ranked", "casual"] else "Reiniciar"
    if match_chat != null:
        var want_chat = mobile and mode in ["ranked", "casual"] and match_chat.active()
        if match_chat.toggle_button.visible != want_chat:
            match_chat.toggle_button.visible = want_chat
            _layout.call_deferred()
    mobile_status.visible = mobile and mode in ["local", "bot"]
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
        bot_info.text = "BOT · %s" % bot_level_name if mode == "bot" else "PARTIDA LOCAL"
    else:
        bot_info.text = "BOT %s  ·  VOCÊ: %s" % [bot_level_name, bot_side_name]

func _clear_selection():
    game.cancel_drag()
    game.selected = Vector2i(-1, -1)
    game.legal_moves.clear()
    game.queue_redraw()

func _refresh_input():
    var audio = get_node_or_null("GameAudio")
    if audio != null: audio.refresh_music()
    var playing = mode in ["local", "online", "bot", "ranked", "casual"]
    bot_controller.set_paused(not pending_navigation.is_empty())
    if ranked != null:
        ranked.set_paused(not pending_navigation.is_empty())
        ranked_ui.hud.visible = mode == "ranked"
    if casual != null:
        casual.set_paused(not pending_navigation.is_empty())
        casual_ui.hud.visible = mode == "casual"
    bot_info.visible = mode == "bot" or (mode == "local" and MobileLayout.active(get_viewport()))
    _refresh_bot_caption()
    game.set_process_unhandled_input(playing and pending_navigation.is_empty())
    # On mobile the online menu has its own full-width back button.
    home_button.visible = mode != "home" and not (mode == "online_menu" and MobileLayout.active(get_viewport()))
    _refresh_account_chip()
    home_button.disabled = not pending_navigation.is_empty()
    refresh_player_card()

func refresh_player_card():
    if not is_instance_valid(player_card): return
    player_card.visible = mode in ["local","online","bot"]
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
    bot_level_name = {"easy":"FÁCIL","medium":"MÉDIO","hard":"DIFÍCIL","expert":"EXPERT"}.get(difficulty,"FÁCIL")
    bot_side_name = "BRANCAS" if bot_controller.human_color == "w" else "PRETAS"
    _refresh_bot_caption()
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
    var needs_confirmation = destination == "quit" or online.joined or mode in ["online","bot"] or (mode == "local" and game.move_count > 0) or (mode == "ranked" and ranked.in_match()) or (mode == "casual" and casual.in_match())
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
    if mode == "ranked" and ranked.in_match(): ranked.resign()
    if mode == "casual" and casual.in_match(): casual.resign()
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
    home_button.add_theme_font_size_override("font_size", 15)
    for button in [home_button] + mobile_actions.get_children():
        _touch_button_style(button)
    player_caption.add_theme_stylebox_override("normal", _badge_style(Color("5d6b58")))
    var board_pixels: float
    if portrait:
        # Column: badges, board (full width), player, controls.
        var ranked_play = mode in ["ranked", "casual"]
        var top_h = 128.0 if online_play else (44.0 if ranked_play else 34.0)
        var player_h = 48.0
        var controls_h = 44.0
        var available = safe.size.y - top_h - player_h - controls_h - gap*4.0
        var board_total = minf(safe.size.x, available)
        board_pixels = maxf(160.0, board_total/rim)
        board_total = board_pixels*rim
        var column_h = top_h + gap + board_total + gap + player_h
        var top = safe.position.y + maxf(0.0, (safe.size.y - controls_h - gap - column_h)/2.0)
        var board_top = top + top_h + gap
        var board_mid = Vector2(safe.get_center().x, board_top + board_total/2.0)
        game.scale = Vector2.ONE * (board_pixels/game.BOARD)
        game.position = board_mid - board_center*game.scale.x
        var half = (safe.size.x - gap)/2.0
        bot_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        bot_info.position = Vector2(safe.position.x, top)
        bot_info.size = Vector2(half, top_h)
        mobile_status.position = Vector2(safe.position.x + half + gap, top)
        mobile_status.size = Vector2(half, top_h)
        var player_y = board_top + board_total + gap + 4.0
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
        for ui in [ranked_ui, casual_ui]:
            if ui != null: ui.layout_hud(Rect2(), true, false, safe, Rect2(left_x, safe.position.y, side_width, 50), Rect2(left_x, safe.end.y - 50, side_width, 50))
    var crowded = portrait and mobile_actions.get_children().filter(func(b): return b.visible).size() > 3
    for button in mobile_actions.get_children():
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
        button.add_theme_font_size_override("font_size", 16)

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
        # Desktop: tela cheia EXCLUSIVA. A não exclusiva do Windows deixa uma linha de 1 px (cor de fundo) tremendo no topo.
        window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
    game.queue_redraw()
