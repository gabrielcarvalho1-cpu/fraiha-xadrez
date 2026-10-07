extends SceneTree
## Capturas do TABULEIRO RANKED MADEIRA (partida real contra o adversário automático) e da tela de SUBIDA DE LIGA,
## para comparar com as referências (tools/board_ref/*). Rodar: tests/run_ranked_board_shots.sh <pasta> [mob]
## Env: BOARD_SHOTS=<pasta>  BOARD_PX=1672x941  BOARD_CSS=427x921 (celular)
var stage
func _initialize(): call_deferred("run")
func wait_until(cond: Callable, seconds: float) -> bool:
    var end = Time.get_ticks_msec() + int(seconds * 1000)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await process_frame
    return cond.call()
func shot(name: String):
    for i in range(8): await process_frame
    await RenderingServer.frame_post_draw
    var out := OS.get_environment("BOARD_SHOTS") + "/" + name + ".png"
    root.get_texture().get_image().save_png(out)
    print("SHOT ", out)
func run():
    var px := OS.get_environment("BOARD_PX").split("x")
    var size := Vector2i(int(px[0]), int(px[1]))
    DisplayServer.window_set_size(size)
    root.size = size
    var css := OS.get_environment("BOARD_CSS")
    if css.is_empty(): root.content_scale_size = Vector2i.ZERO
    else:
        var c := css.split("x")
        root.set_meta("mobile_resize_busy", true)
        root.content_scale_size = Vector2i(int(c[0]), int(c[1]))
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(6): await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    acc.access_token = "dev:SextoSen1"
    acc.user_id = "pending"
    acc._server_auth()
    await wait_until(func(): return acc.server_ready, 8.0)
    if acc.needs_nickname: acc.create_profile("SextoSen1")
    await wait_until(func(): return acc.has_profile(), 6.0)
    stage._open_ranked()
    await wait_until(func(): return stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false) != null, 4.0)
    stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false).pressed.emit()
    var ok: bool = await wait_until(func(): return stage.mode == "ranked" and stage.ranked.status == "playing", 40.0)
    print("PARTIDA ", ok)
    await shot("board")
    # Tela de subida de liga: mesma mensagem que o servidor manda (ranked_result com promoted=true)
    var fake := {"type": "ranked_result", "match_id": stage.ranked.match_id, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": stage.ranked.human_color,
        "outcome": "win", "reason": "resign", "reason_text": "Desistência", "pl_change": 3, "league_before": 0, "pl_before": 97,
        "league_after": 1, "pl_after": 0, "promoted": true, "stats": {"league": 1, "pl": 0, "highest_league": 1}, "saved": true}
    stage.ranked.last_result = fake
    stage.ranked_ui._show("result")
    await shot("promo")
    quit(0)
