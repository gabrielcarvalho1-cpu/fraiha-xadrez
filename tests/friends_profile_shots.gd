extends SceneTree
## R52b · Capturas de AMIGOS (lista de exemplo) e PERFIL DO JOGADOR no PC + cliques de verdade.
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 SHOT_TAG=<prefixo> xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/friends_profile_shots.gd
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

func _click(p: Vector2):
    for down in [true, false]:
        var e := InputEventMouseButton.new()
        e.button_index = MOUSE_BUTTON_LEFT
        e.pressed = down
        e.position = p
        e.global_position = p
        root.push_input(e)

func _find(n: Node, name: String) -> Control:
    return n.find_child(name, true, false) as Control

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
    if only == "" or "friends" in only: await _friends()
    if only == "" or "profile" in only: await _profile()
    quit(0)

func _friends():
    var s = stage.social_ui
    s.data = {"friends": [
        {"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior", "presence": "offline"},
        {"user_id": "u2", "nickname": "Gabriel", "avatar_id": "warrior", "presence": "offline"}],
        "received": [], "sent": [], "blocked": []}
    s.has_list = true
    s._show("list")
    await _shot("amigos.png")
    var bg: Control = _find(s.panel, "RefBg")
    if bg != null:
        var r := bg.get_global_rect()
        var vs := root.get_visible_rect().size
        print("CHECK centro amigos sobra_esq=", snappedf(r.position.x, 0.1), " dir=", snappedf(vs.x - r.end.x, 0.1), " topo=", snappedf(r.position.y, 0.1), " baixo=", snappedf(vs.y - r.end.y, 0.1))
    # um amigo online: aparece CONVIDAR
    s.data.friends[0].presence = "online"
    s._show("list")
    await _shot("amigos_online.png")
    # perfil de um amigo e conversa (outras telas do mesmo painel)
    s.profile = {"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior", "presence": "online", "highest_league": 0, "relation": "friend", "ranked": {}}
    s.profile_id = "u1"
    s._show("profile")
    await _shot("amigos_perfil.png")
    s.dm_id = "u1"
    s.dm_peer = {"nickname": "SextoSentro", "avatar_id": "warrior"}
    s.dm_messages = [{"from": "u1", "body": "Bora uma partida?", "created_at": "2026-10-07T18:00:00Z"}]
    s.dm_can_send = true
    s._show("dm")
    await _shot("amigos_conversa.png")
    s._show("list")
    var inp: LineEdit = _find(s.panel, "FriendSearch")
    print("CHECK busca_existe=", inp != null)
    var back: Control = null
    for c in s.find_children("FriendsBack", "", true, false):
        if c.is_visible_in_tree(): back = c
    if back != null: _click(back.get_global_rect().get_center())
    for i in range(6): await process_frame
    print("CHECK amigos voltar aberto=", s.is_open())

func _profile():
    hub.show_page("profile")
    var p: Control = hub.pages["profile"]
    await _shot("perfil.png")
    var bg: Control = _find(p, "RefBg")
    if bg != null:
        var r := bg.get_global_rect()
        var vs := root.get_visible_rect().size
        print("CHECK centro perfil sobra_esq=", snappedf(r.position.x, 0.1), " dir=", snappedf(vs.x - r.end.x, 0.1), " topo=", snappedf(r.position.y, 0.1), " baixo=", snappedf(vs.y - r.end.y, 0.1))
    var card := _find(p, "AvatarCard_archer")
    if card != null:
        _click(card.get_global_rect().get_center())
        await _shot("perfil_arqueira.png")
        print("CHECK perfil inspecionado=", hub.inspected_avatar)
    var icons := _find(p, "ProfileTabIcons")
    if icons != null:
        _click(icons.get_global_rect().get_center())
        await _shot("perfil_icones.png")
    var back := _find(p, "ProfileBack")
    if back != null:
        _click(back.get_global_rect().get_center())
        for i in range(6): await process_frame
    print("CHECK perfil voltar pagina=", hub.page)
