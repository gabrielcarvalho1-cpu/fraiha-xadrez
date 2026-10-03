extends RefCounted
## XEQUE · bots. A decisão recebe SÓ o estado público (Rules.public_state) e a própria mão.
## Nunca vê a mão de ninguém, o conteúdo das cartas viradas nem a ordem do Relógio de Xeque.
## Devolve um PEDIDO de ação; quem valida e executa é o motor de regras (o mesmo do humano).

const Rules := preload("res://xeque/rules.gd")

## Perfis: honestidade ao jogar, gosto pelo blefe, coragem no XEQUE.
const PROFILES := {
    "cauteloso":   {"truth": 0.92, "mix": 0.04, "max_false": 1, "threshold": 0.68, "noise": 0.08, "many_true": 0.35},
    "equilibrado": {"truth": 0.70, "mix": 0.20, "max_false": 2, "threshold": 0.55, "noise": 0.12, "many_true": 0.55},
    "blefador":    {"truth": 0.42, "mix": 0.30, "max_false": 3, "threshold": 0.42, "noise": 0.16, "many_true": 0.70},
}

## Probabilidade (do ponto de vista de quem decide) de a última jogada ser toda verdadeira.
static func p_last_play_true(pub: Dictionary, hand: Array) -> float:
    var lp: Dictionary = pub.get("last_play", {})
    if lp.is_empty(): return 1.0
    var target: String = pub.target
    var deck: Dictionary = pub.deck_counts
    var total_true: int = int(deck[target]) + int(deck[Rules.JOKER])        # 8
    var total_cards := 0
    for c in deck: total_cards += int(deck[c])                              # 20
    var mine_true := 0
    for c in hand:
        if Rules.is_true_card(c, target): mine_true += 1
    # cartas fora da minha mão que podem estar em jogo nesta rodada
    var dealt := 0
    for n in pub.hand_counts: dealt += int(n)
    for p in pub.plays_this_round: dealt += int(p.count)
    var unknown := maxi(1, dealt - hand.size())
    var true_unknown := maxi(0, total_true - mine_true)
    # o que está fora da rodada (cartas não distribuídas) também esconde verdadeiras
    var pool := maxi(unknown, total_cards - hand.size())
    var k := int(lp.count)
    if true_unknown < k: return 0.0
    var p := 1.0
    for i in k:
        p *= float(true_unknown - i) / float(pool - i)
    # as pessoas jogam verdade quando podem: o sorteio puro subestima a honestidade
    var prior_honest := 0.55
    var seat := int(lp.seat)
    var seen := 0
    var bluffs := 0
    for r in pub.reveals:
        if int(r.seat) == seat:
            seen += 1
            if not bool(r.truthful): bluffs += 1
    if seen > 0: prior_honest = clampf(0.55 + 0.25 * (float(seen - bluffs) / seen - 0.5), 0.3, 0.8)
    # quem joga com mais cartas na mão tem mais chance de ter verdadeiras para escolher
    var before := int(pub.hand_counts[seat]) + k
    var reach := clampf(float(before) / 5.0, 0.4, 1.0)
    return clampf(p + (1.0 - p) * prior_honest * reach * (0.85 if k >= 3 else 1.0) * (0.75 if k == 2 else 1.0), 0.0, 1.0)

## Decide. pub = public_state(seat); hand = a própria mão. rng opcional (testes).
static func decide(pub: Dictionary, hand: Array, profile: String, rng: RandomNumberGenerator = null) -> Dictionary:
    if rng == null:
        rng = RandomNumberGenerator.new()
        rng.randomize()
    var pr: Dictionary = PROFILES.get(profile, PROFILES.equilibrado)
    var me := int(pub.viewer)
    var lp: Dictionary = pub.get("last_play", {})
    var may_challenge := bool(pub.get("can_challenge", false))
    if may_challenge and not lp.is_empty():
        var suspicion := 1.0 - p_last_play_true(pub, hand)
        # relógio do jogador perto do fim (1/2 ou pior): errar o XEQUE pode eliminar → mais cautela
        var my_left := int(pub.clock_left[me])
        var their_left := int(pub.clock_left[int(lp.seat)])
        var need := float(pr.threshold)
        if my_left <= 2: need += 0.12 if my_left == 1 else 0.06
        if their_left <= 2: need -= 0.05
        if hand.is_empty(): need -= 1.0
        # quem acabou de esvaziar a mão já não pode ser pego depois: duvidar agora vale mais
        if int(pub.hand_counts[int(lp.seat)]) == 0: need -= 0.08
        if suspicion + rng.randf_range(-float(pr.noise), float(pr.noise)) >= need:
            return {"action": "challenge"}
    if hand.is_empty(): return {"action": "challenge"}
    return {"action": "play", "idx": choose_cards(pub, hand, pr, rng)}

static func choose_cards(pub: Dictionary, hand: Array, pr: Dictionary, rng: RandomNumberGenerator) -> Array:
    var target: String = pub.target
    var trues := []
    var falses := []
    for i in hand.size():
        if hand[i] == target: trues.push_front(i)       # peças da rodada primeiro
        elif hand[i] == Rules.JOKER: trues.append(i)     # coringa por último (vale sempre)
        else: falses.append(i)
    var roll := rng.randf()
    var out := []
    if not trues.is_empty() and roll < float(pr.truth):
        # verdade: 1 a 3 verdadeiras
        var n := 1
        if trues.size() >= 2 and rng.randf() < float(pr.many_true): n = 2
        if trues.size() >= 3 and rng.randf() < float(pr.many_true) * 0.5: n = 3
        out = trues.slice(0, n)
    elif not trues.is_empty() and not falses.is_empty() and roll < float(pr.truth) + float(pr.mix):
        # meia-verdade: 1 verdadeira + 1 falsa (conta como blefe se alguém der XEQUE)
        out = [trues[0], falses[rng.randi_range(0, falses.size() - 1)]]
    elif not falses.is_empty():
        # blefe: só falsas, guardando as verdadeiras
        var n := 1
        var maxf := mini(int(pr.max_false), falses.size())
        if maxf >= 2 and rng.randf() < 0.45: n = 2
        if maxf >= 3 and rng.randf() < 0.35: n = 3
        for i in range(falses.size() - 1, 0, -1):
            var j := rng.randi_range(0, i)
            var t = falses[i]; falses[i] = falses[j]; falses[j] = t
        out = falses.slice(0, n)
    else:
        out = trues.slice(0, 1)
    out = out.slice(0, mini(Rules.MAX_PLAY, hand.size()))
    if out.is_empty(): out = [0]
    return out
