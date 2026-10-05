extends SceneTree
## R42.1 · Tela de resultado nas trocas Ranked → Casual → (F5) → Ranked com reconexão no meio.
## Gravação do resultado Ranked lenta (como o Supabase). Rodar:
##   PEER_ACTIONS=ranked:resign,casual:wait,ranked:resign:9 TEST=tests/online_result_mixed_client_test.gd tests/run_ranked_result_lifecycle.sh
var failures = 0
var shown: Array = []
var stage
var token := ""
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
func _watch():
    var was := false
    while true:
        await process_frame
        if stage == null or not is_instance_valid(stage) or stage.result_overlay == null:
            was = false
            continue
        var now: bool = stage.result_overlay.is_showing()
        if now and not was: shown.append({"result": String(stage.result_overlay.result)})
        was = now
func boot():
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(6): await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    acc.access_token = token
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada")
    if acc.needs_nickname: acc.create_profile(token.substr(4))
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
func queue(kind: String):
    var ui = stage.ranked_ui if kind == "ranked" else stage.casual_ui
    if kind == "ranked": stage._open_ranked()
    else: stage._open_casual()
    var id := "Queue_ranked_3min" if kind == "ranked" else "Queue_casual_3min"
    await wait_until(func(): var b = ui.box.find_child(id, true, false); return b != null and not b.disabled, 6.0)
    ui.box.find_child(id, true, false).pressed.emit()
func play(n: int, kind: String, expect: String, client_resigns: bool, reconnect := false):
    var ctrl = stage.ranked if kind == "ranked" else stage.casual
    check(await wait_until(func(): return stage.mode == kind and ctrl.status == "playing", 60.0), "%d (%s) começou" % [n, kind])
    var mid := String(ctrl.match_id)
    var before := shown.size()
    var t0 := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t0 < 1000: await process_frame
    check(shown.size() == before, "%d (%s): sem tela de resultado antiga no início" % [n, kind])
    if reconnect:
        stage.account.socket.close()
        check(await wait_until(func(): return not stage.account.server_ready, 4.0), "%d: conexão caiu" % n)
        check(await wait_until(func(): return stage.account.server_ready and ctrl.status == "playing" and ctrl.match_id == mid, 15.0), "%d: reconectou na mesma partida" % n)
        check(shown.size() == before, "%d: reconexão não abre tela de resultado" % n)
    if client_resigns: ctrl.resign()
    check(await wait_until(func(): return String(ctrl.last_result.get("match_id", "")) == mid, 25.0), "%d (%s): resultado oficial chegou" % [n, kind])
    check(await wait_until(func(): return shown.size() > before, 1.5), "%d (%s): tela abre na hora" % [n, kind])
    check(shown.size() == before + 1 and String(shown[before].result if shown.size() > before else "") == expect, "%d (%s): tela certa (%s), uma vez" % [n, kind, expect])
    check(stage.recorder.record.finished and stage.recorder.record.match_id == mid, "%d: histórico fechado nesta partida (%s)" % [n, stage.recorder.record.result])
    stage.result_overlay.hide_result()
    await wait_until(func(): return not stage.result_overlay.visible, 3.0)
    (stage.ranked_ui if kind == "ranked" else stage.casual_ui).play_requested.emit()
func run():
    _watch()
    token = "dev:Mx%d" % (Time.get_ticks_msec() % 100000)
    await boot()
    await queue("ranked")
    await play(1, "ranked", "victory", false)
    await queue("casual")
    await play(2, "casual", "defeat", true)
    if OS.get_environment("NO_F5").is_empty():
        # F5 entre partidas: recarrega o jogo inteiro e entra de novo na mesma conta
        stage.queue_free()
        stage = null
        for i in 10: await process_frame
        await boot()
        check(shown.size() == 2, "F5: nenhuma tela de resultado ao recarregar")
    await queue("ranked")
    await play(3, "ranked", "victory", false, true)
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
