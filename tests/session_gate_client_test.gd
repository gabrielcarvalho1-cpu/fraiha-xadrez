extends SceneTree
## R42 · GATE de sessão com cliente Godot REAL: conta logada em partida Casual atravessando a
## revalidação de 60 s do servidor e uma renovação de token (acct_auth de novo, mesma conta).
var failures = 0
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func wait_until(cond: Callable, seconds: float) -> bool:
    var end = Time.get_ticks_msec() + int(seconds * 1000)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await process_frame
    return cond.call()
func run():
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(6): await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    var nick = "Sess%d" % (Time.get_ticks_msec() % 100000)
    acc.access_token = "dev:" + nick
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada")
    if acc.needs_nickname: acc.create_profile(nick)
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    stage.hub.play_online_requested.emit()
    await wait_until(func(): return stage.casual_ui.panel_open(), 4.0)
    await process_frame
    var q = stage.casual_ui.box.find_child("Queue_casual_10min", true, false)
    check(q != null and not q.disabled, "fila Casual 10 min habilitada (conta)")
    q.pressed.emit()
    check(await wait_until(func(): return stage.mode == "casual" and stage.casual.status == "playing", 25.0), "partida Casual começou")
    var c = stage.casual
    var mine = [[Vector2i(4,6),Vector2i(4,4)],[Vector2i(6,7),Vector2i(5,5)],[Vector2i(5,7),Vector2i(2,4)]] if c.human_color == "w" else [[Vector2i(4,1),Vector2i(4,3)],[Vector2i(6,0),Vector2i(5,2)],[Vector2i(5,0),Vector2i(2,3)]]
    var play = func(pair, label):
        check(await wait_until(func(): return c.can_interact(), 15.0), "minha vez (" + label + ")")
        var before = c.rules.ply
        check(c.request_move(pair[0], pair[1]), "lance enviado (" + label + ")")
        check(await wait_until(func(): return c.rules.ply > before, 8.0), "servidor aplicou (" + label + ")")
    await play.call(mine[0], "antes da revalidação")
    print("DBG esperando 70 s (servidor revalida a sessão aos 60 s)")
    var t0 = Time.get_ticks_msec()
    while Time.get_ticks_msec() - t0 < 70000: await process_frame
    check(c.status == "playing" and stage.mode == "casual", "partida segue depois da revalidação")
    await play.call(mine[1], "depois da revalidação")
    # renovação do token no meio da partida (o cliente faz isso ~2 min antes do exp)
    var states = [0]
    acc.changed.connect(func(): states[0] += 1)
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready and states[0] > 0, 8.0), "renovação: servidor aceitou de novo (acct_state)")
    check(c.status == "playing" and stage.mode == "casual", "renovação não derrubou a partida")
    await play.call(mine[2], "depois da renovação")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
