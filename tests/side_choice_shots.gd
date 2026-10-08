extends SceneTree
## R52d · ESCOLHA SEU LADO na arte nova: capturas e cliques de verdade (BRANCAS, PRETAS, ALEATÓRIO, VOLTAR e ESC).
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 SHOT_TAG=<prefixo> xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/side_choice_shots.gd
var stage
var hub
var failures := 0
var got: Array = []

func _initialize():
    call_deferred("run")

func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1

func _shot(name: String):
    for i in range(14): await process_frame
    await RenderingServer.frame_post_draw
    var p := OS.get_environment("SHOT_DIR").path_join(OS.get_environment("SHOT_TAG") + "_" + name)
    root.get_texture().get_image().save_png(p)
    print("SHOT ", p)

func _click_node(n: String):
    var c: Control = hub.side_art.find_child(n, true, false)
    var p: Vector2 = c.get_global_transform() * (c.size / 2.0)
    for down in [true, false]:
        var e := InputEventMouseButton.new()
        e.button_index = MOUSE_BUTTON_LEFT
        e.pressed = down
        e.position = p
        e.global_position = p
        root.push_input(e)

func _open(bot_id: String):
    hub.open_home()
    hub.show_page("bot")
    for i in range(3): await process_frame
    hub._choose_difficulty(bot_id)
    for i in range(6): await process_frame

func run():
    var sz := OS.get_environment("SHOT_SIZE").split("x")
    var px := Vector2i(int(sz[0]), int(sz[1]))
    DisplayServer.window_set_size(px)
    root.size = px
    root.content_scale_size = Vector2i.ZERO
    OS.set_environment("FRAIHA_SERVER_URL", "")
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(30): await process_frame
    if stage.get("account_ui") != null: stage.account_ui.hide_ui()
    hub = stage.get_node("MainHub")
    var ids: Array = []
    for b in load("res://bot/bot_ladder.gd").bots(): ids.append(String(b.id))
    for i in range(3): hub.bot_progress.defeated[ids[i]] = 1791300000   # Bronze liberado
    hub.bot_progress.changed.emit()
    hub.play_bot_requested.connect(func(d, side): got.append([d, side]))
    await _open(ids[2])
    await _shot("lado.png")
    var vs := root.get_visible_rect().size
    var r := Rect2(hub.side_panel.position, hub.side_panel.size * hub.side_panel.scale)
    check(hub.side_art.visible and hub.page == "bot_side", "tela aberta por cima, com fundo escurecido")
    check(r.position.x >= 0 and r.position.y >= 0 and r.end.x <= vs.x + 0.5 and r.end.y <= vs.y + 0.5, "painel inteiro na tela (nada cortado)")
    check(absf(r.position.x - (vs.x - r.end.x)) <= 1.0 and absf(r.position.y - (vs.y - r.end.y)) <= 1.0, "painel centralizado")
    check(hub.side_opponent.text == "Adversário: BOT BRONZE", "adversário dinâmico: " + hub.side_opponent.text)
    var mob = hub.get("mobile_ui")
    if is_instance_valid(mob):   # R52f · celular: a tela antiga (título, VOLTAR, botões) não aparece atrás do painel
        check(not mob.scroll.visible and not mob.heading.visible and not mob.back_button.visible, "celular: tela antiga escondida atrás do painel")
    await _open(ids[2])
    _click_node("SideBack")
    for i in range(6): await process_frame
    check(hub.page == "bot" and not hub.side_art.visible, "VOLTAR AOS NÍVEIS volta para os níveis")
    if is_instance_valid(mob):
        check(mob.scroll.visible and mob.heading.visible and mob.back_button.visible, "celular: lista dos níveis volta inteira")
    await _open(ids[2])
    var e := InputEventKey.new()
    e.keycode = KEY_ESCAPE
    e.pressed = true
    root.push_input(e)
    for i in range(6): await process_frame
    check(hub.page == "bot" and not hub.side_art.visible, "ESC volta para os níveis")
    for i in range(10): hub.bot_progress.defeated[ids[i]] = 1791300000
    await _open(ids[9])
    await _shot("lado_grande_mestre.png")
    check(hub.side_opponent.text.begins_with("Adversário: BOT GRANDE MESTRE"), "nome longo cabe: " + hub.side_opponent.text)
    for spec in [["SideWhite", "w"], ["SideBlack", "b"], ["SideRandom", "random"]]:
        got.clear()
        await _open(ids[2])
        _click_node(spec[0])
        for i in range(8): await process_frame
        check(got.size() == 1 and got[0][0] == ids[2] and got[0][1] == spec[1], "%s inicia a partida (%s)" % [spec[0], str(got)])
        check(not hub.side_art.is_visible_in_tree(), "%s: a tela some ao começar a partida" % spec[0])
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(0 if failures == 0 else 1)   # R52f · gate: qualquer FAIL sai com código diferente de 0
