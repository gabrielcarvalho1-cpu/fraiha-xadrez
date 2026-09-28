extends SceneTree
const Catalog = preload("res://cosmetics/theme_catalog.gd")
const IDS = ["platina","esmeralda","diamante","mestre","grande_mestre","challenger"]
var failures = 0
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ",label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func run():
    var viewport = SubViewport.new()
    viewport.size = Vector2i(1600,900)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    viewport.add_child(stage)
    await process_frame
    var original = stage.hub.ranked.ratings.duplicate(true)
    for id in IDS:
        var data = Catalog.get_theme(id)
        check(stage.theme_manager.apply_theme(id),id+" applies")
        var pieces = Catalog.piece_textures(id)
        check(pieces.size() == 12 and stage.theme_manager.active_piece_set == id,id+" twelve own pieces")
        var atlas = load(data.pieces_path).get_image()
        check(atlas.detect_alpha() != Image.ALPHA_NONE,id+" transparent pieces")
        stage._start_local()
        for i in range(4): await process_frame
        check(stage.get_node("GameAudio").music_path == data.music_path and ResourceLoader.exists(data.music_path),id+" existing music")
        check(is_equal_approx(stage.game.scale.x,stage.game.scale.y),id+" square board")
        await RenderingServer.frame_post_draw
        viewport.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]+"/"+id+".png")
        stage.open_home()
        stage.hub._select_league(id)
        check(stage.hub.league_preview_button.visible and stage.hub.league_scene_preview.texture != null,id+" league preview")
    check(stage.hub.ranked.ratings == original,"preview leaves PL unchanged")
    check(stage.theme_manager.apply_theme("wood"),"return to original theme")
    stage.hub.show_page("ranking")
    for i in range(3): await process_frame
    await RenderingServer.frame_post_draw
    viewport.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]+"/ranking.png")
    viewport.queue_free()
    await process_frame
    print("V029 FAILURES=",failures)
    quit(failures)
