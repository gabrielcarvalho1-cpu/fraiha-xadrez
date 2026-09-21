extends RefCounted
## Pure, bounded move selection. The caller owns any Thread and passes a position
## snapshot. Every legal move, move application and game outcome comes from Rules.
const MATE_SCORE := 100000
const INFINITY := 1000000
const NON_TERMINAL := 2000000
const PIECE_VALUES := {"P": 100, "N": 320, "B": 330, "R": 500, "Q": 900, "K": 0}
const QUIESCENCE_PLIES := 2

var last_metrics: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _deadline := 0
var _started_at := 0
var _nodes := 0
var _stopped := false

func _init(seed_value: int = -1):
    if seed_value < 0:
        _rng.randomize()
    else:
        _rng.seed = seed_value

## "easy" selects uniformly from Rules.legal_moves(), including underpromotions.
## Any other difficulty uses iterative deepening, alpha-beta and a short capture
## extension. The returned dictionary contains only from/to/promotion, or {}.
func choose(position, difficulty: String, budget_ms: int = 650, max_depth: int = 3) -> Dictionary:
    _started_at = Time.get_ticks_msec()
    _deadline = _started_at + maxi(1, budget_ms)
    _nodes = 0
    _stopped = false
    last_metrics = {"nodes": 0, "depth": 0, "elapsed_ms": 0, "timed_out": false, "difficulty": difficulty, "score": 0}
    # The caller's board and repetition history never receive search moves.
    var root_position = position.copy_position()
    var outcome: String = root_position.outcome()
    if not outcome.is_empty():
        last_metrics["outcome"] = outcome
        _finish_metrics(0, 0)
        return {}
    var moves: Array = root_position.legal_moves()
    if moves.is_empty():
        _finish_metrics(0, 0)
        return {}
    if difficulty.to_lower() in ["easy", "facil", "fácil"]:
        var random_move: Dictionary = moves[_rng.randi_range(0, moves.size() - 1)].duplicate()
        _finish_metrics(0, 0)
        return random_move

    moves = _ordered(root_position, moves)
    # A legal fallback is available even if the budget expires during depth one.
    var best_move: Dictionary = moves[0].duplicate()
    var best_score := 0
    var completed_depth := 0
    for depth in range(1, maxi(1, max_depth) + 1):
        if _expired():
            break
        var alpha := -INFINITY
        var iteration_score := -INFINITY
        var iteration_move: Dictionary = best_move
        # Search last iteration's principal move first, without changing legality.
        var ordered: Array = _ordered(root_position, moves, best_move)
        for move in ordered:
            if _expired():
                break
            var child = root_position.copy_position()
            child.apply_unchecked(move)
            var score := -_negamax(child, depth - 1, -INFINITY, -alpha, 1)
            if _stopped:
                break
            if score > iteration_score:
                iteration_score = score
                iteration_move = move
            alpha = maxi(alpha, score)
        # Incomplete iterations cannot overwrite a fully searched result.
        if _stopped:
            break
        best_move = iteration_move.duplicate()
        best_score = iteration_score
        completed_depth = depth
        if best_score >= MATE_SCORE - depth:
            break
    _finish_metrics(completed_depth, best_score)
    return best_move

func _expired() -> bool:
    if _stopped:
        return true
    if Time.get_ticks_msec() >= _deadline:
        _stopped = true
    return _stopped

func _terminal_score(position, ply: int) -> int:
    # Includes the isolated engine's current automatic draw policy. Search never
    # replaces that policy with its own repetition/material/50-move rules.
    var outcome: String = position.outcome()
    if outcome.is_empty():
        return NON_TERMINAL
    return -MATE_SCORE + ply if outcome == "mate" else 0

func _negamax(position, depth: int, alpha: int, beta: int, ply: int) -> int:
    _nodes += 1
    if _expired():
        return 0
    if depth <= 0:
        return _quiescence(position, alpha, beta, ply, QUIESCENCE_PLIES)
    var terminal := _terminal_score(position, ply)
    if terminal != NON_TERMINAL:
        return terminal
    if _expired():
        return 0
    var best := -INFINITY
    for move in _ordered(position, position.legal_moves()):
        if _expired():
            return 0
        var child = position.copy_position()
        child.apply_unchecked(move)
        var score := -_negamax(child, depth - 1, -beta, -alpha, ply + 1)
        if _stopped:
            return 0
        best = maxi(best, score)
        alpha = maxi(alpha, score)
        if alpha >= beta:
            break
    return best

func _quiescence(position, alpha: int, beta: int, ply: int, remaining: int) -> int:
    _nodes += 1
    if _expired():
        return 0
    var terminal := _terminal_score(position, ply)
    if terminal != NON_TERMINAL:
        return terminal
    if _expired():
        return 0
    var score := _evaluate(position)
    if remaining <= 0:
        return score
    var checked: bool = position.in_check(position.turn)
    if not checked:
        if score >= beta:
            return score
        alpha = maxi(alpha, score)
    # In check, search every legal evasion; otherwise only legal captures and
    # promotions. This filters Rules' moves rather than generating chess rules.
    var tactical: Array = []
    for move in position.legal_moves():
        var moving: String = position.piece(move.from)
        var capture: bool = not position.piece(move.to).is_empty()
        # A legal pawn diagonal to an empty square is en passant; legitimacy was
        # already decided by Rules, and this flag is only move ordering/filtering.
        if moving.ends_with("P") and move.from.x != move.to.x:
            capture = true
        var promotes: bool = moving.ends_with("P") and move.to.y in [0, 7]
        if checked or capture or promotes:
            tactical.append(move)
    var best := -INFINITY if checked else score
    for move in _ordered(position, tactical):
        if _expired():
            return 0
        var child = position.copy_position()
        child.apply_unchecked(move)
        var result := -_quiescence(child, -beta, -alpha, ply + 1, remaining - 1)
        if _stopped:
            return 0
        best = maxi(best, result)
        alpha = maxi(alpha, result)
        if alpha >= beta:
            break
    return best

func _ordered(position, moves: Array, preferred: Dictionary = {}) -> Array:
    var scored: Array = []
    for move in moves:
        var score := 0
        if not preferred.is_empty() and move == preferred:
            score += 100000
        var target: String = position.piece(move.to)
        var moving: String = position.piece(move.from)
        if not target.is_empty():
            score += 10 * int(PIECE_VALUES.get(target[1], 0)) - int(PIECE_VALUES.get(moving[1], 0))
        if moving.ends_with("P") and move.to.y in [0, 7]:
            score += int(PIECE_VALUES.get(move.get("promotion", "Q"), 900))
        scored.append({"move": move, "score": score})
    scored.sort_custom(func(a, b): return a.score > b.score)
    var ordered: Array = []
    for item in scored:
        ordered.append(item.move)
    return ordered

func _evaluate(position) -> int:
    var white_score := 0
    for square in position.board:
        var code: String = position.board[square]
        var kind := code[1]
        var value := int(PIECE_VALUES.get(kind, 0))
        var center: int = 7 - absi(2 * square.x - 7) / 2 - absi(2 * square.y - 7) / 2
        match kind:
            "P":
                var advancement: int = 6 - square.y if code[0] == "w" else square.y - 1
                value += advancement * 7 + center * 2
            "N": value += center * 9
            "B": value += center * 5
            "R": value += center * 2
            "Q": value += center
        white_score += value if code[0] == "w" else -value
    return white_score if position.turn == "w" else -white_score

func _finish_metrics(depth: int, score: int):
    last_metrics["nodes"] = _nodes
    last_metrics["depth"] = depth
    last_metrics["elapsed_ms"] = Time.get_ticks_msec() - _started_at
    last_metrics["timed_out"] = _stopped
    last_metrics["score"] = score
