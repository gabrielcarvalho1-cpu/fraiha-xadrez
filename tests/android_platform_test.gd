extends SceneTree
## Android 01 · lógica de plataforma testável sem aparelho:
## escala dp, safe area nativa, botão Voltar (= Esc) e sanidade do preset/projeto Android.

const Mobile := preload("res://ui_v022/mobile_layout.gd")

var checks := 0
var failures := 0

func verify(ok: bool, description: String):
    checks += 1
    if ok:
        print("PASS: " + description)
    else:
        failures += 1
        push_error(description)

func _initialize():
    call_deferred("run")

func run():
    _density()
    _safe_area()
    _project_settings()
    _preset()
    await _back_button()
    print("android_platform_test: %d checks, %d failures" % [checks, failures])
    quit(1 if failures > 0 else 0)

func _density():
    verify(Mobile.dp_size(Vector2i(1080, 2400), 420) == Vector2i(411, 914), "1080x2400 @420dpi vira 411x914 dp (tamanho CSS de celular)")
    verify(Mobile.dp_size(Vector2i(2400, 1080), 420) == Vector2i(914, 411), "paisagem converte com a mesma densidade")
    verify(Mobile.dp_size(Vector2i(720, 1280), 0) == Vector2i(720, 1280), "DPI desconhecido não escala")
    verify(Mobile.dp_size(Vector2i(480, 800), 120) == Vector2i(480, 800), "densidade < 1x nunca amplia a viewport")

func _safe_area():
    var ins: Array = Mobile.native_insets(Vector2i(1080, 2400), Rect2i(0, 100, 1080, 2200), Vector2(411, 914))
    verify(is_equal_approx(ins[0], 0.0) and is_equal_approx(ins[2], 0.0), "sem recorte lateral → margens laterais zero")
    verify(absf(ins[1] - 38.08) < 0.1 and absf(ins[3] - 38.08) < 0.1, "notch/barra de 100 px físicos vira ~38 dp em cima e embaixo")
    var land: Array = Mobile.native_insets(Vector2i(2400, 1080), Rect2i(100, 0, 2200, 1080), Vector2(914, 411))
    verify(absf(land[0] - 38.08) < 0.1 and is_equal_approx(land[1], 0.0), "em paisagem o recorte vai para a lateral")
    var bad: Array = Mobile.native_insets(Vector2i(1080, 2400), Rect2i(), Vector2(411, 914))
    verify(bad == [0.0, 0.0, 0.0, 0.0], "safe area vazia/inválida não gera margens absurdas")

func _project_settings():
    verify(ProjectSettings.get_setting("application/config/quit_on_go_back", true) == false, "Voltar do Android não fecha o app direto (quit_on_go_back=false)")
    verify(int(ProjectSettings.get_setting("display/window/handheld/orientation", 0)) == DisplayServer.SCREEN_SENSOR, "orientação sensor: retrato e paisagem")
    verify(bool(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false)), "texturas ETC2/ASTC importadas (exigência do export Android)")

func _preset():
    var cfg := ConfigFile.new()
    verify(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg carrega")
    var sec := ""
    for s in cfg.get_sections():
        if not s.ends_with(".options") and String(cfg.get_value(s, "platform", "")) == "Android":
            sec = s
    verify(not sec.is_empty(), "existe preset Android")
    if sec.is_empty():
        return
    var o := sec + ".options"
    verify(String(cfg.get_value(o, "package/unique_name", "")) == "com.fraiha.xadrez.dev", "package ID DEV temporário")
    verify(bool(cfg.get_value(o, "architectures/arm64-v8a", false)), "ARM64 incluído")
    var other_abi := false
    for abi in ["armeabi-v7a", "x86", "x86_64"]:
        other_abi = other_abi or bool(cfg.get_value(o, "architectures/" + abi, false))
    verify(not other_abi, "nenhum ABI extra sem pedido")
    verify(not bool(cfg.get_value(o, "gradle_build/use_gradle_build", false)), "sem custom build Gradle (pasta android/ fora do Git)")
    var perms := []
    for k in cfg.get_section_keys(o):
        if k.begins_with("permissions/") and k != "permissions/custom_permissions" and bool(cfg.get_value(o, k, false)):
            perms.append(k)
    verify(perms == ["permissions/internet"], "só a permissão INTERNET (sem microfone, câmera, localização, armazenamento)")
    var leaked := []
    for k in cfg.get_section_keys(o):
        if ("password" in k or "keystore" in k or "_pass" in k) and not String(cfg.get_value(o, k, "")).is_empty():
            leaked.append(k)
    verify(leaked.is_empty(), "preset sem senha/keystore preenchidos")
    verify("staging" in String(cfg.get_value(sec, "custom_features", "")), "build DEV aponta para staging, nunca produção")

func _back_button():
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    var world = stage.get_node("World")
    var hub = stage.get_node("MainHub")
    verify(stage.mode == "home", "começa na Home")
    verify(stage.account_ui.is_open(), "modal de login começa aberto sem sessão salva")

    stage._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
    await process_frame
    await process_frame
    verify(not stage.account_ui.is_open(), "Voltar fecha primeiro o modal de login")
    verify(stage.mode == "home" and is_instance_valid(stage) and stage.is_inside_tree(), "Voltar na Home não encerra o app")

    hub.play_local_requested.emit()
    await process_frame
    stage._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
    await process_frame
    await process_frame
    verify(stage.mode == "home", "Voltar num tabuleiro vazio retorna à Home")

    hub.play_local_requested.emit()
    world._select(Vector2i(4, 6))
    var move = InputEventMouseButton.new()
    move.button_index = MOUSE_BUTTON_LEFT
    move.pressed = true
    move.position = world.ORIGIN + Vector2(4.5, 4.5) * world.TILE
    world._handle_game_input(move)
    verify(world.move_count == 1, "partida local com lance feito")
    stage._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
    await process_frame
    await process_frame
    verify(stage.mode == "local" and stage.navigation_dialog.visible and world.move_count == 1, "Voltar em partida pede confirmação e não sai em silêncio")
    stage._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
    await process_frame
    await process_frame
    verify(stage.mode == "local" and not stage.navigation_dialog.visible, "Voltar com o diálogo aberto só fecha o diálogo")
    stage.queue_free()
    await process_frame
