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
    # R29.2: UM botão de tela cheia na Home, ao lado do som (entra/sai); nada nas Configurações.
    var fs_btn = stage.hub.fullscreen_button
    check(fs_btn != null and fs_btn.get_parent() == stage.hub.canvas, "Home: botão de tela cheia existe")
    check(fs_btn != null and absf(fs_btn.position.y - stage.hub.sound_button.position.y) < 1.0 and fs_btn.position.x > stage.hub.sound_button.position.x, "botão de tela cheia ao lado do som")
    check(stage.screen_mode != null and stage.screen_mode.supported() and fs_btn.visible, "desktop: botão visível")
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
    var FC = preload("res://ui_v022/fullscreen_control.gd")
    check(FC.JS_ENTER.contains("documentElement") and FC.JS_ENTER.contains("requestFullscreen"), "Web: tela cheia da página inteira (documentElement)")
    check(FC.JS_EXIT.contains("exitFullscreen"), "Web: botão também SAI da tela cheia (exitFullscreen)")
    var all_js: String = FC.JS_SETUP + FC.JS_ENTER + FC.JS_EXIT + FC.JS_AUTO
    check(FC.JS_SETUP.contains("kb.lock(['Escape'])") and FC.JS_SETUP.contains("kb.unlock"), "Web (R35.1): com a tela cheia ativa o Esc é travado para o jogo (Keyboard Lock); sair = botão ou segurar Esc")
    check(FC.JS_AUTO.contains("userLeft") and FC.JS_AUTO.contains("autoDone"), "Web: pedido automático só 1x e nunca depois que o jogador sai")
    check(FC.SITE_URL == "https://fraihaxadrez.com/", "Web: SAIR volta para fraihaxadrez.com")
    # Desktop: o botão alterna nos dois sentidos
    if DisplayServer.get_name() != "headless":
        var w3 = stage.get_window()
        w3.mode = Window.MODE_WINDOWED
        await frames(5)
        fs_btn.pressed.emit()
        await frames(5)
        check(stage.screen_mode.is_on(), "desktop: botão entra em tela cheia")
        await frames(15)
        check(fs_btn.glyph == "exit_fullscreen", "desktop: ícone vira SAIR da tela cheia")
        fs_btn.pressed.emit()
        await frames(5)
        check(not stage.screen_mode.is_on(), "desktop: botão sai da tela cheia")
        await frames(15)
        check(fs_btn.glyph == "fullscreen", "desktop: ícone volta a ENTRAR em tela cheia")
        w3.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
        await frames(5)
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
