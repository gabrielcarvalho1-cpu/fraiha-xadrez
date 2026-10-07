extends SceneTree
## R51d · Capturas do SISTEMA DE LIGAS no PC (Madeira e Prata escolhidas) + cliques de verdade nos cartões e botões.
## Uso: LIGAS_SHOT_DIR=<pasta> LIGAS_SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/ligas_shots.gd
var stage

func _initialize():
    call_deferred("run")

func _shot(name: String):
    for i in range(16): await process_frame
    await RenderingServer.frame_post_draw
    var p := OS.get_environment("LIGAS_SHOT_DIR").path_join(name)
    root.get_texture().get_image().save_png(p)
    print("SHOT ", p)

func _click(p: Vector2):
    for down in [true, false]:
        var e := InputEventMouseButton.new()
        e.button_index = MOUSE_BUTTON_LEFT
        e.pressed = down
        e.position = p
        e.global_position = p
        root.push_input(e)

func run():
    var sz := OS.get_environment("LIGAS_SHOT_SIZE").split("x")
    var px := Vector2i(int(sz[0]), int(sz[1]))
    DisplayServer.window_set_size(px)
    root.size = px
    root.content_scale_size = Vector2i.ZERO
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(30): await process_frame
    if stage.get("account_ui") != null: stage.account_ui.hide_ui()
    var hub = stage.get_node("MainHub")
    hub.player_name = "Gabriel"
    hub.show_page("ranking")
    var tag := OS.get_environment("LIGAS_SHOT_TAG")
    await _shot(tag + "_madeira.png")
    var panel: Control = hub.pages["ranking"]
    var prata: Control = panel.find_child("League_prata", true, false)
    _click(prata.get_global_rect().get_center())
    await _shot(tag + "_prata.png")
    print("CHECK clique_prata selecionada=", hub.selected_league)
    var tm = stage.get_node("ThemeManager")
    var cb: Control = panel.find_child("ClassicPieces", true, false)
    var sub: Label = panel.find_child("ClassicPiecesSub", true, false)
    print("CHECK classicas_antes pecas=", tm.active_piece_set, " texto=", sub.text)
    _click(cb.get_global_rect().get_center())
    await _shot(tag + "_classicas_ligadas.png")
    print("CHECK classicas_ligadas pecas=", tm.active_piece_set, " salvo=", tm.saved_piece_set, " texto=", sub.text)
    # reabrir a página não pode desfazer a escolha
    hub.show_page("main")
    for i in range(4): await process_frame
    hub.show_page("ranking")
    for i in range(4): await process_frame
    print("CHECK reabrir pecas=", tm.active_piece_set, " texto=", sub.text)
    _click(cb.get_global_rect().get_center())
    for i in range(6): await process_frame
    print("CHECK classicas_desligadas pecas=", tm.active_piece_set, " salvo=", tm.saved_piece_set, " texto=", sub.text)
    _click(panel.find_child("RankingBack", true, false).get_global_rect().get_center())
    for i in range(6): await process_frame
    print("CHECK voltar pagina=", hub.page)
    quit(0)
