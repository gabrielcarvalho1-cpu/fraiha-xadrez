extends SceneTree
## Gera tests/fixtures/xeque_parity.json.gz (depois de gzip): ações do XEQUE no motor do Godot com o
## estado antes/depois, para o servidor (online_v021/modes/xeque_rules.js) reproduzir igual.
## Também registra a estimativa do bot (p_last_play_true), que não depende de sorteio.
const Rules := preload("res://xeque/rules.gd")
const AI := preload("res://xeque/ai.gd")

func _initialize(): call_deferred("run")

func snap(g) -> Dictionary:
    return {"state": g.state, "round_no": g.round_no, "target": g.target, "turn": g.turn, "lives": g.lives.duplicate(),
        "hands": g.hands.duplicate(true), "clocks": g.clocks.duplicate(true), "clock_cycles": g.clock_cycles.duplicate(),
        "plays": g.plays.duplicate(true), "last_play": g.last_play.duplicate(true), "winner": g.winner,
        "eliminated_round": g.eliminated_round.duplicate(), "finish_order": g.finish_order.duplicate(),
        "reveals": g.reveals.duplicate(true), "public_log": g.public_log.duplicate(), "next_starter": g.next_starter, "names": g.names.duplicate()}

func run():
    var out := []
    var rng := RandomNumberGenerator.new()
    rng.seed = 77
    var profiles := ["cauteloso", "equilibrado", "blefador", "equilibrado"]
    for game in 60:
        var g = Rules.new()
        g.setup(300 + game, ["A", "B", "C", "D"])
        var guard := 0
        while g.state != Rules.MATCH_END and guard < 400:
            guard += 1
            if g.state == Rules.ROUND_END:
                g.next_round()
                continue
            var s: int = g.turn
            var pub: Dictionary = g.public_state(s)
            var hand: Array = g.private_hand(s)
            var p_true := AI.p_last_play_true(pub, hand)
            var d := AI.decide(pub, hand, profiles[s], rng)
            var before := snap(g)
            var res := {}
            var act := {}
            if d.action == "challenge" and g.can_challenge(s):
                act = {"action": "challenge"}
                res = g.challenge(s)
            else:
                act = {"action": "play", "idx": d.get("idx", [0])}
                res = g.play(s, act.idx)
                if res.is_empty():
                    act = {"action": "play", "idx": [0]}
                    res = g.play(s, [0])
            out.append({"seat": s, "before": before, "pub": pub, "p_true": p_true, "action": act, "result": res, "after": snap(g)})
    var f := FileAccess.open("res://tests/fixtures/xeque_parity.json", FileAccess.WRITE)
    f.store_string(JSON.stringify({"ruleset": Rules.RULESET_VERSION, "steps": out}))
    f.close()
    print("xeque_parity.json: %d passos" % out.size())
    quit()
