extends SceneTree
## MARCHA REAL · regras e bots (sem interface).
## Rodar: godot --headless --path . -s tests/marcha_rules_test.gd
const Rules := preload("res://marcha/rules.gd")
const AI := preload("res://marcha/ai.gd")
const Layout := preload("res://marcha/board_layout.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize():
    # ---------- tabuleiro ----------
    var cells := {}
    for i in Rules.TRACK: cells[Layout.track_cell(i)] = true
    check(cells.size() == 76, "76 casas distintas na Muralha")
    var max_step := 0.0
    for i in Rules.TRACK: max_step = maxf(max_step, Layout.track_cell(i).distance_to(Layout.track_cell(i + 1)))
    check(max_step < 70.0, "casas vizinhas encostadas (passo máx %.0f px)" % max_step)
    check(Layout.track_cell(19).distance_to(Vector2(115, 669)) < 3 and Layout.track_cell(38).distance_to(Vector2(930, 114)) < 3, "Portões do Rubi e do Ônix nas posições da arte")
    check(Layout.lane_cell(1, 3).distance_to(Vector2(375, 799)) < 3, "Salão do Rubi termina na coroa")
    check(Layout.entrance_index(0) == 74 and Layout.track_cell(74).distance_to(Vector2(800, 1484)) < 3, "Entrada do Salão do Marfim")
    # ---------- regras pontuais ----------
    var g = Rules.new()
    g.setup(7)
    check(g.hands[0].size() == 4 and g.deck.size() == 52 - 16, "4 cartas para cada reino; baralho de 52")
    g.hands[0] = ["A", "10", "4", "J"]
    var mv := g.legal_moves(0, 0)
    check(mv.size() == 4 and mv.all(func(m): return m.kind == "exit"), "Ás com todos no Pátio: só sair (qualquer um dos 4 peões)")
    # motor único: a mesma validação vale para humano e bot
    check(g.is_legal(0, mv[2]), "saída escolhida pelo jogador é jogada legal")
    var bad := {"card": 1, "kind": "move", "pawn": [0, 0], "steps": 10}
    check(not g.is_legal(0, bad) and g.apply(0, bad).is_empty() and g.hands[0].size() == 4, "jogada ilegal (peão no Pátio andando 10) é recusada sem mudar nada")
    check(not g.is_legal(0, {"card": 0, "kind": "discard"}), "descartar só quando não há nenhuma jogada")
    check(String(g.RULESET_VERSION) == "marcha-real-1", "versão das regras para o histórico")
    check(g.legal_moves(0, 1).is_empty(), "10 com todos no Pátio: nenhuma jogada")
    g.apply(0, mv[0])
    check(g.pawns[0][0].zone == "track" and g.pawns[0][0].pos == 0, "peão sai para o próprio Portão")
    g.hands[0].append("A")
    check(g.legal_moves(0, g.hands[0].size() - 1).filter(func(m): return m.kind == "exit").is_empty(), "não sai com o próprio peão no Portão")
    # protegido no portão: ninguém passa
    var h = Rules.new()
    h.setup(3)
    h.pawns[1][0] = {"zone": "track", "pos": 19}     # Rubi no próprio Portão
    h.pawns[0][0] = {"zone": "track", "pos": 15}
    check(not h.forward_path(0, 0, 6).ok, "peão no próprio Portão bloqueia a passagem")
    check(h.forward_path(0, 0, 3).ok, "pode andar até antes do bloqueio")
    # captura
    h.pawns[1][0] = {"zone": "track", "pos": 21}
    h.hands[0] = ["6"]
    var cap := h.legal_moves(0, 0)
    h.apply(0, cap[0])
    check(h.pawns[1][0].zone == "home" and h.pawns[0][0].pos == 21, "cair em cima manda o peão de volta ao Pátio")
    # entrada do salão
    h.pawns[0][1] = {"zone": "track", "pos": 72}
    check(h.forward_path(0, 1, 3).end == {"zone": "lane", "pos": 0}, "na Entrada o peão entra no Salão")
    check(h.forward_path(0, 1, 6).end == {"zone": "lane", "pos": 3}, "chega à casa da coroa")
    check(not h.forward_path(0, 1, 7).ok, "não passa do fundo do Salão")
    # volta 4 atrás do portão
    h.pawns[0][2] = {"zone": "track", "pos": 1}
    var b := h.backward_path(0, 2, 4)
    check(b.ok and b.end.pos == 73, "-4 logo depois do Portão vai para trás dele (atalho)")
    # 5 move qualquer peça
    h.pawns[2][0] = {"zone": "track", "pos": 40}
    h.hands[0] = ["5"]
    check(h.legal_moves(0, 0).any(func(m): return m.pawn == [2, 0]), "5 move peça de outro reino")
    # J troca
    h.hands[0] = ["J"]
    var sw: Array = h.legal_moves(0, 0)
    check(sw.any(func(m): return m.kind == "swap" and m.target == [2, 0]), "J troca com outra peça")
    # 7 dividido
    h.hands[0] = ["7"]
    var sp: Array = h.legal_moves(0, 0)
    check(sp.any(func(m): return m.parts.size() == 2), "7 pode ser dividido entre 2 peões")
    # ---------- partidas completas só com bots ----------
    var finished := 0
    var turns_total := 0
    var illegal := false
    for seed in [11, 22, 33, 44, 55, 66]:
        var m = Rules.new()
        m.setup(seed)
        var rng := RandomNumberGenerator.new()
        rng.seed = seed
        var t := 0
        while m.winner < 0 and t < 4000:
            var s: int = m.turn
            if m.hands[s].is_empty():
                m.next_turn()
                continue
            var c := AI.choose(m, s, rng)
            if c.kind != "discard" and not m.legal_moves(s, int(c.card)).has(c): illegal = true
            if c.kind == "discard" and m.has_any_move(s): illegal = true
            m.apply(s, c)
            m.next_turn()
            t += 1
        if m.winner >= 0: finished += 1
        turns_total += t
    check(not illegal, "bots só fazem jogadas legais (e só descartam sem jogada)")
    check(finished == 6, "6 de 6 partidas de bots terminam (%d jogadas em média)" % (turns_total / 6))
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
