extends SceneTree
## XEQUE · motor de regras, relógio e bots (sem interface). Sementes fixas para o sorteio.
const Rules := preload("res://xeque/rules.gd")
const AI := preload("res://xeque/ai.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize(): call_deferred("run")

func count(arr: Array, c: String) -> int:
    return arr.filter(func(x): return x == c).size()

func new_game(seed := 11) -> Rules:
    var g := Rules.new()
    g.setup(seed)
    return g

## Mão conhecida para testes determinísticos.
func force(g: Rules, turn: int, target: String, hands: Array):
    g.target = target
    g.turn = turn
    for s in 4: g.hands[s] = hands[s].duplicate()
    g.plays = []
    g.last_play = {}

func run():
    # ---------- baralho e distribuição ----------
    var g := new_game()
    var all := []
    for s in 4: all.append_array(g.hands[s])
    check(all.size() == 20, "com 4 vivos as 20 cartas vão para as mãos")
    check(count(all, "rei") == 6 and count(all, "rainha") == 6 and count(all, "cavalo") == 6 and count(all, "peao") == 2, "baralho: 6 Rei, 6 Rainha, 6 Cavalo, 2 Peão Coroado")
    check(g.hands.all(func(h): return h.size() == 5), "5 cartas por jogador")
    var targets := {}
    for sd in range(1, 60):
        var gg := new_game(sd)
        targets[gg.target] = true
    check(targets.keys().all(func(t): return t in ["rei", "rainha", "cavalo"]) and targets.size() == 3, "peça da rodada só Rei/Rainha/Cavalo (as 3 aparecem)")
    check(Rules.is_true_card("peao", "rei") and Rules.is_true_card("peao", "rainha") and Rules.is_true_card("peao", "cavalo"), "Peão Coroado sempre verdadeiro")
    check(g.state == Rules.TURN_WAITING and g.round_no == 1, "partida começa em TURN_WAITING, rodada 1")
    var starters := {}
    for sd in range(1, 40): starters[new_game(sd).turn] = true
    check(starters.size() == 4, "primeiro jogador sorteado (os 4 lugares aparecem)")
    # ---------- validação de jogada ----------
    g = new_game(3)
    force(g, 0, "rainha", [["rainha", "cavalo", "rei", "rainha", "peao"], ["rei", "rei", "rei", "cavalo", "cavalo"], ["rainha", "rainha", "cavalo", "cavalo", "rei"], ["rainha", "cavalo", "rei", "rei", "peao"]])
    check(g.play(0, []).is_empty(), "jogar 0 cartas: recusado")
    check(g.play(0, [0, 1, 2, 3]).is_empty(), "jogar 4 cartas: recusado")
    check(g.play(0, [7]).is_empty(), "carta que não está na mão: recusada")
    check(g.play(0, [1, 1]).is_empty(), "a mesma carta duas vezes: recusada")
    check(g.play(2, [0]).is_empty(), "fora da vez: recusado")
    check(not g.can_challenge(0) and g.challenge(0).is_empty(), "XEQUE sem jogada anterior: recusado")
    var pub_play := g.play(0, [0, 1])
    check(not pub_play.is_empty() and g.hands[0] == ["rei", "rainha", "peao"], "cartas jogadas saem da mão")
    check(String(pub_play.declared) == "2 RAINHAS" and not pub_play.has("cards"), "declaração automática \"2 RAINHAS\" (sem revelar as cartas)")
    check(g.turn == 1 and g.can_challenge(1) and not g.can_challenge(2), "só o próximo jogador pode dar XEQUE")
    check(g.challenge(0).is_empty(), "quem jogou não desafia a si mesmo")
    # ---------- XEQUE: mistura verdade + falso = blefe ----------
    g.clocks[0] = [Rules.SAFE, Rules.SAFE, Rules.SAFE, Rules.SAFE, Rules.SAFE, Rules.MATE]
    var r := g.challenge(1)
    check(not r.truthful and r.loser == 0 and r.false_cards == ["cavalo"], "Rainha + Cavalo = BLEFE: quem jogou perde (XEQUE correto)")
    check(r.clock == Rules.SAFE and not r.mate and g.alive(0) and g.clock_left(0) == 5, "relógio SEGURO: continua vivo, posição consumida")
    check(g.state == Rules.ROUND_END and g.next_starter == 0, "todo XEQUE encerra a rodada; quem perdeu começa a próxima")
    check(g.state_log.slice(-4) == [Rules.CHALLENGE, Rules.REVEAL, Rules.CLOCK_RESOLUTION, Rules.ROUND_END], "estados: CHALLENGE → REVEAL → CLOCK_RESOLUTION → ROUND_END")
    check(g.play(1, [0]).is_empty() and g.challenge(1).is_empty(), "rodada encerrada: nenhuma ação até a próxima rodada")
    check(g.next_round() and g.round_no == 2 and g.turn == 0 and g.state == Rules.TURN_WAITING, "nova rodada começa por quem perdeu o desafio")
    var all2 := []
    for s in 4: all2.append_array(g.hands[s])
    check(all2.size() == 20 and count(all2, "peao") == 2 and g.hands.all(func(h): return h.size() == 5), "nova rodada: recolhe, embaralha e distribui 5 de novo")
    # ---------- XEQUE incorreto: coringa + alvo = verdade ----------
    g = new_game(5)
    force(g, 2, "rei", [["cavalo", "cavalo"], ["rei", "rainha"], ["rei", "peao", "cavalo"], ["rainha", "rainha"]])
    g.play(2, [0, 1])
    g.clocks[3] = [Rules.SAFE, Rules.MATE, Rules.SAFE, Rules.SAFE]
    r = g.challenge(3)
    check(r.truthful and r.loser == 3 and not r.mate and g.alive(3), "Rei + Peão Coroado = VERDADE: quem deu XEQUE perde (XEQUE incorreto)")
    check(g.clock_left(3) == 3 and g.clock_left(2) == 6, "o relógio guarda o estado entre rodadas (só o de quem acionou anda)")
    g.next_round()
    force(g, 2, "rei", [["cavalo"], ["rei"], ["cavalo", "rainha"], ["rainha", "rainha"]])
    g.play(2, [0])
    g.clocks[2] = [Rules.SAFE, Rules.MATE, Rules.SAFE, Rules.SAFE, Rules.SAFE, Rules.SAFE]
    r = g.challenge(3)
    check(not r.truthful and r.loser == 2 and not r.mate and g.clock_left(2) == 5 and g.clock_left(3) == 3, "XEQUE correto: quem blefou aciona o relógio DELE")
    g = new_game(6)
    force(g, 2, "rei", [["cavalo"], ["rei"], ["rei", "peao"], ["rainha"]])
    g.play(2, [0, 1])
    g.clocks[3] = [Rules.MATE, Rules.SAFE, Rules.SAFE, Rules.SAFE, Rules.SAFE]
    r = g.challenge(3)
    check(r.truthful and r.mate and r.eliminated and not g.alive(3) and g.lives[3] == 0, "XEQUE-MATE (regra da WePlay): eliminado na hora")
    check(g.hands[3].is_empty() and g.eliminated_round[3] == g.round_no and g.finish_order == [3], "eliminado sai da mesa e entra na ordem de eliminação")
    # ---------- relógio (ruleset 2): chance crescente por nível ----------
    g = new_game(9)
    check(Rules.LIVES == 1 and Rules.CLOCK_SLOTS == 6 and Rules.RULESET_VERSION == "2", "1 vida, relógio de 6 níveis, ruleset 2")
    check(g.clocks.all(func(c): return c.size() == 6 and c.all(func(x): return x == Rules.PENDING)), "relógio começa no 1º nível (nada sorteado antes da hora)")
    check(is_equal_approx(g.clock_chance(1), 0.12), "1º acionamento: 12% (raro, mas pode estourar)")
    var chances := []
    for i in 5:
        chances.append(snappedf(g.clock_chance(1), 0.001))
        g.forced_roll = 0.99
        g._pull_clock(1)
    check(chances == [0.12, 0.2, 0.3, 0.45, 0.65], "chance sobe a cada nível: 12% → 20% → 30% → 45% → 65% (%s)" % str(chances))
    g.forced_roll = 0.99
    check(is_equal_approx(g.clock_chance(1), 1.0) and g._pull_clock(1) == Rules.MATE, "6º nível: XEQUE-MATE certo")
    # frequência real (sorteio do motor): cada nível estoura perto da chance anunciada
    var hits := [0, 0, 0, 0, 0, 0]
    var tries := [0, 0, 0, 0, 0, 0]
    var gs := Rules.new()
    gs.setup(4242)
    for k in 6000:
        var lv: int = gs.clock_level(0)
        tries[lv] += 1
        if gs._pull_clock(0) == Rules.MATE:
            hits[lv] += 1
            gs.reset_clock(0)
    var ok_rates := true
    var rates := []
    for lv in 5:
        var rate := float(hits[lv]) / maxf(1.0, tries[lv])
        rates.append(snappedf(rate, 0.01))
        if absf(rate - float(Rules.CLOCK_CHANCES[lv])) > 0.035: ok_rates = false
    check(ok_rates and float(hits[0]) / tries[0] <= 0.15, "sorteio confere com a tabela (níveis 1–5: %s); 1º nível ≤ 15%%" % str(rates))
    # mesma semente → mesma sequência de sorteios (RNG único do motor, testável)
    var seq := func(sd: int) -> String:
        var q := Rules.new()
        q.setup(sd)
        var out := ""
        for k in 40:
            q.reset_clock(0)
            out += "M" if q._pull_clock(0) == Rules.MATE else "s"
        return out
    check(seq.call(99) == seq.call(99) and seq.call(99) != seq.call(100), "sorteio do relógio reproduzível com a semente")
    check(Rules.deck_size() == 20 and Rules.DECK_COUNTS == {"rei": 6, "rainha": 6, "cavalo": 6, "peao": 2}, "baralho 6/6/6/2 = 20 (fonte única para a UI)")
    # resultado do XEQUE informa chance e sorteio; depois de estourar o relógio volta ao 1º nível
    g = new_game(10)
    force(g, 2, "rei", [["cavalo"], ["rei"], ["rei", "peao"], ["rainha"]])
    g.play(2, [0, 1])
    g.forced_roll = 0.05
    r = g.challenge(3)
    check(r.mate and is_equal_approx(float(r.chance), 0.12) and is_equal_approx(float(r.roll), 0.05), "XEQUE-MATE no 1º nível (azar!): resultado traz chance 12% e o sorteio")
    # ---------- eliminação, pular eliminado/sem cartas, vitória ----------
    g = new_game(21)
    g.lives = [1, 1, 1, 1]
    force(g, 0, "cavalo", [["rei"], ["rei", "rei"], ["cavalo"], ["rainha", "rainha"]])
    g.play(0, [0])          # blefe; jogador 0 fica sem cartas
    check(g.turn == 1, "próximo é o jogador 1")
    g.clocks[0] = [Rules.MATE, Rules.SAFE, Rules.SAFE]
    r = g.challenge(1)
    check(r.eliminated and g.lives[0] == 0 and not g.alive(0) and g.eliminated_round[0] == g.round_no, "XEQUE-MATE: eliminado")
    check(g.next_starter == 1, "eliminado não começa: o próximo vivo inicia a rodada")
    g.next_round()
    check(g.hands[0].is_empty() and g.hands[1].size() == 5, "eliminado não recebe cartas; vivos recebem 5")
    var hit_dead := false
    for i in 12:
        if g.state != Rules.TURN_WAITING: break
        if g.turn == 0: hit_dead = true
        g.play(g.turn, [0])
    check(not hit_dead and g.play(0, [0]).is_empty(), "turno nunca cai no eliminado (e ele não consegue jogar)")
    g = new_game(22)
    force(g, 1, "rei", [["cavalo"], [], ["rei", "rei"], ["rainha", "cavalo"]])
    g.turn = 2
    g.play(2, [0])
    check(g.turn == 3, "jogador sem cartas é pulado")
    g.play(3, [0])
    check(g.turn == 0 or g.turn == 2, "segue para quem tem cartas")
    # todos sem carta menos um → XEQUE automático
    g = new_game(23)
    force(g, 0, "rainha", [["rei"], [], ["rainha", "rainha"], []])
    var pp := g.play(0, [0])
    check(pp.has("forced") and int(pp.forced.caller) == 1 and int(pp.forced.accused) == 0, "só 1 jogador com cartas: XEQUE automático na última jogada (sem travar)")
    check(g.state == Rules.ROUND_END or g.state == Rules.MATCH_END, "rodada resolvida pelo XEQUE automático")
    # vitória
    g = new_game(24)
    g.lives = [0, 1, 0, 1]
    g.finish_order = [0, 2]
    force(g, 1, "rei", [[], ["cavalo", "rei"], [], ["rei", "rei"]])
    g.play(1, [0])
    g.clocks[1] = [Rules.MATE, Rules.SAFE, Rules.SAFE]
    r = g.challenge(3)
    check(g.state == Rules.MATCH_END and g.winner == 3 and r.winner == 3, "último com Coroa vence")
    check(g.placement(3) == 1 and g.placement(1) == 2 and g.placement(2) == 3 and g.placement(0) == 4, "colocação final 1º–4º")
    check(not g.next_round(), "partida encerrada: não começa outra rodada")
    # ---------- timeout ----------
    g = new_game(30)
    var before: int = g.hands[g.turn].size()
    var who := g.turn
    var tp := g.timeout_action(who)
    check(not tp.is_empty() and int(tp.count) == 1 and g.hands[who].size() == before - 1, "tempo esgotado: joga exatamente 1 carta")
    check(g.reveals.is_empty() and g.state == Rules.TURN_WAITING and not g.last_play.is_empty() and int(g.last_play.seat) == who, "tempo esgotado: nunca chama XEQUE")
    # ---------- informação privada ----------
    g = new_game(31)
    var pub := g.public_state(2)
    var keys := pub.keys()
    check(not keys.has("hands") and not keys.has("clocks") and not str(pub.last_play).contains("cards"), "estado público sem mãos, sem ordem do relógio e sem cartas viradas")
    g.play(g.turn, [0, 1])
    pub = g.public_state(g.turn)
    check(not pub.last_play.has("cards") and pub.plays_this_round.all(func(p): return not p.has("cards")), "jogada na mesa: só quantidade, nunca o conteúdo")
    # a decisão do bot depende só do que ela recebe: duas mesas com mãos alheias diferentes, mesmo
    # estado público e mesma mão → mesma decisão
    var ga := new_game(40)
    var gb := new_game(40)
    var seat := ga.turn
    var other := (seat + 1) % 4
    gb.hands[other] = ["peao", "peao", "rei", "rei", "rei"] if ga.hands[other] != ["peao", "peao", "rei", "rei", "rei"] else ["cavalo", "cavalo", "cavalo", "cavalo", "cavalo"]
    var ra := RandomNumberGenerator.new(); ra.seed = 7
    var rb := RandomNumberGenerator.new(); rb.seed = 7
    var da := AI.decide(ga.public_state(seat), ga.private_hand(seat), "equilibrado", ra)
    var db := AI.decide(gb.public_state(seat), gb.private_hand(seat), "equilibrado", rb)
    check(str(da) == str(db), "bot decide igual quando só as mãos ALHEIAS mudam (não enxerga cartas ocultas)")
    # ---------- bots jogam só ações legais e partidas terminam ----------
    var profiles := ["cauteloso", "equilibrado", "blefador"]
    var illegal := 0
    var finished := 0
    var rounds_total := 0
    var stuck := 0
    var challenges := 0
    var bluffs := {"cauteloso": [0, 0], "equilibrado": [0, 0], "blefador": [0, 0]}
    for sd in range(1, 121):
        var gm := Rules.new()
        gm.setup(sd)
        var brng := RandomNumberGenerator.new(); brng.seed = sd * 13
        var steps := 0
        while gm.state != Rules.MATCH_END and steps < 4000:
            steps += 1
            if gm.state == Rules.ROUND_END:
                gm.next_round()
                continue
            var s := gm.turn
            var prof: String = profiles[s % 3]
            var d := AI.decide(gm.public_state(s), gm.private_hand(s), prof, brng)
            if d.action == "challenge":
                if gm.challenge(s).is_empty(): illegal += 1
                else: challenges += 1
            else:
                var hand := gm.private_hand(s)
                var t := gm.target
                var res := gm.play(s, d.idx)
                if res.is_empty():
                    illegal += 1
                    gm.timeout_action(s)
                else:
                    var lied := false
                    for i in d.idx:
                        if not Rules.is_true_card(hand[i], t): lied = true
                    bluffs[prof][0] += 1
                    if lied: bluffs[prof][1] += 1
        if gm.state == Rules.MATCH_END: finished += 1
        else: stuck += 1
        rounds_total += gm.round_no
    check(illegal == 0, "bots nunca pedem ação ilegal (%d recusadas)" % illegal)
    check(finished == 120 and stuck == 0, "120 partidas bot × bot terminam sem travar (média %.1f rodadas, %d XEQUES)" % [rounds_total / 120.0, challenges])
    var rate := func(p): return float(bluffs[p][1]) / maxf(1.0, bluffs[p][0])
    check(rate.call("cauteloso") < rate.call("equilibrado") and rate.call("equilibrado") < rate.call("blefador"), "perfis diferentes: blefe cauteloso %.0f%% < equilibrado %.0f%% < blefador %.0f%%" % [rate.call("cauteloso") * 100, rate.call("equilibrado") * 100, rate.call("blefador") * 100])
    # suspeita cresce com declaração impossível
    g = new_game(50)
    force(g, 1, "rei", [["rei", "rei", "rei", "peao", "cavalo"], ["rainha", "cavalo", "rainha"], [], []])
    g.lives = [1, 1, 1, 1]
    g.play(1, [0, 1, 2])
    var p3 := AI.p_last_play_true(g.public_state(2), ["rei", "rei", "rei", "peao", "peao"])
    var p_low := AI.p_last_play_true(g.public_state(2), ["cavalo", "cavalo", "rainha", "rainha", "cavalo"])
    check(p3 < p_low, "bot com 3 Reis + Peões suspeita mais de \"3 REIS\" (%.2f < %.2f)" % [p3, p_low])
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
