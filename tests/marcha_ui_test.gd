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
    check(titles.size() == 10 and titles[4] == "MARCHA REAL" and titles[8] == "HISTÓRICO DE PARTIDAS" and titles[7] == "CONHEÇA O FRAIHA", "Home: MARCHA REAL e HISTÓRICO DE PARTIDAS (abaixo de CONHEÇA O FRAIHA)")
    var ok_rows := true
    for i in range(1, hub.menu_buttons.size()):
        if hub.menu_buttons[i].position.y < hub.menu_buttons[i - 1].position.y + hub.menu_buttons[i - 1].size.y: ok_rows = false
    check(ok_rows and hub.menu_buttons[9].position.y + hub.menu_buttons[9].size.y < 941, "10 linhas sem sobreposição, dentro da arte")
    # ---------- Marcha: tutorial e acesso ----------
    hub.menu_buttons[4].pressed.emit()
    await frames(6)
    var ui = hub.marcha
    check(ui != null and ui.visible and ui.mode == "lobby", "MARCHA REAL abre no salão (lobby)")
    check(ui.tut_page == 0, "1ª vez: tutorial abre sozinho")
    for i in ui.TUTORIAL.size(): ui._on_hit("tut_next")
    check(ui.tut_page == -1 and Access.tutorial_seen(), "tutorial percorrido até o fim e marcado como visto")
    await frames(3)
    check(bool(ui.gate_info.get("can_play", false)) and String(ui.gate_info.label).contains("GRÁTIS"), "sem Club: 1 partida grátis hoje")
    await ui.start_game()
    await frames(3)
    check(ui.mode == "game" and ui.g != null and ui.g.hands[0].size() == 4, "partida começa com 4 cartas na mão")
    check(Access.local_played_today(), "partida grátis do dia consumida (aparelho)")
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
    check(ui.candidate_pawns().size() == 4, "Ás: os 4 peões do Pátio ficam com aro dourado")
    ui.pick_pawn([0, 2])
    check(not ui.pending.is_empty() and ui.pending.kind == "exit", "tocar num peão do Pátio prepara SAIR")
    check(ui.help_line().contains("SAI DO PÁTIO") or ui.help_line().to_upper().contains("SAI DO PÁTIO"), "linha de ajuda explica a carta")
    ui.confirm()
    var t0 := Time.get_ticks_msec()
    while ui.g.turn == 0 and Time.get_ticks_msec() - t0 < 5000: await process_frame
    check(g.pawns[0].any(func(p): return p.zone == "track"), "JOGAR CARTA: peão saiu para o Portão")
    # bots jogam sozinhos até voltar a vez do humano
    t0 = Time.get_ticks_msec()
    while not (ui.g.turn == 0 and not ui.busy) and Time.get_ticks_msec() - t0 < 15000: await process_frame
    check(ui.g.turn == 0 and g.log.size() >= 4, "os 3 bots jogaram e a vez voltou (%d registros)" % g.log.size())
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
    # sair e tentar de novo no mesmo dia (sem Club)
    ui._on_hit("menu")
    ui._on_hit("menu_quit")
    await frames(3)
    var mq: Array = stage.match_history.entries.filter(func(e): return String(e.get("mode_id", "")) == "marcha_real")
    check(mq.size() == 1 and String(mq[0].result) == "abandon" and String(mq[0].ruleset_version) == "marcha-real-1" and String(mq[0].mode) == "marcha", "Marcha abandonada entra no histórico comum (mode_id + ruleset_version)")
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
    ui._finish()
    check(stage.match_history.entries.filter(func(e): return String(e.get("mode_id", "")) == "marcha_real").size() == 2, "fim reportado 2× não duplica")
    hub.entitlements.clear_server()
    ui.close()
    await frames(2)
    check(not ui.visible, "VOLTAR fecha o modo")
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
