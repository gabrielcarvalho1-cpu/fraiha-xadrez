extends SceneTree
## R52d · Regressão: a caixa de mensagem (DmInput) e o ENVIAR da conversa privada não podem se mexer
## enquanto a tela está aberta (vazia, digitando, com foco, recebendo e enviando mensagens, rolando).
## Uso: SHOT_SIZE=1672x941 [SHOT_DIR=<pasta> SHOT_TAG=<prefixo>] xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/dm_jitter_test.gd
var stage
var s
var failures := 0

func _initialize():
    call_deferred("run")

func _rects() -> Array:
    var i: Control = s.dm_input
    var b: Control = s.panel.find_child("DmSend", true, false)
    if not is_instance_valid(i) or b == null: return []
    return [i.get_global_rect(), b.get_global_rect()]

## mede N quadros seguidos; devolve quantas vezes a caixa/botão mudou de lugar ou tamanho
func _watch(label: String, frames: int, each: Callable = Callable()) -> int:
    var last: Array = _rects()
    var moves := 0
    var seen := {}
    for f in range(frames):
        if each.is_valid(): each.call(f)
        await process_frame
        var now: Array = _rects()
        if now.is_empty() or last.is_empty():
            last = now
            continue
        if now[0] != last[0] or now[1] != last[1]:
            moves += 1
            seen[str(now[0])] = true
        last = now
    var open: bool = s.is_open() and s.screen == "dm"
    print(("PASS " if moves == 0 and open else "FAIL "), label, " mudancas=", moves, " posicoes=", seen.size(), " aberta=", open)
    if moves != 0 or not open: failures += 1
    return moves

func _msg(i: int, mine: bool) -> Dictionary:
    return {"id": "m%d" % i, "from": "eu" if mine else "u1", "to": "u1" if mine else "eu", "body": "Mensagem número %d — bora uma partida?" % i, "created_at": "2026-10-07T18:%02d:00Z" % (i % 60)}

func run():
    var sz := OS.get_environment("SHOT_SIZE").split("x")
    var px := Vector2i(int(sz[0]), int(sz[1]))
    DisplayServer.window_set_size(px)
    root.size = px
    root.content_scale_size = Vector2i.ZERO
    # sem servidor: a conta de teste não fica oscilando (o que fecharia Amigos no meio da medição)
    OS.set_environment("FRAIHA_SERVER_URL", "")
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(30): await process_frame
    if stage.get("account_ui") != null: stage.account_ui.hide_ui()
    s = stage.social_ui
    s.dm_id = "u1"
    s.dm_peer = {"nickname": "SextoSentro", "avatar_id": "warrior", "user_id": "u1"}
    s.dm_messages = []
    s.dm_can_send = true
    s.dm_loading = false
    s.dm_error = ""
    s._show("dm")
    for i in range(10): await process_frame
    await _watch("conversa vazia parada", 90)
    s.dm_input.grab_focus()
    await _watch("com foco no campo", 60)
    await _watch("digitando", 60, func(f):
        if f % 3 == 0: s.dm_input.insert_text_at_caret("a"))
    # várias mensagens chegando (reconstrói a conversa como o recebimento real faz)
    for k in range(12): s.dm_messages.append(_msg(k, k % 2 == 0))
    s.dm_to_end = true
    s._show("dm")
    for i in range(10): await process_frame
    await _watch("com 12 mensagens", 90)
    await _watch("chegando mensagens", 90, func(f):
        if f % 15 == 0:
            s.dm_messages.append(_msg(100 + f, false))
            s._show("dm"))
    s.dm_scroll.scroll_vertical = 0
    await _watch("rolando a conversa", 60, func(f): s.dm_scroll.scroll_vertical = f * 6)
    s.dm_input.release_focus()
    await _watch("sem foco", 60)
    if OS.get_environment("SHOT_DIR") != "":
        await RenderingServer.frame_post_draw
        var p := OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "_conversa.png")
        root.get_texture().get_image().save_png(p)
        print("SHOT ", p)
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(0)
