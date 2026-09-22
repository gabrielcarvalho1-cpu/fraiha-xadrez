extends SceneTree
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
    checks += 1
    if ok: print("PASS ",label)
    else:
        failures += 1
        push_error(label)
func run():
    check(ProjectSettings.get_setting("display/window/size/mode") == Window.MODE_FULLSCREEN,"fullscreen configured before native window creation")
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    var audio = stage.get_node("GameAudio")
    var hub = stage.hub
    check(audio.music_path.ends_with("wood.mp3") and audio.music.playing,"Home starts Madeira")
    var starts = audio.music_starts
    stage._start_local()
    await process_frame
    check(audio.music_starts == starts,"Home to Madeira game does not restart track")
    stage.open_home()
    await process_frame
    check(audio.music_starts == starts,"Madeira game to Home preserves playback")
    for theme in ["wood","iron","bronze","silver","gold"]:
        stage.theme_manager.apply_theme(theme)
        stage._start_local()
        await process_frame
        check(audio.music_path.ends_with(theme+".mp3") and audio.music.playing,theme+" selects supplied music")
        var stream: AudioStreamMP3 = audio.music.stream
        check(stream.loop and stream.loop_offset == 0 and stream.get_length() > 30,theme+" full track loop from zero")
        print("TRACK ",theme," seconds=",stream.get_length())
        audio.music.seek(stream.get_length()-0.15)
        await create_timer(0.5).timeout
        check(audio.music.playing and audio.music.get_playback_position() < 1.5,theme+" actually wraps after end")
        stage.open_home()
        await process_frame
        check(audio.music_path.ends_with("wood.mp3"),theme+" returns to Home Madeira")
    var effects_bus = AudioServer.get_bus_index("Effects")
    var music_bus = AudioServer.get_bus_index("Music")
    hub._set_volume(80,false)
    hub._set_music_volume(0,false)
    check(AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(effects_bus),"music mute leaves chess effects enabled")
    hub._set_music_volume(65,false)
    hub._set_volume(0,false)
    check(not AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(effects_bus),"effect mute leaves music enabled")
    hub._set_volume(80,false)
    check(stage.game.sound_ambient == null and stage.game.sound_water == null and not audio.streams.has("castle"),"old environmental players absent")
    check(audio.players.size() == 4 and audio.players[0].bus == "Effects" and audio.music.bus == "Music","one music player and separate chess effect pool")
    stage.theme_manager.apply_theme("wood")
    stage._start_local()
    await process_frame
    for cell in [Vector2i(4,6),Vector2i(4,4)]:
        var click = InputEventMouseButton.new()
        click.pressed = true
        click.button_index = MOUSE_BUTTON_LEFT
        click.position = stage.game.square_center(cell)
        stage.game._handle_game_input(click)
    await process_frame
    check(audio.last_cue == "wood","real piece move still triggers chess sound")
    for resolution in [Vector2i(1920,1080),Vector2i(1600,900),Vector2i(1366,768)]:
        root.size = resolution
        await process_frame
        for theme in ["bronze","wood","iron"]:
            stage.theme_manager.apply_theme(theme)
            var game = stage.game
            var valid: bool = is_equal_approx(game.scale.x,game.scale.y)
            var spacing: float = game.square_center(Vector2i(1,0)).distance_to(game.square_center(Vector2i(0,0)))
            for y in range(8):
                for x in range(8):
                    var center = game.square_center(Vector2i(x,y))
                    valid = valid and game.cell_at(center) == Vector2i(x,y)
                    if y < 7: valid = valid and is_equal_approx(center.distance_to(game.square_center(Vector2i(x,y+1))),spacing)
            check(valid,theme+" square grid and centered input "+str(resolution))
    stage.queue_free()
    await process_frame
    print("V026 CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures == 0 else 1)
