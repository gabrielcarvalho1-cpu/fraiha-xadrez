extends SceneTree
const Rules = preload("res://chess/rules.gd")
const Search = preload("res://bot/search.gd")
const Profile = preload("res://league/local_profile.gd")
const Catalog = preload("res://league/catalog.gd")
const Cosmetics = preload("res://cosmetics/theme_catalog.gd")
var checks := 0
var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
    checks += 1
    if ok: print("PASS ",label)
    else:
        failures += 1
        push_error(label)

func position(board: Dictionary, turn := "w"):
    var p = Rules.new()
    p.board = board.duplicate()
    p.turn = turn
    p.rights = ""
    p.repetitions = {p.position_key():1}
    return p

func run():
    var entries = Catalog.entries(Profile.defaults())
    check(entries.size() == 11 and entries[6].league_id == "esmeralda" and entries[10].league_id == "challenger","all eleven official leagues")
    for entry in entries:
        check(entry.min_lp == 0 and entry.max_lp == 100 and Cosmetics.badge_texture(entry.league_id) != null,entry.display_name+" has badge and 0–100 PL")
    var profile = Profile.new()
    var profile_path = "user://v024-test-profile.json"
    profile.data.lp = 37
    check(profile.save_profile(profile_path) == OK,"profile saved")
    var restored = Profile.new()
    check(restored.load_profile(profile_path) == OK and restored.data.lp == 37,"profile survives round trip")
    var invalid = Profile.validated({"lp":400,"current_league":"bogus","wins":-2})
    check(invalid.lp == 100 and invalid.current_league == "madeira" and invalid.wins == 0,"profile validates bounds and identifiers")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
    for theme in ["wood","iron"]:
        var textures = Cosmetics.piece_textures(theme)
        check(textures.size() == 12,theme+" has twelve pieces")
        var pixels = Cosmetics.texture(Cosmetics.get_theme(theme).pieces_path).get_image()
        check(pixels.detect_alpha() != Image.ALPHA_NONE,theme+" sprites have real transparency")
    var capture = position({Vector2i(0,0):"bQ",Vector2i(6,0):"bK",Vector2i(0,7):"wR",Vector2i(6,7):"wK"})
    var mate = position({Vector2i(7,0):"bK",Vector2i(5,1):"wQ",Vector2i(7,2):"wK"})
    for level in ["hard","expert"]:
        var search = Search.new(1)
        var original = capture.board.duplicate()
        var move = search.choose(capture,level)
        check(move in capture.legal_moves() and move.to == Vector2i(0,0),level+" captures hanging queen legally")
        check(capture.board == original and search.last_metrics.advanced,level+" uses advanced evaluation without mutating position")
        check(search.last_metrics.elapsed_ms < Search.profile(level).budget_ms + 500,level+" respects time budget")
        move = search.choose(mate,level)
        var child = mate.copy_position()
        check(child.play(move) and child.outcome() == "mate",level+" finds mate in one")
        print("METRICS ",level," ",search.last_metrics)
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    var hub = stage.hub
    var before = hub.league_profile.snapshot()
    hub.show_page("ranking")
    check(hub.league_buttons.size() == 11 and hub.pages.ranking.visible,"real league page opens all badges")
    hub.league_buttons.ferro.pressed.emit()
    hub.league_preview_button.pressed.emit()
    check(stage.theme_manager.active_theme == "iron" and stage.game.visual_theme == "iron" and hub.page == "main","Iron preview switches Home and game theme")
    check(hub.league_profile.snapshot() == before,"debug preview neither awards PL nor unlocks leagues")
    stage._start_local()
    check(stage.mode == "local" and stage.game.pieces.size() == 32 and stage.game.bot == null,"Local starts on same World with Iron pieces")
    check(stage.theme_manager.apply_piece_set("classic") and stage.game.piece_textures.size() == 12,"classic pieces remain usable")
    stage.open_home()
    for level in ["hard","expert"]:
        hub.difficulty_buttons[level].pressed.emit()
        check(hub.selected_difficulty == level and hub.page == "bot_side",level+" difficulty button opens side selection")
        hub.side_buttons.b.pressed.emit()
        var elapsed = Time.get_ticks_msec()
        var frames = 0
        var animation = stage.game.anim_time
        while stage.game.move_count == 0 and Time.get_ticks_msec()-elapsed < 4500:
            await process_frame
            frames += 1
        check(stage.game.move_count == 1 and stage.bot_controller.can_interact(),level+" plays White automatically when user chooses Black")
        check(frames > 10 and stage.game.anim_time > animation,level+" worker keeps interface and animation running")
        stage.return_to_home()
        check(stage.bot_controller.paused and not stage.bot_controller.can_interact(),"abandon dialog blocks board")
        stage._confirm_navigation()
        check(stage.mode == "home" and not stage.bot_controller.active,"confirmed abandonment returns Home")
    hub.theme_preview_requested.emit("wood")
    check(stage.theme_manager.active_theme == "wood" and stage.forest.visible,"Madeira can be restored")
    check(hub.league_profile.snapshot() == before,"games/previews do not invent ranked rewards")
    stage.queue_free()
    await process_frame
    print("V024 CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures == 0 else 1)
