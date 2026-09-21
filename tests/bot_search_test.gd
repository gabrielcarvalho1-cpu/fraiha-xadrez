extends SceneTree
const Rules = preload("res://chess/rules.gd")
const Search = preload("res://bot/search.gd")
var checks := 0
var failures := 0

func _initialize():
    call_deferred("run")

func expect(ok: bool, label: String):
    checks += 1
    if ok:
        print("PASS ", label)
    else:
        failures += 1
        push_error("FAIL " + label)

func square(text: String) -> Vector2i:
    return Vector2i("abcdefgh".find(text[0]), 8 - int(text[1]))

func fen(text: String):
    var p = Rules.new()
    var fields = text.split(" ")
    var rows = fields[0].split("/")
    for y in range(8):
        var x = 0
        for ch in rows[y]:
            if ch.is_valid_int():
                x += int(ch)
            else:
                p.board[Vector2i(x, y)] = ("w" if ch == ch.to_upper() else "b") + ch.to_upper()
                x += 1
    p.turn = fields[1]
    p.rights = "" if fields[2] == "-" else fields[2]
    p.ep = Rules.EMPTY if fields[3] == "-" else square(fields[3])
    p.halfmove = int(fields[4])
    p.repetitions = {p.position_key(): 1}
    return p

func snapshot(p) -> Dictionary:
    return {"board": p.board.duplicate(), "turn": p.turn, "rights": p.rights, "ep": p.ep, "halfmove": p.halfmove, "ply": p.ply, "repetitions": p.repetitions.duplicate()}

func run():
    var p = Rules.new()
    p.reset()
    var before = snapshot(p)
    var a = Search.new(42)
    var b = Search.new(42)
    var c = Search.new(99)
    var deterministic := true
    var varied := false
    var all_legal := true
    var legal: Array = p.legal_moves()
    for i in range(24):
        var ma: Dictionary = a.choose(p, "easy")
        var mb: Dictionary = b.choose(p, "easy")
        var mc: Dictionary = c.choose(p, "easy")
        deterministic = deterministic and ma == mb
        varied = varied or ma != mc
        all_legal = all_legal and ma in legal and mb in legal and mc in legal
    expect(deterministic, "easy is reproducible with identical seed")
    expect(varied, "easy differs across deterministic seeds")
    expect(all_legal, "all sampled easy moves belong to Rules legal moves")
    expect(snapshot(p) == before, "easy search never mutates caller position/history")

    p = fen("q5k1/8/8/8/8/8/8/R5K1 w - - 0 1")
    var search = Search.new(1)
    before = snapshot(p)
    var move: Dictionary = search.choose(p, "medium", 650, 3)
    expect(move.get("from") == square("a1") and move.get("to") == square("a8"), "medium captures an undefended queen")
    expect(move in p.legal_moves(), "medium capture is legal")
    expect(snapshot(p) == before, "medium leaves board and all repetition metadata unchanged")
    expect(search.last_metrics.depth >= 1 and search.last_metrics.nodes > 0, "medium reports completed search depth and nodes")

    p = fen("r5k1/8/8/8/8/8/8/Q5K1 b - - 0 1")
    move = search.choose(p, "medium", 650, 3)
    expect(move.get("from") == square("a8") and move.get("to") == square("a1"), "medium evaluates captures correctly when playing black")

    p = fen("3r2k1/8/8/3p4/8/8/8/3Q2K1 w - - 0 1")
    move = search.choose(p, "medium", 650, 3)
    expect(move in p.legal_moves(), "medium defensive choice is legal")
    expect(not (move.get("from") == square("d1") and move.get("to") == square("d5")), "medium does not sacrifice queen for a rook-defended pawn")

    p = fen("7k/5Q2/7K/8/8/8/8/8 w - - 0 1")
    move = search.choose(p, "medium", 650, 3)
    var result = p.copy_position()
    expect(result.play(move) and result.outcome() == "mate", "medium finds mate in one using Rules outcome")

    p = fen("7k/P7/8/8/8/8/8/6K1 w - - 0 1")
    var promotions := {}
    a = Search.new(7)
    all_legal = true
    legal = p.legal_moves()
    for i in range(64):
        move = a.choose(p, "easy")
        all_legal = all_legal and move in legal
        if move.get("from") == square("a7"):
            promotions[move.get("promotion")] = true
    expect(all_legal, "easy promotions and king moves are always legal")
    expect(promotions.has("Q") and promotions.has("R") and promotions.has("B") and promotions.has("N"), "easy samples all four legal promotion choices")

    p = fen("8/k1P5/2K5/8/8/8/8/8 w - - 0 1")
    var queen_promotion = p.copy_position()
    queen_promotion.play({"from": square("c7"), "to": square("c8"), "promotion": "Q"})
    expect(queen_promotion.outcome() == "stalemate", "underpromotion fixture has stalemate after queen promotion")
    move = search.choose(p, "medium", 650, 3)
    expect(move.get("from") == square("c7") and move.get("to") == square("c8") and move.get("promotion") == "R", "medium underpromotes to rook instead of stalemating")

    p = fen("4r1k1/8/8/8/8/8/8/4K3 w - - 0 1")
    move = a.choose(p, "easy")
    result = p.copy_position()
    expect(result.play(move) and not result.in_check("w"), "easy only selects a legal evasion while in check")

    p = fen("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1")
    expect(search.choose(p, "medium").is_empty(), "no move after checkmate")
    p = fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    expect(search.choose(p, "easy").is_empty(), "no move after stalemate")
    p = fen("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    expect(search.choose(p, "medium").is_empty(), "no move after material draw despite available king moves")
    p = fen("4k3/8/8/8/8/8/8/R3K3 w - - 100 1")
    expect(search.choose(p, "easy").is_empty(), "easy respects Rules fifty-move terminal policy")
    p = Rules.new()
    p.reset()
    p.repetitions[p.position_key()] = 3
    expect(search.choose(p, "medium").is_empty(), "medium respects Rules repetition terminal policy")

    p.reset()
    before = snapshot(p)
    var started := Time.get_ticks_msec()
    move = search.choose(p, "medium", 40, 20)
    var elapsed := Time.get_ticks_msec() - started
    expect(move in p.legal_moves(), "time-limited search returns a legal fallback or completed result")
    expect(elapsed <= 240 and search.last_metrics.timed_out, "40ms budget stops deep search within scheduling tolerance")
    expect(snapshot(p) == before, "interrupted search never mutates caller position")
    expect(search.last_metrics.elapsed_ms <= elapsed, "metrics report measured search time")
    print("BOT_SEARCH_CHECKS=", checks, " FAILURES=", failures, " TIME_LIMIT_TEST_MS=", elapsed)
    quit(failures)
