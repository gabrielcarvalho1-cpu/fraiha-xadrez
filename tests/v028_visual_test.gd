extends SceneTree
var failures = 0
func check(value: bool, label: String):
    print("PASS " if value else "FAIL ",label)
    if not value: failures += 1
func _initialize(): call_deferred("run")
func run():
    var viewport = SubViewport.new()
    viewport.size = Vector2i(1920,1080)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    viewport.add_child(stage)
    for i in range(3): await process_frame
    var hub = stage.hub
    check(hub.menu_buttons.size() == 8,"eight central actions")
    for i in range(8):
        var button = hub.menu_buttons[i]
        check(button.position == Vector2(611,341+i*63) and button.size == Vector2(450,57),"equal geometry %d" % i)
    check(hub.menu_buttons[3].material is ShaderMaterial,"gold Ranked")
    hub.menu_buttons[3].pressed.emit()
    check(hub.page == "ranked","Ranked button navigation")
    for id in ["about","profile","ranked","bot","settings"]:
        hub.show_page(id)
        check(not hub.home_signature[0].visible and not hub.home_signature[1].visible and not hub.home_signature[2].visible,"no signature " + id)
    for id in ["main","about"]:
        hub.show_page(id)
        for i in range(4): await process_frame
        await RenderingServer.frame_post_draw
        viewport.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]+"/"+id+".png")
    viewport.queue_free()
    await process_frame
    print("V028 FAILURES=",failures)
    quit(failures)
