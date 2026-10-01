extends SceneTree
## Mede a análise pós-partida de uma partida fixa (Morphy, "Ópera", 33 lances) com o motor
## disponível: FRAIHA_STOCKFISH definido → Stockfish; senão → motor interno (fallback).
## Uso: godot --headless --path . -s tools/analysis_bench.gd
const OPERA := "e2e4 e7e5 g1f3 d7d6 d2d4 c8g4 d4e5 g4f3 d1f3 d6e5 f1c4 g8f6 f3b3 d8e7 b1c3 c7c6 c1g5 b7b5 c3b5 c6b5 c4b5 b8d7 e1c1 a8d8 d1d7 d8d7 h1d1 e7e6 b5d7 f6d7 b3b8 d7b8 d1d8"
func _init():
    _run.call_deferred()
func _run():
    var eng = preload("res://analysis/engine.gd").new("analysis")
    root.add_child(eng)
    await eng.start()
    var rec = preload("res://analysis/match_record.gd").new()
    rec.start("bot", "w", "Morphy", "Duque")
    for u in OPERA.split(" "): rec.add_move(u)
    rec.finish("win", "XEQUE-MATE")
    var an = preload("res://analysis/analyzer.gd").new(eng)
    root.add_child(an)
    var Cfg = preload("res://analysis/analysis_config.gd")
    var prof: Dictionary = Cfg.engine_profile(eng.transport)
    an.depth = int(prof.depth)
    an.max_ms_per_pos = int(prof.max_ms)
    var t0 := Time.get_ticks_msec()
    var rep: Dictionary = await an.analyze(rec)
    var ms := Time.get_ticks_msec() - t0
    var acc = rep.get("players", {})
    print("ANALYSIS_BENCH engine=%s kind=%s depth=%d plies=%d total_ms=%d ms_per_ply=%d players=%s" % [eng.engine_name, eng.engine_kind(), an.depth, rec.moves.size(), ms, ms / maxi(1, rec.moves.size()), JSON.stringify(acc)])
    eng.stop()
    quit()
