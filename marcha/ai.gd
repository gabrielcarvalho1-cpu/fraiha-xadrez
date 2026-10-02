extends RefCounted
## MARCHA REAL · bots (aliado e adversários). Escolha gulosa: simula cada jogada legal de cada carta
## e pontua o resultado para a DUPLA do bot. Sem engine, sem rede; rápido o bastante para a Web.
const Rules := preload("res://marcha/rules.gd")
const Layout := preload("res://marcha/board_layout.gd")
const KEEP := {"A": 9, "K": 9, "J": 6, "7": 6, "5": 5, "4": 5, "Q": 4, "10": 3, "9": 3, "8": 3, "6": 2, "3": 2, "2": 2}

## Devolve a jogada escolhida (sempre uma: se nada vale, descarta a carta menos útil).
static func choose(g, seat: int, rng: RandomNumberGenerator = null) -> Dictionary:
    var best := {}
    var best_score := -INF
    var base := evaluate(g, seat)
    for c in g.hands[seat].size():
        for mv in g.legal_moves(seat, c):
            var sim = g.clone()
            sim.apply(seat, mv)
            var sc: float = evaluate(sim, seat) - base
            sc -= float(KEEP.get(String(mv.rank), 2)) * 0.6    # gastar carta valiosa custa um pouco
            if rng != null: sc += rng.randf() * 0.5
            if sc > best_score:
                best_score = sc
                best = mv
    if not best.is_empty(): return best
    # sem jogada: descarta a carta de menor valor de guarda
    var idx := 0
    var low := INF
    for c in g.hands[seat].size():
        var v: float = KEEP.get(String(g.hands[seat][c]), 2)
        if v < low:
            low = v
            idx = c
    return {"card": idx, "rank": g.hands[seat][idx], "kind": "discard"}

## Valor da mesa para a dupla do reino `seat`.
static func evaluate(g, seat: int) -> float:
    var team := Rules.team_of(seat)
    var v := 0.0
    for s in 4:
        var sign := 1.0 if Rules.team_of(s) == team else -1.0
        for i in 4:
            var pr: int = g.progress(s, i)
            var val := 0.0
            if pr < 0: val = -20.0
            elif pr >= 75: val = 110.0 + (pr - 75) * 3.0
            else:
                val = pr * 1.0
                if g.pawns[s][i].pos == Layout.gate_index(s): val += 4.0   # protegido no Portão
                val -= _danger(g, s, i) * (8.0 + pr * 0.25)
            v += sign * val
    if g.winner == team: v += 10000.0
    elif g.winner >= 0: v -= 10000.0
    return v

## Quantos peões adversários podem alcançar este peão com um avanço comum (1..13 casas atrás dele).
static func _danger(g, s: int, i: int) -> float:
    var p: Dictionary = g.pawns[s][i]
    if p.zone != "track" or p.pos == Layout.gate_index(s): return 0.0
    var d := 0.0
    for o in 4:
        if Rules.team_of(o) == Rules.team_of(s): continue
        for j in 4:
            var q: Dictionary = g.pawns[o][j]
            if q.zone != "track": continue
            var dist := posmod(int(p.pos) - int(q.pos), Rules.TRACK)
            if dist >= 2 and dist <= 13 and dist != 4 and dist != 7: d += 0.12
    return minf(d, 0.6)
