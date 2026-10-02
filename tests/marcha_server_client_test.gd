extends SceneTree
## R32 · MARCHA REAL com conta: o SERVIDOR é a autoridade da partida grátis do dia.
## Apagar o arquivo do aparelho (outro navegador, F5 com dados limpos) não libera outra partida.
## Rodar com servidor dev: /tmp/run_account_session.sh tests/marcha_server_client_test.gd
const Access := preload("res://marcha/marcha_access.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize(): call_deferred("run")

func wait_until(f: Callable, secs: float) -> bool:
    var t0 := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
        if f.call(): return true
        await process_frame
    return f.call()

func run():
    var local := ProjectSettings.globalize_path(Access.LOCAL_FILE)
    DirAccess.remove_absolute(local)
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 3: await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    acc.access_token = "dev:MarchaSrv%d" % (Time.get_ticks_msec() % 100000)
    acc.user_id = "pending"
    acc.email = "marcha@teste.local"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada ao servidor dev")
    if acc.needs_nickname: acc.create_profile("Marcha%d" % (Time.get_ticks_msec() % 100000))
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    var hub = stage.hub
    hub.entitlements.clear_server()
    hub.open_marcha()
    for i in 3: await process_frame
    var ui = hub.marcha
    ui.tut_page = -1
    await ui.access.refresh()
    check(bool(ui.gate_info.get("can_play", false)) and not bool(ui.gate_info.get("unlimited", true)), "servidor: 1 partida grátis disponível hoje")
    check(await ui.access.request_start(), "servidor libera a 1ª partida (marcha_granted)")
    DirAccess.remove_absolute(local)
    check(not Access.local_played_today(), "aparelho sem registro local (dados do navegador limpos)")
    check(not await ui.access.request_start(), "mesmo assim o servidor recusa a 2ª partida do dia")
    # recarregar (F5): novo pedido de estado vem do servidor
    await ui.access.refresh()
    check(not bool(ui.gate_info.get("can_play", true)) and String(ui.gate_info.label).contains("JÁ USADA"), "após recarregar o estado: PARTIDA GRÁTIS DE HOJE JÁ USADA")
    ui.close()
    DirAccess.remove_absolute(local)
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
