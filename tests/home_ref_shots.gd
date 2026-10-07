extends SceneTree
## Capturas da HOME para comparar com as referências (PC 1672x941 · celular 854x1842 = 427x921 CSS @2x).
## Uso (numa CÓPIA do projeto, com xvfb): tests/run_home_ref_shots.sh <pasta>
## Env: HOME_SHOT_OUT=<arquivo.png>  HOME_SHOT_SIZE=1672x941  HOME_SHOT_CSS=427x921 (só celular)
##      HOME_SHOT_LOGGED=1 → conta de exemplo "SextoSen1" (só a interface; nada de rede)
##      HOME_SHOT_CASUAL_OFF=1 → Home com o Casual fechado (JOGAR ONLINE indisponível)
##      HOME_SHOT_HOVER=2,5 → liga o brilho de hover desses botões do PC (conferência visual)
var stage

func _initialize():
    call_deferred("run")

func run():
    var out := OS.get_environment("HOME_SHOT_OUT")
    var sz := OS.get_environment("HOME_SHOT_SIZE").split("x")
    var css := OS.get_environment("HOME_SHOT_CSS")
    var px := Vector2i(int(sz[0]), int(sz[1]))
    DisplayServer.window_set_size(px)
    root.size = px
    if css.is_empty():
        root.content_scale_size = Vector2i.ZERO
    else:
        var c := css.split("x")
        root.set_meta("mobile_resize_busy", true)   # a captura fixa o tamanho CSS (DPR 2)
        root.content_scale_size = Vector2i(int(c[0]), int(c[1]))
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(30): await process_frame
    var hub = stage.get_node("MainHub")
    if OS.get_environment("HOME_SHOT_LOGGED") == "1":
        hub.player_name = "SextoSen1"
        if is_instance_valid(hub.profile_name): hub.profile_name.text = "SextoSen1"
        if hub.has_method("set_account_card"): hub.set_account_card("MINHA CONTA", "SextoSen1", true)
        var photo := OS.get_environment("HOME_SHOT_AVATAR")
        if not photo.is_empty():
            var img := Image.load_from_file(photo)
            if img != null:
                hub.set_meta("shot_avatar", ImageTexture.create_from_image(img))
        if hub.has_method("shot_refresh"): hub.shot_refresh()
    var acc = stage.get_node_or_null("AccountUI")
    if acc != null and acc.has_method("hide_ui"): acc.hide_ui()
    if stage.get("account_ui") != null: stage.account_ui.hide_ui()
    if OS.get_environment("HOME_SHOT_CASUAL_OFF") == "1":   # R48: Casual fechado pelo Admin (como o servidor avisaria)
        stage.account._set_casual_modes([])
        hub.refresh_online_button()
    var pg := OS.get_environment("HOME_SHOT_PAGE")   # abre uma página interna antes da captura
    if pg == "mais" and is_instance_valid(hub.mobile_ui): hub.mobile_ui.show_page("mais")
    elif not pg.is_empty(): hub.show_page(pg)
    var hov := OS.get_environment("HOME_SHOT_HOVER")   # índices dos botões do PC com o brilho de hover ligado
    if not hov.is_empty() and not is_instance_valid(hub.mobile_ui):
        for k in hov.split(","): hub.ref_hovers[hub.menu_buttons[int(k)]].show()
    for i in range(20): await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(out)
    print("SHOT ", out, " ", root.get_texture().get_image().get_size())
    quit(0)
