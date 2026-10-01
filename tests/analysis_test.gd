extends SceneTree
## Análise pós-partida: registro de lances, fair play, cota (1/3, 2/3, 3/3, 4ª bloqueada, Club
## ilimitado), progresso/cancelamento, relatório, gráfico, navegação, melhor lance, tentar
## novamente, treine meus erros, histórico. Motor interno (sem rede). -- --mobile-test opcional.
const Notation := preload("res://analysis/notation.gd")
const Config := preload("res://analysis/analysis_config.gd")
const Book := preload("res://analysis/opening_book.gd")
const FairPlay := preload("res://analysis/fair_play.gd")
const Export := preload("res://analysis/export.gd")
var failures := 0
var checks := 0
var stage
func check(ok: bool, label: String):
    checks += 1
    print(("PASS " if ok else "FAIL ") + label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func wait_until(cond: Callable, seconds: float) -> bool:
    var end = Time.get_ticks_msec() + int(seconds * 1000)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await process_frame
    return cond.call()
func click(game, cell: Vector2i):
    var e = InputEventMouseButton.new()
    e.button_index = MOUSE_BUTTON_LEFT
    e.pressed = true
    e.position = game.square_center(cell)
    game._handle_game_input(e)
func node(n: String) -> Node:
    return stage.find_child(n, true, false)
func press(n: String) -> bool:
    var b = node(n)
    if b == null or not (b is BaseButton) or b.disabled or not b.is_visible_in_tree(): return false
    b.pressed.emit()
    return true

func run():
    var mobile := "--mobile-test" in OS.get_cmdline_user_args()
    root.size = Vector2i(390, 844) if mobile else Vector2i(1920, 1080)
    root.content_scale_size = root.size
    await process_frame
    # ---------- notação
    var pos = preload("res://chess/rules.gd").new()
    pos.reset()
    check(Notation.fen(pos) == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "FEN inicial")
    var back = Notation.from_fen("r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4")
    check(back != null and back.piece(Vector2i(2, 4)) == "wB" and back.turn == "w" and back.ply == 6, "FEN → posição")
    check(Notation.san(pos, Notation.uci_to_move("g1f3")) == "Cf3" and Notation.san(pos, Notation.uci_to_move("e2e4")) == "e4", "SAN em português")
    var castle = Notation.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    check(Notation.san(castle, Notation.uci_to_move("e1g1")) == "O-O", "SAN roque")
    check(Book.is_book(["e2e4", "e7e5", "g1f3"]) and not Book.is_book(["a2a4", "a7a5"]), "livro de aberturas")
    # ---------- classificação / precisão
    check(Config.classify(60.0, 60.0, 40.0, false, 0, true, false, false) == "brilliant", "único lance bom = EXTRAORDINÁRIO")
    check(Config.classify(60.0, 60.0, 55.0, false, 0, true, false, false) == "best", "melhor lance comum = MELHOR LANCE")
    check(Config.classify(60.0, 60.0, 30.0, false, 300, true, false, false) == "legendary", "sacrifício único = LENDÁRIO")
    check(Config.classify(99.0, 99.0, 50.0, false, 300, true, false, false) == "best", "posição já ganha não vira lendário")
    check(Config.classify(60.0, 59.0, -1, false, 0, false, false, false) == "excellent", "perda 1 = EXCELENTE")
    check(Config.classify(60.0, 56.0, -1, false, 0, false, false, false) == "good", "perda 4 = BOM")
    check(Config.classify(60.0, 52.0, -1, false, 0, false, false, false) == "inaccuracy", "perda 8 = IMPRECISÃO")
    check(Config.classify(60.0, 45.0, -1, false, 0, false, false, false) == "mistake", "perda 15 = ERRO")
    check(Config.classify(60.0, 30.0, -1, false, 0, false, false, false) == "blunder", "perda 30 = ERRO GRAVE")
    check(Config.classify(100.0, 70.0, -1, false, 0, false, false, true) == "missed", "mate perdido = OPORTUNIDADE PERDIDA")
    check(Config.classify(50.0, 0.0, -1, false, 0, false, true, false) == "blunder", "entrar em mate = ERRO GRAVE")
    check(Config.classify(10.0, 10.0, -1, true, 0, true, false, false) == "book", "livro = TEÓRICO")
    check(absf(Config.win_percent(0) - 50.0) < 0.01 and Config.win_percent(300) > 75.0 and Config.win_percent(-300) < 25.0 and Config.win_percent(0, 2) == 100.0, "win% logística")
    check(Config.accuracy([0, 0, 0], [50, 50, 50]) == 100.0 and Config.accuracy([30, 30], [50, 50]) < 40.0, "precisão: perda 0 = 100, perdas grandes caem")
    check(Config.eval_text(80, 0, "w") == "+0.8" and Config.eval_text(80, 0, "b") == "-0.8" and Config.eval_text(0, 2, "w") == "M2" and Config.eval_text(0, -2, "w") == "-M2", "texto da avaliação")

    # ---------- partida contra o computador com registro
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 8: await process_frame
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    var hub = stage.hub
    hub.monetization_state.mock_reset()
    stage.analysis_access.dev_reset()
    stage.analysis_access._load_dev()
    check(stage.recorder != null and stage.analysis_access != null and stage.analysis_engine != null, "nós de análise criados")
    stage._start_bot("easy", "w")
    for i in 3: await process_frame
    var game = stage.game
    var rec = stage.recorder.current()
    check(rec != null and rec.mode == "bot" and rec.human_color == "w" and rec.moves.is_empty(), "registro começa na partida contra o computador")
    check(not stage.analysis_available() and (node("AnalyzeButton") == null or not node("AnalyzeButton").visible), "sem ANALISAR durante a partida")
    # jogada do humano + marcar
    click(game, Vector2i(4, 6)); click(game, Vector2i(4, 4))
    for i in 2: await process_frame
    check(rec.moves.size() >= 1 and rec.moves[0] == "e2e4", "lance registrado em UCI")
    stage.mark_for_review()
    check(rec.marked == [0], "MARCAR PARA REVISAR guarda só o índice (sem engine)")
    check(not stage.analysis_engine.engine_ready, "engine não foi iniciada durante a partida")
    await wait_until(func(): return stage.bot_controller.can_interact(), 10.0)
    # Deixa o computador responder alguns lances e termina a partida por mate do pastor quando possível.
    var seq := [[Vector2i(3, 7), Vector2i(7, 3)], [Vector2i(5, 7), Vector2i(2, 4)], [Vector2i(7, 3), Vector2i(5, 1)]]
    for mv in seq:
        await wait_until(func(): return stage.bot_controller.can_interact() or game.game_over, 10.0)
        if game.game_over: break
        click(game, mv[0])
        if not game.legal_moves.has(mv[1]):
            # lance indisponível (o bot defendeu): joga o primeiro lance legal
            var alt = game.legal_moves[0] if not game.legal_moves.is_empty() else null
            if alt == null:
                click(game, mv[0])
                continue
            click(game, alt)
        else:
            click(game, mv[1])
        for i in 2: await process_frame
    # se ainda não acabou, resolve pela via local: declara fim
    if not game.game_over:
        stage.bot_controller.stop()
        game.game_over = true
        game.status = "VENCERAM AS BRANCAS"
        game.bot = null
    for i in 3: await process_frame
    check(rec.finished and rec.moves.size() >= 3, "registro termina com o fim da partida (%d lances)" % rec.moves.size())
    check(stage.analysis_available(), "ANALISAR PARTIDA disponível depois do fim")
    stage._refresh_analysis_buttons()
    check((mobile and stage.mobile_analyze.visible) or (not mobile and node("AnalyzeButton").visible), "botão ANALISAR visível no fim")
    # ---------- fair play (controle)
    var fake = preload("res://analysis/match_record.gd").new()
    fake.start("ranked", "w", "a", "b")
    check(not FairPlay.can_analyze(fake, null), "fair play: partida não terminada nunca pode ser analisada")
    fake.finish("win")
    check(FairPlay.can_analyze(fake, null), "fair play: terminada pode")

    # ---------- cota (dev local, sem servidor): 1/3, 2/3, 3/3, 4ª bloqueada
    var access = stage.analysis_access
    check(access.counter_text() == "0 / 3", "cota começa 0 / 3")
    stage.open_analysis()
    var ui = stage.analysis_ui
    check(ui != null and ui.visible, "abre a tela de análise")
    check(await wait_until(func(): return ui.page == "progress", 5.0), "página ANALISANDO")
    check(access.counter_text() == "1 / 3", "1 / 3 consumida")
    check(node("ProgressBar") != null and node("AnalysisCancel") != null and node("ProgressLabel") != null, "progresso: barra, lance, cancelar")
    check(await wait_until(func(): return ui.page == "report", 60.0), "relatório pronto (motor %s)" % stage.analysis_engine.engine_name)
    var rep = ui.report
    check(rep.moves.size() == rec.moves.size() and rep.players.has("w") and rep.players.has("b"), "relatório com todos os lances e dois jogadores")
    check(node("AccuracyMe") != null and node("AccuracyOpp") != null and "%" in node("AccuracyMe").text, "precisão VOCÊ / ADVERSÁRIO")
    check(node("EvalGraph") != null and node("ReviewBoard") != null and node("MoveListPanel") != null, "gráfico, tabuleiro e lista")
    check(node("Move_0") != null and "◆" in node("Move_0").text, "lance marcado aparece com marcador na lista")
    # lista padrão: sem rótulos/ícones de classificação; exportação dos lances
    var plain := true
    for i in rep.moves.size():
        var bt: String = node("Move_%d" % i).text.replace("  ◆", "")
        if bt != String(rep.moves[i].san): plain = false
    check(plain, "lista de lances só anota o lance (sem rótulos de classificação)")
    check(node("DetailClass") == null and node("CopyMoves") != null and node("SaveMovesText") != null and node("SaveScreenshot") != null, "sem selo de classe no detalhe; botões copiar / salvar texto / salvar print")
    check(Export.pgn_san("Cf3") == "Nf3" and Export.pgn_san("Txe1+") == "Rxe1+" and Export.pgn_san("e8=D") == "e8=Q" and Export.pgn_san("O-O") == "O-O" and Export.pgn_san("Bb5") == "Bb5" and Export.pgn_san("Rg1") == "Kg1" and Export.pgn_san("e4") == "e4", "conversão PT → PGN")
    var sans := []
    for m in rep.moves: sans.append(String(m.san))
    var txt := Export.text_of(rec, sans)
    check(txt.begins_with("FRAIHA XADREZ") and ("1. " + sans[0]) in txt and "[Result " in txt and ("1. " + Export.pgn_san(sans[0])) in txt, "texto exportado: cabeçalho, lances em português e PGN")
    press("CopyMoves")
    check(DisplayServer.clipboard_get().begins_with("FRAIHA XADREZ") or OS.has_feature("headless"), "COPIAR LANCES copia o texto")
    check(node("ExportStatus") != null and "copiad" in node("ExportStatus").text, "status de exportação atualizado")
    ui._goto(0)
    check(ui.cur_ply == 0 and node("DetailSan").text == rep.moves[0].san, "navegação para o lance 1")
    press("NavNext")
    check(ui.cur_ply == 1, "próximo lance")
    press("NavPrev")
    check(ui.cur_ply == 0, "lance anterior")
    press("NavLast")
    check(ui.cur_ply == rep.moves.size() - 1, "último lance")
    press("NavFirst")
    check(ui.cur_ply == -1, "posição inicial")
    # melhor lance (procura um lance que não foi o melhor)
    var not_best := -1
    for m in rep.moves:
        if m.best != "" and m.best != m.uci: not_best = m.ply; break
    if not_best >= 0:
        ui._goto(not_best)
        check(press("ShowBest") and ui.showing_best and ui.board.arrows.size() >= 1, "VER MELHOR LANCE: seta e casas")
        press("ShowBest")
        check(not ui.showing_best, "volta ao lance jogado")
    else:
        print("SKIP sem lance diferente do melhor")
    # tentar novamente num erro do humano (se houver), senão força um
    var err_ply := -1
    for m in rep.moves:
        if m.color == "w" and m.class in ["blunder", "mistake", "missed", "inaccuracy"]: err_ply = m.ply; break
    if err_ply < 0 and rep.moves.size() > 0:
        rep.moves[0].class = "mistake"
        err_ply = 0
    ui._goto(err_ply)
    check(press("TryAgain") and ui.trying and ui.board.interactive, "TENTAR NOVAMENTE abre tabuleiro de treino")
    var tpos = Notation.from_fen(String(rep.moves[err_ply].fen_before))
    var legal_moves = tpos.legal_moves()
    var orig_before := String(rep.moves[err_ply].fen_before)
    ui.board.move_tried.emit(legal_moves[0])
    check(await wait_until(func(): return node("TryVerdict") != null, 30.0), "lance avaliado: veredito")
    check(node("TryGrid") != null, "JOGADA ORIGINAL / SUA NOVA JOGADA / MELHOR POSSÍVEL")
    check(rec.moves[err_ply] == rep.moves[err_ply].uci and rep.moves[err_ply].fen_before == orig_before, "partida original intacta")
    press("TryBack")
    check(not ui.trying, "volta à revisão")
    # treine meus erros
    rep.moves[0].class = "blunder"
    ui.report = rep
    ui._show_page("report")
    for i in 2: await process_frame
    check(press("TrainButton"), "TREINE MEUS ERROS abre")
    await process_frame
    var tr = stage.training_ui
    check(tr != null and tr.visible and node("ExerciseTitle") != null and node("ExerciseTitle").text.begins_with("EXERCÍCIO 1 DE"), "EXERCÍCIO 1 DE N")
    var epos = Notation.from_fen(String(rep.moves[tr.exercises[0]].fen_before))
    tr.board.move_tried.emit(epos.legal_moves()[0])
    check(await wait_until(func(): return node("Verdict") != null, 30.0), "exercício avaliado")
    check(node("NextBtn") != null or node("RetryBtn") != null, "feedback com próximo/tentar novamente")
    press("TrainingBack")
    check(not tr.visible, "treino fecha")
    # histórico
    check(stage.analysis_history.entries.size() >= 1 and stage.analysis_history.entries[0].has("accuracy"), "histórico local gravado")
    ui.close()
    # cancelamento + cota 2/3 e 3/3 + 4ª bloqueada
    stage.open_analysis()
    check(await wait_until(func(): return ui.page == "progress", 5.0) and access.counter_text() == "2 / 3", "2 / 3")
    press("AnalysisCancel")
    check(not ui.visible and await wait_until(func(): return not ui.analyzer.running, 8.0), "cancelar fecha e para a análise")
    stage.open_analysis()
    check(await wait_until(func(): return ui.page == "progress", 5.0) and access.counter_text() == "3 / 3", "3 / 3")
    ui.close()
    stage.open_analysis()
    check(await wait_until(func(): return ui.page == "quota", 5.0), "4ª análise bloqueada: tela de limite")
    check(node("QuotaActivateClub") != null and node("QuotaPanel") != null, "CTA ATIVAR CLUB FRAIHA e aviso de renovação")
    ui.close()
    # Club (simulação) → ilimitado no modo dev local
    hub.monetization_state.mock_activate_club()
    for i in 2: await process_frame
    check(access.club_unlimited() and access.status_line() == "CLUB · ILIMITADO", "Club: ILIMITADO")
    stage.open_analysis()
    check(await wait_until(func(): return ui.page == "progress", 5.0), "Club: análise liberada sem contador")
    ui.close()
    hub.monetization_state.mock_reset()
    stage.analysis_access.dev_reset()
    print("ANALYSIS_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit()
