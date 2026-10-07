extends SceneTree
## R52 · Capturas das telas em painel/modal (Configurações, Contra o Computador, Conheça o FRAIHA) e cliques de verdade.
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 SHOT_TAG=<prefixo> xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/modal_pages_shots.gd
var stage
var hub
var tag := ""

func _initialize():
    call_deferred("run")

func _shot(name: String):
    for i in range(16): await process_frame
    await RenderingServer.frame_post_draw
    var p := OS.get_environment("SHOT_DIR").path_join(tag + "_" + name)
    root.get_texture().get_image().save_png(p)
    print("SHOT ", p)

func _mouse(p: Vector2, down: bool):
    var e := InputEventMouseButton.new()
    e.button_index = MOUSE_BUTTON_LEFT
    e.pressed = down
    e.position = p
    e.global_position = p
    root.push_input(e)

func _click(p: Vector2):
    _mouse(p, true); _mouse(p, false)

func _click_node(page: Control, n: String) -> bool:
    var c: Control = page.find_child(n, true, false)
    if c == null:
        print("CHECK faltando ", n)
        return false
    _click(c.get_global_rect().get_center())
    return true

func _at(page: Control, v: Vector2) -> Vector2:
    return page.get_global_transform() * v

func _centered(page: Control, n: String):
    var bg: Control = page.find_child("RefBg", true, false)
    if bg == null: return
    var r := bg.get_global_rect()
    var vs := root.get_visible_rect().size
    print("CHECK centro ", n, " painel=", r, " tela=", vs, " sobra_esq=", snappedf(r.position.x, 0.1), " sobra_dir=", snappedf(vs.x - r.end.x, 0.1), " sobra_topo=", snappedf(r.position.y, 0.1), " sobra_baixo=", snappedf(vs.y - r.end.y, 0.1))

func run():
    var sz := OS.get_environment("SHOT_SIZE").split("x")
    var px := Vector2i(int(sz[0]), int(sz[1]))
    tag = OS.get_environment("SHOT_TAG")
    DisplayServer.window_set_size(px)
    root.size = px
    root.content_scale_size = Vector2i.ZERO
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(30): await process_frame
    if stage.get("account_ui") != null: stage.account_ui.hide_ui()
    hub = stage.get_node("MainHub")
    var only := OS.get_environment("SHOT_PAGES")
    if only == "" or "settings" in only: await _settings()
    if only == "" or "bots" in only: await _bots()
    if only == "" or "about" in only: await _about()
    quit(0)

func _settings():
    hub.show_page("settings")
    var p: Control = hub.pages["settings"]
    await _shot("config.png")
    _centered(p, "config")
    var ms: HSlider = p.find_child("MusicVolume", true, false)
    var v0 := ms.value
    _click(_at(p, Vector2(600, 562)))
    for i in range(4): await process_frame
    print("CHECK musica antes=", v0, " depois=", ms.value)
    var pm0: bool = hub.premove_enabled
    _click_node(p, "PremoveToggle")
    await _shot("config_premove.png")
    print("CHECK premove antes=", pm0, " depois=", hub.premove_enabled)
    _click_node(p, "PremoveToggle")
    _click_node(p, "SettingsBack")
    for i in range(6): await process_frame
    print("CHECK config voltar pagina=", hub.page)

func _bots():
    # progresso de exemplo: 3 derrotados, Prata disponível (igual à referência)
    var bp = hub.bot_progress
    if bp != null:
        var ids: Array = []
        for b in load("res://bot/bot_ladder.gd").bots(): ids.append(String(b.id))
        for i in range(3): bp.defeated[ids[i]] = 1791300000
        bp.changed.emit()
    hub.show_page("bot")
    var p: Control = hub.pages["bot"]
    await _shot("bots.png")
    _centered(p, "bots")
    var avail := ""
    for b in p.find_children("Challenge_*", "", true, false):
        if not b.disabled: avail = b.name
    print("CHECK bots botoes_ativos ultimo=", avail)
    if avail != "":
        _click_node(p, avail)
        for i in range(6): await process_frame
        print("CHECK bots desafiar -> pagina=", hub.page)
        hub.show_page("bot")
        for i in range(4): await process_frame
    _click_node(p, "BotBack")
    for i in range(6): await process_frame
    print("CHECK bots voltar pagina=", hub.page)

func _about():
    hub.show_page("about")
    var p: Control = hub.pages["about"]
    await _shot("conheca.png")
    _centered(p, "conheca")
    _click_node(p, "AboutTopic2")
    await _shot("conheca_ligas.png")
    print("CHECK conheca topico=", hub.get("about_topic"))
    _click_node(p, "AboutBack")
    for i in range(6): await process_frame
    print("CHECK conheca voltar pagina=", hub.page)
