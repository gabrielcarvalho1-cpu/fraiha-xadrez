extends SceneTree
const Ranked = preload("res://ranked/progression.gd")
var failures = 0
func check(value: bool, label: String):
    print("PASS " if value else "FAIL ",label)
    if not value: failures += 1
func _initialize(): call_deferred("run")
func run():
    var ranked = Ranked.new()
    for row in [[100,10,-3],[60,10,-3],[59,8,-4],[30,8,-4],[29,6,-6],[0,6,-6],[-29,6,-6],[-30,4,-8],[-59,4,-8],[-60,3,-10],[-100,3,-10]]:
        check(Ranked.points(row[0],"win") == row[1] and Ranked.points(row[0],"loss") == row[2],"PL band %d" % row[0])
    ranked.ratings.blitz.lp = 95
    ranked.apply_result("blitz","win",60)
    check(ranked.ratings.blitz.league == 1 and ranked.ratings.blitz.lp == 5,"promotion carries surplus")
    ranked.apply_result("blitz","loss",-100)
    check(ranked.ratings.blitz.league == 1 and ranked.ratings.blitz.lp == 0,"no demotion")
    ranked.apply_result("blitz","draw",0)
    check(ranked.ratings.blitz.games == 3 and ranked.ratings.blitz.draws == 1 and ranked.ratings.blitz.highest_league == 1,"independent statistics")
    for id in ["rapid","normal","classical"]: check(ranked.ratings[id].games == 0 and ranked.ratings[id].league == 0,"unaffected " + id)
    check(ranked.save_local("user://ranked_test.cfg") == OK,"local save")
    var restored = Ranked.new()
    restored.load_local("user://ranked_test.cfg")
    check(restored.ratings == ranked.ratings,"local roundtrip")
    DirAccess.remove_absolute("user://ranked_test.cfg")
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    stage.hub.show_page("ranked")
    check(stage.hub.pages.ranked.visible,"Ranked navigation")
    stage.hub.back()
    check(stage.hub.page == "main" and stage.hub.pages.has("bot"),"Home and Bot preserved")
    stage.hub.show_page("profile")
    check(stage.hub.pages.profile.visible,"Profile opens")
    stage.queue_free()
    await process_frame
    print("V027 FAILURES=",failures)
    quit(failures)
