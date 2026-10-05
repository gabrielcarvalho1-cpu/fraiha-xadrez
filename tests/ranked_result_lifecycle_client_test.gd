extends SceneTree
## R42.1 · Regressão: com a gravação do resultado Ranked lenta (RPC do Supabase), a tela de
## VITÓRIA/DERROTA não aparecia no fim da partida e "vazava" para o início da Ranked seguinte.
## Confere: animação certa NA HORA do resultado; nova Ranked começa limpa; 3 partidas seguidas.
## Rodar: tests/run_ranked_result_lifecycle.sh
var failures = 0
var shown: Array = []      # [{result, at_ms, match}]
var stage
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
    # registra cada vez que a tela de resultado abre (e em qual partida o jogador estava)
    var was := false
    while true:
        await process_frame
        if stage == null or stage.result_overlay == null: continue
        var now: bool = stage.result_overlay.is_showing()
        if now and not was: shown.append({"result": String(stage.result_overlay.result), "at": Time.get_ticks_msec(), "match": String(stage.ranked.match_id)})
        was = now
func button(text: String) -> Button:
    for b in stage.ranked_ui.box.find_children("*", "Button", true, false):
        if String(b.text).strip_edges() == text and b.is_visible_in_tree(): return b
    return null
func play_match(n: int, expect: String, client_resigns: bool):
    check(await wait_until(func(): return stage.mode == "ranked" and stage.ranked.status == "playing", 40.0), "partida %d começou" % n)
    var mid := String(stage.ranked.match_id)
    var before := shown.size()
    # nada de tela de resultado antiga no começo da partida nova
    var t0 := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t0 < 1200: await process_frame
    check(shown.size() == before and not stage.result_overlay.is_showing(), "partida %d: NENHUMA tela de resultado antiga no início" % n)
    check(stage.recorder.record != null and not stage.recorder.record.finished and stage.recorder.record.match_id == mid, "partida %d: registro novo, aberto, desta partida" % n)
    if client_resigns: stage.ranked.resign()
    check(await wait_until(func(): return not stage.ranked.last_result.is_empty() and String(stage.ranked.last_result.get("match_id", "")) == mid, 20.0), "partida %d: resultado oficial chegou" % n)
    var got := Time.get_ticks_msec()
    check(await wait_until(func(): return shown.size() > before, 1.5), "partida %d: tela de resultado abre NA HORA (≤1,5 s do resultado)" % n)
    var s: Dictionary = shown[before] if shown.size() > before else {}
    check(String(s.get("result", "")) == expect and String(s.get("match", "")) == mid, "partida %d: tela certa (%s) para esta partida (veio %s)" % [n, expect, s.get("result", "-")])
    check(shown.size() == before + 1, "partida %d: abriu uma vez só" % n)
    var rec = stage.recorder.record
    check(rec.finished and rec.match_id == mid and rec.result == ("win" if expect == "victory" else "loss"), "partida %d: histórico com o resultado oficial (%s)" % [n, rec.result])
    stage.result_overlay.hide_result()
    await wait_until(func(): return not stage.result_overlay.visible, 3.0)
func run():
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(6): await process_frame
    stage.account_ui.hide_ui()
    _watch()
    var acc = stage.account
    var nick = "Rk%d" % (Time.get_ticks_msec() % 100000)
    acc.access_token = "dev:" + nick
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada")
    if acc.needs_nickname: acc.create_profile(nick)
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    stage._open_ranked()
    await wait_until(func(): return stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false) != null, 4.0)
    stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false).pressed.emit()
    await play_match(1, "victory", false)
    var back = button("VOLTAR AO RANKED")
    check(back != null, "VOLTAR AO RANKED")
    if back: back.pressed.emit()
    await wait_until(func(): return stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false) != null, 4.0)
    stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false).pressed.emit()
    await play_match(2, "defeat", true)
    var again = button("JOGAR NOVAMENTE")
    check(again != null, "JOGAR NOVAMENTE")
    if again: again.pressed.emit()
    await play_match(3, "victory", false)
    # Rede real: "ranked_found" da partida nova chega num frame e o 1º estado só frames depois.
    # O fim da partida anterior não pode virar resultado da partida nova nesse intervalo.
    var before := shown.size()
    stage.account.server_message.emit({"type": "ranked_found", "match_id": "00000000-0000-4000-8000-00000000f00d", "mode": "ranked_3min", "mode_name": "Relâmpago", "you": "w", "opponent": {"nickname": "Simulado"}})
    for i in 30: await process_frame
    check(shown.size() == before and not stage.result_overlay.is_showing(), "nova Ranked (estado ainda não chegou): resultado anterior NÃO aparece")
    check(stage.recorder.record != null and not stage.recorder.record.finished, "nova Ranked: registro novo continua aberto (não herda VITÓRIA/DERROTA antiga)")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
