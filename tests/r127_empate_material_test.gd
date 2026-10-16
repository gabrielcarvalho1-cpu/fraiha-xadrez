extends SceneTree
## R127 · Empate contra o bot por MATERIAL INSUFICIENTE abre a animação de EMPATE (não vitória/derrota).
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/r127_empate_material_test.gd [-- --mobile-test]
## R38.3 · pontos e peças capturadas nas partidas de xadrez (valores do Chess.com: P1 N3 B3 R5 Q9).
const Rules = preload("res://chess/rules.gd")
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
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 20: await process_frame
    if stage.account_ui.is_open(): stage.account_ui.close()
    world = stage.game
    bot = stage.bot_controller
    # Rei + torre contra rei: as brancas comem a torre e sobra rei contra rei → EMPATE — MATERIAL INSUFICIENTE
    fixture("4k3/8/8/8/8/8/3r4/4K3 w - - 0 40")
    for i in 4: await process_frame
    var ok_mv: bool = bot.request_move(square("e1"), square("d2"))
    check(ok_mv, "Kxd2 aceito pelo motor")
    for i in 6: await process_frame
    check(String(world.status).begins_with("EMPATE") and "MATERIAL" in String(world.status), "tabuleiro: %s" % world.status)
    var rec = stage.recorder.current()
    check(rec != null and rec.finished and String(rec.result) == "draw", "registro da partida: EMPATE (antes virava vitória/derrota por causa do \"MATE\" de MATERIAL) [%s]" % (String(rec.result) if rec != null else "?"))
    check(stage.result_overlay.is_showing() and String(stage.result_overlay.result) == "draw", "animação de EMPATE na tela [%s]" % String(stage.result_overlay.result))
    print("RESULT " + ("OK" if failures == 0 else "%d FALHAS" % failures))
    quit(0 if failures == 0 else 1)
