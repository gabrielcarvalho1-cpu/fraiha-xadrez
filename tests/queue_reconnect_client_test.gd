extends SceneTree
## Regressão: a conexão cai enquanto o jogador está na fila (celular em segundo plano, rede
## oscilando). O servidor tira o jogador da fila ao fechar o socket; o cliente precisa voltar
## para a fila sozinho ao reconectar, senão fica "buscando" para sempre e nunca pareia.
## Uso: servidor local (FRAIHA_DEV_AUTH=1) + `node tests/server/casual_peer.cjs PORTA casual_3min 9000`
## (adversário entra na fila 9 s depois) + FRAIHA_SERVER_URL=ws://127.0.0.1:PORTA godot -s este arquivo.
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
    for i in range(3): await process_frame
    stage.account_ui.hide_ui()
    stage.hub.play_online_requested.emit()
    check(await wait_until(func(): return stage.account.online_ready(), 8.0), "convidado conectado")
    await process_frame
    stage.casual_ui.box.find_child("Queue_casual_3min", true, false).pressed.emit()
    check(await wait_until(func(): return stage.casual.searching, 4.0), "entrou na fila")
    # Queda de conexão enquanto busca.
    stage.account.socket.close()
    check(await wait_until(func(): return stage.casual.get("requeue_pending") == true, 4.0), "queda detectada: continua buscando e marca reentrada")
    check(stage.casual_ui.screen == "searching", "tela continua em BUSCANDO ADVERSÁRIO")
    check(await wait_until(func(): return stage.account.online_ready() and not stage.casual.get("requeue_pending"), 10.0), "reconectou e voltou para a fila sozinho")
    check(await wait_until(func(): return stage.mode == "casual", 20.0), "adversário que entrou depois foi pareado sem sair e entrar de novo")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
