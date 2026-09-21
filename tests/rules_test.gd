extends SceneTree
const Rules = preload("res://chess/rules.gd")
var failures = 0
var checks = 0

func _initialize():
    call_deferred("run")

func expect(value: bool, label: String):
    checks += 1
    if value: print("PASS ",label)
    else:
        failures += 1
        push_error("FAIL "+label)

func fen(text: String):
    var p = Rules.new()
    var fields = text.split(" ")
    var ranks = fields[0].split("/")
    for y in range(8):
        var x = 0
        for ch in ranks[y]:
            if ch.is_valid_int(): x += int(ch)
            else:
                p.board[Vector2i(x,y)] = ("w" if ch == ch.to_upper() else "b")+ch.to_upper()
                x += 1
    p.turn = fields[1]
    p.rights = "" if fields[2] == "-" else fields[2]
    p.ep = Rules.EMPTY if fields[3] == "-" else square(fields[3])
    p.halfmove = int(fields[4])
    p.repetitions = {p.position_key():1}
    return p

func square(text: String) -> Vector2i:
    return Vector2i("abcdefgh".find(text[0]),8-int(text[1]))

func play(p, from: String, to: String, promotion: String = "Q") -> bool:
    return p.play({"from":square(from),"to":square(to),"promotion":promotion})

func perft(p, depth: int) -> int:
    if depth == 0: return 1
    var count = 0
    for move in p.legal_moves():
        var next = p.copy_position()
        next.apply_unchecked(move,false)
        count += perft(next,depth-1)
    return count

func run():
    var start = Time.get_ticks_msec()
    var p = Rules.new()
    p.reset()
    expect(p.board.size() == 32,"initial board has 32 pieces")
    expect(perft(p,1) == 20,"initial perft depth 1 = 20")
    expect(perft(p,2) == 400,"initial perft depth 2 = 400")
    expect(perft(p,3) == 8902,"initial perft depth 3 = 8902")
    var original = p.position_key()
    p.legal_moves()
    expect(p.position_key() == original and p.ply == 0,"move generation is side-effect free")
    var copy = p.copy_position()
    play(copy,"e2","e4")
    expect(p.position_key() == original,"position copy is isolated")
    expect(not play(p,"e2","e5"),"illegal move rejected")
    expect(not play(p,"e7","e5"),"wrong side rejected")
    expect(not p.play({"from":square("e2"),"to":square("e4"),"promotion":"K"}),"invalid promotion kind rejected")
    var kiwi = fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    expect(perft(kiwi,1) == 48,"Kiwipete perft depth 1 = 48")
    expect(perft(kiwi,2) == 2039,"Kiwipete perft depth 2 = 2039")
    var ep_position = fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
    expect(perft(ep_position,2) == 191,"rook/pawn endgame perft depth 2 = 191")
    expect(perft(ep_position,3) == 2812,"rook/pawn endgame perft depth 3 = 2812")
    p = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    expect(square("g1") in p.legal_from(square("e1")) and square("c1") in p.legal_from(square("e1")),"both castles available")
    expect(play(p,"e1","g1") and p.piece(square("f1")) == "wR" and p.piece(square("h1")) == "","castling moves rook")
    expect(not p.rights.contains("K") and not p.rights.contains("Q"),"castling revokes both king rights")
    p = fen("4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    expect(not square("g1") in p.legal_from(square("e1")),"cannot castle through attacked square")
    p = fen("4k3/8/8/8/8/8/4r3/R3K2R w KQ - 0 1")
    expect(not square("c1") in p.legal_from(square("e1")),"cannot castle out of check")
    p = fen("4k3/8/8/8/8/8/8/4K3 w KQ - 0 1")
    expect(not square("g1") in p.legal_from(square("e1")),"cannot castle without rook")
    p = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    play(p,"h1","h2"); play(p,"h8","h7"); play(p,"h2","h1"); play(p,"h7","h8")
    expect(not p.rights.contains("K") and not p.rights.contains("k"),"rook returning never restores rights")
    p = fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    play(p,"a1","a8")
    expect(not p.rights.contains("q"),"capturing original rook revokes rights")
    p = fen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
    expect(play(p,"e5","d6") and p.piece(square("d5")) == "" and p.piece(square("d6")) == "wP","en passant removes captured pawn")
    p = fen("4k3/8/8/r4pPK/8/8/8/8 w - f6 0 1")
    expect(not square("f6") in p.legal_from(square("g5")),"en passant cannot expose own king")
    p = Rules.new(); p.reset()
    play(p,"e2","e4"); play(p,"a7","a6")
    expect(p.ep == Rules.EMPTY,"en passant expires after one reply")
    p = fen("4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1")
    expect(not square("d2") in p.legal_from(square("e2")),"pinned piece cannot expose king")
    p = fen("4k3/8/8/8/8/8/4K3/8 w - - 0 1")
    expect(not square("e8") in p.legal_from(square("e2")),"king never jumps or captures enemy king")
    for kind in ["Q","R","B","N"]:
        p = fen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        expect(play(p,"a7","a8",kind) and p.piece(square("a8")) == "w"+kind,"promotion to "+kind)
    p = fen("7k/6Q1/6K1/8/8/8/8/8 b - - 0 1")
    expect(p.outcome() == "mate","checkmate")
    p = fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    expect(p.outcome() == "stalemate","stalemate")
    p = fen("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
    expect(p.outcome() == "material","king versus king draw")
    p = fen("4k3/8/8/8/8/8/8/3BK3 w - - 0 1")
    expect(p.outcome() == "material","single bishop draw")
    p = fen("4k3/8/8/8/8/8/8/3NK3 w - - 0 1")
    expect(p.outcome() == "material","single knight draw")
    p = fen("4k3/8/8/8/8/8/8/2NNK3 w - - 0 1")
    expect(not p.insufficient_material(),"two knights are not an automatic dead position")
    p = fen("4k3/8/8/8/8/8/8/R3K3 w - - 99 1")
    play(p,"a1","a2")
    expect(p.outcome() == "fifty_moves","fifty-move threshold")
    p = Rules.new(); p.reset()
    for cycle in range(2):
        play(p,"g1","f3"); play(p,"g8","f6"); play(p,"f3","g1"); play(p,"f6","g8")
    expect(p.outcome() == "repetition","threefold repetition")
    p = Rules.new(); p.reset(); p.halfmove = 99
    play(p,"e2","e4")
    expect(p.halfmove == 0,"pawn move resets fifty-move clock")
    var with_ep = fen("4k3/8/8/8/4P3/8/8/4K3 b - e3 0 1")
    var without_ep = fen("4k3/8/8/8/4P3/8/8/4K3 b - - 0 1")
    expect(with_ep.position_key() == without_ep.position_key(),"irrelevant en passant excluded from repetition key")
    print("RULES_CHECKS=",checks," FAILURES=",failures," ELAPSED_MS=",Time.get_ticks_msec()-start)
    quit(failures)
