extends SceneTree
var failures := 0
var checks := 0
var stage
var hub
var requests: Array = []

func verify(ok: bool, description: String):
    checks += 1
    if not ok:
        failures += 1
        push_error(description)

func _initialize():
    call_deferred("run")

func settle():
    for i in range(4):
        await process_frame

func labels_bounded(node: Node):
    if node is Label and node.is_visible_in_tree():
        var label: Label = node
        verify(label.autowrap_mode != TextServer.AUTOWRAP_OFF, "label wraps: " + label.text.left(32))
        verify(label.size.y + 0.6 >= label.get_minimum_size().y, "label has complete text height: " + label.text.left(32))
        var parent = label.get_parent()
        if parent is Control:
            verify(label.size.x <= parent.size.x + 0.6, "label width stays inside container: " + label.text.left(32))
        while parent and parent != hub.canvas:
            if parent is TextureButton:
                verify(parent.get_global_rect().grow(1).encloses(label.get_global_rect()), "button fully contains live text: " + label.text.left(32))
                break
            parent = parent.get_parent()
    for child in node.get_children():
        labels_bounded(child)

func count_forest(node: Node) -> int:
    var count = 1 if node is TextureRect and node.texture == hub.FOREST else 0
    for child in node.get_children():
        count += count_forest(child)
    return count

func run():
    root.content_scale_size = Vector2i.ZERO
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await settle()
    hub = stage.get_node("MainHub")
    verify(count_forest(hub) == 1, "composition renders exactly one whole forest image")
    for dimensions in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768),Vector2i(1920,1040),Vector2i(1280,720)]:
        root.size = dimensions
        await settle()
        hub._layout()
        verify(is_equal_approx(hub.canvas.scale.x,hub.canvas.scale.y), "uniform proportional composition at " + str(dimensions))
        var viewport = Rect2(Vector2.ZERO,root.get_visible_rect().size)
        for button in hub.menu_buttons:
            verify(viewport.grow(1).encloses(button.get_global_rect()), "main menu stays on screen at " + str(dimensions))
        verify(viewport.grow(1).encloses(hub.profile_button.get_global_rect()), "profile stays on screen at " + str(dimensions))
        for id in hub.pages:
            hub.show_page(id)
            await settle()
            labels_bounded(hub.canvas)
            if hub.page_scrolls.has(id):
                var scroll = hub.page_scrolls[id]
                verify(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "page cannot expand sideways: " + id)
                var content = scroll.get_child(0)
                verify(content.size.x <= scroll.size.x + 1, "scroll content has constrained width: " + id)
    hub.player_name = "WWWWWWWWWWWWWWWWWWWW"
    hub.profile_name.text = hub.player_name
    hub.show_page("profile")
    await settle()
    labels_bounded(hub.canvas)
    verify(hub.profile_button.get_global_rect().grow(1).encloses(hub.profile_name.get_global_rect()), "longest local profile name remains within profile button")
    # Disconnect gameplay integration to isolate the UI's difficulty/side payload.
    for connection in hub.play_bot_requested.get_connections():
        hub.play_bot_requested.disconnect(connection.callable)
    hub.play_bot_requested.connect(func(difficulty,side): requests.append([difficulty,side]))
    hub.show_page("bot")
    verify(hub.difficulty_buttons.hard.disabled and hub.difficulty_buttons.expert.disabled, "future bot levels are visibly disabled")
    hub.difficulty_buttons.easy.pressed.emit()
    verify(hub.page == "bot_side" and hub.selected_difficulty == "easy", "easy opens side selection")
    hub.side_buttons.w.pressed.emit()
    hub.side_buttons.b.pressed.emit()
    hub.side_buttons.random.pressed.emit()
    verify(requests == [["easy","w"],["easy","b"],["easy","random"]], "all easy side buttons emit correct requests")
    hub.back()
    verify(hub.page == "bot", "back from side selection returns to difficulty")
    hub.difficulty_buttons.medium.pressed.emit()
    hub.side_buttons.b.pressed.emit()
    verify(requests.back() == ["medium","b"], "medium preserves difficulty through side selection")
    hub.back()
    hub.back()
    verify(hub.page == "main", "back from difficulty returns Home")
    hub.play_online_requested.emit()
    var online = stage.get_node("Online")
    online.menu_info.text = "Conectando ao servidor… A hospedagem gratuita pode levar um momento. Aguarde enquanto preparamos uma sala para você e seu amigo."
    for dimensions in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
        root.size = dimensions
        await settle()
        labels_bounded(online.menu)
        verify(root.get_visible_rect().grow(1).encloses(online.menu.get_global_rect()), "online menu stays inside viewport at " + str(dimensions) + " rect=" + str(online.menu.get_global_rect()) + " view=" + str(root.get_visible_rect()))
        verify(online.menu.size.x <= 501, "online menu keeps constrained width at " + str(dimensions))
        verify(online.menu.get_global_rect().grow(1).encloses(online.menu_info.get_global_rect()), "long connection status remains inside online menu")
    stage.queue_free()
    await process_frame
    print("HOME_LAYOUT_CHECKS=", checks, " FAILURES=", failures)
    quit(failures)
