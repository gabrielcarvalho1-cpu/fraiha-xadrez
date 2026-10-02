extends SceneTree
## Tela cheia no desktop: exclusiva por padrão; Alt+Enter (só desktop) alterna janela <-> exclusiva.
## Sem botão/opção TELA CHEIA (R29). Web: tela cheia real pedida no 1º gesto do jogador.
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
    # R29: não existe mais opção/botão de TELA CHEIA (o jogo sempre usa a área máxima).
    var found := []
    for n in stage.find_children("*", "", true, false):
        if n is Button and String(n.text).to_lower().contains("tela cheia"): found.append(n.get_path())
        if String(n.name) == "FullscreenButton": found.append(n.get_path())
    check(found.is_empty(), "nenhum botão TELA CHEIA / FullscreenButton na árvore %s" % [found])
    check(not stage.hub.has_method("_toggle_fullscreen") and stage.hub.get("fullscreen") == null, "Configurações sem opção de tela cheia (sem estado no hub)")
    stage.hub.show_page("settings")
    await frames(3)
    var settings_text := ""
    for n in stage.hub.pages.settings.find_children("*", "", true, false):
        if n is Button or n is Label: settings_text += String(n.text) + "\n"
    check(not settings_text.to_upper().contains("TELA CHEIA:"), "página Configurações não mostra TELA CHEIA")
    stage.hub._save_preferences()
    var cfg := ConfigFile.new()
    cfg.load(stage.hub.PREFS)
    check(not cfg.has_section_key("video", "fullscreen"), "nenhuma preferência persistente de tela cheia")
    check(stage.has_method("_web_fullscreen_once"), "Web: pedido de tela cheia no 1º gesto (_web_fullscreen_once)")
    var js: String = stage.WEB_FULLSCREEN_JS
    check(js.contains("documentElement") and js.contains("requestFullscreen"), "Web: tela cheia da página inteira (documentElement)")
    check(js.contains("keyboard.lock") or js.contains("k.lock(['Escape'])"), "Web: Keyboard Lock do Esc em tela cheia (Esc curto volta a página sem derrubar a tela cheia)")
    check(js.contains("lost >= 3") and not js.contains("exitFullscreen"), "Web: re-tenta no próximo gesto se cair; nunca sai da tela cheia por conta própria")
    # Trocar de página interna NÃO mexe no modo nem no tamanho da janela
    var win2 = stage.get_window()
    var mode0 = win2.mode
    var size0 = win2.size
    for pg in ["bot", "main", "profile", "settings", "main"]:
        stage.hub.show_page(pg)
        await frames(3)
    stage.open_home()
    await frames(3)
    check(win2.mode == mode0 and win2.size == size0, "Home → Bots → Home → Perfil → Configurações → Home: modo/tamanho da janela intactos")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
