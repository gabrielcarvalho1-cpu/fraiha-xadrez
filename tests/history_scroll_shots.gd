extends SceneTree
## R51c · Capturas do HISTÓRICO DE PARTIDAS no PC com 12 partidas (lista maior que o painel):
## topo, depois de rolar pela barra da direita e no fim da lista. Também confere que a barra rola de verdade.
## Uso: HIST_SHOT_DIR=<pasta> xvfb-run godot --rendering-driver opengl3 --resolution 1672x941 --path <proj> -s tests/history_scroll_shots.gd
var stage

func _initialize():
    call_deferred("run")

func _shot(name: String):
    for i in range(12): await process_frame
    await RenderingServer.frame_post_draw
    var p := OS.get_environment("HIST_SHOT_DIR").path_join(name)
    root.get_texture().get_image().save_png(p)
    print("SHOT ", p)

func run():
    DisplayServer.window_set_size(Vector2i(1672, 941))
    root.size = Vector2i(1672, 941)
    root.content_scale_size = Vector2i.ZERO
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(30): await process_frame
    if stage.get("account_ui") != null: stage.account_ui.hide_ui()
    var hub = stage.get_node("MainHub")
    var mh = stage.match_history
    mh.entries.clear()
    var t := 1791300000
    for i in range(12):
        var mode: String = ["ranked", "bot", "ranked", "casual"][i % 4]
        mh.entries.append({"mode_id": "chess", "mode": mode, "opponent": "BOT MADEIRA" if mode == "bot" else "SextoSen%d" % (i + 1),
            "result": "win" if i % 3 != 0 else "loss", "color": "w" if i % 2 == 0 else "b", "plies": 20 + i * 7,
            "started_at": t - i * 3600, "finished_at": t - i * 3600 + 900, "record": {}})
    hub.show_page("history")
    await _shot("1_topo.png")
    var scroll: ScrollContainer = hub.pages["history"].find_child("HistoryScroll", true, false)
    var bar = hub.pages["history"].find_child("HistoryBar", true, false)
    var inner := scroll.get_v_scroll_bar()
    print("CHECK max=", inner.max_value, " page=", inner.page, " barra_existe=", bar != null)
    if bar != null:
        bar.value = (inner.max_value - inner.page) * 0.5
    else:
        scroll.scroll_vertical = int((inner.max_value - inner.page) * 0.5)
    await _shot("2_meio.png")
    print("CHECK meio scroll=", scroll.scroll_vertical)
    if bar != null: bar.value = bar.max_value
    else: scroll.scroll_vertical = int(inner.max_value)
    await _shot("3_fim.png")
    print("CHECK fim scroll=", scroll.scroll_vertical, " barra=", bar.value if bar != null else -1.0)
    scroll.scroll_vertical = 0   # rolar a lista (roda do mouse/arrasto) move a barra junto
    for i in range(4): await process_frame
    print("CHECK volta lista=0 barra=", bar.value if bar != null else -1.0)
    # clique de verdade (evento de mouse) na seta de baixo e arraste da alça
    var panel: Control = hub.pages["history"]
    var down: Vector2 = panel.get_global_transform() * Vector2(1819, 722)
    _click(down)
    for i in range(4): await process_frame
    print("CHECK seta_baixo scroll=", scroll.scroll_vertical)
    var g0: Vector2 = panel.get_global_transform() * Vector2(1819, 330)
    var g1: Vector2 = panel.get_global_transform() * Vector2(1819, 650)
    _mouse(g0, true); _move(g0, g1); _mouse(g1, false)
    for i in range(4): await process_frame
    print("CHECK arrastar_alca scroll=", scroll.scroll_vertical)
    quit(0)

func _mouse(p: Vector2, down: bool):
    var e := InputEventMouseButton.new()
    e.button_index = MOUSE_BUTTON_LEFT
    e.pressed = down
    e.position = p
    e.global_position = p
    root.push_input(e)

func _move(a: Vector2, b: Vector2):
    for i in range(1, 11):
        var e := InputEventMouseMotion.new()
        e.position = a.lerp(b, i / 10.0)
        e.global_position = e.position
        e.relative = (b - a) / 10.0
        e.button_mask = MOUSE_BUTTON_MASK_LEFT
        root.push_input(e)

func _click(p: Vector2):
    _mouse(p, true); _mouse(p, false)
