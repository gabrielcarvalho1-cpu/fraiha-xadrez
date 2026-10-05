extends Node
## R42 · GATE MANUAL (Web real, Chromium): Stockfish Worker/WASM fora de PvP + fair play com job em voo.
## Roda como cena principal numa CÓPIA de QA da build (não vai para o produto).
var checks := 0
var failures := 0
var stage

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("GATE PASS " if ok else "GATE FAIL ") + label)

func frames(n: int):
    for i in n: await get_tree().process_frame

func secs(s: float):
    await get_tree().create_timer(s).timeout

func _ready():
    call_deferred("run")

func run():
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    add_child(stage)
    await frames(10)
    if stage.account_ui != null: stage.account_ui.hide_ui()
    var eng = stage.analysis_engine
    # ---------- 1) Análise fora de PvP: Stockfish real no navegador ----------
    stage.mode = "home"
    await eng.start()
    check(eng.transport == "web" and eng.engine_kind() == "STOCKFISH", "ANALYSIS ENGINE = %s (%s, transporte %s)" % [eng.engine_kind(), eng.engine_name, eng.transport])
    var fen := "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
    var r: Dictionary = await eng.evaluate(fen, 10, 3000)
    check(String(r.get("bestmove", "")).length() >= 4, "fora de PvP: análise devolve bestmove (%s)" % r.get("bestmove", ""))
    # ---------- 2) Análise EM VOO quando começa partida humana ----------
    var box := {"done": false, "r": null, "ms": 0}
    var t0 := Time.get_ticks_msec()
    var job := func():
        box.r = await eng.evaluate(fen, 40, 15000)
        box.ms = Time.get_ticks_msec() - t0
        box.done = true
    job.call()
    await secs(0.6)
    check(eng._busy and not box.done, "(preparo) busca longa em andamento")
    stage.mode = "casual"                       # partida humana começou
    stage.game.game_over = false
    var t1 := Time.get_ticks_msec()
    while not box.done and Time.get_ticks_msec() - t1 < 6000: await get_tree().process_frame
    check(box.done and (box.r as Dictionary).is_empty(), "PvP iniciou com análise em voo: resultado descartado (vazio)")
    check(box.done and Time.get_ticks_msec() - t1 < 3000, "busca interrompida rápido (stop UCI): %d ms" % (Time.get_ticks_msec() - t1))
    check(not eng._busy, "engine livre depois do stop")
    var r2: Dictionary = await eng.evaluate(fen, 10, 2000)
    check(r2.is_empty(), "durante PvP: nova consulta de análise recusada")
    # ---------- 3) Depois da partida: engine volta a funcionar ----------
    stage.mode = "home"
    stage.game.game_over = true
    await secs(0.3)
    var r3: Dictionary = await eng.evaluate(fen, 10, 3000)
    check(String(r3.get("bestmove", "")).length() >= 4, "pós-partida: análise volta a responder (%s)" % r3.get("bestmove", ""))
    # ---------- 4) Bot Stockfish fora de PvP ----------
    var bc = stage.bot_controller
    stage._start_bot("madeira", "b")             # bot de Brancas joga primeiro
    var t2 := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t2 < 20000 and stage.game.move_count < 1: await get_tree().process_frame
    check(bc.engine_mode == "STOCKFISH", "BOT ENGINE = %s" % bc.engine_mode)
    check(stage.game.move_count == 1, "bot Stockfish jogou o 1º lance no navegador")
    # ---------- 5) Bot com busca EM VOO quando começa partida humana ----------
    stage._start_bot("challenger", "b")
    var t3 := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t3 < 20000 and not (bc.sf_engine != null and bc.sf_engine._busy): await get_tree().process_frame
    check(bc.sf_engine != null and bc.sf_engine._busy, "(preparo) bot pensando com Stockfish")
    var before: int = stage.game.move_count
    stage.mode = "casual"
    stage.game.game_over = false
    await secs(4.0)
    check(stage.game.move_count == before, "PvP iniciou com bot pensando: nenhum lance do bot aplicado")
    check(not bc.active, "controlador do bot parado")
    check(not bc.sf_engine._busy, "engine do bot livre (stop UCI)")
    # ---------- 6) Jogo LOCAL (2 humanos) continua funcionando ----------
    stage.mode = "home"
    stage.game.game_over = true
    bc.start_local(stage.game)
    stage.mode = "local"
    await frames(5)
    var mc0: int = stage.game.move_count
    var ok_local: bool = bc.request_move(Vector2i(4, 6), Vector2i(4, 4)) and stage.game.move_count == mc0 + 1
    check(ok_local and bc.active, "modo LOCAL (2 humanos): lance aplicado, controlador ativo (sem engine)")
    print("GATE RESULT %d/%d %s" % [checks - failures, checks, "OK" if failures == 0 else "FALHAS=%d" % failures])
