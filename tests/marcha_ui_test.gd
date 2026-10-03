extends SceneTree
## R32 · MARCHA REAL na interface: entrada pela Home, tutorial na 1ª vez, acesso (Club ilimitado,
## sem Club 1 partida por dia no aparelho), jogada humana (carta → peão → JOGAR CARTA), bots jogando,
## e Perfil/Histórico (APLICAR avatar, ícones separados, histórico de partidas).
const Access := preload("res://marcha/marcha_access.gd")
const BACKUP := ["user://marcha_daily.cfg", "user://marcha.cfg", "user://home_preferences.cfg", "user://match_history.json"]
var checks := 0
var failures := 0
var saved := {}

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func wait_frames_until(f: Callable, n: int) -> bool:
    for i in n:
        if f.call(): return true
        await process_frame
    return f.call()

func _initialize(): call_deferred("run")

func frames(n := 3):
    for i in n: await process_frame

func run():
    for p in BACKUP:
        var g := ProjectSettings.globalize_path(p)
        saved[p] = FileAccess.get_file_as_bytes(g) if FileAccess.file_exists(g) else PackedByteArray()
        DirAccess.remove_absolute(g)
    root.size = Vector2i(1600, 900)
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await frames(20)
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    var hub = stage.hub
    hub.monetization_state.mock_reset()
    hub.entitlements.clear_server()
    # ---------- Home ----------
    var titles: Array = hub.menu_buttons.map(func(b): return hub.title_of(b))
    check(titles.size() == 11 and titles[4] == "MARCHA REAL" and titles[5] == "XEQUE" and titles[9] == "HISTÓRICO DE PARTIDAS" and titles[8] == "CONHEÇA O FRAIHA", "Home: MARCHA REAL, XEQUE e HISTÓRICO DE PARTIDAS (abaixo de CONHEÇA O FRAIHA)")
    var ok_rows := true
    for i in range(1, hub.menu_buttons.size()):
        if hub.menu_buttons[i].position.y < hub.menu_buttons[i - 1].position.y + hub.menu_buttons[i - 1].size.y: ok_rows = false
    check(ok_rows and hub.menu_buttons[10].position.y + hub.menu_buttons[10].size.y < 941, "11 linhas sem sobreposição, dentro da arte")
    # ---------- Marcha: tutorial e acesso ----------
    hub.menu_buttons[4].pressed.emit()
    await frames(6)
    var ui = hub.marcha
    check(ui != null and ui.visible and ui.mode == "lobby", "MARCHA REAL abre no salão (lobby)")
    var audio = stage.get_node_or_null("GameAudio")
    check(audio != null and audio.music_path == "res://marcha/audio/musica_marcha.mp3" and bool(audio.music.stream.loop), "música da MARCHA REAL tocando, em loop")
    check(ui.tut_page == 0, "1ª vez: tutorial abre sozinho")
    for i in ui.TUTORIAL.size(): ui._on_hit("tut_next")
    check(ui.tut_page == -1 and Access.tutorial_seen(), "tutorial percorrido até o fim e marcado como visto")
    await frames(3)
    check(ui.hits.any(func(h): return String(h.id) == "mute_music") and ui.hits.any(func(h): return String(h.id) == "mute_fx"), "botões MÚSICA e EFEITOS no salão")
    check(bool(ui.gate_info.get("can_play", false)) and String(ui.gate_info.label).contains("GRÁTIS"), "sem Club: 1 partida grátis hoje")
    await ui.start_game()
    await frames(3)
    check(ui.mode == "game" and ui.g != null and ui.g.hands[0].size() == 4, "partida começa com 4 cartas na mão")
    check(Access.local_played_today(), "partida grátis do dia consumida (aparelho)")
    ui._on_hit("mute_fx")
    check(hub.effects_muted and AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "EFEITOS desliga só os efeitos")
    ui._on_hit("mute_fx")
    # celular: o mesmo toque chega 2× (toque + clique emulado) → o 2º não pode voltar ao lobby
    var g0 = ui.g
    ui._on_hit("lobby_play")
    await frames(2)
    ui._redraw()
    check(ui.hits.is_empty(), "áreas de toque antigas somem até o próximo desenho")
    await frames(2)
    check(ui.mode == "game" and ui.g == g0, "2º toque em JOGAR AGORA durante a partida é ignorado")
    # jogada humana: força uma mão conhecida
    var g = ui.g
    g.turn = 0
    g.hands[0] = ["A", "3", "8", "2"]
    ui._clear_selection()
    ui.pick_card(0)
    check(not ui.pending.is_empty() and ui.pending.kind == "exit", "Ás com todos no Pátio: saída já pronta, sem escolher peão")
    check(ui.candidate_pawns().size() == 4, "Ás: os 4 peões do Pátio ficam com aro dourado")
    ui.pick_pawn([0, 2])
    check(not ui.pending.is_empty() and ui.pending.kind == "exit", "tocar num peão do Pátio prepara SAIR")
    check(ui.help_line().to_upper().contains("SAI DA BASE"), "linha de ajuda explica a carta")
    # 10: duas funções
    ui.choice_commits = false     # (aqui só confere o que cada escolha prepara; jogar na hora é testado no fim)
    var keep_hand: Array = g.hands[0].duplicate()
    var keep_pawns: Array = g.pawns.duplicate(true)
    g.pawns[0][0] = {"zone": "track", "pos": 3}
    g.hands[0] = ["10", "3", "8", "2"]
    ui._clear_selection()
    ui.pick_card(0)
    check(ui.choice_open and ui.pending.is_empty() and ui.two_choices().size() == 2 and ui.help_line().contains("escolha o que fazer"), "10 com as duas funções: abre a caixa ANDAR 10 / PERDE A VEZ")
    check(ui.candidate_pawns().is_empty(), "com a caixa aberta nenhum peão recebe toque")
    ui._redraw()
    await frames(2)
    check(ui.hits.any(func(h): return h.id == "choice_move") and ui.hits.any(func(h): return h.id == "choice_burn") and ui.hits.any(func(h): return h.id == "choice_cancel") and not ui.hits.any(func(h): return String(h.id).begins_with("card_")), "caixa desenhada por cima (só os botões dela recebem toque)")
    ui._on_hit("choice_burn")
    check(not ui.choice_open and not ui.pending.is_empty() and ui.pending.kind == "burn" and ui.help_line().contains("perde a vez"), "PERDE A VEZ prepara a 2ª função do 10")
    ui.pick_card(0)
    ui._on_hit("choice_move")
    check(not ui.pending.is_empty() and ui.pending.kind == "move" and ui.pending.pawn == [0, 0] and int(ui.pending.steps) == 10, "ANDAR 10 com peça única: já vem pronto nela, sem tocar no peão")
    ui.pick_card(0)
    ui._on_hit("choice_cancel")
    check(not ui.choice_open and ui.sel_card < 0, "CANCELAR fecha a caixa")
    # Ás com peão na pista e peões no Pátio: caixa TIRAR UMA PEÇA NOVA / ANDAR 11
    g.hands[0] = ["A", "3", "8", "2"]
    ui.pick_card(0)
    var ace: Array = ui.two_choices()
    check(ui.choice_open and ace.size() == 3 and String(ace[0][1]).contains("DA BASE") and String(ace[1][1]).contains("11") and String(ace[2][1]).contains("1 CASA") and ace.all(func(o): return bool(o[3])), "R37: Ás com as 3 funções: caixa TIRAR DA BASE / ANDAR 11 / ANDAR 1")
    ui._on_hit("choice_exit")
    check(not ui.pending.is_empty() and ui.pending.kind == "exit", "TIRAR DA BASE: saída pronta")
    ui.pick_card(0)
    ui._on_hit("choice_move11")
    check(not ui.pending.is_empty() and ui.pending.kind == "move" and int(ui.pending.steps) == 11 and ui.pending.pawn == [0, 0], "ANDAR 11: só os peões da pista contam (peça única já escolhida)")
    ui.pick_card(0)
    ui._on_hit("choice_move1")
    check(not ui.pending.is_empty() and ui.pending.kind == "move" and int(ui.pending.steps) == 1 and ui.pending.pawn == [0, 0], "R37: ANDAR 1 CASA")
    # Ás: uma função só possível (todos na pista, sem nada na base) mas 11 travado → anda 1 sozinho
    var keep_ace: Array = g.pawns.duplicate(true)
    for i in 4: g.pawns[0][i] = {"zone": "track", "pos": 3 + i * 20}
    g.pawns[0][0] = {"zone": "track", "pos": 70}      # 11 passaria do fundo do Salão; 1 cabe
    for i in range(1, 4): g.pawns[0][i] = {"zone": "lane", "pos": i}
    ui.pick_card(0)
    var a1: Array = ui.two_choices().filter(func(o): return bool(o[3]))
    check(a1.size() == 1 and not ui.choice_open and not ui.pending.is_empty() and int(ui.pending.get("steps", 0)) == 1, "R37: Ás com só ANDAR 1 possível: ativa sozinho, sem caixa")
    g.pawns = keep_ace
    # Rei: só tira da base, sem tocar em peão
    g.hands[0] = ["K", "3", "8", "2"]
    ui.pick_card(0)
    check(not ui.choice_open and not ui.pending.is_empty() and ui.pending.kind == "exit" and ui.help_line().contains("base"), "R37: Rei tira peão da base direto (sem escolher peão)")
    # R38.2 · 5: sem perguntar a cor — JOGAR CARTA e depois toque direto na peça (de qualquer cor)
    g.pawns[1][0] = {"zone": "track", "pos": 30}
    g.pawns[2][0] = {"zone": "track", "pos": 50}
    g.hands[0] = ["5", "3", "8", "2"]
    ui.pick_card(0)
    check(not ui.choice_open and ui.two_choices().is_empty() and ui.awaiting_play() and ui.candidate_pawns().is_empty() and ui.can_play() and ui.help_line().contains("JOGAR CARTA"), "R38.2: 5 não pergunta a cor; primeiro JOGAR CARTA (peças ainda sem aro)")
    ui.confirm()
    var c5: Array = ui.candidate_pawns()
    check(ui.card_played and not ui.busy and c5.has([1, 0]) and c5.has([2, 0]), "R38.2: 5 jogado na mesa → peças de qualquer cor ficam com aro para o toque")
    ui._on_hit("cancel")
    check(not ui.card_played and ui.sel_card < 0, "R38.2: CANCELAR devolve a carta jogada para a mão")
    ui._clear_selection()
    # R37 · cartão de perfil: passar o mouse na placa de um bot abre o cartão de bot (sem placar)
    ui._redraw()
    await frames(2)
    var seat1: Rect2 = Rect2()
    for h in ui.hits: if String(h.id) == "seat_1": seat1 = h.rect
    check(seat1.size.x > 0, "R37: placa do Rubi é área de cartão de perfil")
    ui.on_hover(seat1.get_center())
    await create_timer(0.4).timeout
    var pp = stage.profile_popup
    check(pp.is_open() and pp.state == "bot" and pp.info.mode == "marcha" and not pp.view.get_global_rect().intersects(ui._seat_screen_rect(1).grow(-2)), "R37: mouse na placa do bot abre o cartão BOT ao lado (modo MARCHA REAL)")
    ui.on_hover(Vector2(-50, -50))
    await create_timer(0.6).timeout
    check(not pp.is_open(), "R37: mouse saiu: o cartão fecha")
    pp.show_card("t", {"user_id": "x", "name": "Teste", "mode": "marcha"}, Rect2(100, 100, 50, 50))
    pp.state = "ready"
    pp.card = {"relation": "none", "stats_ready": true, "stats": {"wins": 6, "losses": 4, "draws": 0}}
    var sl: Dictionary = pp.stats_line()
    check(sl.win_pct == 60 and sl.loss_pct == 40 and pp.button_label() == "ADICIONAR AMIGO", "R37: cartão mostra 60% de vitória / 40% de derrota e ADICIONAR AMIGO")
    pp.close()
    # R38.5 · peça na Muralha + peça no Salão: automático só quando a do Salão NÃO pode andar com a carta
    var keep_s: Array = g.pawns.duplicate(true)
    g.pawns[0][0] = {"zone": "track", "pos": 12}
    g.pawns[0][1] = {"zone": "lane", "pos": 0}
    g.pawns[0][2] = {"zone": "home", "pos": 0}
    g.pawns[0][3] = {"zone": "home", "pos": 1}
    for i in 4: g.pawns[1][i] = {"zone": "home", "pos": i}
    var all_auto := true
    for rk in ["3", "6", "4", "2", "8", "9", "Q", "10", "7"]:
        g.hands[0] = [rk, "2", "2", "2"]
        ui._clear_selection()
        ui.pick_card(0)
        var pd: Dictionary = ui.pending
        var movers := []
        for m in g.legal_moves(0, 0):
            if m.kind in ["burn", "exit"]: continue
            var w: Array = m.parts[0].pawn if m.kind == "split" else m.pawn
            if not movers.has(w): movers.append(w)
        var on_it: bool = not pd.is_empty() and ((pd.get("pawn", []) == [0, 0]) or (pd.kind == "split" and pd.parts[0].pawn == [0, 0]))
        if rk == "10": on_it = ui.choice_open or on_it
        var ok_rk: bool = on_it if movers.size() == 1 else (pd.is_empty() and not ui.sel_pawn == [0, 0])
        if not ok_rk:
            all_auto = false
            print("DBG auto errado: ", rk, " ", pd, " movers=", movers, " choice=", ui.choice_open)
    check(all_auto, "R38.5: carta que só UMA peça pode jogar fica pronta nela; se a do Salão também pode andar, nada é escolhido sozinho")
    # o caso relatado: carta 2, peão recém-saído na Muralha e outro no Salão que ainda anda 3 → o jogador escolhe
    g.pawns[0][1] = {"zone": "lane", "pos": 0}
    g.pawns[0][0] = {"zone": "track", "pos": ui.Layout.gate_index(0)}
    g.hands[0] = ["2", "3", "3", "3"]
    ui._clear_selection()
    ui.pick_card(0)
    check(ui.pending.is_empty() and ui.sel_pawn.is_empty() and ui.awaiting_play(), "R38.5: 2 com peão recém-saído + peão no Salão: nada automático")
    ui.confirm()
    var c25: Array = ui.candidate_pawns()
    check(c25.has([0, 0]) and c25.has([0, 1]), "R38.5: depois de JOGAR CARTA as duas peças podem ser escolhidas")
    ui._clear_selection()
    g.pawns = keep_s
    ui._clear_selection()
    # R38.3 · J com só 2 peças na mesa: NADA automático — 1º toque no seu peão, 2º na peça que troca
    var keep_j: Array = g.pawns.duplicate(true)
    for st in 4:
        for i in 4: g.pawns[st][i] = {"zone": "home", "pos": i}
    g.pawns[0][0] = {"zone": "track", "pos": 10}
    g.pawns[1][0] = {"zone": "track", "pos": 30}
    g.hands[0] = ["J", "2", "2", "2"]
    ui._clear_selection()
    ui.pick_card(0)
    check(ui.pending.is_empty() and ui.sel_pawn.is_empty() and ui.awaiting_play(), "R38.3: J com só 2 peças na mesa: nada escolhido sozinho (primeiro JOGAR CARTA)")
    ui.confirm()
    check(ui.card_played and ui.candidate_pawns() == [[0, 0]] and ui.help_line().contains("SEU peão"), "R38.3: J jogado → 1º toque só no SEU peão")
    ui.pick_pawn([0, 0])
    check(ui.candidate_pawns().has([1, 0]) and ui.pending.is_empty(), "R38.3: J → depois a peça que vai trocar com o seu")
    ui._clear_selection()
    # Ás: as peças na Muralha não conseguem andar 11 nem 1 → só sair da base, automático
    for i in 4: g.pawns[0][i] = {"zone": "home", "pos": i}
    g.pawns[0][0] = {"zone": "track", "pos": ui.Layout.gate_index(2) - 1}
    g.pawns[2][0] = {"zone": "track", "pos": ui.Layout.gate_index(2)}   # aliado no Portão dele: bloqueia 1 e 11
    g.pawns[1][0] = {"zone": "home", "pos": 0}
    g.hands[0] = ["A", "2", "2", "2"]
    ui._clear_selection()
    ui.pick_card(0)
    check(not ui.choice_open and not ui.pending.is_empty() and ui.pending.kind == "exit", "R37.3: Ás só com SAIR possível: já pronto, sem caixa")
    # nenhuma jogada: DESCARTAR TODAS
    for st in 4:
        for i in 4: g.pawns[st][i] = {"zone": "home", "pos": i}
    g.hands[0] = ["Q", "9", "8"]
    ui._clear_selection()
    ui._redraw()
    await frames(2)
    check(ui.can_discard_all() and ui.hits.any(func(h): return h.id == "discard_all"), "R37.3: sem nenhuma jogada aparece DESCARTAR TODAS")
    ui.pile = []
    ui.call("_fly_cards", 0, ["Q", "9", "8"], [0, 1, 2])
    await frames(2)
    check(ui.flies.size() == 3 and ui.fly_hide == [0, 1, 2], "R37.3: as cartas voam da mão até a mesa (escondidas na mão enquanto voam)")
    await create_timer(ui.CARD_FLY + 0.4).timeout
    check(ui.flies.is_empty(), "R37.3: voo termina sozinho")
    var evd: Array = g.apply(0, {"card": 0, "kind": "discard_all"})
    ui._pile_add(evd, {"kind": "discard_all"}, "Q")
    check(g.hands[0].is_empty() and ui.pile.size() == 3 and ui.pile.all(func(p): return bool(p.dead)), "R37.3: as 3 caem no monte com a cor de descartadas")
    g.pawns = keep_j
    g.turn = 0
    ui.busy = false
    ui._clear_selection()
    # ABATER e CHEGADA na mão e no caminho
    var keep_ab: Array = g.pawns.duplicate(true)
    g.pawns[0][0] = {"zone": "track", "pos": 20}
    g.pawns[1][0] = {"zone": "track", "pos": 23}      # Rubi 3 casas à frente
    g.pawns[0][1] = {"zone": "track", "pos": 72}      # 2 casas antes da Entrada (74): 3 casas entra no Salão
    g.hands[0] = ["3", "8", "9", "Q"]
    check(ui.card_can_capture(0) and not ui.card_can_capture(1), "R37: carta 3 marcada ABATER (derruba o Rubi); 8 não")
    check(ui.card_can_crown(0), "R37: carta 3 marcada CHEGADA (leva peão ao Salão)")
    ui.pick_card(0)
    ui.pick_pawn([0, 0])
    var cp: Dictionary = ui.captures_of(ui.pending)
    check(cp.enemy == [[1, 0]] and cp.ally.is_empty(), "R37: caminho do 3 avisa ABATER no peão Rubi")
    g.pawns = keep_ab
    ui._clear_selection()
    g.hands[0] = ["A", "3", "8", "2"]
    # Ás sem peão na pista: uma função só → sem caixa
    g.pawns[0][0] = {"zone": "home", "pos": 0}
    ui.pick_card(0)
    check(not ui.choice_open and not ui.pending.is_empty() and ui.pending.kind == "exit", "Ás só com saída possível: sem caixa, saída automática")
    g.pawns[0][0] = {"zone": "track", "pos": 3}
    # Valete: 1º o SEU peão, depois a peça do outro; as duas brilham
    g.pawns[0][1] = {"zone": "track", "pos": 9}
    g.pawns[1][0] = {"zone": "track", "pos": 30}
    g.pawns[2][0] = {"zone": "track", "pos": 50}
    g.hands[0] = ["J", "3", "8", "2"]
    ui.pick_card(0)
    check(ui.candidate_pawns().is_empty() and ui.awaiting_play(), "R38.2: J — antes de JOGAR CARTA nenhuma peça recebe toque")
    ui.confirm()
    var c1: Array = ui.candidate_pawns()
    check(c1.has([0, 0]) and c1.has([0, 1]) and not c1.has([1, 0]) and ui.help_line().contains("SEU peão"), "J: 1º toque só nos SEUS peões")
    ui.pick_pawn([0, 1])
    var c2: Array = ui.candidate_pawns()
    check(c2.has([1, 0]) and c2.has([2, 0]) and ui.help_line().contains("2º toque"), "J: depois do 1º toque, as peças do amigo e do adversário")
    ui.pick_pawn([0, 0])
    check(ui.sel_pawn == [0, 0] and ui.pending.is_empty(), "J: tocar outro peão seu troca a 1ª escolha")
    ui.card_played = false        # (abaixo a troca é aplicada à mão para medir a animação)
    ui.pick_pawn([1, 0])
    check(not ui.pending.is_empty() and ui.pending.kind == "swap" and ui.sel_target == [1, 0] and ui.help_line().contains("JOGAR CARTA"), "J: 2º toque prepara a troca (as duas ficam brilhando)")
    # animação da troca: as duas peças viajam e brilham; leva de 1,0 a 2,4 s
    var pa_before: Vector2 = ui.pawn_point(0, 0)
    var pb_before: Vector2 = ui.pawn_point(1, 0)
    ui.busy = true
    var ev: Array = g.apply(0, ui.pending)
    ui._clear_selection()
    var t_sw := Time.get_ticks_msec()
    var mid_ok := false
    ui._animate.call_deferred(ev)
    await wait_frames_until(func(): return ui.swap_glow.size() == 2, 30)
    check(ui.swap_glow.size() == 2, "troca: as duas peças brilham")
    await create_timer(0.9).timeout
    var mid: Vector2 = ui.pawn_point(0, 0)
    mid_ok = mid.distance_to(pa_before) > 20.0 and mid.distance_to(pb_before) > 20.0
    while ui.swap_glow.size() > 0 and Time.get_ticks_msec() - t_sw < 5000: await process_frame
    var took := (Time.get_ticks_msec() - t_sw) / 1000.0
    check(mid_ok, "troca: no meio da animação a peça está no caminho (nem na origem nem no destino)")
    check(took >= 1.6 and took <= 3.4, "troca animada sem pressa (%.1f s)" % took)
    check(ui.pawn_point(0, 0).distance_to(pb_before) < 2.0 and ui.pawn_point(1, 0).distance_to(pa_before) < 2.0, "troca: cada peça termina no lugar da outra")
    ui.busy = false
    g.pawns[0][0] = {"zone": "track", "pos": 3}
    g.pawns[0][1] = {"zone": "home", "pos": 1}
    g.pawns[1][0] = {"zone": "home", "pos": 0}
    g.pawns[2][0] = {"zone": "home", "pos": 0}
    g.hands[0] = ["8", "3", "4", "2"]
    ui._clear_selection()
    ui.pick_card(0)
    check(not ui.pending.is_empty() and ui.pending.kind == "move" and ui.pending.pawn == [0, 0], "só um peão pode jogar a carta: jogada já pronta")
    for rk in ["2", "3", "5", "7", "9", "Q", "4"]:
        g.hands[0] = [rk, "3", "8", "2"]
        ui._clear_selection()
        ui.pick_card(0)
        if ui.sole_pawn().is_empty(): continue
        check(ui.sel_pawn == [0, 0] and not ui.pending.is_empty(), "peça única no tabuleiro: carta %s já age nela" % rk)
    g.hands[0] = ["J", "3", "8", "2"]
    g.pawns[1][0] = {"zone": "track", "pos": 30}
    g.pawns[3][0] = {"zone": "track", "pos": 45}
    ui._clear_selection()
    ui.pick_card(0)
    ui.confirm()
    check(ui.sel_pawn.is_empty() and ui.pending.is_empty() and ui.candidate_pawns() == [[0, 0]], "R38.3: J com peça única: o seu peão NÃO é escolhido sozinho (1º toque nele)")
    g.hands[0] = keep_hand
    g.pawns = keep_pawns
    ui._clear_selection()
    ui.pick_card(0)
    ui.pick_pawn([0, 2])
    ui.confirm()
    var t0 := Time.get_ticks_msec()
    while ui.g.turn == 0 and Time.get_ticks_msec() - t0 < 5000: await process_frame
    check(g.pawns[0].any(func(p): return p.zone == "track"), "JOGAR CARTA: peão saiu para o Portão")
    check(ui.cues_played.has("card") and ui.cues_played.has("exit"), "sons: carta jogada e peão saindo do pátio")
    # bots jogam sozinhos até voltar a vez do humano
    t0 = Time.get_ticks_msec()
    while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 30000: await process_frame
    check(ui.g.turn == 0 and g.log.size() >= 4, "os 3 bots jogaram e a vez voltou (%d registros)" % g.log.size())
    check(ui.cues_played.has("your_turn") and (ui.cues_played.has("step") or ui.cues_played.has("discard") or ui.cues_played.has("exit")), "sons: jogadas dos bots (passos, saída ou descarte) e aviso da sua vez")
    # 7 dividido pela interface
    g.pawns[0][0] = {"zone": "track", "pos": 5}
    g.pawns[0][1] = {"zone": "track", "pos": 20}
    g.hands[0] = ["7", "3", "8", "2"]
    ui._clear_selection()
    ui.pick_card(0)
    ui.pick_pawn([0, 0])
    check(ui.split_options().has(7) and ui.split_options().has(4), "7: opções de divisão aparecem")
    ui.pick_split(4)
    ui.pick_pawn([0, 1])
    check(not ui.pending.is_empty() and ui.pending.parts.size() == 2 and int(ui.pending.parts[1].steps) == 3, "7 dividido 4 + 3 entre dois peões")
    ui._on_hit("cancel")
    check(ui.pending.is_empty() and ui.sel_card < 0, "CANCELAR limpa a escolha")
    # R38.2 · o caso da foto: 2 peões (um no Portão), 7 → JOGAR CARTA → toque no 1º → 5+2 → toque no 2º = joga
    for s7 in 4:
        for i in 4: g.pawns[s7][i] = {"zone": "home", "pos": i}      # ninguém mais na Muralha (bots não interferem)
    g.pawns[0][0] = {"zone": "track", "pos": 26}
    g.pawns[0][1] = {"zone": "track", "pos": 0}
    g.hands[0] = ["7", "3", "8", "2"]
    ui._clear_selection()
    ui.pick_card(0)
    check(ui.awaiting_play() and ui.pending.is_empty(), "R38.2: 7 com 2 peões: primeiro JOGAR CARTA")
    ui._on_hit("play")
    var br7: Rect2 = ui.board_rect()
    var sc7: float = br7.size.x / ui.Layout.SIZE
    ui.on_press(br7.position + ui.pawn_point(0, 0) * sc7)
    check(ui.sel_pawn == [0, 0] and ui.split_options().has(5) and ui.help_line().contains("divisão"), "R38.2: toque no 1º peão → escolher a divisão")
    ui._on_hit("split_5")
    check(ui.candidate_pawns().has([0, 1]), "R38.2: 5+2 → o peão do Portão é o 2º")
    var hand7: int = g.hands[0].size()
    ui.on_press(br7.position + ui.pawn_point(0, 1) * sc7)
    check(ui.sel_second == [0, 1] or ui.busy or g.hands[0].size() < hand7, "R38.2: toque no 2º peão (no Portão) aceito")
    t0 = Time.get_ticks_msec()
    while ui.g.turn == 0 and Time.get_ticks_msec() - t0 < 6000: await process_frame      # (logo depois, um bot pode usar o 5 nela)
    check(int(g.pawns[0][0].pos) == 31 and int(g.pawns[0][1].pos) == 2, "R38.2: 7 = 5 + 2 jogado sem 2º JOGAR CARTA (26→31, 0→2) · %s" % str(g.pawns[0]))
    t0 = Time.get_ticks_msec()
    while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 15000: await process_frame
    # R38.3 · escolher na caixa já JOGA: ANDAR 10 com um peão só anda sozinho; TIRAR DA BASE sai sozinho
    ui.choice_commits = true
    for s3 in 4:
        for i in 4: g.pawns[s3][i] = {"zone": "home", "pos": i}
    g.pawns[0][0] = {"zone": "track", "pos": 10}
    for s3 in range(1, 4): if g.hands[s3].is_empty(): g.hands[s3] = ["2"]
    g.hands[0] = ["10", "3", "8", "2"]
    ui._clear_selection()
    ui.pick_card(0)
    check(ui.choice_open, "R38.3: 10 abre a caixa ANDAR 10 / PERDE A VEZ")
    ui._on_hit("choice_move")
    t0 = Time.get_ticks_msec()
    while ui.g.turn == 0 and Time.get_ticks_msec() - t0 < 6000: await process_frame
    check(int(g.pawns[0][0].pos) == 20, "R38.3: ANDAR 10 com um peão só: andou sozinho, sem tocar no peão nem em JOGAR CARTA (pos %d)" % int(g.pawns[0][0].pos))
    t0 = Time.get_ticks_msec()
    while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 15000: await process_frame
    for s3 in 4:
        for i in 4: g.pawns[s3][i] = {"zone": "home", "pos": i}
    g.pawns[0][0] = {"zone": "track", "pos": 30}
    g.hands[0] = ["A", "3", "8", "2"]
    ui._clear_selection()
    ui.pick_card(0)
    check(ui.choice_open and ui.two_choices().size() == 3, "R38.3: Ás abre a caixa das 3 funções")
    ui._on_hit("choice_exit")
    t0 = Time.get_ticks_msec()
    while ui.g.turn == 0 and Time.get_ticks_msec() - t0 < 6000: await process_frame
    check(g.pawns[0].filter(func(q): return q.zone == "track").size() == 2 and g.pawns[0].any(func(q): return q.zone == "track" and int(q.pos) == ui.Layout.gate_index(0)), "R38.3: TIRAR DA BASE: o peão saiu sozinho (sem tocar nele nem em JOGAR CARTA)")
    t0 = Time.get_ticks_msec()
    while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 15000: await process_frame
    # R38.3 · peão abatido volta para a base girando, sem pressa
    for s3 in 4:
        for i in 4: g.pawns[s3][i] = {"zone": "home", "pos": i}
    g.pawns[0][0] = {"zone": "track", "pos": 10}
    g.pawns[1][0] = {"zone": "track", "pos": 13}
    g.hands[0] = ["3", "4", "4", "4"]
    ui._clear_selection()
    ui.pick_card(0)
    check(not ui.pending.is_empty() and ui.captures_of(ui.pending).enemy == [[1, 0]], "R38.3: o 3 abate o Rubi")
    ui.confirm()
    t0 = Time.get_ticks_msec()
    var spun := false
    var rot_t0 := -1
    var mid_far := false
    var home_pt: Vector2 = ui.Layout.home_cell(1, 0)
    while ui.g.turn == 0 and Time.get_ticks_msec() - t0 < 8000:
        if ui.anim_rot.has("1_0"):
            if rot_t0 < 0: rot_t0 = Time.get_ticks_msec()
            if float(ui.anim_rot["1_0"]) > 1.0: spun = true
            if ui.pawn_point(1, 0).distance_to(home_pt) > 120.0 and float(ui.anim_rot["1_0"]) > 2.0: mid_far = true
            if OS.get_environment("MARCHA_SHOTS") != "" and spun and not FileAccess.file_exists("/tmp/claude-0/sc/capture_mid.png"): root.get_texture().get_image().save_png("/tmp/claude-0/sc/capture_mid.png")
        elif rot_t0 > 0 and not ui.anim_rot.has("1_0"): break
        await process_frame
    var rot_ms := Time.get_ticks_msec() - rot_t0
    check(spun and mid_far, "R38.3: abatido gira no caminho de volta (no meio, ainda longe da base)")
    check(rot_ms >= 1000 and rot_ms <= 2200, "R38.3: volta para a base sem pressa (%d ms)" % rot_ms)
    check(g.pawns[1][0].zone == "home" and ui.pawn_point(1, 0).distance_to(home_pt) < 2.0, "R38.3: termina na casa da base dele")
    t0 = Time.get_ticks_msec()
    while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 15000: await process_frame
    # R38.3 · com um 5 que tem jogada (peão do aliado na Muralha), DESCARTAR TODAS nunca aparece
    for s3 in 4:
        for i in 4: g.pawns[s3][i] = {"zone": "home", "pos": i}
    g.pawns[2][0] = {"zone": "track", "pos": 50}
    g.hands[0] = ["Q", "9", "5", "8"]
    ui._clear_selection()
    check(g.has_any_move(0) and not ui.can_discard_all(), "R38.3: tem um 5 com jogada na mão → DESCARTAR TODAS não aparece")
    g.pawns[0][0] = {"zone": "track", "pos": ui.Layout.gate_index(0)}
    g.pawns[2][0] = {"zone": "home", "pos": 0}
    g.hands[0] = ["5", "4", "4", "4"]
    check(not ui.can_discard_all() and g.legal_moves(0, 0).any(func(m): return m.pawn == [0, 0]), "R38.3: 5 com o seu peão parado no seu Portão → tem jogada, sem DESCARTAR TODAS")
    # R38.3 · 3ª rodada do ciclo: 5 cartas na mão cabem sem encostar nos botões (paisagem e retrato)
    g.hands[0] = ["5", "4", "4", "4", "2"]
    ui._clear_selection()
    for lay in ["land", "port"]:
        if lay == "port":
            root.size = Vector2i(900, 1600)
            await frames(6)
            ui._relayout()
        ui._redraw()
        await frames(3)
        var rs: Array = []
        for i in 5: rs.append(ui.card_rect(i, 5))
        var ok5 := true
        for i in 5:
            var r: Rect2 = rs[i]
            if r.end.x > ui.design.x - 8 or r.position.x < 0: ok5 = false
            if (not ui.portrait and (r.position.x < 1480 or r.end.y > 800)) or (ui.portrait and r.end.y > 1800): ok5 = false
            for j in range(i + 1, 5): if r.intersects(rs[j]): ok5 = false
        check(ok5 and ui.hits.filter(func(h): return String(h.id).begins_with("card_")).size() == 5, "R38.3: 5 cartas na mão sem sobrepor (%s)" % ("retrato" if ui.portrait else "paisagem"))
        if OS.get_environment("MARCHA_SHOTS") != "": root.get_texture().get_image().save_png("/tmp/claude-0/sc/hand5_%s.png" % lay)
    root.size = Vector2i(1600, 900)
    await frames(6)
    ui._relayout()
    # sair e tentar de novo no mesmo dia (sem Club)
    ui._on_hit("menu")
    ui._on_hit("menu_quit")
    await frames(3)
    var mq: Array = stage.match_history.entries.filter(func(e): return String(e.get("mode_id", "")) == "marcha_real")
    check(mq.size() == 1 and String(mq[0].result) == "abandon" and String(mq[0].ruleset_version) == "marcha-real-9" and String(mq[0].mode) == "marcha", "Marcha abandonada entra no histórico comum (mode_id + ruleset_version)")
    var again: bool = await ui.access.request_start()
    check(not again, "sem Club: 2ª partida no mesmo dia bloqueada")
    hub.entitlements.apply_server({"is_founder": false, "club_active": true, "club_expires_at": "2099-01-01T00:00:00Z"})
    await ui.access.refresh()
    check(bool(ui.gate_info.unlimited) and bool(ui.gate_info.can_play), "Club: partidas ilimitadas")
    check(await ui.access.request_start(), "Club: começa outra partida no mesmo dia")
    await ui.start_game()
    await frames(2)
    ui.g.winner = 0
    ui._finish()
    var mw: Array = stage.match_history.entries.filter(func(e): return String(e.get("mode_id", "")) == "marcha_real" and String(e.result) == "win")
    check(ui.mode == "over" and mw.size() == 1 and mw[0].get("data") is Dictionary and mw[0].data.has("crowned"), "Marcha terminada (vitória) entra no histórico com os dados do modo")
    check(stage.result_overlay.is_showing() and stage.result_overlay.result == "victory" and stage.result_overlay.layer > ui.layer and ui.overlay_wait, "R37: vitória da Marcha usa a MESMA tela de VITÓRIA da partida contra bot, por cima da mesa")
    stage.result_overlay.hide_result()
    await frames(40)
    check(not ui.overlay_wait and stage.result_overlay.layer == 60, "R37: depois da tela de VITÓRIA vem o painel da Marcha")
    ui._finish()
    check(stage.match_history.entries.filter(func(e): return String(e.get("mode_id", "")) == "marcha_real").size() == 2, "fim reportado 2× não duplica")
    hub.entitlements.clear_server()
    ui.close()
    await frames(2)
    check(not ui.visible, "VOLTAR fecha o modo")
    check(audio.music_override == "", "saindo da MARCHA REAL a música da Home volta")
    # ---------- Histórico de partidas ----------
    var Rec = preload("res://analysis/match_record.gd")
    var rec = Rec.new()
    rec.start("bot", "w", "Eu", "BOT MADEIRA")
    for u in ["e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7"]: rec.add_move(u)
    rec.finish("win", "XEQUE-MATE")
    stage._on_match_finished(rec)
    check(stage.match_history.entries.size() >= 1 and String(stage.match_history.entries[0].opponent) == "BOT MADEIRA", "partida terminada entra no histórico")
    stage._on_match_finished(rec)
    check(stage.match_history.entries.filter(func(e): return int(e.started_at) == rec.started_at and String(e.mode_id) == "chess").size() == 1, "a mesma partida não entra duas vezes")
    if stage.result_overlay != null and stage.result_overlay.has_method("hide_result"): stage.result_overlay.hide_result()
    hub.show_page("history")
    await frames(3)
    var row = hub.history_list.get_node_or_null("HistoryRow")
    check(row != null and row.find_child("HistoryAnalyze", true, false) != null, "página HISTÓRICO mostra a partida com ANALISAR")
    row.find_child("HistoryAnalyze", true, false).pressed.emit()
    await frames(3)
    check(stage.analysis_ui != null and stage.analysis_ui.visible and stage.analysis_ui.record == rec or (stage.analysis_ui != null and stage.analysis_ui.visible), "ANALISAR abre a análise da partida guardada")
    stage.analysis_ui.close()
    check(stage.match_history.entries.all(func(e): return e.has("mode_id") and e.has("ruleset_version")), "todo registro tem mode_id e ruleset_version")
    hub.history_filter = "marcha"
    hub.refresh_history()
    var mrow = hub.history_list.get_node_or_null("HistoryRow")
    check(mrow != null and mrow.find_child("HistoryAnalyze", true, false) == null and hub.history_list.get_child_count() == 2, "filtro MARCHA REAL: só partidas da Marcha, sem ANALISAR (modo de cartas)")
    # registro antigo (R32 inicial, sem mode_id) é lido como xadrez
    var MHs = preload("res://analysis/match_history.gd")
    var old = MHs.new()
    old.file = "user://_mh_old_test.json"
    var fo := FileAccess.open(old.file, FileAccess.WRITE)
    fo.store_string(JSON.stringify([{"mode": "bot", "result": "win", "started_at": 5, "plies": 3}]))
    fo.close()
    old.load_local()
    check(old.entries.size() == 1 and old.entries[0].mode_id == "chess" and old.entries[0].ruleset_version == "chess-fide-1", "histórico antigo migra para mode_id=chess")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(old.file))
    old.free()
    hub.history_filter = "ranked"
    hub.refresh_history()
    check(hub.history_list.get_node_or_null("HistoryEmpty") != null, "filtro RANQUEADAS sem partidas mostra aviso")
    hub.history_filter = "all"
    for p in BACKUP:
        var gp := ProjectSettings.globalize_path(p)
        DirAccess.remove_absolute(gp)
        if not saved[p].is_empty():
            var f := FileAccess.open(gp, FileAccess.WRITE)
            f.store_buffer(saved[p])
            f.close()
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
