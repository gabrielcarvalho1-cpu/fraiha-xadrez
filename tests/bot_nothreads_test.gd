extends SceneTree
## BOT sem threads (como no build Web exportado sem "Suporte a Threads"): a busca precisa
## responder em todas as dificuldades, sem travar os quadros, e respeitar abandono/reinício.
var checks := 0
var failures := 0
var stage
var world
var bot

func _initialize():
    call_deferred("run")

func verify(ok: bool, label: String):
    checks += 1
    if ok: print("PASS ", label)
    else:
        failures += 1
        push_error(label)

func square(cell: String) -> Vector2i:
    return Vector2i("abcdefgh".find(cell[0]), 8-int(cell[1]))

func run():
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    world = stage.get_node("World")
    bot = stage.bot_controller
    bot._threads_ok = false   # simula o build Web sem threads
    verify(not bot.threads_available(), "modo sem threads ativo")
    for level in ["easy", "medium", "hard", "expert"]:
        stage._start_bot(level, "b")   # BOT joga de brancas e começa
        var started = Time.get_ticks_msec()
        var frames = 0
        var longest = 0
        var last = Time.get_ticks_msec()
        while world.move_count < 1 and Time.get_ticks_msec() - started < 9000:
            await process_frame
            var now = Time.get_ticks_msec()
            longest = maxi(longest, now - last)
            last = now
            frames += 1
        verify(world.move_count == 1 and bot.worker == null, "%s responde sem thread (%d ms)" % [level, Time.get_ticks_msec() - started])
        verify(level == "easy" or frames > 5, "%s: a tela continua desenhando durante a busca (%d quadros)" % [level, frames])
        verify(longest < 250, "%s: nenhum quadro travado por muito tempo (maior intervalo %d ms)" % [level, longest])
        verify(bot.can_interact(), "%s: devolve a vez ao jogador" % level)
    # Resposta a um lance humano, e busca antiga descartada ao reiniciar.
    stage._start_bot("hard", "w")
    world._select(square("e2"))
    bot.request_move(square("e2"), square("e4"))
    var wait_until = Time.get_ticks_msec() + 2000
    while bot.coop_search == null and Time.get_ticks_msec() < wait_until: await process_frame
    verify(bot.thinking and bot.coop_search != null, "lance humano dispara busca cooperativa")
    stage._start_bot("hard", "w")
    verify(bot.coop_search == null and world.move_count == 0, "reiniciar descarta a busca anterior")
    var deadline = Time.get_ticks_msec() + 3500
    while Time.get_ticks_msec() < deadline: await process_frame
    verify(world.move_count == 0 and bot.can_interact(), "busca descartada nunca aplica lance no tabuleiro novo")
    print("BOT_NOTHREADS_CHECKS=", checks, " FAILURES=", failures)
    quit(failures)
