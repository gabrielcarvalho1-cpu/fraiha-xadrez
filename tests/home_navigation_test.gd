extends SceneTree

var checks := 0
var failures := 0
var stage
var world
var online
var hub

func verify(ok: bool, description: String):
    checks += 1
    if ok:
        print("PASS: " + description)
    else:
        failures += 1
        push_error(description)

func escape():
    var event = InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    stage._input(event)

func _initialize():
    call_deferred("run")

func run():
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    world = stage.get_node("World")
    online = stage.get_node("Online")
    hub = stage.get_node("MainHub")
    verify(stage.mode == "home" and hub.is_home_visible(), "startup shows Home")
    verify(not world.visible and not world.is_processing_unhandled_input(), "Home hides board and blocks game input")
    verify(not online.menu.visible and not online.hud.visible, "legacy online panels do not cover Home")
    var enter = InputEventKey.new()
    enter.keycode = KEY_ENTER
    enter.pressed = true
    Input.parse_input_event(enter)
    await process_frame
    enter.pressed = false
    Input.parse_input_event(enter)
    verify(not world.game_started and stage.mode == "home", "unfocused Enter on Home cannot start the hidden legacy board")

    hub.play_local_requested.emit()
    verify(stage.mode == "local" and world.visible and world.game_started, "local action starts the existing game")
    verify(world.is_processing_unhandled_input() and stage.home_button.visible, "local board accepts input and exposes Home button")
    escape()
    verify(stage.mode == "home" and not stage.navigation_dialog.visible, "ESC returns from an untouched local board")

    hub.play_local_requested.emit()
    world._select(Vector2i(4, 6))
    var move = InputEventMouseButton.new()
    move.button_index = MOUSE_BUTTON_LEFT
    move.pressed = true
    move.position = world.ORIGIN + Vector2(4.5, 4.5) * world.TILE
    world._handle_game_input(move)
    verify(world.move_count == 1 and world.turn == "b", "real local pawn move progresses match")
    world._select(Vector2i(3, 1))
    escape()
    verify(stage.navigation_dialog.visible and stage.mode == "local", "ESC asks before abandoning progressed local match")
    verify(not world.is_processing_unhandled_input() and world.selected == Vector2i(-1, -1), "confirmation blocks board input and clears selection")
    stage.navigation_dialog.canceled.emit()
    verify(stage.mode == "local" and world.move_count == 1 and world.is_processing_unhandled_input(), "cancel preserves match and restores interaction")
    stage.home_button.pressed.emit()
    stage.navigation_dialog.confirmed.emit()
    verify(stage.mode == "home" and world.move_count == 0 and not world.visible, "Home button confirmation clears match and returns Home")

    hub.play_online_requested.emit()
    verify(stage.mode == "online_menu" and online.menu.visible and not world.is_processing_unhandled_input(), "online action opens create/join menu without board input")
    online.endpoint = "ws://127.0.0.1:1"
    online.connect_room({"type": "create"})
    verify(online.online_mode and online.socket != null, "connection attempt starts")
    escape()
    verify(stage.mode == "home" and online.socket == null and not online.online_mode and online.retry_after == 0.0, "ESC cancels pending socket and reconnect timer")

    hub.play_online_requested.emit()
    online.online_mode = true
    online.receive({"type": "error", "message": "Sala inexistente."})
    verify(stage.mode == "online_menu" and online.menu.visible and not world.visible and not world.is_processing_unhandled_input(), "failed join keeps menu usable without exposing board input")
    escape()

    hub.play_online_requested.emit()
    # A server welcome is enough to test navigation; no production room is created.
    online.online_mode = true
    online.receive({"type": "welcome", "room": "NAV123", "color": "w", "token": "navigation-fixture"})
    verify(stage.mode == "online" and online.hud.visible and world.visible, "welcome shows online board and HUD")
    escape()
    verify(stage.navigation_dialog.visible and online.joined, "ESC asks before leaving an online room")
    stage.navigation_dialog.canceled.emit()
    verify(online.joined and world.is_processing_unhandled_input(), "cancel keeps online membership")
    stage.home_button.pressed.emit()
    stage.navigation_dialog.confirmed.emit()
    verify(stage.mode == "home" and not online.joined and not online.hud.visible and not world.visible, "confirmed disconnected-room exit returns cleanly to Home")

    hub.play_online_requested.emit()
    online.online_mode = true
    online.receive({"type": "welcome", "room": "NAV456", "color": "b", "token": "navigation-fixture"})
    online.joined = false
    online.connected = false
    online.retry_after = 4.0
    escape()
    verify(stage.navigation_dialog.visible and stage.mode == "online", "reconnecting match still requires abandonment confirmation")
    stage.navigation_dialog.confirmed.emit()
    verify(stage.mode == "home" and online.saved.is_empty() and not online.online_mode, "abandoning a reconnecting match clears its saved membership")

    hub.show_page("about")
    escape()
    verify(hub.page == "main" and stage.mode == "home", "ESC returns from a Home subpage")
    hub.quit_requested.emit()
    verify(stage.navigation_dialog.visible and stage.pending_navigation == "quit", "Sair asks for confirmation")
    stage.navigation_dialog.canceled.emit()
    verify(stage.pending_navigation.is_empty() and hub.is_home_visible(), "cancel quit keeps Home usable")
    stage._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
    verify(stage.navigation_dialog.visible and stage.pending_navigation == "quit", "window close uses the same quit confirmation")
    stage.navigation_dialog.canceled.emit()
    stage.queue_free()
    await process_frame
    print("HOME_NAVIGATION_CHECKS=", checks, " FAILURES=", failures)
    quit(failures)
