extends SceneTree
## R52c · Capturas da tela BUSCANDO ADVERSÁRIO (Ranked e Casual) + contador e CANCELAR de verdade.
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 SHOT_TAG=<prefixo> xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/search_art_shots.gd
var stage

func _initialize():
    call_deferred("run")

func _shot(name: String):
    for i in range(14): await process_frame
    await RenderingServer.frame_post_draw
    var p := OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "_" + name)
    root.get_texture().get_image().save_png(p)
    print("SHOT ", p)

func run():
    var sz := OS.get_environment("SHOT_SIZE").split("x")
    var px := Vector2i(int(sz[0]), int(sz[1]))
    DisplayServer.window_set_size(px)
    root.size = px
    root.content_scale_size = Vector2i.ZERO
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(30): await process_frame
    if stage.get("account_ui") != null: stage.account_ui.hide_ui()
    for ui_name in ["ranked_ui", "casual_ui"]:
        var ui = stage.get(ui_name)
        if ui == null:
            print("CHECK sem ", ui_name)
            continue
        var c = ui.controller
        c.set("mode", "ranked_3min" if ui_name == "ranked_ui" else "casual_10min")
        ui.last_mode = "ranked_3min" if ui_name == "ranked_ui" else "casual_10min"
        ui._show("searching")
        ui.search_started = Time.get_ticks_msec() - 4200
        await _shot(ui_name + "_buscando.png")
        var art: Control = ui.search_art
        var r := art.get_global_rect()
        r = Rect2(art.position, art.size * art.scale)
        var vs := root.get_visible_rect().size
        print("CHECK ", ui_name, " visivel=", art.visible, " ritmo=", ui.search_mode_label.text, " tempo=", ui.search_time_label.text,
            " sobra_esq=", snappedf(r.position.x, 0.1), " dir=", snappedf(vs.x - r.end.x, 0.1), " topo=", snappedf(r.position.y, 0.1), " baixo=", snappedf(vs.y - r.end.y, 0.1))
        var cancel: Control = art.find_child("SearchCancel", true, false)
        var p := cancel.get_global_transform() * (cancel.size / 2.0)
        for down in [true, false]:
            var e := InputEventMouseButton.new()
            e.button_index = MOUSE_BUTTON_LEFT
            e.pressed = down
            e.position = p
            e.global_position = p
            root.push_input(e)
        for i in range(6): await process_frame
        print("CHECK ", ui_name, " cancelar -> tela=", ui.screen, " busca_visivel=", art.visible)
        ui.close_panel()
    quit(0)
