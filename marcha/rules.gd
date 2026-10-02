extends RefCounted
## MARCHA REAL — regras (mecânica no estilo Jackaroo, pele FRAIHA). Só lógica: sem desenho, sem rede.
##
## Mesa: 4 reinos em cruz; dupla Marfim(0)+Ônix(2) contra Rubi(1)+Esmeralda(3). Vez no sentido horário 0→1→2→3.
## Cada reino tem 4 peões: Pátio (casa inicial) → Portão (saída) → Muralha (76 casas, sentido horário)
## → Entrada do Salão → Salão do Trono (4 casas). Peão no Salão = coroado.
##
## Cartas (vale o valor; o naipe é só a ilustração):
##   A  sai do pátio OU anda 11          K  sai do pátio OU anda 13          Q  anda 12
##   J  troca de lugar com outra peça    10/9/8/6/3/2  anda N               7  divide 7 casas entre até 2 peças
##   5  anda 5 com QUALQUER peça da mesa (segue o caminho do dono)          4  só volta 4 casas
## Regras da mesa:
##   • Cair numa casa ocupada por outro peão manda esse peão de volta ao Pátio (inclusive o do aliado).
##   • Peão parado no PRÓPRIO Portão protege a casa: ninguém passa por cima nem cai nela, e não pode ser trocado.
##   • Sair do Pátio é para o próprio Portão; se houver peão de outro reino lá, ele volta ao Pátio.
##   • Na Entrada do Salão o peão do dono entra no Salão; o número de casas tem de caber (sem passar do fundo
##     e sem pular peões do próprio reino lá dentro). Se não couber, essa jogada não vale.
##   • Voltar 4 a partir do Portão (ou logo depois dele) leva o peão para trás do Portão — atalho clássico.
##   • Sem jogada possível: a carta é descartada.
##   • Quem coroou os 4 peões passa a jogar com os peões do aliado.
##   • Vence a dupla que coroar os 8 peões.
const Layout := preload("res://marcha/board_layout.gd")
## Versão das regras gravada no histórico (mudou regra → muda a versão).
const RULESET_VERSION := "marcha-real-1"

const TRACK := 76
const KINGDOMS := ["Marfim", "Rubi", "Ônix", "Esmeralda"]
## Baralho: o valor manda; o naipe é o da ilustração enviada (uma arte por valor).
const RANKS := ["A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3", "2"]
const SUIT_OF := {"A": "copas", "K": "espadas", "Q": "copas", "J": "ouros", "10": "paus", "9": "ouros", "8": "espadas",
    "7": "paus", "6": "copas", "5": "ouros", "4": "paus", "3": "copas", "2": "espadas"}
const SUIT_NAME := {"copas": "Copas", "espadas": "Espadas", "ouros": "Ouros", "paus": "Paus"}
const STEPS := {"A": 11, "K": 13, "Q": 12, "10": 10, "9": 9, "8": 8, "7": 7, "6": 6, "5": 5, "4": -4, "3": 3, "2": 2}
const HAND := 4

## pawns[seat][i] = {"zone": "home"|"track"|"lane", "pos": int}  (track: índice absoluto 0..75; lane: 0..3)
var pawns: Array = []
var hands: Array = [[], [], [], []]
var deck: Array = []
var discard: Array = []
var turn := 0
var round_no := 1
var winner := -1          # dupla vencedora (0 = Marfim/Ônix, 1 = Rubi/Esmeralda); -1 em jogo
var log: Array = []       # últimas jogadas (texto)
var names: Array = ["Marfim", "Rubi", "Ônix", "Esmeralda"]   # nomes exibidos no registro
var rng := RandomNumberGenerator.new()

func setup(seed := 0):
    if seed != 0: rng.seed = seed
    else: rng.randomize()
    pawns.clear()
    for s in 4:
        var row := []
        for i in 4: row.append({"zone": "home", "pos": i})
        pawns.append(row)
    deck.clear()
    discard.clear()
    for r in RANKS:
        for c in 4: deck.append(r)
    _shuffle(deck)
    hands = [[], [], [], []]
    turn = 0
    round_no = 1
    winner = -1
    log.clear()
    deal()

func _shuffle(a: Array):
    for i in range(a.size() - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var t = a[i]
        a[i] = a[j]
        a[j] = t

## Reparte 4 cartas para cada reino (quando todas as mãos acabam). Baralho vazio → embaralha o descarte.
func deal():
    for s in 4:
        while hands[s].size() < HAND:
            if deck.is_empty():
                deck = discard.duplicate()
                discard.clear()
                _shuffle(deck)
                if deck.is_empty(): return
            hands[s].append(deck.pop_back())

static func team_of(seat: int) -> int:
    return seat % 2

static func partner_of(seat: int) -> int:
    return (seat + 2) % 4

static func card_label(rank: String) -> String:
    return ("-4" if rank == "4" else rank) + " de " + SUIT_NAME[SUIT_OF[rank]]

# ---------------------------------------------------------------- consultas do tabuleiro
func crowned(seat: int) -> int:
    var n := 0
    for p in pawns[seat]:
        if p.zone == "lane": n += 1
    return n

func team_crowned(team: int) -> int:
    return crowned(team) + crowned(team + 2)

func in_home(seat: int) -> int:
    var n := 0
    for p in pawns[seat]:
        if p.zone == "home": n += 1
    return n

## De quem são os peões que este reino movimenta (o aliado depois de coroar os 4).
func controlled(seat: int) -> int:
    return partner_of(seat) if crowned(seat) == 4 else seat

## Quem está numa casa da Muralha: [seat, i] ou [] se vazia.
func occupant(abs_index: int) -> Array:
    for s in 4:
        for i in 4:
            var p: Dictionary = pawns[s][i]
            if p.zone == "track" and p.pos == abs_index: return [s, i]
    return []

func protected_at(abs_index: int) -> bool:
    var o := occupant(abs_index)
    return not o.is_empty() and Layout.gate_index(o[0]) == abs_index

## Caminho de N casas para frente do peão (seguindo o caminho do DONO). Devolve
## {"ok", "path": [{"zone","pos"}...], "end": {"zone","pos"}} ou ok=false.
func forward_path(seat: int, i: int, steps: int) -> Dictionary:
    var p: Dictionary = pawns[seat][i]
    var zone: String = p.zone
    var pos: int = p.pos
    var path := []
    if zone == "home": return {"ok": false}
    for k in range(steps):
        if zone == "track":
            if pos == Layout.entrance_index(seat):
                zone = "lane"
                pos = 0
            else:
                pos = posmod(pos + 1, TRACK)
                if protected_at(pos) and not (occupant(pos) == [seat, i]): return {"ok": false}
        else:
            pos += 1
            if pos > 3: return {"ok": false}
        if zone == "lane" and _lane_taken(seat, pos, i): return {"ok": false}
        path.append({"zone": zone, "pos": pos})
    return _landing(seat, i, path)

func backward_path(seat: int, i: int, steps: int) -> Dictionary:
    var p: Dictionary = pawns[seat][i]
    if p.zone != "track": return {"ok": false}
    var pos: int = p.pos
    var path := []
    for k in range(steps):
        pos = posmod(pos - 1, TRACK)
        if protected_at(pos): return {"ok": false}
        path.append({"zone": "track", "pos": pos})
    return _landing(seat, i, path)

func _lane_taken(seat: int, k: int, except_i: int) -> bool:
    for j in 4:
        if j != except_i and pawns[seat][j].zone == "lane" and pawns[seat][j].pos == k: return true
    return false

func _landing(seat: int, i: int, path: Array) -> Dictionary:
    if path.is_empty(): return {"ok": false}
    var end: Dictionary = path[path.size() - 1]
    if end.zone == "track":
        var o := occupant(end.pos)
        if not o.is_empty():
            if o[0] == seat: return {"ok": false}
            if Layout.gate_index(o[0]) == end.pos: return {"ok": false}
    return {"ok": true, "path": path, "end": end}

# ---------------------------------------------------------------- jogadas legais
## Jogada: {"card": idx, "rank", "kind": "exit"|"move"|"back"|"swap"|"split"|"discard",
##          "pawn": [seat,i], "steps", "target": [seat,i], "parts": [{"pawn","steps"}...]}
func legal_moves(seat: int, card_idx: int) -> Array:
    var out := []
    if card_idx < 0 or card_idx >= hands[seat].size(): return out
    var rank: String = hands[seat][card_idx]
    var who := controlled(seat)
    match rank:
        "A", "K":
            for ex in _exit_moves(who):
                ex.card = card_idx
                ex.rank = rank
                out.append(ex)
            out.append_array(_forward_moves(who, card_idx, rank, STEPS[rank]))
        "4":
            for i in 4:
                if pawns[who][i].zone == "track" and backward_path(who, i, 4).ok:
                    out.append({"card": card_idx, "rank": rank, "kind": "back", "pawn": [who, i], "steps": 4})
        "5":
            for s in 4:
                for i in 4:
                    if pawns[s][i].zone == "track" and forward_path(s, i, 5).ok:
                        out.append({"card": card_idx, "rank": rank, "kind": "move", "pawn": [s, i], "steps": 5})
        "J":
            for i in 4:
                var a: Dictionary = pawns[who][i]
                if a.zone != "track" or Layout.gate_index(who) == a.pos: continue
                for s in 4:
                    for j in 4:
                        if s == who: continue
                        var b: Dictionary = pawns[s][j]
                        if b.zone != "track" or Layout.gate_index(s) == b.pos: continue
                        out.append({"card": card_idx, "rank": rank, "kind": "swap", "pawn": [who, i], "target": [s, j]})
        "7":
            out.append_array(_split_moves(who, card_idx))
        _:
            out.append_array(_forward_moves(who, card_idx, rank, STEPS[rank]))
    return out

## Uma saída por peão do Pátio (o jogador escolhe qual; para as regras são equivalentes).
func _exit_moves(who: int) -> Array:
    var out := []
    var gate := Layout.gate_index(who)
    var o := occupant(gate)
    if not o.is_empty() and o[0] == who: return out
    for i in 4:
        if pawns[who][i].zone == "home": out.append({"kind": "exit", "pawn": [who, i]})
    return out

func _forward_moves(who: int, card_idx: int, rank: String, steps: int) -> Array:
    var out := []
    for i in 4:
        var z: String = pawns[who][i].zone
        if z == "home": continue
        if forward_path(who, i, steps).ok:
            out.append({"card": card_idx, "rank": rank, "kind": "move", "pawn": [who, i], "steps": steps})
    return out

## 7: todas as 7 casas num peão, ou divididas entre dois peões (a + b = 7). Cada parte tem de valer em sequência.
func _split_moves(who: int, card_idx: int) -> Array:
    var out := []
    for i in 4:
        if pawns[who][i].zone != "home" and forward_path(who, i, 7).ok:
            out.append({"card": card_idx, "rank": "7", "kind": "split", "parts": [{"pawn": [who, i], "steps": 7}]})
    for i in 4:
        for j in 4:
            if i == j or pawns[who][i].zone == "home" or pawns[who][j].zone == "home": continue
            for a in range(1, 7):
                var sim = clone()
                if not sim.forward_path(who, i, a).ok: continue
                sim._apply_forward(who, i, a, [])
                if sim.pawns[who][j].zone == "home": continue    # o segundo foi capturado pelo primeiro
                if sim.forward_path(who, j, 7 - a).ok:
                    out.append({"card": card_idx, "rank": "7", "kind": "split", "parts": [{"pawn": [who, i], "steps": a}, {"pawn": [who, j], "steps": 7 - a}]})
    return out

## A jogada é uma das devolvidas por legal_moves (ou descarte quando não existe nenhuma jogada).
func is_legal(seat: int, mv: Dictionary) -> bool:
    if seat < 0 or seat > 3 or winner >= 0: return false
    var c := int(mv.get("card", -1))
    if c < 0 or c >= hands[seat].size(): return false
    if String(mv.get("kind", "")) == "discard": return not has_any_move(seat)
    var key := _move_key(mv)
    for m in legal_moves(seat, c):
        if _move_key(m) == key: return true
    return false

static func _move_key(mv: Dictionary) -> String:
    var parts := []
    for p in mv.get("parts", []): parts.append([_ints(p.get("pawn", [])), int(p.get("steps", 0))])
    return JSON.stringify([String(mv.get("kind", "")), int(mv.get("card", -1)), _ints(mv.get("pawn", [])), int(mv.get("steps", 0)), _ints(mv.get("target", [])), parts])

static func _ints(a) -> Array:
    var out := []
    for x in a: out.append(int(x))
    return out

func has_any_move(seat: int) -> bool:
    for c in hands[seat].size():
        if not legal_moves(seat, c).is_empty(): return true
    return false

# ---------------------------------------------------------------- aplicar
## Aplica e devolve eventos para a animação: [{"type":"move","pawn","path"}, {"type":"capture","pawn"},
## {"type":"exit","pawn"}, {"type":"swap",...}, {"type":"crown","pawn"}, {"type":"discard","rank"}]
func apply(seat: int, mv: Dictionary) -> Array:
    # Mesmo motor e mesma validação para humano e bots: jogada fora da lista legal é recusada.
    if not is_legal(seat, mv): return []
    var ev := []
    var rank: String = hands[seat][int(mv.card)]
    hands[seat].remove_at(int(mv.card))
    discard.append(rank)
    var name: String = String(names[seat])
    match String(mv.kind):
        "discard":
            ev.append({"type": "discard", "rank": rank})
            _log("%s descartou %s" % [name, rank])
        "exit":
            var w: Array = mv.pawn
            var gate := Layout.gate_index(w[0])
            var o := occupant(gate)
            if not o.is_empty():
                _send_home(o[0], o[1])
                ev.append({"type": "capture", "pawn": o})
            pawns[w[0]][w[1]] = {"zone": "track", "pos": gate}
            ev.append({"type": "exit", "pawn": w})
            _log("%s jogou %s · saiu do pátio" % [name, rank])
        "move":
            var w: Array = mv.pawn
            _apply_forward(w[0], w[1], int(mv.steps), ev)
            _log("%s jogou %s · %d casas" % [name, rank, int(mv.steps)])
        "back":
            var w: Array = mv.pawn
            var r := backward_path(w[0], w[1], 4)
            _land(w[0], w[1], r, ev)
            _log("%s jogou -4 · voltou 4 casas" % name)
        "swap":
            var a: Array = mv.pawn
            var b: Array = mv.target
            var pa: Dictionary = pawns[a[0]][a[1]]
            var pb: Dictionary = pawns[b[0]][b[1]]
            pawns[a[0]][a[1]] = pb.duplicate()
            pawns[b[0]][b[1]] = pa.duplicate()
            ev.append({"type": "swap", "pawn": a, "target": b})
            _log("%s jogou J · trocou de lugar" % name)
        "split":
            var total := 0
            for part in mv.parts:
                var w: Array = part.pawn
                if pawns[w[0]][w[1]].zone == "home": continue
                if forward_path(w[0], w[1], int(part.steps)).ok:
                    _apply_forward(w[0], w[1], int(part.steps), ev)
                    total += int(part.steps)
            _log("%s jogou 7 · %s" % [name, " + ".join(mv.parts.map(func(p): return str(int(p.steps))))])
    _check_winner()
    return ev

func _apply_forward(s: int, i: int, steps: int, ev: Array):
    _land(s, i, forward_path(s, i, steps), ev)

func _land(s: int, i: int, r: Dictionary, ev: Array):
    if not r.get("ok", false): return
    var end: Dictionary = r.end
    var was_lane: bool = pawns[s][i].zone == "lane"
    if end.zone == "track":
        var o := occupant(end.pos)
        if not o.is_empty() and o != [s, i]:
            _send_home(o[0], o[1])
            ev.append({"type": "capture", "pawn": o})
    pawns[s][i] = {"zone": end.zone, "pos": end.pos}
    ev.push_front({"type": "move", "pawn": [s, i], "path": r.path})
    if end.zone == "lane" and not was_lane:
        ev.append({"type": "crown", "pawn": [s, i]})
        _log("%s coroou um peão" % String(names[s]))

func _send_home(s: int, i: int):
    var used := []
    for j in 4:
        if pawns[s][j].zone == "home": used.append(pawns[s][j].pos)
    var slot := 0
    while slot in used: slot += 1
    pawns[s][i] = {"zone": "home", "pos": slot}

func _check_winner():
    for t in 2:
        if team_crowned(t) == 8: winner = t

func _log(text: String):
    log.push_front(text)
    if log.size() > 8: log.resize(8)

## Passa a vez; quando todas as mãos acabam, nova rodada (reparte).
func next_turn():
    turn = (turn + 1) % 4
    var empty := true
    for s in 4:
        if not hands[s].is_empty(): empty = false
    if empty:
        round_no += 1
        deal()

func clone():
    var c = new()
    c.pawns = []
    for row in pawns:
        var r := []
        for p in row: r.append(p.duplicate())
        c.pawns.append(r)
    c.hands = []
    for h in hands: c.hands.append(h.duplicate())
    c.deck = deck.duplicate()
    c.discard = discard.duplicate()
    c.turn = turn
    c.round_no = round_no
    c.winner = winner
    c.names = names
    return c

## Progresso de um peão no caminho do dono (0 no Portão … 74 na Entrada, 75..78 no Salão, -1 no Pátio).
func progress(s: int, i: int) -> int:
    var p: Dictionary = pawns[s][i]
    if p.zone == "home": return -1
    if p.zone == "lane": return 75 + int(p.pos)
    return posmod(int(p.pos) - Layout.gate_index(s), TRACK)
