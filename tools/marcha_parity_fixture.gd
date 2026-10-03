extends SceneTree
## Gera tests/fixtures/marcha_parity.json: posições da MARCHA REAL produzidas pelo motor do Godot
## (partidas de bots + posições sorteadas) com as jogadas legais de cada carta, a escolha do bot
## (sem ruído) e o resultado de aplicar uma jogada. O servidor (online_v021/modes/marcha_rules.js)
## tem de reproduzir tudo igual: tests/server/modes_parity_test.cjs.
## Rodar: godot --headless --path . -s tools/marcha_parity_fixture.gd
const Rules := preload("res://marcha/rules.gd")
const AI := preload("res://marcha/ai.gd")

func _initialize(): call_deferred("run")

func snap(g) -> Dictionary:
    return {"pawns": g.pawns.duplicate(true), "hands": g.hands.duplicate(true), "turn": g.turn, "winner": g.winner, "round_no": g.round_no}

func record(g, seat: int, mv: Dictionary) -> Dictionary:
    var st := snap(g)
    var legal := []
    for c in g.hands[seat].size(): legal.append(g.legal_moves(seat, c))
    var ai: Dictionary = AI.choose(g, seat, null)
    var before: Array = g.hands.duplicate(true)
    var ev: Array = g.apply(seat, mv)
    var pick := -1
    if String(mv.get("kind", "")) == "burn":
        var t := int(mv.target_seat)
        var hb: Array = before[t]
        var ha: Array = g.hands[t]
        pick = hb.size() - 1
        for k in ha.size():
            if hb[k] != ha[k]:
                pick = k
                break
    return {"seat": seat, "state": st, "legal": legal, "ai": ai, "move": mv, "burn_pick": pick, "events": ev, "after": snap(g)}

func run():
    var out := []
    var rng := RandomNumberGenerator.new()
    rng.seed = 2026
    # 1) partidas de bots (com ruído para variar), cada passo registrado
    for game in 10:
        var g = Rules.new()
        g.setup(1000 + game)
        var t := 0
        while g.winner < 0 and t < 700:
            var s: int = g.turn
            if g.hands[s].is_empty():
                g.next_turn()
                continue
            var mv: Dictionary = AI.choose(g, s, rng)
            out.append(record(g, s, mv))
            g.next_turn()
            t += 1
    # 2) posições sorteadas (peões espalhados, mãos variadas): jogadas legais e uma jogada aplicada
    for k in 500:
        var g = Rules.new()
        g.setup(5000 + k)
        for s in 4:
            for i in 4:
                var r := rng.randf()
                if r < 0.25: g.pawns[s][i] = {"zone": "home", "pos": i}
                elif r < 0.85:
                    var pos := rng.randi_range(0, 75)
                    if g.occupant(pos).is_empty(): g.pawns[s][i] = {"zone": "track", "pos": pos}
                else:
                    var lp := rng.randi_range(0, 3)
                    var free := true
                    for j in 4:
                        if j != i and g.pawns[s][j].zone == "lane" and g.pawns[s][j].pos == lp: free = false
                    if free: g.pawns[s][i] = {"zone": "lane", "pos": lp}
        # às vezes um inimigo parado na Entrada de alguém
        if rng.randf() < 0.4:
            var victim := rng.randi_range(0, 3)
            var ent: int = posmod(victim * 19 - 2, 76)
            if g.occupant(ent).is_empty(): g.pawns[(victim + 1) % 4][rng.randi_range(0, 3)] = {"zone": "track", "pos": ent}
        var seat := rng.randi_range(0, 3)
        g.turn = seat
        for c in 4: g.hands[seat][c] = Rules.RANKS[rng.randi_range(0, 12)]
        g.winner = -1
        g._check_winner()
        if g.winner >= 0: continue
        var all := []
        for c in g.hands[seat].size(): all.append_array(g.legal_moves(seat, c))
        var mv: Dictionary = all[rng.randi_range(0, all.size() - 1)] if not all.is_empty() else {"card": 0, "rank": g.hands[seat][0], "kind": "discard"}
        out.append(record(g, seat, mv))
    var f := FileAccess.open("res://tests/fixtures/marcha_parity.json", FileAccess.WRITE)
    f.store_string(JSON.stringify({"ruleset": Rules.RULESET_VERSION, "steps": out}))
    f.close()
    print("marcha_parity.json: %d passos" % out.size())
    quit()
