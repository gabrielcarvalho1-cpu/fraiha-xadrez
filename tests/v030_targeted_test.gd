extends SceneTree
const Rules = preload("res://chess/rules.gd")
var failures = 0
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ",label)
    if not ok: failures += 1
func move(a:String,b:String) -> Dictionary:
    return {"from":Vector2i(a.unicode_at(0)-97,8-int(a[1])),"to":Vector2i(b.unicode_at(0)-97,8-int(b[1])),"promotion":"Q"}
func _initialize(): call_deferred("run")
func run():
    var viewport = SubViewport.new()
    viewport.size = Vector2i(1600,900)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    viewport.add_child(stage)
    await process_frame
    stage._start_local()
    var c = stage.bot_controller
    for pair in [["e2","e4"],["a7","a6"],["e4","e5"],["d7","d5"],["e5","d6"]]:
        var m = move(pair[0],pair[1])
        check(c.request_move(m.from,m.to),"Local " + pair[0]+pair[1])
    check(not stage.game.pieces.has(Vector2i(3,3)) and stage.game.pieces.get(Vector2i(3,2)) == "wP" and stage.game.captured_black == ["bP"],"white EP removes victim and records capture")
    c.restart()
    for pair in [["a2","a3"],["e7","e5"],["a3","a4"],["e5","e4"],["d2","d4"],["e4","d3"]]:
        var m = move(pair[0],pair[1])
        check(c.request_move(m.from,m.to),"Local " + pair[0]+pair[1])
    check(not stage.game.pieces.has(Vector2i(3,4)) and stage.game.captured_white == ["wP"],"black EP removes victim")
    c.restart()
    for pair in [["e2","e4"],["a7","a6"],["e4","e5"],["d7","d5"],["h2","h3"],["a6","a5"]]: c._apply(move(pair[0],pair[1]))
    check(not c.request_move(Vector2i(4,3),Vector2i(3,2)),"EP expires after one opportunity")
    var r = Rules.new()
    r.board = {Vector2i(7,3):"wK",Vector2i(6,3):"wP",Vector2i(5,1):"bP",Vector2i(0,3):"bR",Vector2i(0,0):"bK"}
    r.turn = "b"
    r.rights = ""
    r.play(move("f7","f5"))
    check(not r.play(move("g5","f6")),"EP cannot expose king")
    stage._start_bot("easy","w")
    for pair in [["e2","e4"],["a7","a6"],["e4","e5"],["d7","d5"]]: check(c._apply(move(pair[0],pair[1])),"Bot bridge setup")
    check(c.request_move(Vector2i(4,3),Vector2i(3,2)) and not stage.game.pieces.has(Vector2i(3,3)),"Bot human EP shares engine")
    stage.open_home()
    for id in ["madeira","ferro","bronze","prata","ouro","platina","esmeralda","diamante","mestre","grande_mestre","challenger"]:
        stage.hub._select_league(id)
        var theme = preload("res://league/catalog.gd").theme_for(id)
        check(stage.theme_manager.active_theme == theme,"select applies " + id)
        var data = preload("res://cosmetics/theme_catalog.gd").get_theme(theme)
        var expected:String = data.arena_path if data.get("free_arena",false) else data.home_path
        check(stage.hub.canvas.get_node("ForestArtwork").texture.resource_path == expected,"Home background " + id)
    check(stage.hub.avatar_texture("paladin") != null,"Paladin loads")
    check(stage.hub.avatar_choices.size() == 4,"four avatars")
    for id in stage.hub.avatar_choices:
        check(stage.hub.avatar_choices[id].get_node("LeagueFrame").league_id == stage.hub.league_profile.data.current_league,"actual league frame " + id)
    for page in ["main","ranking","profile"]:
        stage.hub.show_page(page)
        for i in range(4): await process_frame
        await RenderingServer.frame_post_draw
        viewport.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]+"/"+page+".png")
    viewport.queue_free()
    await process_frame
    print("V030 FAILURES=",failures)
    quit(failures)
