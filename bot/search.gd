extends RefCounted
## Pure, bounded move selection. The caller owns any Thread and passes a position
## snapshot. Every legal move, move application and game outcome comes from Rules.
const MATE_SCORE := 100000
const INFINITY := 1000000
const NON_TERMINAL := 2000000
const PIECE_VALUES := {"P": 100, "N": 320, "B": 330, "R": 500, "Q": 900, "K": 0}
const QUIESCENCE_PLIES := 2
const TT_EXACT := 0
const TT_LOWER := 1
const TT_UPPER := 2
const TT_LIMIT := 4096
const PROFILES := {
    "easy": {"label": "FÁCIL", "budget_ms": 10, "max_depth": 1, "quiescence": 0},
    "medium": {"label": "MÉDIO", "budget_ms": 650, "max_depth": 3, "quiescence": 2},
    "hard": {"label": "DIFÍCIL", "budget_ms": 1400, "max_depth": 4, "quiescence": 3},
    "expert": {"label": "EXPERT", "budget_ms": 2500, "max_depth": 5, "quiescence": 4}
}

var last_metrics: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _deadline := 0
var _started_at := 0
var _nodes := 0
var _stopped := false
var _advanced := false
var _quiescence_plies := QUIESCENCE_PLIES
var _tt: Dictionary = {}
var _move_hints: Dictionary = {}
var _history: Dictionary = {}
var _killers: Dictionary = {}
var _tt_hits := 0
var _tt_cutoffs := 0

static func normalize_difficulty(level: String) -> String:
    match level.to_lower():
        "easy", "facil", "fácil": return "easy"
        "medium", "medio", "médio": return "medium"
        "hard", "dificil", "difícil": return "hard"
        "expert", "especialista": return "expert"
    return "easy"

static func profile(level: String) -> Dictionary:
    return PROFILES[normalize_difficulty(level)].duplicate()

static func difficulty_label(level: String) -> String:
    return String(PROFILES[normalize_difficulty(level)].label)

func _init(seed_value: int = -1):
    if seed_value < 0:
        _rng.randomize()
    else:
        _rng.seed = seed_value

## "easy" selects uniformly from Rules.legal_moves(), including underpromotions.
## Medium preserves its original evaluation and move ordering. Hard/Expert add
## positional evaluation, history/TT ordering and longer bounded quiescence.
## Max depth is a ceiling, not a promise: the time limit always takes priority.
## The returned dictionary contains only from/to/promotion, or {}.
func choose(position, difficulty: String, budget_ms: int = -1, max_depth: int = -1) -> Dictionary:
    difficulty = normalize_difficulty(difficulty)
    var settings := profile(difficulty)
    if budget_ms < 0: budget_ms = int(settings.budget_ms)
    if max_depth < 0: max_depth = int(settings.max_depth)
    _started_at = Time.get_ticks_msec()
    _deadline = _started_at + maxi(1, budget_ms)
    _nodes = 0
    _stopped = false
    _advanced = difficulty in ["hard", "expert"]
    _quiescence_plies = int(settings.quiescence)
    _tt.clear()
    _move_hints.clear()
    _history.clear()
    _killers.clear()
    _tt_hits = 0
    _tt_cutoffs = 0
    last_metrics = {"nodes": 0, "depth": 0, "elapsed_ms": 0, "timed_out": false, "difficulty": difficulty, "score": 0, "budget_ms": budget_ms, "max_depth": max_depth, "advanced": _advanced, "quiescence_plies": _quiescence_plies}
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
    if difficulty == "easy":
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
        return _quiescence(position, alpha, beta, ply, _quiescence_plies)
    var cache_key := ""
    var position_key := ""
    var preferred: Dictionary = {}
    if _advanced:
        position_key = position.position_key()
        cache_key = _cache_key(position, position_key)
        preferred = _move_hints.get(position_key, {})
        if _tt.has(cache_key):
            var entry: Dictionary = _tt[cache_key]
            _tt_hits += 1
            preferred = entry.move
            if int(entry.depth) >= depth:
                var cached := _from_tt_score(int(entry.score), ply)
                if int(entry.bound) == TT_EXACT:
                    _tt_cutoffs += 1
                    return cached
                if int(entry.bound) == TT_LOWER: alpha = maxi(alpha, cached)
                elif int(entry.bound) == TT_UPPER: beta = mini(beta, cached)
                if alpha >= beta:
                    _tt_cutoffs += 1
                    return cached
    var terminal := _terminal_score(position, ply)
    if terminal != NON_TERMINAL:
        return terminal
    if _expired():
        return 0
    var window_alpha := alpha
    var window_beta := beta
    var best := -INFINITY
    var best_move: Dictionary = {}
    for move in _ordered(position, position.legal_moves(), preferred, ply):
        if _expired():
            return 0
        var child = position.copy_position()
        child.apply_unchecked(move)
        var score := -_negamax(child, depth - 1, -beta, -alpha, ply + 1)
        if _stopped:
            return 0
        if score > best:
            best = score
            best_move = move
        alpha = maxi(alpha, score)
        if alpha >= beta:
            if _advanced and position.piece(move.to).is_empty():
                var history_key := _history_key(position.turn, move)
                _history[history_key] = mini(2000, int(_history.get(history_key, 0)) + depth * depth)
                var killers: Array = _killers.get(ply, [])
                if not move in killers:
                    killers.push_front(move.duplicate())
                    if killers.size() > 2: killers.pop_back()
                    _killers[ply] = killers
            break
    if _advanced and not _stopped:
        var bound := TT_EXACT
        if best <= window_alpha: bound = TT_UPPER
        elif best >= window_beta: bound = TT_LOWER
        if _tt.size() >= TT_LIMIT: _tt.clear()
        _tt[cache_key] = {"depth": depth, "bound": bound, "score": _to_tt_score(best, ply), "move": best_move.duplicate()}
        _move_hints[position_key] = best_move.duplicate()
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
    for move in _ordered(position, tactical, {}, ply):
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

func _ordered(position, moves: Array, preferred: Dictionary = {}, ply: int = 0) -> Array:
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
        if _advanced and target.is_empty():
            score += int(_history.get(_history_key(position.turn, move), 0))
            if move in _killers.get(ply, []): score += 1500
            score += (_centrality(move.to) - _centrality(move.from)) * 3
        scored.append({"move": move, "score": score})
    scored.sort_custom(func(a, b): return a.score > b.score)
    var ordered: Array = []
    for item in scored:
        ordered.append(item.move)
    return ordered

func _evaluate(position) -> int:
    if _advanced: return _evaluate_advanced(position)
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

func _history_key(color: String, move: Dictionary) -> String:
    return color + str(move.from) + str(move.to) + str(move.get("promotion", "Q"))

func _cache_key(position, current_key: String = "") -> String:
    if current_key.is_empty(): current_key = position.position_key()
    # Scores can depend on any previous occurrence, not merely this position's
    # count. Hash the complete sorted repetition map, including the search path.
    # This intentionally sacrifices cross-history hits for correct draw scores.
    # SHA-256 makes keys bounded in size; the table is also cleared every choose.
    var history_keys: Array = position.repetitions.keys()
    history_keys.sort()
    var history_parts := PackedStringArray()
    for key in history_keys:
        history_parts.append(str(key) + "=" + str(position.repetitions[key]))
    return current_key + "|half=" + str(position.halfmove) + "|history=" + "\n".join(history_parts).sha256_text()

func _to_tt_score(score: int, ply: int) -> int:
    if score > MATE_SCORE - 1000: return score + ply
    if score < -MATE_SCORE + 1000: return score - ply
    return score

func _from_tt_score(score: int, ply: int) -> int:
    if score > MATE_SCORE - 1000: return score - ply
    if score < -MATE_SCORE + 1000: return score + ply
    return score

func _centrality(square: Vector2i) -> int:
    return 14 - absi(2 * square.x - 7) - absi(2 * square.y - 7)

func _evaluate_advanced(position) -> int:
    var pawn_files := {"w": [0,0,0,0,0,0,0,0], "b": [0,0,0,0,0,0,0,0]}
    var pawn_squares := {"w": [], "b": []}
    var bishops := {"w": 0, "b": 0}
    var material := {"w": 0, "b": 0}
    var non_pawn_material := 0
    for square in position.board:
        var code: String = position.board[square]
        material[code[0]] += int(PIECE_VALUES.get(code[1], 0))
        if code[1] == "P":
            pawn_files[code[0]][square.x] += 1
            pawn_squares[code[0]].append(square)
        elif code[1] != "K": non_pawn_material += int(PIECE_VALUES.get(code[1], 0))
        if code[1] == "B": bishops[code[0]] += 1
    var phase := clampf(float(non_pawn_material) / 6400.0, 0.0, 1.0)
    var scores := {"w": 0, "b": 0}
    for square in position.board:
        if _expired(): return 0
        var code: String = position.board[square]
        var color := code[0]
        var enemy := "b" if color == "w" else "w"
        var kind := code[1]
        var value := int(PIECE_VALUES.get(kind, 0))
        var center := _centrality(square)
        var home_row := 7 if color == "w" else 0
        var advance: int = 6 - square.y if color == "w" else square.y - 1
        match kind:
            "P":
                value += advance * 6 + center
                if pawn_files[color][square.x] > 1: value -= 13
                var isolated: bool = (square.x == 0 or pawn_files[color][square.x - 1] == 0) and (square.x == 7 or pawn_files[color][square.x + 1] == 0)
                if isolated: value -= 12
                var passed := true
                for enemy_pawn in pawn_squares[enemy]:
                    if absi(enemy_pawn.x - square.x) <= 1 and (enemy_pawn.y < square.y if color == "w" else enemy_pawn.y > square.y):
                        passed = false
                        break
                if passed: value += maxi(0, advance) * maxi(0, advance) * 4
            "N", "B":
                value += center * (5 if kind == "N" else 3)
                if square.y == home_row: value -= int(phase * 20)
                # Mobility comes from Rules.pseudo; it is a positional estimate,
                # never an alternative legal-move generator (pins remain Rules').
                value += position.pseudo(square).size() * (3 if kind == "N" else 2)
            "R":
                value += center
                if pawn_files[color][square.x] == 0:
                    value += 12
                    if pawn_files[enemy][square.x] == 0: value += 10
                if square.y == (1 if color == "w" else 6): value += 16
                value += position.pseudo(square).size()
            "Q":
                value += center + position.pseudo(square).size()
                # Early queen travel should not outweigh developing minor pieces.
                if phase > 0.7 and square.y != home_row: value -= 12
            "K":
                value += int((1.0 - phase) * center * 5.0)
                var shield := 0
                var pressure := 0
                var forward := -1 if color == "w" else 1
                for dx in [-1,0,1]:
                    if position.piece(square + Vector2i(dx, forward)) == color + "P": shield += 1
                    for dy in [-1,0,1]:
                        var nearby: Vector2i = square + Vector2i(dx,dy)
                        if position.inside(nearby) and position.attacked(nearby, enemy): pressure += 1
                value += int(phase * (shield * 14 - pressure * 12))
                if square.x >= 3 and square.x <= 4: value -= int(phase * 18)
        if kind != "K" and position.attacked(square, enemy):
            # Threat penalties remain below material values; actual exchanges
            # are resolved by legal search/quiescence, including pinned pieces.
            value -= mini(75, int(PIECE_VALUES.get(kind, 0)) / 9) if not position.attacked(square, color) else 6
        scores[color] += value
    for color in ["w", "b"]:
        if bishops[color] >= 2: scores[color] += 24
    var white_score: int = scores.w - scores.b
    # Prefer simplifying a material advantage, without valuing an exchange more
    # than the pieces themselves; no exchange is assumed legal here.
    white_score += int((material.w - material.b) * (1.0 - phase) * 0.08)
    return white_score if position.turn == "w" else -white_score

func _finish_metrics(depth: int, score: int):
    last_metrics["nodes"] = _nodes
    last_metrics["depth"] = depth
    last_metrics["elapsed_ms"] = Time.get_ticks_msec() - _started_at
    last_metrics["timed_out"] = _stopped
    last_metrics["score"] = score
    last_metrics["tt_hits"] = _tt_hits
    last_metrics["tt_cutoffs"] = _tt_cutoffs
    last_metrics["tt_entries"] = _tt.size()
