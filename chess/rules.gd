extends RefCounted
## Pure position model: no nodes, rendering, sockets or shared mutable state.
const EMPTY = Vector2i(-1, -1)
const KNIGHTS = [Vector2i(1,2),Vector2i(2,1),Vector2i(2,-1),Vector2i(1,-2),Vector2i(-1,-2),Vector2i(-2,-1),Vector2i(-2,1),Vector2i(-1,2)]
const DIRECTIONS = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]
var board: Dictionary = {}
var turn = "w"
var rights = "KQkq"
var ep = EMPTY
var halfmove = 0
var ply = 0
var repetitions: Dictionary = {}

func reset():
    board.clear()
    var back = ["R","N","B","Q","K","B","N","R"]
    for x in range(8):
        board[Vector2i(x,0)] = "b" + back[x]
        board[Vector2i(x,1)] = "bP"
        board[Vector2i(x,6)] = "wP"
        board[Vector2i(x,7)] = "w" + back[x]
    turn = "w"
    rights = "KQkq"
    ep = EMPTY
    halfmove = 0
    ply = 0
    repetitions = {position_key(): 1}

func copy_position():
    var p = get_script().new()
    p.board = board.duplicate()
    p.turn = turn
    p.rights = rights
    p.ep = ep
    p.halfmove = halfmove
    p.ply = ply
    p.repetitions = repetitions.duplicate()
    return p

static func other(c: String) -> String:
    return "b" if c == "w" else "w"

static func inside(p: Vector2i) -> bool:
    return p.x >= 0 and p.y >= 0 and p.x < 8 and p.y < 8

func piece(p: Vector2i) -> String:
    return board.get(p, "")

func attacked(square: Vector2i, by: String) -> bool:
    var dy = -1 if by == "w" else 1
    for dx in [-1,1]:
        if piece(square - Vector2i(dx,dy)) == by + "P": return true
    for d in KNIGHTS:
        if piece(square + d) == by + "N": return true
    for i in range(8):
        var d: Vector2i = DIRECTIONS[i]
        var p = square + d
        var distance = 1
        while inside(p):
            var code = piece(p)
            if not code.is_empty():
                if code[0] == by:
                    if code[1] == "K" and distance == 1: return true
                    if code[1] == "Q" or code[1] == ("R" if i < 4 else "B"): return true
                break
            distance += 1
            p += d
    return false

func in_check(c: String) -> bool:
    for p in board:
        if board[p] == c + "K": return attacked(p, other(c))
    return true

func pseudo(fr: Vector2i) -> Array:
    var moves: Array = []
    var code = piece(fr)
    if code.is_empty(): return moves
    var c = code[0]
    var kind = code[1]
    if kind == "P":
        var dy = -1 if c == "w" else 1
        var one = fr + Vector2i(0,dy)
        if inside(one) and piece(one).is_empty():
            moves.append(one)
            var two = fr + Vector2i(0,2*dy)
            if fr.y == (6 if c == "w" else 1) and piece(two).is_empty(): moves.append(two)
        for dx in [-1,1]:
            var to = fr + Vector2i(dx,dy)
            if not inside(to): continue
            var target = piece(to)
            if not target.is_empty() and target[0] != c and target[1] != "K": moves.append(to)
            elif to == ep and target.is_empty() and piece(Vector2i(to.x,fr.y)) == other(c)+"P": moves.append(to)
    elif kind == "N" or kind == "K":
        for d in (KNIGHTS if kind == "N" else DIRECTIONS):
            var to: Vector2i = fr + d
            var target = piece(to)
            if inside(to) and (target.is_empty() or (target[0] != c and target[1] != "K")): moves.append(to)
        if kind == "K" and fr == Vector2i(4,7 if c == "w" else 0) and not in_check(c):
            for side in [0,1]:
                var symbol = ("K" if side == 0 else "Q") if c == "w" else ("k" if side == 0 else "q")
                var rook_x = 7 if side == 0 else 0
                var step = 1 if side == 0 else -1
                if not rights.contains(symbol) or piece(Vector2i(rook_x,fr.y)) != c+"R": continue
                var clear = true
                for x in (range(5,7) if side == 0 else range(1,4)):
                    if not piece(Vector2i(x,fr.y)).is_empty(): clear = false
                if clear and not attacked(fr+Vector2i(step,0),other(c)) and not attacked(fr+Vector2i(2*step,0),other(c)):
                    moves.append(fr+Vector2i(2*step,0))
    else:
        for i in range(8):
            if kind == "B" and i < 4: continue
            if kind == "R" and i >= 4: continue
            var d: Vector2i = DIRECTIONS[i]
            var to = fr + d
            while inside(to):
                var target = piece(to)
                if target.is_empty(): moves.append(to)
                else:
                    if target[0] != c and target[1] != "K": moves.append(to)
                    break
                to += d
    return moves

func legal_from(fr: Vector2i) -> Array:
    var result: Array = []
    var code = piece(fr)
    if code.is_empty() or code[0] != turn: return result
    for to in pseudo(fr):
        var p = copy_position()
        p.apply_unchecked({"from":fr,"to":to,"promotion":"Q"}, false)
        if not p.in_check(code[0]): result.append(to)
    return result

func legal_moves() -> Array:
    var moves: Array = []
    for fr in board:
        if board[fr][0] != turn: continue
        for to in legal_from(fr):
            if board[fr][1] == "P" and to.y in [0,7]:
                for promotion in ["Q","R","B","N"]: moves.append({"from":fr,"to":to,"promotion":promotion})
            else: moves.append({"from":fr,"to":to,"promotion":"Q"})
    return moves

func play(move: Dictionary) -> bool:
    if not move.has("from") or not move.has("to") or not String(move.get("promotion","Q")) in ["Q","R","B","N"]: return false
    if not move.to in legal_from(move.from): return false
    apply_unchecked(move)
    return true

func apply_unchecked(move: Dictionary, record: bool = true):
    var fr: Vector2i = move.from
    var to: Vector2i = move.to
    var code = piece(fr)
    var capture = not piece(to).is_empty()
    if code[1] == "P" and to == ep and fr.x != to.x and not capture:
        board.erase(Vector2i(to.x,fr.y))
        capture = true
    for start in [Vector2i(7,7),Vector2i(0,7),Vector2i(7,0),Vector2i(0,0)]:
        if fr == start or to == start:
            var symbol = ("K" if start.x == 7 else "Q") if start.y == 7 else ("k" if start.x == 7 else "q")
            rights = rights.replace(symbol, "")
    if code[1] == "K":
        rights = rights.replace("K" if code[0] == "w" else "k", "").replace("Q" if code[0] == "w" else "q", "")
        if abs(to.x-fr.x) == 2:
            var rook = Vector2i(7 if to.x > fr.x else 0,fr.y)
            board.erase(rook)
            board[Vector2i(5 if to.x > fr.x else 3,fr.y)] = code[0]+"R"
    board.erase(fr)
    board[to] = code[0]+String(move.get("promotion","Q")) if code[1] == "P" and to.y in [0,7] else code
    ep = Vector2i(fr.x,(fr.y+to.y)/2) if code[1] == "P" and abs(fr.y-to.y) == 2 else EMPTY
    halfmove = 0 if capture or code[1] == "P" else halfmove+1
    ply += 1
    turn = other(turn)
    if record:
        var key = position_key()
        repetitions[key] = int(repetitions.get(key,0))+1

func position_key() -> String:
    var parts = PackedStringArray()
    for y in range(8):
        for x in range(8): parts.append(piece(Vector2i(x,y)))
    # EP affects repetition only when a legal EP capture exists (including pins).
    var effective_ep = EMPTY
    if ep != EMPTY:
        var row = ep.y + (1 if turn == "w" else -1)
        for dx in [-1,1]:
            var fr = Vector2i(ep.x+dx,row)
            if piece(fr) == turn+"P" and ep in legal_from(fr): effective_ep = ep
    return ",".join(parts)+"|"+turn+"|"+rights+"|"+str(effective_ep)

func insufficient_material() -> bool:
    var minors: Array = []
    for p in board:
        var kind: String = board[p][1]
        if kind in ["P","R","Q"]: return false
        if kind != "K": minors.append([kind,(p.x+p.y)%2])
    if minors.size() <= 1: return true
    for m in minors:
        if m[0] != "B" or m[1] != minors[0][1]: return false
    return true

func outcome() -> String:
    if legal_moves().is_empty(): return "mate" if in_check(turn) else "stalemate"
    if insufficient_material(): return "material"
    if halfmove >= 100: return "fifty_moves"
    if int(repetitions.get(position_key(),0)) >= 3: return "repetition"
    return ""
