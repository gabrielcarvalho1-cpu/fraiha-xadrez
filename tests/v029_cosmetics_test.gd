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
    # R53 · desde que os cenários superiores passaram a ser liberados só pelo Ranked (a Madeira é o único
    # liberado para convidado/perfil novo), o teste usa o caminho REAL de liberação: uma conta (estado que o
    # acct_state preencheria, sem rede) com o Ranked já no Challenger. No fim a conta é desfeita e a Madeira volta.
    var acc = stage.account
    acc.user_id = "u1"
    acc.access_token = "teste"
    acc.server_ready = true
    acc.profile = {"user_id": "u1", "nickname": "Tester", "avatar_id": "warrior"}
    acc.ranked = {"ranked_3min": {"league": 10, "pl": 0, "highest_league": 10}}
    stage._sync_theme_unlocks()
    await process_frame
    var shots := String(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else ""
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
        if not shots.is_empty(): viewport.get_texture().get_image().save_png(shots+"/"+id+".png")
        stage.open_home()
        stage.hub._select_league(id)
        # R53 · o botão "TESTAR UNIVERSO" virou ferramenta interna (DEV_PREVIEW_BUTTON = false): só aparece quando ligado.
        check(stage.hub.league_preview_button.visible == stage.hub.DEV_PREVIEW_BUTTON and stage.hub.league_scene_preview.texture != null,id+" league preview")
    check(stage.hub.ranked.ratings == original,"preview leaves PL unchanged")
    check(stage.theme_manager.apply_theme("wood"),"return to original theme")
    acc.profile = {}
    acc.ranked = {}
    acc.access_token = ""
    acc.user_id = ""
    acc.server_ready = false
    stage._sync_theme_unlocks()
    stage.hub.show_page("ranking")
    for i in range(3): await process_frame
    await RenderingServer.frame_post_draw
    if not shots.is_empty(): viewport.get_texture().get_image().save_png(shots+"/ranking.png")
    viewport.queue_free()
    await process_frame
    print("V029 FAILURES=",failures)
    quit(1 if failures > 0 else 0)
