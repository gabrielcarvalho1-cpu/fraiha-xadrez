extends SceneTree
## Tela cheia no desktop: exclusiva por padrão; TELA CHEIA e Alt+Enter alternam janela <-> exclusiva.
## Web continua com janela (mode.web=0). Rodar com janela real: xvfb-run ... -s tests/fullscreen_mode_test.gd
var failures = 0
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func frames(n: int):
    for i in range(n): await process_frame
func run():
    check(int(ProjectSettings.get_setting("display/window/size/mode")) == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, "project.godot: desktop inicia em tela cheia EXCLUSIVA (mode=4)")
    check(int(ProjectSettings.get_setting("display/window/size/mode.web", -1)) == DisplayServer.WINDOW_MODE_WINDOWED, "Web continua em janela (mode.web=0)")
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await frames(5)
    var win = stage.get_window()
    if DisplayServer.get_name() == "headless":
        print("AVISO: headless não troca modo de janela; rode com xvfb-run para os passos abaixo")
    else:
        win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN  # o -s script não aplica o modo do projeto na janela principal
        await frames(5)
        stage.toggle_fullscreen()
        await frames(5)
        check(win.mode == Window.MODE_WINDOWED, "TELA CHEIA: exclusiva -> janela")
        stage.toggle_fullscreen()
        await frames(5)
        check(win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN, "TELA CHEIA: janela -> exclusiva (não volta para a não exclusiva)")
        var alt = InputEventKey.new()
        alt.keycode = KEY_ENTER
        alt.alt_pressed = true
        alt.pressed = true
        Input.parse_input_event(alt)
        await frames(5)
        check(win.mode == Window.MODE_WINDOWED, "Alt+Enter: exclusiva -> janela")
        Input.parse_input_event(alt)
        await frames(5)
        check(win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN, "Alt+Enter: janela -> exclusiva")
        stage.hub._toggle_fullscreen()
        await frames(5)
        check(win.mode == Window.MODE_WINDOWED and not stage.hub.fullscreen, "botão TELA CHEIA da Home: volta para janela e atualiza o estado")
        stage.hub._toggle_fullscreen()
        await frames(5)
        check(win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN and stage.hub.fullscreen, "botão TELA CHEIA da Home: volta para exclusiva")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
