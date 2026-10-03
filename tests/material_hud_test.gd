extends SceneTree
## R38.3 · pontos e peças capturadas nas partidas de xadrez (valores do Chess.com: P1 N3 B3 R5 Q9).
const Rules = preload("res://chess/rules.gd")
const Mat = preload("res://presentation_v019/material_hud.gd")
var checks := 0
var failures := 0
var stage
var world
var bot

func _initialize():
    call_deferred("run")

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func square(cell: String) -> Vector2i:
    return Vector2i("abcdefgh".find(cell[0]), 8 - int(cell[1]))

func board_of(fen: String) -> Dictionary:
    var out := {}
    var ranks = fen.split(" ")[0].split("/")
    for y in 8:
        var x := 0
        for ch in ranks[y]:
            if ch.is_valid_int(): x += int(ch)
            else:
                out[Vector2i(x, y)] = ("w" if ch == ch.to_upper() else "b") + ch.to_upper()
                x += 1
    return out

func fixture(fen: String, side := "w"):
    stage._start_bot("easy", side)
    var position = Rules.new()
    var fields = fen.split(" ")
    position.board = board_of(fen)
    position.turn = fields[1]
    position.rights = "" if fields[2] == "-" else fields[2]
    position.ep = Rules.EMPTY if fields[3] == "-" else square(fields[3])
    position.halfmove = int(fields[4])
    position.repetitions = {position.position_key(): 1}
    bot.rules = position
    bot.thinking = position.turn != bot.human_color
    bot._sync_view()

func run():
    # ---------- cálculo (só o tabuleiro) ----------
    var s0 := Mat.summarize(board_of("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))
    check(int(s0.diff) == 0 and s0.captured_by.w.is_empty() and s0.captured_by.b.is_empty() and int(s0.material.w) == 39, "início: 39 pontos cada, nada capturado")
    var s1 := Mat.summarize(board_of("r1bqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))
    check(s1.captured_by.w == ["bN"] and int(s1.diff) == 3, "brancas capturaram um cavalo: +3")
    var s2 := Mat.summarize(board_of("rnb1kbnr/pppppppp/8/8/8/8/1PPPPPP1/R1BQKBN1 w Qkq - 0 1"))
    check(int(s2.points.w) == 9 and int(s2.points.b) == 10, "pontos capturados: brancas 9 (dama), pretas 10 (2 peões + cavalo + torre)")
    check(s2.captured_by.b == ["wP", "wP", "wN", "wR"] and s2.captured_by.w == ["bQ"] and int(s2.diff) == 9 - (1 + 1 + 3 + 5), "ordem como no Chess.com (peões, cavalos, bispos, torres, dama) e saldo %d" % int(s2.diff))
    var s3 := Mat.summarize(board_of("Q3k3/8/8/8/8/8/1PPPPPPP/RNBQKBNR w KQ - 0 1"))
    check(s3.captured_by.b.is_empty() and int(s3.material.w) == 39 - 1 + 9, "peão promovido a dama: não conta como peão capturado; a dama nova entra no material")
    # ---------- na partida contra o bot ----------
    root.size = Vector2i(1600, 900)
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 10: await process_frame
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    world = stage.get_node("World")
    bot = stage.bot_controller
    stage.get_node("MainHub").play_bot_requested.emit("easy", "w")
    for i in 5: await process_frame
    var mh = stage.material_hud
    check(mh != null and mh.visible and mh.top_rect.size.x > 0 and mh.bottom_rect.size.x > 0, "faixas de capturas aparecem na partida contra o bot")
    var mobile_run: bool = preload("res://ui_v022/mobile_layout.gd").active(root)
    var board := Rect2(world.position + world.ORIGIN * world.scale.x, Vector2.ONE * world.BOARD * world.scale.x)
    if not mobile_run: check(not mh.top_rect.intersects(board) and not mh.bottom_rect.intersects(board) and mh.top_rect.end.x <= stage.get_viewport_rect().size.x and mh.top_rect.position.y < mh.bottom_rect.position.y, "faixas ao lado do tabuleiro (adversário em cima, você embaixo), dentro da tela")
    if not mobile_run: check(not mh.top_rect.intersects(stage.desk_panel.get_global_rect()) and not mh.bottom_rect.intersects(stage.desk_panel.get_global_rect()), "faixas não cobrem o cartão do jogador")
    fixture("rnb1kbnr/pppppppp/8/8/8/8/1PPPPPP1/R1BQKBN1 w Qkq - 0 1")
    for i in 4: await process_frame
    check(mh.advantage_for("w") == -1 and mh.my_color() == "w", "partida: você (brancas) está -1 (perdeu P,P,N,R = 10; ganhou a dama = 9)")
    if OS.get_environment("MAT_SHOTS") != "": root.get_texture().get_image().save_png("/tmp/claude-0/sc/mat_bot_w.png")
    fixture("rnbqkbnr/ppp2ppp/8/8/8/8/PPPP1PPP/RNB1KBNR b KQkq - 0 1", "b")
    for i in 4: await process_frame
    check(mh.my_color() == "b" and mh.advantage_for("b") == 8, "jogando de pretas: as faixas trocam de lado (+8 para você)")
    if OS.get_environment("MAT_SHOTS") != "": root.get_texture().get_image().save_png("/tmp/claude-0/sc/mat_bot_b.png")
    # lance real com captura atualiza a faixa
    fixture("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2")
    for i in 3: await process_frame
    var ok_mv: bool = bot.request_move(square("e4"), square("d5"))
    check(ok_mv, "lance exd5 aceito pelo motor")
    for i in 3: await process_frame
    var sm := Mat.summarize(world.pieces)
    check(sm.captured_by.w == ["bP"] and mh.advantage_for("w") == 1, "captura de verdade (exd5): faixa mostra o peão e +1")
    if not mobile_run:
        # online / ranqueada no desktop: faixas coladas nas faixas de nome+relógio, sem cobrir RENDER-SE
        var keep_mode: String = stage.mode
        stage.mode = "casual"
        stage._layout()
        var ui = stage.casual_ui
        var rs: Array = [ui.strips.top.bg.get_global_rect(), ui.strips.bottom.bg.get_global_rect(), Rect2(ui.resign_button.position, ui.resign_button.size)]
        var clear := true
        for r in rs:
            if mh.top_rect.intersects(r) or mh.bottom_rect.intersects(r): clear = false
        check(clear and absf(mh.top_rect.position.x - ui.strips.top.bg.position.x) < 1.0, "online/ranqueada: faixas abaixo do nome do adversário e acima do seu, sem cobrir relógio nem RENDER-SE")
        stage.mode = keep_mode
        stage._layout()
        stage.return_to_home()
        print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
        quit(failures)
        return
    # celular em retrato (rodar com -- --mobile-test): faixas acima e abaixo do tabuleiro, sem cobrir nada
    root.size = Vector2i(430, 900)
    for i in 8: await process_frame
    stage._layout()
    for i in 3: await process_frame
    board = Rect2(world.position + world.ORIGIN * world.scale.x, Vector2.ONE * world.BOARD * world.scale.x)
    check(mh.compact and mh.top_rect.end.y <= board.position.y + 2.0 and mh.bottom_rect.position.y >= board.end.y - 2.0 and mh.bottom_rect.end.y <= stage.player_card.position.y + 2.0, "retrato: faixas logo acima e logo abaixo do tabuleiro")
    if OS.get_environment("MAT_SHOTS") != "": root.get_texture().get_image().save_png("/tmp/claude-0/sc/mat_portrait.png")
    root.size = Vector2i(900, 430)
    for i in 8: await process_frame
    stage._layout()
    for i in 3: await process_frame
    board = Rect2(world.position + world.ORIGIN * world.scale.x, Vector2.ONE * world.BOARD * world.scale.x)
    check(not mh.top_rect.intersects(board) and not mh.bottom_rect.intersects(board) and mh.top_rect.end.y <= mh.bottom_rect.position.y, "celular deitado: faixas na coluna ao lado do tabuleiro")
    if OS.get_environment("MAT_SHOTS") != "": root.get_texture().get_image().save_png("/tmp/claude-0/sc/mat_landscape.png")
    root.size = Vector2i(1600, 900)
    for i in 6: await process_frame
    stage.return_to_home()
    for i in 4: await process_frame
    check(not mh.visible or stage.mode == "bot", "fora da partida as faixas somem")
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
