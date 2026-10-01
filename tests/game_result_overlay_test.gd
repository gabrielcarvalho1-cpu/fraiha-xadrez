extends SceneTree
## Tela de resultado (VITÓRIA / DERROTA) e botão ANALISAR PARTIDA dentro da tela.
## Uso: godot --path . -s tests/game_result_overlay_test.gd [-- --mobile-test]
var checks := 0
var failures := 0
var stage
func check(ok: bool, label: String):
    checks += 1
    if ok: print("PASS " + label)
    else:
        failures += 1
        print("FAIL " + label)
func wait(sec: float):
    var end = Time.get_ticks_msec() + int(sec * 1000)
    while Time.get_ticks_msec() < end: await process_frame
func _initialize(): call_deferred("run")

func end_bot(side: String, moves: Array, status: String):
    stage._start_bot("expert", side)
    stage.bot_controller.stop()
    for i in range(4): await process_frame
    var rec = stage.recorder.current()
    rec.moves = moves
    stage.game.pieces = rec.position_after(moves.size()).board
    stage.game.turn = "w" if moves.size() % 2 == 0 else "b"
    stage.game.game_over = true
    stage.game.status = status
    stage.game.queue_redraw()
    stage._refresh_desk_hud()
    for i in range(3): await process_frame
    return rec

func run():
    var args = OS.get_cmdline_user_args()
    var mobile: bool = "--mobile-test" in args
    root.mode = Window.MODE_WINDOWED
    root.size = Vector2i(390, 844) if mobile else Vector2i(1366, 768)
    # --logical: viewport lógico = janela (como um PC em 1366x768 sem esticar); senão 1920x1080
    root.content_scale_size = root.size if (mobile or "--logical" in args) else Vector2i(1920, 1080)
    await process_frame
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(10): await process_frame
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    var ov = stage.result_overlay
    check(ov != null and ov.name == "GameResultOverlay" and ov.layer == 60, "GameResultOverlay existe acima do HUD (layer 60)")
    check(not ov.visible, "começa escondida")
    # 1) humano de PRETAS, brancas dão mate → DERROTA (resultado real, não a cor)
    var rec = await end_bot("b", ["e2e4", "f7f6", "d2d4", "g7g5", "d1h5"], "XEQUE-MATE! BRANCAS VENCEM")
    check(rec.finished and rec.result == "loss", "registro: derrota do humano (pretas)")
    check(ov.visible and ov.is_showing() and ov.result == "defeat", "tela DERROTA aparece")
    await wait(1.0)
    check(ov.art.modulate.a > 0.9 and absf(ov.art.scale.x - 1.0) < 0.05, "arte entrou (fade + scale concluídos)")
    var vs = stage.get_viewport_rect().size
    var big: bool = (ov.art.size.y >= vs.y * 0.6 and ov.art.size.y <= vs.y * 0.75) or (mobile and ov.art.size.x >= vs.x * 0.85)
    check(big and ov.art.size.x <= vs.x * 0.95, "arte ocupa ~60–70%% da tela (%.0f x %.0f em %.0f x %.0f)" % [ov.art.size.x, ov.art.size.y, vs.x, vs.y])
    var c = ov.art.position + ov.art.size / 2.0
    check(absf(c.x - vs.x / 2.0) < 2.0 and absf(c.y - vs.y / 2.0) < vs.y * 0.05, "arte centralizada sobre o tabuleiro")
    check(stage.game.game_over and String(stage.game.status).begins_with("XEQUE-MATE"), "estado de xeque-mate preservado; texto inferior continua")
    # botão ANALISAR PARTIDA dentro da tela (desktop)
    if not mobile:
        var panel = stage.desk_panel
        check(panel.visible and panel.position.x + panel.size.x <= vs.x - 8.0 and panel.position.x >= 0.0, "cartão com ANALISAR PARTIDA cabe na tela (direita = %.0f de %.0f)" % [panel.position.x + panel.size.x, vs.x])
        check(stage.desk_analyze.visible, "ANALISAR PARTIDA visível após o fim")
    # dismiss por clique
    var ev := InputEventMouseButton.new()
    ev.button_index = MOUSE_BUTTON_LEFT
    ev.pressed = true
    ov._on_input(ev)
    await wait(0.7)
    check(not ov.visible and not ov.is_showing(), "some ao clicar")
    # 2) humano de PRETAS, pretas dão mate → VITÓRIA
    rec = await end_bot("b", ["f2f3", "e7e5", "g2g4", "d8h4"], "XEQUE-MATE! PRETAS VENCEM")
    check(rec.result == "win" and ov.visible and ov.result == "victory", "tela VITÓRIA para o humano de pretas quando as pretas vencem")
    ov.hide_result()
    await wait(0.6)
    # 3) humano de BRANCAS, brancas dão mate → VITÓRIA (compara vencedor com a cor do jogador)
    rec = await end_bot("w", ["e2e4", "f7f6", "d2d4", "g7g5", "d1h5"], "XEQUE-MATE! BRANCAS VENCEM")
    check(rec.result == "win" and ov.visible and ov.result == "victory", "tela VITÓRIA para o humano de brancas quando as brancas vencem")
    ov.hide_result()
    await wait(0.6)
    # 4) empate → nenhuma tela
    rec = await end_bot("w", ["e2e4", "e7e5"], "EMPATE — AFOGAMENTO")
    check(rec.result == "draw" and not ov.visible, "empate não abre a tela")
    # 5) partida local (dois humanos) → nenhuma tela
    stage._start_local()
    for i in range(4): await process_frame
    rec = stage.recorder.current()
    rec.moves = ["e2e4", "f7f6", "d2d4", "g7g5", "d1h5"]
    stage.game.pieces = rec.position_after(5).board
    stage.game.turn = "b"
    stage.game.game_over = true
    stage.game.status = "XEQUE-MATE! BRANCAS VENCEM"
    for i in range(3): await process_frame
    check(rec.finished and not ov.visible, "partida local não abre a tela")
    # 6) valor inválido ignorado; componente reutilizável
    ov.show_result("banana")
    check(not ov.visible, "show_result só aceita victory | defeat")
    ov.show_result("victory")
    check(ov.visible and ov.result == "victory", "show_result('victory') direto (componente reutilizável)")
    ov.hide_result()
    await wait(0.6)
    print("GAME_RESULT_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit()
