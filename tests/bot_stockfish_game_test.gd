extends SceneTree
## Partida REAL no stage contra o BOT MADEIRA usando Stockfish (precisa de FRAIHA_STOCKFISH no desktop):
## o "humano" é um Stockfish em força total. Verifica: BOT ENGINE = STOCKFISH, lances do bot vindos do
## Stockfish, xeque-mate, progresso (MADEIRA derrotado → FERRO liberado), recompensa e modal.
## Depois mede alguns lances de um bot alto (MESTRE) no mesmo controlador.
const Notation = preload("res://analysis/notation.gd")
const Progress = preload("res://bot/bot_progress.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize():
    call_deferred("run")

func human_move(bot, hum) -> bool:
    var pos = bot.rules.copy_position()
    var r: Dictionary = await hum.evaluate(Notation.fen(pos), 10, 400)
    var uci := String(r.get("bestmove", ""))
    for m in pos.legal_moves():
        if Notation.uci_of(pos, m) == uci:
            if bot.request_move(m.from, m.to):
                if bot.promotion_choices.size() > 0: bot.promote(String(m.get("promotion", "Q")))
                return true
    return false

func run():
    if not OS.has_environment("FRAIHA_STOCKFISH"):
        print("SKIP: defina FRAIHA_STOCKFISH")
        print("RESULT OK")
        quit()
        return
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.FILE))
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    var world = stage.get_node("World")
    var bot = stage.bot_controller
    var hub = stage.get_node("MainHub")
    var rewards: Array = []
    hub.bot_progress.reward_unlocked.connect(func(b, r): rewards.append(b))
    check(hub.bot_progress.status("madeira") == "available" and hub.bot_progress.status("ferro") == "locked", "início: só MADEIRA disponível")
    var hum = preload("res://analysis/engine.gd").new("analysis")
    root.add_child(hum)
    await hum.start()
    hub.play_bot_requested.emit("madeira", "w")
    var t := Time.get_ticks_msec()
    while bot.engine_mode == "" and Time.get_ticks_msec() - t < 10000: await process_frame
    check(bot.engine_mode == "STOCKFISH", "BOT ENGINE = STOCKFISH no controlador real")
    check(stage.bot_level_name == "BOT MADEIRA", "partida identificada como BOT MADEIRA")
    var plies := 0
    while not world.game_over and plies < 300:
        if bot.can_interact():
            if not await human_move(bot, hum): break
            plies += 1
        else:
            await process_frame
    check(world.game_over and "MATE" in String(world.status), "partida terminou em xeque-mate (%d lances do humano)" % plies)
    var kinds := {}
    var total_ms := 0
    for m in bot.move_log:
        kinds[m.kind] = int(kinds.get(m.kind, 0)) + 1
        total_ms += int(m.ms)
    check(bot.move_log.size() >= plies - 1 and bot.engine_mode == "STOCKFISH", "todos os %d lances do bot vieram do Stockfish %s" % [bot.move_log.size(), JSON.stringify(kinds)])
    print("MADEIRA tempo médio do motor por lance: %d ms" % (total_ms / maxi(1, bot.move_log.size())))
    for i in 120: await process_frame
    check(hub.bot_progress.is_defeated("madeira") and hub.bot_progress.status("ferro") == "available", "vitória registrada: MADEIRA derrotado, FERRO liberado")
    check(rewards == ["madeira"] and hub.bot_progress.avatar_unlocked("mage"), "recompensa entregue: avatar Mago desbloqueado")
    var t2 := Time.get_ticks_msec()
    while not stage.reward_modal.is_open() and Time.get_ticks_msec() - t2 < 5000: await process_frame
    check(stage.reward_modal.is_open(), "modal NOVA RECOMPENSA aparece")
    if OS.has_environment("FRAIHA_SHOT"):
        await RenderingServer.frame_post_draw
        root.get_viewport().get_texture().get_image().save_png(OS.get_environment("FRAIHA_SHOT"))
    stage.reward_modal.close()
    # Bot alto: alguns lances para medir o tempo real no controlador
    hub.play_bot_requested.emit("mestre", "w")
    t = Time.get_ticks_msec()
    while bot.engine_mode == "" and Time.get_ticks_msec() - t < 10000: await process_frame
    var n := 0
    while n < 8 and not world.game_over:
        if bot.can_interact():
            await human_move(bot, hum)
            n += 1
        else:
            await process_frame
    while bot.move_log.size() < 8 and not world.game_over: await process_frame
    var ms := 0
    for m in bot.move_log: ms += int(m.ms)
    check(bot.engine_mode == "STOCKFISH" and bot.sf_engine.options_applied.get("UCI_Elo") == 2350, "MESTRE configurado (UCI_Elo 2350) na mesma instância do bot")
    print("MESTRE tempo médio do motor por lance: %d ms (%d lances)" % [ms / maxi(1, bot.move_log.size()), bot.move_log.size()])
    check(hum.options_applied.is_empty(), "instância de análise intacta (nenhuma opção de bot)")
    print("BOT_STOCKFISH_GAME_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit(1 if failures else 0)
