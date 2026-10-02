extends SceneTree
## BLEFE REAL na interface: entrada pela Home, tutorial, partida completa contra 3 bots, seleção de
## cartas, JOGAR/XEQUE travados contra toque duplo, tempo esgotado, XEQUE-MATE, abandono e
## histórico comum (mode_id = blefe_real, ruleset_version = 1, sem ANALISAR).
const Rules := preload("res://blefe/rules.gd")
const BACKUP := ["user://match_history.json"]
var checks := 0
var failures := 0
var saved := {}

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize(): call_deferred("run")

func frames(n := 3):
    for i in n: await process_frame

func touch(view: Control, ui, design_pos: Vector2):
    # o mesmo toque chega como toque + clique emulado (como no celular)
    var p: Vector2 = ui.origin + design_pos * ui.k
    var t := InputEventScreenTouch.new()
    t.pressed = true
    t.position = p
    view._gui_input(t)
    var m := InputEventMouseButton.new()
    m.button_index = MOUSE_BUTTON_LEFT
    m.pressed = true
    m.position = p
    view._gui_input(m)

func hit_center(ui, id: String) -> Vector2:
    for h in ui.hits:
        if String(h.id) == id: return Rect2(h.rect).get_center()
    return Vector2(-1, -1)

func run():
    for p in BACKUP:
        var gp := ProjectSettings.globalize_path(p)
        saved[p] = FileAccess.get_file_as_bytes(gp) if FileAccess.file_exists(gp) else PackedByteArray()
        DirAccess.remove_absolute(gp)
    root.size = Vector2i(1920, 1080)
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await frames(20)
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    var hub = stage.hub
    # ---------- Home ----------
    var titles: Array = hub.menu_buttons.map(func(b): return hub.title_of(b))
    check(titles.size() == 11 and titles[5] == "BLEFE REAL", "Home: BLEFE REAL logo abaixo da MARCHA REAL (11 linhas)")
    hub.menu_buttons[5].pressed.emit()
    await frames(6)
    var ui = hub.blefe
    check(ui != null and ui.visible and ui.mode == "tutorial", "BLEFE REAL abre no tutorial")
    check(hit_center(ui, "tut_play") != Vector2(-1, -1) and hit_center(ui, "tut_back") != Vector2(-1, -1), "tutorial com JOGAR AGORA e VOLTAR")
    ui.seed_override = 77
    ui._on_hit("tut_play")
    await frames(3)
    var g: Rules = ui.g
    check(ui.mode == "game" and g != null and g.hands[0].size() == 5 and g.state == Rules.TURN_WAITING, "JOGAR AGORA: partida com 5 cartas na mão")
    check(g.names[1] == "Dama de Ferro" and g.names[2] == "Sir Gambito" and g.names[3] == "Torre Velha", "3 bots da referência à mesa")
    # ---------- vez do humano: seleção, JOGAR travado ----------
    g.turn = 0
    g.last_play = {}
    ui._begin_turn()
    await frames(2)
    check(not ui.can_human_play() and not ui.can_human_challenge(), "sem carta escolhida: JOGAR desabilitado; sem jogada anterior: XEQUE desabilitado")
    ui.toggle_card(0); ui.toggle_card(1); ui.toggle_card(2); ui.toggle_card(3)
    check(ui.selected.size() == 3, "no máximo 3 cartas selecionadas")
    ui.toggle_card(1)
    check(ui.selected.size() == 2 and not (1 in ui.selected), "tocar de novo tira a carta da seleção")
    await frames(2)
    var before: int = g.hands[0].size()
    var play_pos := hit_center(ui, "play")
    check(play_pos != Vector2(-1, -1), "JOGAR CARTAS habilitado com 1 a 3 cartas")
    touch(ui.view, ui, play_pos)
    touch(ui.view, ui, play_pos)
    check(g.hands[0].size() == before - 2 and g.plays.size() == 1, "toque duplo em JOGAR: uma jogada só (2 cartas)")
    check(not ui.bubble.is_empty() and int(ui.bubble.count) == 2, "balão \"2 × peça\" do jogador")
    # ---------- toque na carta: o toque duplo não seleciona e desseleciona ----------
    g.turn = 0
    g.last_play = {"seat": 3, "cards": ["rei"], "count": 1}
    g.plays.append(g.last_play)
    ui._begin_turn()
    await frames(2)
    var cpos := hit_center(ui, "card_0")
    touch(ui.view, ui, cpos)
    check(ui.selected == [0], "toque numa carta seleciona uma vez só (sem o clique emulado desfazer)")
    ui.selected = []
    # ---------- XEQUE do humano com o relógio no xeque-mate ----------
    g.target = "rainha"
    g.last_play = {"seat": 3, "cards": ["rei", "rainha"], "count": 2}
    g.plays.append(g.last_play)
    g.clocks[3] = [Rules.MATE, Rules.SAFE, Rules.SAFE]
    var lives3: int = g.lives[3]
    await frames(2)
    var xp := hit_center(ui, "xeque")
    check(xp != Vector2(-1, -1) and ui.can_human_challenge(), "XEQUE habilitado na jogada anterior de outro jogador")
    touch(ui.view, ui, xp)
    touch(ui.view, ui, xp)
    check(ui.phase == "reveal" and ui.input_locked and int(ui.result.loser) == 3 and not bool(ui.result.truthful), "XEQUE: revela, blefe pego (Rei + Rainha), entradas travadas")
    check(g.lives[3] == lives3 - 1, "o motor já resolveu: Torre Velha perdeu 1 Coroa (animação não é a autoridade)")
    ui.toggle_card(0)
    check(ui.selected.is_empty(), "durante a resolução nenhuma carta pode ser escolhida")
    ui._advance_phase()
    check(ui.phase == "clock" and ui.seat_status(3).id == "com_o_relogio", "Relógio de Xeque: placa COM O RELÓGIO")
    ui._advance_phase()
    check(ui.phase == "mate" and ui.seat_status(3).id == "xeque_mate" and ui.clock_visual(3) == "disparado", "XEQUE-MATE: relógio disparado e placa XEQUE-MATE!")
    await frames(2)
    ui.skip_presentation()
    check(ui.phase == "" and g.round_no >= 2 and g.state == Rules.TURN_WAITING and g.turn == 3, "nova rodada começa por quem perdeu o desafio")
    # ---------- tempo esgotado ----------
    g.turn = 0
    g.last_play = {"seat": 2, "cards": ["cavalo"], "count": 1}
    g.plays.append(g.last_play)
    ui._begin_turn()
    var n0: int = g.hands[0].size()
    var reveals0: int = g.reveals.size()
    ui.turn_left_ms = 5
    ui._process(0.02)
    check(g.hands[0].size() == n0 - 1 and g.reveals.size() == reveals0 and int(g.last_play.seat) == 0, "tempo esgotado: joga 1 carta, nunca XEQUE")
    # ---------- partida completa só com bots + humano automático ----------
    var guard := 0
    while ui.mode == "game" and guard < 6000:
        guard += 1
        if ui.phase != "":
            ui.skip_presentation()
        elif g.state == Rules.TURN_WAITING and g.turn == 0:
            # humano joga 1 carta ou dá XEQUE, sempre pela interface
            if g.can_challenge(0) and guard % 3 == 0: ui.human_challenge()
            else:
                ui.toggle_card(0)
                ui.human_play()
        elif g.state == Rules.TURN_WAITING:
            ui._bot_act()
        g = ui.g
    check(ui.mode == "over" and g.state == Rules.MATCH_END and g.winner >= 0, "partida inteira termina (%d passos, %d rodadas)" % [guard, g.round_no])
    check(g.alive_seats().size() == 1 and g.placement(g.winner) == 1, "último com Coroa é o vencedor")
    var mh = stage.match_history
    var rows: Array = mh.entries.filter(func(e): return String(e.get("mode_id", "")) == "blefe_real")
    check(rows.size() == 1 and String(rows[0].ruleset_version) == "1" and String(rows[0].mode) == "blefe" and String(rows[0].result) in ["win", "loss"], "histórico comum: mode_id blefe_real, ruleset_version 1")
    check(int(rows[0].players) == 4 and int(rows[0].placement) >= 1 and rows[0].has("duration_s") and int(rows[0].data.winner_player_id) == g.winner and rows[0].data.final.size() == 4, "histórico: jogadores, posição final, duração, vencedor e estado final dos 4")
    await frames(2)
    check(hit_center(ui, "again") != Vector2(-1, -1) and hit_center(ui, "over_menu") != Vector2(-1, -1), "resultado: JOGAR NOVAMENTE e VOLTAR AO MENU")
    # ---------- jogar novamente e abandonar ----------
    ui._on_hit("again")
    await frames(2)
    check(ui.mode == "game" and ui.g != null and ui.g.round_no == 1, "JOGAR NOVAMENTE começa outra partida")
    ui._on_hit("menu")
    ui._on_hit("menu_quit")
    check(ui.confirm_quit and ui.mode == "game", "sair pede confirmação")
    ui._on_hit("quit_no")
    check(not ui.confirm_quit and ui.mode == "game", "cancelar mantém a partida")
    ui._on_hit("menu")
    ui._on_hit("menu_quit")
    ui._on_hit("quit_yes")
    await frames(2)
    rows = mh.entries.filter(func(e): return String(e.get("mode_id", "")) == "blefe_real")
    check(not ui.visible and ui.g == null and rows.size() == 2 and String(rows[0].result) == "abandon", "confirmar: abandono registrado, partida encerrada (sem partida fantasma)")
    # ---------- histórico ----------
    hub.show_page("history")
    hub.history_filter = "blefe"
    hub.refresh_history()
    await frames(2)
    var row = hub.history_list.get_node_or_null("HistoryRow")
    check(row != null and row.find_child("HistoryAnalyze", true, false) == null and hub.history_list.get_child_count() == 2, "filtro BLEFE REAL: 2 partidas, sem ANALISAR")
    hub.history_filter = "all"
    # ---------- formatos ----------
    hub.open_blefe()
    for sz in [Vector2i(1080, 1920), Vector2i(1950, 900), Vector2i(1920, 1080)]:
        root.size = sz
        await frames(3)
        ui._relayout()
        check(ui.layout == {Vector2i(1080, 1920): "portrait", Vector2i(1950, 900): "landscape", Vector2i(1920, 1080): "desktop"}[sz], "formato %dx%d → %s" % [sz.x, sz.y, ui.layout])
    ui.close()
    for p in BACKUP:
        var gp := ProjectSettings.globalize_path(p)
        DirAccess.remove_absolute(gp)
        if not saved[p].is_empty():
            var f := FileAccess.open(gp, FileAccess.WRITE)
            f.store_buffer(saved[p])
            f.close()
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
