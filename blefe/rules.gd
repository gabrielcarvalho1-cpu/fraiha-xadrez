extends RefCounted
## BLEFE REAL · motor de regras (único). Humano, bots e tempo esgotado só PEDEM ações aqui;
## a interface e a IA nunca decidem regra. Nada do xadrez (regras, Ranked, Elo, PL, Stockfish) é usado.
##
## Regras (ruleset 1):
##   • 4 lugares (0 = você embaixo, 1 esquerda, 2 cima, 3 direita), sentido horário 0→1→2→3.
##   • 3 Coroas por jogador. 0 Coroas = eliminado (o lugar fica na mesa, marcado).
##   • Baralho de 20: 6 Rei, 6 Rainha, 6 Cavalo, 2 Peão Coroado (coringa). 5 cartas por jogador vivo;
##     o que sobra fica fora da rodada.
##   • A rodada sorteia a PEÇA DA RODADA (Rei, Rainha ou Cavalo). Verdadeira = a peça da rodada ou o Peão.
##   • Na vez: JOGAR 1 a 3 cartas viradas (a declaração é automática: "N <peça da rodada>"),
##     ou XEQUE na jogada imediatamente anterior (se existir). Não existe passar.
##   • XEQUE revela só a última jogada: todas verdadeiras → quem chamou perde o desafio;
##     pelo menos uma falsa → quem jogou perde. Todo XEQUE encerra a rodada.
##   • Quem perde o desafio aciona o SEU Relógio de Xeque: ciclo de 3 posições (2 seguras + 1
##     XEQUE-MATE) em ordem embaralhada e consumida SEM reposição (1/3 → 1/2 → 1). XEQUE-MATE tira
##     1 Coroa e embaralha um ciclo novo só daquele jogador.
##   • Próxima rodada começa por quem perdeu o desafio (ou o próximo vivo, se ele foi eliminado).
##   • Sem cartas: fica fora dos turnos até o fim da rodada. Se só 1 jogador (ou nenhum) ainda tem
##     cartas, a última jogada é resolvida por XEQUE automático do próximo jogador vivo.
##   • Último jogador com Coroa vence.

const MODE_ID := "blefe_real"
const RULESET_VERSION := "1"
const KING := "rei"
const QUEEN := "rainha"
const KNIGHT := "cavalo"
const JOKER := "peao"               # Peão Coroado
const TARGETS := [KING, QUEEN, KNIGHT]
const DECK_COUNTS := {KING: 6, QUEEN: 6, KNIGHT: 6, JOKER: 2}
const SEATS := 4
const LIVES := 3
const HAND := 5
const MAX_PLAY := 3
const CLOCK_SLOTS := 3
const SAFE := "safe"
const MATE := "mate"
const NAMES := {KING: "Rei", QUEEN: "Rainha", KNIGHT: "Cavalo", JOKER: "Peão Coroado"}
const PLURAL := {KING: "Reis", QUEEN: "Rainhas", KNIGHT: "Cavalos", JOKER: "Peões Coroados"}

# estados da partida (a animação nunca é a autoridade)
const SETUP := "SETUP"
const ROUND_START := "ROUND_START"
const TURN_WAITING := "TURN_WAITING"
const CARDS_PLAYED := "CARDS_PLAYED"
const CHALLENGE := "CHALLENGE"
const REVEAL := "REVEAL"
const CLOCK_RESOLUTION := "CLOCK_RESOLUTION"
const CHECKMATE := "CHECKMATE"
const ROUND_END := "ROUND_END"
const MATCH_END := "MATCH_END"

var rng := RandomNumberGenerator.new()
var state := SETUP
var state_log: Array = []          # transições (para testes e depuração)
var names: Array = ["Você", "Dama de Ferro", "Sir Gambito", "Torre Velha"]
var lives: Array = []
var hands: Array = []              # PRIVADO: hands[seat] = [cartas]
var clocks: Array = []             # PRIVADO: ordem das posições restantes de cada jogador
var clock_cycles: Array = []       # quantos ciclos de relógio cada jogador já começou
var target := ""
var round_no := 0
var turn := -1
var plays: Array = []              # jogadas da rodada: {seat, cards (PRIVADO), count}
var last_play := {}
var next_starter := -1
var winner := -1
var eliminated_round: Array = []   # rodada em que cada um caiu (-1 = vivo)
var finish_order: Array = []       # eliminados, do primeiro ao último
var public_log: Array = []         # histórico público ("Dama de Ferro disse 2 Rainhas", revelações…)
var reveals: Array = []            # revelações públicas: {seat, cards, target, truthful}
var last_result := {}

func _set_state(s: String):
    state = s
    state_log.append(s)

## Prepara a partida. seed 0 = aleatória (produção); seed fixa = testes.
func setup(seed: int = 0, p_names: Array = []):
    if seed == 0: rng.randomize()
    else: rng.seed = seed
    if p_names.size() == SEATS: names = p_names.duplicate()
    lives = []; hands = []; clocks = []; clock_cycles = []; eliminated_round = []
    for s in SEATS:
        lives.append(LIVES)
        hands.append([])
        clocks.append([])
        clock_cycles.append(0)
        eliminated_round.append(-1)
        reset_clock(s)
    finish_order = []; public_log = []; reveals = []; state_log = []
    winner = -1; round_no = 0
    _set_state(SETUP)
    start_round(rng.randi_range(0, SEATS - 1))

# ---------------------------------------------------------------- relógio
## Ciclo novo: 2 seguras + 1 XEQUE-MATE, embaralhadas (sem reposição).
func reset_clock(seat: int):
    var c := []
    for i in CLOCK_SLOTS - 1: c.append(SAFE)
    c.append(MATE)
    for i in range(c.size() - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var t = c[i]; c[i] = c[j]; c[j] = t
    clocks[seat] = c
    clock_cycles[seat] += 1

## Posições que ainda restam no relógio do jogador (público: 3, 2 ou 1).
func clock_left(seat: int) -> int:
    return clocks[seat].size()

## Chance de XEQUE-MATE no próximo acionamento (1/3 → 1/2 → 1).
func clock_chance(seat: int) -> float:
    return 1.0 / float(maxi(1, clocks[seat].size()))

## Aciona o relógio (consome a próxima posição; o resultado já estava definido no embaralhamento).
func _pull_clock(seat: int) -> String:
    var r: String = clocks[seat].pop_front()
    return r

# ---------------------------------------------------------------- consulta
static func is_true_card(card: String, round_target: String) -> bool:
    return card == round_target or card == JOKER

func alive(seat: int) -> bool:
    return lives[seat] > 0

func alive_seats() -> Array:
    var out := []
    for s in SEATS:
        if alive(s): out.append(s)
    return out

func with_cards() -> Array:
    var out := []
    for s in SEATS:
        if alive(s) and not hands[s].is_empty(): out.append(s)
    return out

## Próximo lugar vivo depois de `seat` (sentido horário). need_cards: pula quem está sem cartas.
func next_seat(seat: int, need_cards := false) -> int:
    for k in range(1, SEATS + 1):
        var s := (seat + k) % SEATS
        if not alive(s): continue
        if need_cards and hands[s].is_empty(): continue
        return s
    return -1

func can_challenge(seat: int) -> bool:
    return state == TURN_WAITING and seat == turn and not last_play.is_empty() and int(last_play.seat) != seat

func can_play(seat: int, idx: Array) -> bool:
    if state != TURN_WAITING or seat != turn or not alive(seat): return false
    if idx.size() < 1 or idx.size() > MAX_PLAY: return false
    var seen := {}
    for i in idx:
        if typeof(i) != TYPE_INT and typeof(i) != TYPE_FLOAT: return false
        var n := int(i)
        if n < 0 or n >= hands[seat].size() or seen.has(n): return false
        seen[n] = true
    return true

func declared_text(count: int, round_target := "") -> String:
    var t := round_target if round_target != "" else target
    return "%d %s" % [count, (NAMES[t] if count == 1 else PLURAL[t]).to_upper()]

# ---------------------------------------------------------------- rodada
func start_round(starter: int):
    _set_state(ROUND_START)
    round_no += 1
    var deck := []
    for c in DECK_COUNTS:
        for i in DECK_COUNTS[c]: deck.append(c)
    for i in range(deck.size() - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var t = deck[i]; deck[i] = deck[j]; deck[j] = t
    for s in SEATS:
        hands[s] = []
        if not alive(s): continue
        for k in HAND: hands[s].append(deck.pop_back())
    target = TARGETS[rng.randi_range(0, TARGETS.size() - 1)]
    plays = []
    last_play = {}
    last_result = {}
    turn = starter if alive(starter) else next_seat(starter)
    public_log.append("Rodada %d · a mesa pede %s" % [round_no, NAMES[target].to_upper()])
    _set_state(TURN_WAITING)

## Inicia a rodada seguinte depois de um XEQUE (chamado pela interface quando a animação acaba,
## ou direto pelos testes). Recusado se a partida acabou.
func next_round() -> bool:
    if state != ROUND_END: return false
    start_round(next_starter)
    return true

# ---------------------------------------------------------------- ações
## JOGAR: idx = posições na mão do jogador. Devolve {} se recusado; senão a jogada pública
## e, se a mesa travou (≤ 1 jogador com cartas), o resultado do XEQUE automático em "forced".
func play(seat: int, idx: Array) -> Dictionary:
    if not can_play(seat, idx): return {}
    var order := idx.map(func(i): return int(i))
    order.sort()
    var cards := []
    for i in range(order.size() - 1, -1, -1):
        cards.push_front(hands[seat][order[i]])
        hands[seat].remove_at(order[i])
    last_play = {"seat": seat, "cards": cards, "count": cards.size()}
    plays.append(last_play)
    _set_state(CARDS_PLAYED)
    public_log.append("%s disse %s" % [names[seat], declared_text(cards.size()).capitalize()])
    var pub := {"seat": seat, "count": cards.size(), "declared": declared_text(cards.size())}
    if with_cards().size() <= 1:
        # ninguém mais pode continuar a rodada: o próximo jogador vivo dá XEQUE automático
        var caller := next_seat(seat)
        _set_state(TURN_WAITING)
        turn = caller
        pub["forced"] = _resolve_challenge(caller, true)
        return pub
    turn = next_seat(seat, true)
    _set_state(TURN_WAITING)
    return pub

## Tempo esgotado: joga exatamente 1 carta da própria mão (escolha cega, sem olhar se é verdadeira).
## Nunca chama XEQUE.
func timeout_action(seat: int) -> Dictionary:
    if state != TURN_WAITING or seat != turn or hands[seat].is_empty(): return {}
    var i := rng.randi_range(0, hands[seat].size() - 1)
    return play(seat, [i])

## XEQUE na jogada imediatamente anterior. Resolve TUDO (revelar, relógio, coroas, eliminação,
## vitória) e devolve o resultado para a interface animar. {} se recusado.
func challenge(seat: int) -> Dictionary:
    if not can_challenge(seat): return {}
    return _resolve_challenge(seat, false)

func _resolve_challenge(caller: int, forced: bool) -> Dictionary:
    _set_state(CHALLENGE)
    var accused := int(last_play.seat)
    var cards: Array = last_play.cards.duplicate()
    _set_state(REVEAL)
    var truthful := true
    var false_cards := []
    for c in cards:
        if not is_true_card(c, target):
            truthful = false
            false_cards.append(c)
    var loser := caller if truthful else accused
    reveals.append({"seat": accused, "cards": cards, "target": target, "truthful": truthful, "round": round_no})
    public_log.append("XEQUE de %s: %s" % [names[caller], "VERDADE" if truthful else "BLEFE"])
    _set_state(CLOCK_RESOLUTION)
    var left_before := clock_left(loser)
    var pulled := _pull_clock(loser)
    var mate := pulled == MATE
    var lost_crown := false
    var eliminated := false
    if mate:
        _set_state(CHECKMATE)
        lives[loser] -= 1
        lost_crown = true
        reset_clock(loser)
        public_log.append("XEQUE-MATE em %s" % names[loser])
        if lives[loser] <= 0:
            eliminated = true
            eliminated_round[loser] = round_no
            finish_order.append(loser)
            hands[loser] = []
    else:
        public_log.append("%s sobreviveu ao relógio" % names[loser])
    var alive_now := alive_seats()
    if alive_now.size() == 1:
        winner = alive_now[0]
        next_starter = -1
        _set_state(MATCH_END)
    else:
        next_starter = loser if alive(loser) else next_seat(loser)
        _set_state(ROUND_END)
    last_result = {
        "caller": caller, "accused": accused, "cards": cards, "target": target,
        "truthful": truthful, "false_cards": false_cards, "loser": loser, "forced": forced,
        "clock_left_before": left_before, "clock": pulled, "mate": mate, "lost_crown": lost_crown,
        "lives_after": lives[loser], "eliminated": eliminated, "winner": winner,
        "next_starter": next_starter, "round": round_no,
    }
    return last_result

# ---------------------------------------------------------------- informação pública / privada
## Estado PÚBLICO: o que qualquer jogador pode ver. Nunca contém cartas ocultas nem a ordem
## do relógio. É o ÚNICO estado que a IA recebe (junto com a própria mão).
func public_state(viewer: int = -1) -> Dictionary:
    var counts := []
    var clock_public := []
    for s in SEATS:
        counts.append(hands[s].size())
        clock_public.append(clock_left(s))
    var lp := {}
    if not last_play.is_empty(): lp = {"seat": int(last_play.seat), "count": int(last_play.count)}
    var reveal_pub := []
    for r in reveals: reveal_pub.append(r.duplicate(true))
    return {
        "viewer": viewer, "state": state, "round": round_no, "target": target, "turn": turn,
        "lives": lives.duplicate(), "hand_counts": counts, "clock_left": clock_public,
        "last_play": lp, "plays_this_round": plays.map(func(p): return {"seat": p.seat, "count": p.count}),
        "reveals": reveal_pub, "names": names.duplicate(), "winner": winner,
        "eliminated_round": eliminated_round.duplicate(), "deck_counts": DECK_COUNTS.duplicate(),
        "can_challenge": viewer >= 0 and can_challenge(viewer),
    }

func private_hand(seat: int) -> Array:
    return hands[seat].duplicate()

## Colocação final (1 = vencedor). Só faz sentido em MATCH_END.
func placement(seat: int) -> int:
    if seat == winner: return 1
    var i := finish_order.find(seat)
    if i < 0: return 0
    return SEATS - i
