extends RefCounted
## Busca do BOT: tabuleiro próprio e rápido (0x88, faz/desfaz sem alocação), usado SÓ para
## escolher o lance. As regras oficiais continuam em Rules: a posição/terminal da raiz e a
## lista de lances possíveis da raiz vêm de Rules, e o lance devolvido é sempre um deles.
## choose() é síncrona (usada em Thread no desktop). choose_async() faz a mesma busca em
## fatias curtas, devolvendo o controle a cada quadro — para Web sem suporte a threads.
const MATE_SCORE := 100000
const INFINITY := 1000000
const NON_TERMINAL := 2000000
const PIECE_VALUES := {"P": 100, "N": 320, "B": 330, "R": 500, "Q": 900, "K": 0}
const PROFILES := {
    "easy": {"label": "FÁCIL", "budget_ms": 10, "max_depth": 1, "quiescence": 0},
    "medium": {"label": "MÉDIO", "budget_ms": 700, "max_depth": 3, "quiescence": 6},
    "hard": {"label": "DIFÍCIL", "budget_ms": 1500, "max_depth": 6, "quiescence": 8},
    "expert": {"label": "EXPERT", "budget_ms": 3000, "max_depth": 64, "quiescence": 10}
}

# ---------- Tabuleiro 0x88 (sq = y*16 + x; y=0 é a 8ª fileira, como em Rules) ----------
const P := 1
const N := 2
const B := 3
const R := 4
const Q := 5
const K := 6
const BLACK := 8
const F_DOUBLE := 1
const F_EP := 2
const F_CASTLE := 3
const KNIGHT_OFF := [33, 31, 18, 14, -33, -31, -18, -14]
const KING_OFF := [1, -1, 16, -16, 15, 17, -15, -17]
const BISHOP_OFF := [15, 17, -15, -17]
const ROOK_OFF := [1, -1, 16, -16]
const VALUE := [0, 100, 320, 330, 500, 900, 0]
const PROMO_LETTER := {2: "N", 3: "B", 4: "R", 5: "Q"}
const LETTER_TYPE := {"P": 1, "N": 2, "B": 3, "R": 4, "Q": 5, "K": 6}

# Tabelas posicionais (visão das brancas, índice y*8+x com y=0 na 8ª fileira).
const PST_P := [0,0,0,0,0,0,0,0, 50,50,50,50,50,50,50,50, 10,10,20,30,30,20,10,10, 5,5,10,25,25,10,5,5, 0,0,0,20,20,0,0,0, 5,-5,-10,0,0,-10,-5,5, 5,10,10,-20,-20,10,10,5, 0,0,0,0,0,0,0,0]
const PST_N := [-50,-40,-30,-30,-30,-30,-40,-50, -40,-20,0,0,0,0,-20,-40, -30,0,10,15,15,10,0,-30, -30,5,15,20,20,15,5,-30, -30,0,15,20,20,15,0,-30, -30,5,10,15,15,10,5,-30, -40,-20,0,5,5,0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50]
const PST_B := [-20,-10,-10,-10,-10,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,10,10,5,0,-10, -10,5,5,10,10,5,5,-10, -10,0,10,10,10,10,0,-10, -10,10,10,10,10,10,10,-10, -10,5,0,0,0,0,5,-10, -20,-10,-10,-10,-10,-10,-10,-20]
const PST_R := [0,0,0,0,0,0,0,0, 5,10,10,10,10,10,10,5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, 0,0,0,5,5,0,0,0]
const PST_Q := [-20,-10,-10,-5,-5,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,5,5,5,0,-10, -5,0,5,5,5,5,0,-5, 0,0,5,5,5,5,0,-5, -10,5,5,5,5,5,0,-10, -10,0,5,0,0,0,0,-10, -20,-10,-10,-5,-5,-10,-10,-20]
const PST_K_MG := [-30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -20,-30,-30,-40,-40,-30,-30,-20, -10,-20,-20,-20,-20,-20,-20,-10, 20,20,0,0,0,0,20,20, 20,30,10,0,0,10,30,20]
const PST_K_EG := [-50,-40,-30,-20,-20,-30,-40,-50, -30,-20,-10,0,0,-10,-20,-30, -30,-10,20,30,30,20,-10,-30, -30,-10,30,40,40,30,-10,-30, -30,-10,30,40,40,30,-10,-30, -30,-10,20,30,30,20,-10,-30, -30,-30,0,0,0,0,-30,-30, -50,-30,-30,-30,-30,-30,-30,-50]
const PASSED_BONUS := [0, 10, 18, 30, 50, 80, 120, 0]   # por avanço (0..7)

static var _zobrist: PackedInt64Array
static var _z_side: int
static var _z_castle: PackedInt64Array
static var _z_ep: PackedInt64Array
static var _castle_mask: PackedInt32Array

var last_metrics: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _deadline := 0
var _started_at := 0
var _nodes := 0
var _stopped := false
var _advanced := false
var _quiescence_plies := 6
var _coop := false
var _slice_end := 0
var _abort := false
var _tt: Dictionary = {}
var _tt_hits := 0
var _tt_cutoffs := 0
var _killers: PackedInt32Array
var _history: PackedInt32Array

# Estado do tabuleiro rápido
var b := PackedInt32Array()
var side := 0
var castle := 0
var ep := -1
var halfmove := 0
var hash := 0
var king_sq := PackedInt32Array([0, 0])
var _u_move := PackedInt32Array()
var _u_cap := PackedInt32Array()
var _u_castle := PackedInt32Array()
var _u_ep := PackedInt32Array()
var _u_half := PackedInt32Array()
var _u_hash := PackedInt64Array()
var _sp := 0
var _game_hashes: Dictionary = {}   # posições já ocorridas na partida real

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
    if seed_value < 0: _rng.randomize()
    else: _rng.seed = seed_value
    _init_tables()
    b.resize(128)
    for arr in [_u_move, _u_cap, _u_castle, _u_ep, _u_half]: arr.resize(512)
    _u_hash.resize(512)
    _killers.resize(256)
    _history.resize(2 * 128 * 128)

static func _init_tables():
    if not _zobrist.is_empty(): return
    var rng := RandomNumberGenerator.new()
    rng.seed = 20260930
    var r64 := func() -> int: return (rng.randi() << 32) ^ rng.randi() ^ (rng.randi() << 16)
    _zobrist.resize(16 * 128)
    for i in _zobrist.size(): _zobrist[i] = r64.call()
    _z_side = r64.call()
    _z_castle.resize(16)
    for i in 16: _z_castle[i] = r64.call()
    _z_ep.resize(8)
    for i in 8: _z_ep[i] = r64.call()
    _castle_mask.resize(128)
    _castle_mask.fill(15)
    _castle_mask[119] = 15 & ~1
    _castle_mask[112] = 15 & ~2
    _castle_mask[116] = 15 & ~3
    _castle_mask[7] = 15 & ~4
    _castle_mask[0] = 15 & ~8
    _castle_mask[4] = 15 & ~12

## Chamada pedida pelo controlador para abandonar uma busca cooperativa em andamento.
func abort():
    _abort = true
    _stopped = true

## "easy" sorteia entre Rules.legal_moves() (inclui subpromoções). Os demais níveis fazem
## busca alfa-beta com aprofundamento iterativo; a profundidade máxima é um teto, o tempo manda.
func choose(position, difficulty: String, budget_ms: int = -1, max_depth: int = -1) -> Dictionary:
    _coop = false
    # Chamada dinâmica: a busca nunca suspende fora do modo cooperativo, então devolve o resultado direto.
    return Callable(self, "_choose_core").call(position, difficulty, budget_ms, max_depth)

## Mesma busca, fatiada (~10 ms por quadro) para não travar a tela quando não há threads (Web).
func choose_async(position, difficulty: String, budget_ms: int = -1, max_depth: int = -1) -> Dictionary:
    _coop = true
    var result = await _choose_core(position, difficulty, budget_ms, max_depth)
    _coop = false
    return result

func _choose_core(position, difficulty: String, budget_ms: int, max_depth: int) -> Dictionary:
    difficulty = normalize_difficulty(difficulty)
    var settings := profile(difficulty)
    if budget_ms < 0: budget_ms = int(settings.budget_ms)
    if max_depth < 0: max_depth = int(settings.max_depth)
    _started_at = Time.get_ticks_msec()
    _deadline = _started_at + maxi(1, budget_ms)
    _slice_end = Time.get_ticks_usec() + 10000
    _nodes = 0
    _stopped = _abort
    _advanced = difficulty in ["hard", "expert"]
    _quiescence_plies = int(settings.quiescence)
    _tt.clear()
    _tt_hits = 0
    _tt_cutoffs = 0
    _killers.fill(0)
    _history.fill(0)
    last_metrics = {"nodes": 0, "depth": 0, "elapsed_ms": 0, "timed_out": false, "difficulty": difficulty, "score": 0, "budget_ms": budget_ms, "max_depth": max_depth, "advanced": _advanced, "quiescence_plies": _quiescence_plies}
    # A posição e o histórico de quem chamou nunca recebem lances de busca.
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

    _load(root_position)
    # Lances da raiz = exatamente os de Rules (o que for devolvido é sempre legal lá).
    var root: Array = []   # [move_int, rules_dict]
    for m in moves: root.append([_from_rules(m), m])
    var noise := {}
    if difficulty == "medium":
        for item in root: noise[item[0]] = _rng.randi_range(-12, 12)
    # Ordem inicial: capturas valiosas e promoções primeiro.
    root.sort_custom(func(x, y): return _order_score(x[0], 0, 0) > _order_score(y[0], 0, 0))
    var best: Array = root[0]
    var best_score := -INFINITY
    var completed_depth := 0
    for depth in range(1, maxi(1, max_depth) + 1):
        if _expired(): break
        var alpha := -INFINITY
        var beta := INFINITY
        var it_best: Array = []
        var it_score := -INFINITY
        var first := true
        for item in root:
            if _stopped: break
            if not _make(item[0]): continue   # (Rules já garantiu a legalidade)
            var score := 0
            if first:
                score = -(await _negamax(depth - 1, -beta, -alpha, 1, true))
            else:
                score = -(await _negamax(depth - 1, -alpha - 1, -alpha, 1, true))
                if not _stopped and score > alpha:
                    score = -(await _negamax(depth - 1, -beta, -alpha, 1, true))
            _unmake()
            if _stopped: break
            score += int(noise.get(item[0], 0))
            first = false
            if score > it_score:
                it_score = score
                it_best = item
            alpha = maxi(alpha, score)
        # Iteração interrompida só vale se o melhor anterior já foi reavaliado e superado.
        if _stopped:
            if not it_best.is_empty() and it_best != root[0] and it_score > best_score and completed_depth > 0:
                best = it_best
            break
        best = it_best
        best_score = it_score
        completed_depth = depth
        # Melhor lance vai para a frente na próxima iteração.
        root.erase(best)
        root.push_front(best)
        if absi(best_score) >= MATE_SCORE - 1000: break
    _finish_metrics(completed_depth, best_score)
    return (best[1] as Dictionary).duplicate()

func _expired() -> bool:
    if _stopped: return true
    if Time.get_ticks_msec() >= _deadline: _stopped = true
    return _stopped

# ---------- Carregar de Rules ----------
func _piece_int(code: String) -> int:
    return int(LETTER_TYPE[code[1]]) | (BLACK if code[0] == "b" else 0)

func _load(pos):
    b.fill(0)
    for sq in pos.board:
        var v: int = _piece_int(pos.board[sq])
        var i: int = sq.y * 16 + sq.x
        b[i] = v
        if v & 7 == K: king_sq[v >> 3] = i
    side = 0 if pos.turn == "w" else 1
    castle = 0
    var rights: String = pos.rights
    if rights.contains("K"): castle |= 1
    if rights.contains("Q"): castle |= 2
    if rights.contains("k"): castle |= 4
    if rights.contains("q"): castle |= 8
    ep = -1 if pos.ep == Vector2i(-1, -1) else pos.ep.y * 16 + pos.ep.x
    halfmove = int(pos.halfmove)
    _sp = 0
    hash = _compute_hash()
    _game_hashes.clear()
    for key in pos.repetitions: _game_hashes[_hash_from_key(String(key))] = true

func _from_rules(m: Dictionary) -> int:
    var fr: int = m.from.y * 16 + m.from.x
    var to: int = m.to.y * 16 + m.to.x
    var p: int = b[fr] & 7
    var flag := 0
    var promo := 0
    if p == K and absi(m.to.x - m.from.x) == 2: flag = F_CASTLE
    elif p == P:
        if m.to.x != m.from.x and b[to] == 0: flag = F_EP
        elif absi(m.to.y - m.from.y) == 2: flag = F_DOUBLE
        if m.to.y == 0 or m.to.y == 7: promo = int(LETTER_TYPE[String(m.get("promotion", "Q"))])
    return fr | (to << 8) | (promo << 16) | (flag << 20)

# ep só entra no hash se houver peão do lado a jogar pronto para capturar (como Rules).
func _ep_hash(sq: int, stm: int) -> int:
    if sq < 0: return 0
    var row := sq + (16 if stm == 0 else -16)
    var mine := P | (BLACK if stm == 1 else 0)
    for d in [-1, 1]:
        var s: int = row + d
        if (s & 0x88) == 0 and b[s] == mine: return _z_ep[sq & 7]
    return 0

func _compute_hash() -> int:
    var h := 0
    for i in 128:
        if (i & 0x88) == 0 and b[i] != 0: h ^= _zobrist[b[i] * 128 + i]
    if side == 1: h ^= _z_side
    h ^= _z_castle[castle]
    h ^= _ep_hash(ep, side)
    return h

func _hash_from_key(key: String) -> int:
    var parts := key.split("|")
    if parts.size() < 4: return 0
    var cells := parts[0].split(",")
    var saved := b.duplicate()
    var saved_side := side
    b.fill(0)
    for idx in mini(64, cells.size()):
        if not cells[idx].is_empty(): b[(idx / 8) * 16 + idx % 8] = _piece_int(cells[idx])
    side = 0 if parts[1] == "w" else 1
    var c := 0
    if parts[2].contains("K"): c |= 1
    if parts[2].contains("Q"): c |= 2
    if parts[2].contains("k"): c |= 4
    if parts[2].contains("q"): c |= 8
    var h := 0
    for i in 128:
        if (i & 0x88) == 0 and b[i] != 0: h ^= _zobrist[b[i] * 128 + i]
    if side == 1: h ^= _z_side
    h ^= _z_castle[c]
    var e := parts[3].replace("(", "").replace(")", "").split(",")
    if e.size() == 2 and int(e[0]) >= 0: h ^= _z_ep[int(e[0]) & 7]
    b = saved
    side = saved_side
    return h

# ---------- Ataques, geração, faz/desfaz ----------
func _attacked(sq: int, by: int) -> bool:
    var bp := BLACK if by == 1 else 0
    if by == 0:
        for s in [sq + 15, sq + 17]:
            if (s & 0x88) == 0 and b[s] == P: return true
    else:
        for s in [sq - 15, sq - 17]:
            if (s & 0x88) == 0 and b[s] == (P | BLACK): return true
    for o in KNIGHT_OFF:
        var s: int = sq + o
        if (s & 0x88) == 0 and b[s] == (N | bp): return true
    for o in KING_OFF:
        var s: int = sq + o
        if (s & 0x88) == 0 and b[s] == (K | bp): return true
    for o in ROOK_OFF:
        var s: int = sq + o
        while (s & 0x88) == 0:
            var v := b[s]
            if v != 0:
                if v == (R | bp) or v == (Q | bp): return true
                break
            s += o
    for o in BISHOP_OFF:
        var s: int = sq + o
        while (s & 0x88) == 0:
            var v := b[s]
            if v != 0:
                if v == (B | bp) or v == (Q | bp): return true
                break
            s += o
    return false

func _in_check() -> bool:
    return _attacked(king_sq[side], side ^ 1)

func _gen(captures_only: bool) -> PackedInt32Array:
    var out := PackedInt32Array()
    var us := side
    var mine := BLACK if us == 1 else 0
    var fwd := 16 if us == 1 else -16
    var start_row := 1 if us == 1 else 6
    var promo_row := 7 if us == 1 else 0
    for fr in 128:
        if fr & 0x88: continue
        var v := b[fr]
        if v == 0 or (v & BLACK) != mine: continue
        var t := v & 7
        if t == P:
            var to := fr + fwd
            if (to & 0x88) == 0 and b[to] == 0:
                if (to >> 4) == promo_row:
                    for pr in [Q, N, R, B]:
                        if captures_only and pr != Q: continue
                        out.append(fr | (to << 8) | (pr << 16))
                elif not captures_only:
                    out.append(fr | (to << 8))
                    var two := to + fwd
                    if (fr >> 4) == start_row and b[two] == 0: out.append(fr | (two << 8) | (F_DOUBLE << 20))
            for d in [-1, 1]:
                var c: int = fr + fwd + d
                if c & 0x88: continue
                var tv := b[c]
                if tv != 0 and (tv & BLACK) != mine and (tv & 7) != K:
                    if (c >> 4) == promo_row:
                        for pr in [Q, N, R, B]:
                            if captures_only and pr != Q: continue
                            out.append(fr | (c << 8) | (pr << 16))
                    else: out.append(fr | (c << 8))
                elif c == ep and tv == 0: out.append(fr | (c << 8) | (F_EP << 20))
        elif t == N or t == K:
            for o in (KNIGHT_OFF if t == N else KING_OFF):
                var to: int = fr + o
                if to & 0x88: continue
                var tv := b[to]
                if tv == 0:
                    if not captures_only: out.append(fr | (to << 8))
                elif (tv & BLACK) != mine and (tv & 7) != K: out.append(fr | (to << 8))
            if t == K and not captures_only:
                var home := 4 if us == 1 else 116
                if fr == home and not _attacked(fr, us ^ 1):
                    var kbit := 4 if us == 1 else 1
                    var qbit := 8 if us == 1 else 2
                    if (castle & kbit) and b[fr + 3] == (R | mine) and b[fr + 1] == 0 and b[fr + 2] == 0 and not _attacked(fr + 1, us ^ 1) and not _attacked(fr + 2, us ^ 1):
                        out.append(fr | ((fr + 2) << 8) | (F_CASTLE << 20))
                    if (castle & qbit) and b[fr - 4] == (R | mine) and b[fr - 1] == 0 and b[fr - 2] == 0 and b[fr - 3] == 0 and not _attacked(fr - 1, us ^ 1) and not _attacked(fr - 2, us ^ 1):
                        out.append(fr | ((fr - 2) << 8) | (F_CASTLE << 20))
        else:
            var offs: Array = BISHOP_OFF if t == B else (ROOK_OFF if t == R else KING_OFF)
            for o in offs:
                var to: int = fr + o
                while (to & 0x88) == 0:
                    var tv := b[to]
                    if tv == 0:
                        if not captures_only: out.append(fr | (to << 8))
                    else:
                        if (tv & BLACK) != mine and (tv & 7) != K: out.append(fr | (to << 8))
                        break
                    to += o
    return out

func _make(m: int) -> bool:
    var fr := m & 0xff
    var to := (m >> 8) & 0xff
    var promo := (m >> 16) & 0xf
    var flag := (m >> 20) & 0xf
    var sp := _sp
    _u_move[sp] = m
    _u_castle[sp] = castle
    _u_ep[sp] = ep
    _u_half[sp] = halfmove
    _u_hash[sp] = hash
    _sp += 1
    var v := b[fr]
    var cap := b[to]
    var us := side
    hash ^= _ep_hash(ep, us)
    hash ^= _z_castle[castle]
    hash ^= _zobrist[v * 128 + fr]
    if flag == F_EP:
        var cs := to + (16 if us == 0 else -16)
        cap = b[cs]
        b[cs] = 0
        hash ^= _zobrist[cap * 128 + cs]
    elif cap != 0:
        hash ^= _zobrist[cap * 128 + to]
    _u_cap[sp] = cap
    var nv := (promo | (v & BLACK)) if promo != 0 else v
    b[to] = nv
    b[fr] = 0
    hash ^= _zobrist[nv * 128 + to]
    if flag == F_CASTLE:
        var rf := fr + 3 if to > fr else fr - 4
        var rt := fr + 1 if to > fr else fr - 1
        var rv := b[rf]
        b[rt] = rv
        b[rf] = 0
        hash ^= _zobrist[rv * 128 + rf] ^ _zobrist[rv * 128 + rt]
    if (v & 7) == K: king_sq[us] = to
    castle &= _castle_mask[fr] & _castle_mask[to]
    ep = (fr + to) / 2 if flag == F_DOUBLE else -1
    halfmove = 0 if (cap != 0 or (v & 7) == P) else halfmove + 1
    side ^= 1
    hash ^= _z_side
    hash ^= _z_castle[castle]
    hash ^= _ep_hash(ep, side)
    if _attacked(king_sq[us], side):
        _unmake()
        return false
    return true

func _unmake():
    _sp -= 1
    var sp := _sp
    var m := _u_move[sp]
    var fr := m & 0xff
    var to := (m >> 8) & 0xff
    var promo := (m >> 16) & 0xf
    var flag := (m >> 20) & 0xf
    side ^= 1
    var v := b[to]
    if promo != 0: v = P | (v & BLACK)
    b[fr] = v
    var cap := _u_cap[sp]
    if flag == F_EP:
        b[to] = 0
        b[to + (16 if side == 0 else -16)] = cap
    else:
        b[to] = cap
    if flag == F_CASTLE:
        var rf := fr + 3 if to > fr else fr - 4
        var rt := fr + 1 if to > fr else fr - 1
        b[rf] = b[rt]
        b[rt] = 0
    if (v & 7) == K: king_sq[side] = fr
    castle = _u_castle[sp]
    ep = _u_ep[sp]
    halfmove = _u_half[sp]
    hash = _u_hash[sp]

func _make_null():
    var sp := _sp
    _u_move[sp] = 0
    _u_castle[sp] = castle
    _u_ep[sp] = ep
    _u_half[sp] = halfmove
    _u_hash[sp] = hash
    _u_cap[sp] = 0
    _sp += 1
    hash ^= _ep_hash(ep, side)
    ep = -1
    side ^= 1
    hash ^= _z_side
    halfmove += 1

func _unmake_null():
    _sp -= 1
    side ^= 1
    ep = _u_ep[_sp]
    halfmove = _u_half[_sp]
    hash = _u_hash[_sp]

# ---------- Empates ----------
func _is_repetition() -> bool:
    # Caminho atual (só até o último lance irreversível) e posições reais da partida.
    var i := _sp - 2
    var limit := _sp - halfmove
    while i >= 0 and i >= limit:
        if _u_hash[i] == hash: return true
        i -= 2
    return _game_hashes.has(hash)

func _insufficient() -> bool:
    var minors := 0
    var bishop_color := -1
    var only_bishops_same := true
    for i in 128:
        if i & 0x88: continue
        var t := b[i] & 7
        if t == 0 or t == K: continue
        if t == P or t == R or t == Q: return false
        minors += 1
        if t == B:
            var c := ((i >> 4) + (i & 7)) % 2
            if bishop_color == -1: bishop_color = c
            elif c != bishop_color: only_bishops_same = false
        else: only_bishops_same = false
    return minors <= 1 or only_bishops_same

# ---------- Busca ----------
func _tick() -> bool:
    # Checagem de tempo barata (a cada 128 nós) e, no modo cooperativo, fim da fatia.
    if (_nodes & 127) != 0: return false
    if Time.get_ticks_msec() >= _deadline: _stopped = true
    return _coop and Time.get_ticks_usec() >= _slice_end

func _yield_frame():
    await Engine.get_main_loop().process_frame
    _slice_end = Time.get_ticks_usec() + 10000

func _order_score(m: int, tt_move: int, ply: int) -> int:
    if m == tt_move: return 10000000
    var fr := m & 0xff
    var to := (m >> 8) & 0xff
    var promo := (m >> 16) & 0xf
    var cap := b[to] & 7
    if ((m >> 20) & 0xf) == F_EP: cap = P
    var s := 0
    if cap != 0: s = 1000000 + VALUE[cap] * 10 - VALUE[b[fr] & 7] / 10
    if promo != 0: s += 900000 + VALUE[promo]
    if s == 0:
        if ply < 128 and (_killers[ply * 2] == m or _killers[ply * 2 + 1] == m): return 800000
        s = _history[side * 16384 + fr * 128 + to]
    return s

func _negamax(depth: int, alpha: int, beta: int, ply: int, allow_null: bool) -> int:
    _nodes += 1
    if _tick(): await _yield_frame()
    if _stopped: return 0
    if halfmove >= 100 or _is_repetition() or _insufficient(): return 0
    var checked := _in_check()
    if checked: depth += 1
    if depth <= 0: return await _quiesce(alpha, beta, ply, _quiescence_plies)
    if ply >= 120: return _evaluate()
    var alpha0 := alpha
    var tt_move := 0
    var entry = _tt.get(hash)
    if entry != null:
        _tt_hits += 1
        tt_move = entry[3]
        if int(entry[0]) >= depth:
            var sc := _from_tt(int(entry[2]), ply)
            var bound := int(entry[1])
            if bound == 0 or (bound == 1 and sc >= beta) or (bound == 2 and sc <= alpha):
                _tt_cutoffs += 1
                return sc
    # Lance nulo (só nos níveis avançados, fora de xeque e com peças além de peões).
    if _advanced and allow_null and not checked and depth >= 3 and beta < MATE_SCORE - 1000 and _has_pieces(side) and _evaluate() >= beta:
        _make_null()
        var ns := -(await _negamax(depth - 3, -beta, -beta + 1, ply + 1, false))
        _unmake_null()
        if _stopped: return 0
        if ns >= beta: return beta
    var moves := _gen(false)
    var scores := PackedInt32Array()
    scores.resize(moves.size())
    for i in moves.size(): scores[i] = _order_score(moves[i], tt_move, ply)
    var best := -INFINITY
    var best_move := 0
    var legal := 0
    for i in moves.size():
        # Seleção incremental: o melhor restante vai para a posição i.
        var bi := i
        for j in range(i + 1, moves.size()):
            if scores[j] > scores[bi]: bi = j
        if bi != i:
            var tm := moves[i]; moves[i] = moves[bi]; moves[bi] = tm
            var ts := scores[i]; scores[i] = scores[bi]; scores[bi] = ts
        var m := moves[i]
        if not _make(m): continue
        legal += 1
        var quiet := scores[i] < 800000
        var score := 0
        if legal == 1:
            score = -(await _negamax(depth - 1, -beta, -alpha, ply + 1, true))
        else:
            var reduction := 1 if (_advanced and quiet and depth >= 3 and legal > 4 and not checked and not _in_check()) else 0
            score = -(await _negamax(depth - 1 - reduction, -alpha - 1, -alpha, ply + 1, true))
            if not _stopped and score > alpha and (reduction > 0 or score < beta):
                score = -(await _negamax(depth - 1, -beta, -alpha, ply + 1, true))
        _unmake()
        if _stopped: return 0
        if score > best:
            best = score
            best_move = m
        if score > alpha:
            alpha = score
            if alpha >= beta:
                if quiet:
                    if ply < 128 and _killers[ply * 2] != m:
                        _killers[ply * 2 + 1] = _killers[ply * 2]
                        _killers[ply * 2] = m
                    var hk := side * 16384 + (m & 0xff) * 128 + ((m >> 8) & 0xff)
                    _history[hk] = mini(700000, _history[hk] + depth * depth)
                break
    if legal == 0:
        return -MATE_SCORE + ply if checked else 0
    var bound_out := 0
    if best <= alpha0: bound_out = 2
    elif best >= beta: bound_out = 1
    if _tt.size() > 200000: _tt.clear()
    _tt[hash] = [depth, bound_out, _to_tt(best, ply), best_move]
    return best

func _quiesce(alpha: int, beta: int, ply: int, remaining: int) -> int:
    _nodes += 1
    if _tick(): await _yield_frame()
    if _stopped: return 0
    var stand := _evaluate()
    if stand >= beta: return stand
    if remaining <= 0: return stand
    if stand > alpha: alpha = stand
    var moves := _gen(true)
    var scores := PackedInt32Array()
    scores.resize(moves.size())
    for i in moves.size(): scores[i] = _order_score(moves[i], 0, ply)
    var best := stand
    for i in moves.size():
        var bi := i
        for j in range(i + 1, moves.size()):
            if scores[j] > scores[bi]: bi = j
        if bi != i:
            var tm := moves[i]; moves[i] = moves[bi]; moves[bi] = tm
            var ts := scores[i]; scores[i] = scores[bi]; scores[bi] = ts
        var m := moves[i]
        # Poda delta: captura que nem com folga alcança alfa.
        var gain: int = VALUE[b[(m >> 8) & 0xff] & 7] + (800 if ((m >> 16) & 0xf) != 0 else 0)
        if ((m >> 20) & 0xf) == F_EP: gain = 100
        if stand + gain + 200 < alpha: continue
        if not _make(m): continue
        var score := -(await _quiesce(-beta, -alpha, ply + 1, remaining - 1))
        _unmake()
        if _stopped: return 0
        if score > best: best = score
        if score > alpha:
            alpha = score
            if alpha >= beta: break
    return best

func _has_pieces(color: int) -> bool:
    var mine := BLACK if color == 1 else 0
    for i in 128:
        if i & 0x88: continue
        var v := b[i]
        if v != 0 and (v & BLACK) == mine and (v & 7) >= N and (v & 7) <= Q: return true
    return false

func _to_tt(score: int, ply: int) -> int:
    if score > MATE_SCORE - 1000: return score + ply
    if score < -MATE_SCORE + 1000: return score - ply
    return score

func _from_tt(score: int, ply: int) -> int:
    if score > MATE_SCORE - 1000: return score - ply
    if score < -MATE_SCORE + 1000: return score + ply
    return score

# ---------- Avaliação ----------
func _evaluate() -> int:
    var mg := [0, 0]
    var eg := [0, 0]
    var phase := 0
    var bishops := [0, 0]
    var material := [0, 0]
    var pawn_files := [PackedInt32Array([0,0,0,0,0,0,0,0]), PackedInt32Array([0,0,0,0,0,0,0,0])]
    # Peão mais avançado/recuado por coluna para peões passados.
    var min_row := [PackedInt32Array([8,8,8,8,8,8,8,8]), PackedInt32Array([8,8,8,8,8,8,8,8])]
    var max_row := [PackedInt32Array([-1,-1,-1,-1,-1,-1,-1,-1]), PackedInt32Array([-1,-1,-1,-1,-1,-1,-1,-1])]
    for i in 128:
        if i & 0x88: continue
        var v := b[i]
        if v == 0: continue
        var c := v >> 3
        var t := v & 7
        var x := i & 7
        var y := i >> 4
        var idx := (y if c == 0 else 7 - y) * 8 + x
        material[c] += VALUE[t]
        match t:
            P:
                mg[c] += 100 + PST_P[idx]
                eg[c] += 110 + PST_P[idx] / 2
                pawn_files[c][x] += 1
                if y < min_row[c][x]: min_row[c][x] = y
                if y > max_row[c][x]: max_row[c][x] = y
            N:
                mg[c] += 320 + PST_N[idx]; eg[c] += 300 + PST_N[idx]; phase += 1
            B:
                mg[c] += 330 + PST_B[idx]; eg[c] += 330 + PST_B[idx]; phase += 1; bishops[c] += 1
            R:
                mg[c] += 500 + PST_R[idx]; eg[c] += 520 + PST_R[idx]; phase += 2
            Q:
                mg[c] += 900 + PST_Q[idx]; eg[c] += 920 + PST_Q[idx]; phase += 4
            K:
                mg[c] += PST_K_MG[idx]; eg[c] += PST_K_EG[idx]
    for c in 2:
        if bishops[c] >= 2:
            mg[c] += 30; eg[c] += 45
    if _advanced:
        for c in 2:
            var e := c ^ 1
            for x in 8:
                var n: int = pawn_files[c][x]
                if n == 0: continue
                if n > 1: mg[c] -= 12 * (n - 1); eg[c] -= 18 * (n - 1)
                var left: int = pawn_files[c][x - 1] if x > 0 else 0
                var right: int = pawn_files[c][x + 1] if x < 7 else 0
                if left == 0 and right == 0: mg[c] -= 10; eg[c] -= 14
                # Peão passado: nenhum peão inimigo à frente na mesma coluna ou vizinhas.
                var front: int = min_row[c][x] if c == 0 else max_row[c][x]
                var passed := true
                for dx in [-1, 0, 1]:
                    var fx: int = x + dx
                    if fx < 0 or fx > 7 or pawn_files[e][fx] == 0: continue
                    if c == 0 and min_row[e][fx] < front: passed = false
                    if c == 1 and max_row[e][fx] > front: passed = false
                if passed:
                    var adv: int = (6 - front) if c == 0 else (front - 1)
                    adv = clampi(adv, 0, 7)
                    mg[c] += PASSED_BONUS[adv] / 2
                    eg[c] += PASSED_BONUS[adv]
            # Torres em colunas abertas/semiabertas.
            var rook := R | (BLACK if c == 1 else 0)
            for i in 128:
                if (i & 0x88) == 0 and b[i] == rook:
                    var x := i & 7
                    if pawn_files[c][x] == 0:
                        mg[c] += 10 if pawn_files[e][x] > 0 else 20
    phase = mini(phase, 24)
    var white_mg: int = mg[0] - mg[1]
    var white_eg: int = eg[0] - eg[1]
    var score := (white_mg * phase + white_eg * (24 - phase)) / 24
    # Final ganho: empurrar o rei inimigo para a borda e aproximar o próprio (converte mates).
    var diff: int = material[0] - material[1]
    if phase <= 8 and absi(diff) >= 300:
        var strong := 0 if diff > 0 else 1
        var ek: int = king_sq[strong ^ 1]
        var sk: int = king_sq[strong]
        var ex := ek & 7
        var ey := ek >> 4
        var center_dist := maxi(3 - ex, ex - 4) + maxi(3 - ey, ey - 4)
        var kings := absi(ex - (sk & 7)) + absi(ey - (sk >> 4))
        var mop := 10 * center_dist + 4 * (14 - kings)
        score += mop if strong == 0 else -mop
    return score if side == 0 else -score

func _finish_metrics(depth: int, score: int):
    last_metrics["nodes"] = _nodes
    last_metrics["depth"] = depth
    last_metrics["elapsed_ms"] = Time.get_ticks_msec() - _started_at
    last_metrics["timed_out"] = _stopped
    last_metrics["score"] = score
    last_metrics["tt_hits"] = _tt_hits
    last_metrics["tt_cutoffs"] = _tt_cutoffs
    last_metrics["tt_entries"] = _tt.size()
