extends SceneTree
## Animação do lance + destaque de origem/destino (world.gd show_move) — só apresentação.
## Usa as REGRAS reais do bot (bot/rules.gd via controller) e o tabuleiro real (world.tscn).
## Rodar: FRAIHA_SERVER_URL=ws://127.0.0.1:9 xvfb-run -a godot --path . -s tests/move_animation_test.gd
var checks := 0
var failures := 0
var world

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize(): call_deferred("run")

func frames(n := 2):
    for i in n: await process_frame

func sq(n: String) -> Vector2i:
    return Vector2i(n.unicode_at(0) - 97, 8 - int(n.substr(1, 1)))

func board(spec: Dictionary) -> Dictionary:
    var b := {}
    for k in spec: b[sq(k)] = spec[k]
    return b

## Aplica `after` como o jogo faz (pieces já com o resultado) e chama show_move.
func play(before: Dictionary, after: Dictionary, f: String, t: String, emph := true, drag := false):
    world.pieces = after.duplicate()
    world.show_move(before, sq(f), sq(t), emph, drag)

func wait_anim():
    var t0 := Time.get_ticks_msec()
    while world.move_animating() and Time.get_ticks_msec() - t0 < 3000: await process_frame
    return Time.get_ticks_msec() - t0

func run():
    world = load("res://world.tscn").instantiate()
    root.add_child(world)
    await frames(3)
    world.game_started = true

    # ---------- lance normal ----------
    var before := board({"e2": "wP", "e8": "bK", "e1": "wK"})
    var after := board({"e4": "wP", "e8": "bK", "e1": "wK"})
    play(before, after, "e2", "e4")
    check(world.move_animating(), "normal: animação começa")
    check(world.last_from == sq("e2") and world.last_to == sq("e4"), "normal: origem e2 / destino e4 corretos")
    check(world.move_anim.size() == 1 and world.move_anim[0].code == "wP" and world.move_hidden.has(sq("e4")), "normal: peça viaja (destino escondido até chegar)")
    var p0: Vector2 = world.move_anim[0].from
    var p1: Vector2 = world.move_anim[0].to
    check(p0 == world.square_center(sq("e2")) and p1 == world.square_center(sq("e4")), "normal: trajeto da casa de origem até a de destino")
    await frames(4)
    var mid: float = world._ease_move(world.move_anim_t)
    check(world.move_anim_t > 0.0 and world.move_anim_t < 1.0 and mid > 0.0 and mid < 1.0, "normal: durante o lance a peça está entre as casas")
    var ms = await wait_anim()
    check(world.MOVE_ANIM >= 0.45 and world.MOVE_ANIM <= 0.7, "normal: duração configurada %d ms (R38: alvo 450–700 ms, mais fácil de acompanhar)" % int(world.MOVE_ANIM * 1000))
    check(ms >= 120 and ms <= 700, "normal: animação realmente leva tempo (%d ms medidos após 4 frames)" % ms)
    check(world.move_hidden.is_empty() and world.move_anim.is_empty(), "normal: ao terminar a peça fica na casa (nada escondido)")
    check(world.last_move_emph and world.last_move_age < 1.0, "normal: destaque forte do lance do adversário ativo")

    # ---------- destaque: forte → esmaece → residual; novo lance substitui ----------
    world.last_move_age = world.LAST_MOVE_HOLD + world.LAST_MOVE_FADE + 0.1
    check(world.last_from == sq("e2"), "destaque residual mantém o último lance (discreto)")
    before = after.duplicate()
    after = board({"e4": "wP", "d8": "bK", "e1": "wK"})
    play(before, after, "e8", "d8")
    check(world.last_from == sq("e8") and world.last_to == sq("d8") and world.last_move_age < 0.1, "próximo lance substitui o destaque anterior (sem destaque antigo)")
    await wait_anim()

    # ---------- captura ----------
    before = board({"d4": "wQ", "d7": "bR", "e8": "bK", "e1": "wK"})
    after = board({"d7": "wQ", "e8": "bK", "e1": "wK"})
    play(before, after, "d4", "d7")
    check(world.move_fades.size() == 1 and world.move_fades[0].code == "bR" and world.move_fades[0].at == world.square_center(sq("d7")), "captura: peça capturada esmaece na casa de destino")
    check(world.move_anim.size() == 1 and world.move_anim[0].code == "wQ", "captura: atacante anima até o destino")
    await wait_anim()
    check(world.move_fades.is_empty(), "captura: peça capturada sai no fim do movimento")

    # ---------- roque ----------
    before = board({"e1": "wK", "h1": "wR", "e8": "bK"})
    after = board({"g1": "wK", "f1": "wR", "e8": "bK"})
    play(before, after, "e1", "g1")
    var codes := []
    for m in world.move_anim: codes.append(m.code)
    check(world.move_anim.size() == 2 and "wK" in codes and "wR" in codes, "roque: rei E torre animados")
    var rook = world.move_anim.filter(func(m): return m.code == "wR")[0]
    check(rook.from == world.square_center(sq("h1")) and rook.to == world.square_center(sq("f1")), "roque: torre h1 → f1")
    check(world.last_from == sq("e1") and world.last_to == sq("g1"), "roque: casas do rei destacadas")
    await wait_anim()

    # ---------- promoção ----------
    before = board({"a7": "wP", "e8": "bK", "e1": "wK"})
    after = board({"a8": "wQ", "e8": "bK", "e1": "wK"})
    play(before, after, "a7", "a8")
    check(world.move_anim[0].code == "wP" and world.move_hidden.has(sq("a8")), "promoção: o PEÃO viaja; a dama só aparece no fim")
    await wait_anim()
    check(not world.move_hidden.has(sq("a8")) and world.pieces[sq("a8")] == "wQ", "promoção: troca para a peça promovida depois da animação")

    # ---------- en passant ----------
    before = board({"e5": "wP", "d5": "bP", "e8": "bK", "e1": "wK"})
    after = board({"d6": "wP", "e8": "bK", "e1": "wK"})
    play(before, after, "e5", "d6")
    check(world.move_fades.size() == 1 and world.move_fades[0].at == world.square_center(sq("d5")), "en passant: peão capturado (d5, fora do destino) esmaece na casa certa")
    await wait_anim()

    # ---------- lance próprio arrastado: não anima de novo ----------
    before = board({"g1": "wN", "e8": "bK", "e1": "wK"})
    after = board({"f3": "wN", "e8": "bK", "e1": "wK"})
    play(before, after, "g1", "f3", false, true)
    check(not world.move_animating() and not world.last_move_emph and world.last_to == sq("f3"), "lance próprio arrastado: sem re-animação, só o marcador discreto")

    # ---------- bot real (controller + regras) ----------
    world.clear_last_move()
    var ctrl = load("res://bot/controller.gd").new()
    root.add_child(ctrl)
    ctrl.game = world
    world.bot = ctrl
    ctrl.start(world, "madeira", "w")
    await frames(2)
    ctrl.thinking = false
    check(world.last_from == Vector2i(-1,-1), "nova partida: nenhum destaque antigo")
    check(ctrl.request_move(sq("e2"), sq("e4")), "bot: lance do humano aceito pelas regras")
    check(world.last_to == sq("e4") and not world.last_move_emph, "bot: lance do humano = marcador discreto")
    # resposta do bot pelas regras reais (sem engine: usa o 1º lance legal)
    var reply: Dictionary = ctrl.rules.legal_moves()[0]
    ctrl.thinking = false
    ctrl._apply(reply)
    check(world.last_from == reply.from and world.last_to == reply.to and world.last_move_emph, "bot: lance do BOT com origem/destino corretos e destaque forte")
    check(world.move_animating(), "bot: lance do bot animado")
    ctrl.stop()

    # ---------- remoto (casual online: mesmo caminho do client.gd) ----------
    world.bot = null
    var client = load("res://online_v020/client.gd").new()
    client.color = "w"
    world.pieces = board({"e4": "wP", "e7": "bP", "e8": "bK", "e1": "wK"})
    world.move_count = 1
    var state := {"type": "state", "revision": 2, "started": true, "white_connected": true, "black_connected": true,
        "board": [[4, 4, "wP"], [4, 3, "bP"], [4, 0, "bK"], [4, 7, "wK"]], "turn": "w", "status": "SUA VEZ", "game_over": false,
        "promotion_pending": false, "promotion_color": "w", "promotion_cell": [-1, -1], "last_from": [4, 1], "last_to": [4, 3],
        "captured_white": [], "captured_black": [], "move_count": 2, "restart_votes": []}
    client.game = world
    client.receive(state)
    check(world.last_from == sq("e7") and world.last_to == sq("e5") and world.last_move_emph, "remoto: lance do adversário online com origem/destino e destaque forte")
    check(world.move_animating() and world.move_anim[0].code == "bP", "remoto: peça do adversário animada")
    client.free()

    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
