extends SceneTree
## Exercises the real Home/controller/World integration, with the unchanged rules.
const Rules = preload("res://chess/rules.gd")
var checks := 0
var failures := 0
var stage
var world
var bot
var hub

func _initialize():
    call_deferred("run")

func verify(ok: bool, label: String):
    checks += 1
    if ok: print("PASS ", label)
    else:
        failures += 1
        push_error(label)

func until(predicate: Callable, label: String, timeout_ms := 4000) -> bool:
    var deadline = Time.get_ticks_msec() + timeout_ms
    while not predicate.call() and Time.get_ticks_msec() < deadline:
        await process_frame
    var ok = predicate.call()
    verify(ok, label)
    return ok

func square(cell: String) -> Vector2i:
    return Vector2i("abcdefgh".find(cell[0]), 8-int(cell[1]))

func fixture(fen: String, side := "w", level := "easy"):
    stage._start_bot(level,side)
    var position = Rules.new()
    var fields = fen.split(" ")
    var ranks = fields[0].split("/")
    for y in range(8):
        var x = 0
        for symbol in ranks[y]:
            if symbol.is_valid_int(): x += int(symbol)
            else:
                position.board[Vector2i(x,y)] = ("w" if symbol == symbol.to_upper() else "b") + symbol.to_upper()
                x += 1
    position.turn = fields[1]
    position.rights = "" if fields[2] == "-" else fields[2]
    position.ep = Rules.EMPTY if fields[3] == "-" else square(fields[3])
    position.halfmove = int(fields[4])
    position.repetitions = {position.position_key():1}
    bot.rules = position
    bot.thinking = position.turn != bot.human_color
    bot._sync_view()

func click_move(from: String, to: String):
    world._select(square(from))
    var click = InputEventMouseButton.new()
    click.button_index = MOUSE_BUTTON_LEFT
    click.pressed = true
    click.position = world.ORIGIN + (Vector2(square(to))+Vector2(0.5,0.5))*world.TILE
    world._handle_game_input(click)

func escape():
    var event = InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    stage._input(event)

func run():
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    world = stage.get_node("World")
    bot = stage.bot_controller
    hub = stage.get_node("MainHub")
    var world_id = world.get_instance_id()
    hub.play_bot_requested.emit("easy","w")
    verify(stage.mode == "bot" and world.bot == bot and world.visible, "Home launches Easy on the existing visible World")
    verify(bot.human_color == "w" and not bot.thinking and bot.can_interact(), "White human moves first")
    verify(not bot.request_move(square("e2"),square("e5")) and world.move_count == 0, "controller rejects illegal human move without mutating board")
    click_move("e2","e4")
    verify(world.move_count == 1 and bot.rules.piece(square("e4")) == "wP" and bot.thinking, "real board click routes legal move through rules and starts Bot")
    verify(not bot.request_move(square("e4"),square("e5")), "human cannot play during Bot turn")
    var easy_legal = bot.rules.legal_moves()
    if await until(func(): return world.move_count == 2, "Easy completes a legal reply"):
        var chosen_was_legal = false
        for move in easy_legal:
            if move.from == world.last_from and move.to == world.last_to: chosen_was_legal = true
        verify(chosen_was_legal and bot.rules.turn == "w" and bot.can_interact(), "Easy reply belongs to engine legal list and returns control")
    hub.play_bot_requested.emit("easy","b")
    verify(bot.human_color == "b" and bot.thinking and not bot.can_interact(), "choosing Black schedules White Bot automatically")
    await until(func(): return world.move_count == 1 and bot.can_interact(), "White Bot makes first move for Black human")
    stage._start_bot("easy","random")
    verify(bot.human_color in ["w","b"] and bot.thinking == (bot.human_color == "b"), "random side maps to valid color and correct first player")

    fixture("k7/8/8/8/8/8/8/4K2R w K - 0 1")
    click_move("e1","g1")
    verify(world.pieces.get(square("g1")) == "wK" and world.pieces.get(square("f1")) == "wR" and not world.pieces.has(square("h1")), "castling moves king and rook on existing board")
    fixture("7k/8/8/3pP3/8/8/8/K7 w - d6 0 1")
    click_move("e5","d6")
    verify(world.pieces.get(square("d6")) == "wP" and not world.pieces.has(square("d5")) and world.captured_black == ["bP"], "en passant removes victim and updates captured display")
    fixture("7k/P7/8/8/8/8/8/5K2 w - - 0 1")
    click_move("a7","a8")
    verify(world.promotion_pending and bot.rules.piece(square("a7")) == "wP" and bot.rules.ply == 0, "promotion waits for human choice without half-applied move")
    world._finish_promotion("N")
    verify(world.pieces.get(square("a8")) == "wN" and not world.promotion_pending and world.move_count == 1, "human underpromotion uses engine and existing promotion overlay")
    fixture("k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1")
    verify(not bot.request_move(square("e2"),square("d2")) and world.move_count == 0, "pinned human piece cannot expose its king")
    fixture("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1")
    verify(world.game_over and world.status.contains("XEQUE-MATE") and not bot.thinking, "checkmate stops Bot and reaches existing result presentation")
    fixture("7k/5Q2/5K2/8/8/8/8/8 b - - 0 1")
    verify(world.game_over and world.status.contains("AFOGAMENTO"), "stalemate reaches draw presentation")
    fixture("7k/8/8/8/8/8/8/K7 w - - 0 1")
    verify(world.game_over and world.status.contains("MATERIAL"), "insufficient material stops match")
    fixture("7k/8/8/8/8/8/8/KR6 w - - 100 1")
    verify(world.game_over and world.status.contains("50 LANCES"), "engine fifty-move policy reaches draw presentation")

    # The king has no legal steps, so every engine move is a promotion. This
    # remains deterministic even though Easy intentionally chooses randomly.
    fixture("8/P7/8/8/8/2n5/2k5/K7 w - - 0 1", "b")
    if await until(func(): return world.move_count == 1, "Bot can promote automatically"):
        verify(world.pieces.get(square("a8"),"") in ["wQ","wR","wB","wN"], "Bot promotion is a legal engine promotion choice")

    stage._start_bot("medium","b")
    verify(world.get_instance_id() == world_id, "Medium reuses the same board instance")
    if await until(func(): return bot.worker != null, "Medium launches background worker"):
        var animation_before = world.anim_time
        escape()
        verify(stage.navigation_dialog.visible and stage.navigation_dialog.dialog_text == "Deseja abandonar a partida?", "ESC opens exact Bot abandonment confirmation")
        verify(stage.navigation_dialog.cancel_button_text == "Continuar partida" and stage.navigation_dialog.ok_button_text == "Sair para Home", "Bot confirmation exposes requested actions")
        verify(bot.paused and not world.is_processing_unhandled_input() and not bot.can_interact(), "dialog pauses Bot application and blocks board input")
        verify(not bot.request_move(square("a2"),square("a3")), "direct move request also blocked behind dialog")
        var frames = 0
        var pause_deadline = Time.get_ticks_msec()+900
        while Time.get_ticks_msec() < pause_deadline:
            frames += 1
            await process_frame
        verify(world.move_count == 0 and not bot.completed.is_empty(), "finished worker cannot apply a move through open dialog")
        verify(frames > 10 and world.anim_time > animation_before, "animations and main-loop frames continue during search and modal pause")
        print("MEDIUM_UI_FRAMES_DURING_900MS=",frames)
        stage.navigation_dialog.canceled.emit()
        await until(func(): return world.move_count == 1 and bot.can_interact(), "continuing resumes completed Medium move")
        verify(not bot.paused and world.is_processing_unhandled_input(), "cancel restores board interaction")

    stage._start_bot("medium","b")
    if await until(func(): return bot.worker != null, "second Medium worker launches"):
        escape()
        stage.navigation_dialog.confirmed.emit()
        hub.play_local_requested.emit()
        verify(stage.mode == "local" and world.bot == null and not bot.active, "confirmed exit detaches Bot before Local starts")
        await until(func(): return bot.worker == null, "discarded worker collected after navigation")
        verify(world.move_count == 0 and world.pieces.get(square("e2")) == "wP" and stage.mode == "local", "stale worker never mutates Local board")

    stage._start_bot("medium","b")
    if await until(func(): return bot.worker != null, "worker launches before match replacement"):
        stage._start_bot("easy","w")
        await until(func(): return bot.worker == null, "old worker collected after new match")
        verify(world.move_count == 0 and bot.human_color == "w" and bot.can_interact(), "stale previous-match result never mutates new Bot match")
    escape()
    verify(stage.navigation_dialog.visible, "even untouched Bot match requires exit confirmation")
    stage.navigation_dialog.confirmed.emit()
    verify(stage.mode == "home" and not bot.active and world.bot == null and not world.visible, "Bot confirmation returns cleanly to Home")
    hub.play_online_requested.emit()
    verify(stage.mode == "online_menu" and world.bot == null and not bot.active, "Online menu remains available after Bot session")
    stage.queue_free()
    await process_frame
    print("BOT_INTEGRATION_CHECKS=",checks," FAILURES=",failures)
    quit(failures)
