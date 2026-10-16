extends SceneTree
const Catalog = preload("res://cosmetics/theme_catalog.gd")
const MobileLayout = preload("res://ui_v022/mobile_layout.gd")
var checks := 0
var failures := 0
var stage
var world
class OnlineProbe extends RefCounted:
    var color = "b"
    var actions := []
    func can_interact(): return true
    func send_action(action, payload = {}): actions.append({"action":action,"payload":payload})

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
    checks += 1
    if ok: print("PASS ",label)
    else:
        failures += 1
        push_error(label)
func click(point: Vector2):
    var event = InputEventMouseButton.new()
    event.pressed = true
    event.button_index = MOUSE_BUTTON_LEFT
    event.position = point
    world._handle_game_input(event)
func run():
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await process_frame
    # R127 · os universos agora são liberados pela liga do Ranked: o teste simula uma conta que já chegou ao topo
    var acc = stage.account
    acc.access_token = "t"; acc.user_id = "u"; acc.server_ready = true
    acc.profile = {"nickname": "Teste"}
    acc.ranked = {"ranked_3min": {"highest_league": 10}, "ranked_5min": {"highest_league": 10}, "ranked_10min": {"highest_league": 10}, "ranked_20min": {"highest_league": 10}}
    stage._sync_theme_unlocks()
    world = stage.game
    var hub = stage.hub
    var before = hub.league_profile.snapshot()
    for theme in ["wood","iron","bronze","silver","gold"]:
        # R127 · as peças seguem a escolha do jogador (Madeira usa as clássicas): confere o universo aplicado
        check(stage.theme_manager.apply_theme(theme) and stage.theme_manager.active_theme == theme,theme+" applies complete universe")
        check(world.piece_textures.size() == 12,theme+" has full light/dark set")
        if theme in ["bronze","silver","gold"]:
            var pixels = Catalog.texture(Catalog.get_theme(theme).pieces_path).get_image()
            check(pixels.detect_alpha() != Image.ALPHA_NONE,theme+" true transparent sprites")
            check(world.piece_textures.bP.region.size.y < 350,theme+" clean pawn atlas cell")
        stage._start_local()
        check(not world.board_flipped() and world.pieces.size() == 32,theme+" preserves Local orientation")
        stage.open_home()
    check(hub.league_profile.snapshot() == before,"five debug themes do not award PL")
    for league in ["bronze","prata","ouro"]:
        hub.show_page("ranking")
        hub._select_league(league)
        # R127 · "TESTAR UNIVERSO" virou ferramenta interna (DEV_PREVIEW_BUTTON): só confere quando ligada
        check((hub.league_preview_button.visible if hub.DEV_PREVIEW_BUTTON else not hub.league_preview_button.visible) and hub.league_scene_preview.texture != null,league+" has working preview")
    var original_avatar: String = hub.avatar_id
    # R127 · avatares agora se conquistam (ligas/bots/Premium): o teste usa dois liberados e com arte
    var free_av: Array = Array(hub.AvatarCatalog.ids()).filter(func(a): return hub.avatar_unlocked(a) and hub.AvatarCatalog.has_art(a) and a != original_avatar)
    check(free_av.size() >= 1, "há avatar liberado para trocar")
    var pick: String = free_av[0] if free_av.size() > 0 else original_avatar
    hub.choose_avatar(pick)
    check(hub.avatar_id == pick,"avatar chosen and displayed")
    hub.avatar_id = original_avatar
    hub._load_preferences()
    check(hub.avatar_id == pick,"avatar persists")
    hub.choose_avatar(original_avatar)
    stage._start_bot("easy","b")
    var deadline = Time.get_ticks_msec()+2000
    while world.move_count == 0 and Time.get_ticks_msec() < deadline: await process_frame
    check(world.move_count == 1 and world.board_flipped(),"Black human receives automatic White reply on flipped board")
    check(world.square_center(Vector2i(0,0)).is_equal_approx(world.ORIGIN+Vector2(7.5,7.5)*world.TILE),"black a8 appears at lower right")
    check(world.cell_at(world.ORIGIN+Vector2(3.5,6.5)*world.TILE) == Vector2i(4,1),"visual d2 maps to logical e7")
    click(world.ORIGIN+Vector2(3.5,6.5)*world.TILE)
    click(world.ORIGIN+Vector2(3.5,4.5)*world.TILE)
    check(stage.bot_controller.rules.piece(Vector2i(4,3)) == "bP" and world.move_count == 2,"Black click move uses engine coordinates")
    stage.open_home()
    stage._start_bot("easy","b")
    var bot = stage.bot_controller
    bot.rules.board = {Vector2i(0,6):"bP",Vector2i(7,0):"bK",Vector2i(7,7):"wK"}
    bot.rules.turn = "b"
    bot.rules.rights = ""
    bot.rules.repetitions = {bot.rules.position_key():1}
    bot.thinking = false
    bot._sync_view()
    click(world.square_center(Vector2i(0,6)))
    click(world.square_center(Vector2i(0,7)))
    check(world.promotion_pending,"Black flipped board opens promotion")
    if stage.mobile_promotion != null and MobileLayout.active(root):
        # celular: a escolha é o painel do palco (botões Dama/Torre/Bispo/Cavalo), tocado de verdade.
        # O teste abre a partida direto (sem conta): a tela de login do início ainda estaria por cima.
        if stage.account_ui.is_open(): stage.account_ui.hide_ui()
        await process_frame
        stage._layout()
        await process_frame
        var dama: Button = null
        for b in stage.mobile_promotion.find_children("*", "Button", true, false):
            if b.text == "Dama": dama = b
        check(stage.mobile_promotion.visible and dama != null and dama.is_visible_in_tree(), "celular: painel da promoção aparece")
        if dama != null:
            var at: Vector2 = dama.get_global_rect().get_center()
            for down in [true, false]:
                var ev := InputEventMouseButton.new()
                ev.button_index = MOUSE_BUTTON_LEFT
                ev.pressed = down
                ev.position = at
                ev.global_position = at
                root.push_input(ev, true)
                await process_frame
    else:
        click(Vector2(320,520))
    check(bot.rules.piece(Vector2i(0,7)) == "bQ" and not world.promotion_pending,"promotion dialog stays upright and functional")
    stage.open_home()
    stage._start_local()
    var probe = OnlineProbe.new()
    world.bot = null   # R127 · a partida local guarda o controlador do bot anterior; aqui é o caminho online (world.online)
    world.online = probe
    world.turn = "b"
    click(world.ORIGIN+Vector2(3.5,6.5)*world.TILE)
    click(world.ORIGIN+Vector2(3.5,4.5)*world.TILE)
    check(probe.actions.size() == 1 and probe.actions[0].payload == {"from":[4,1],"to":[4,3]},"Online Black sends unchanged logical move payload")
    probe.actions.clear()
    world.selected = Vector2i(-1,-1)
    var press = InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = world.ORIGIN+Vector2(3.5,6.5)*world.TILE
    world._drag_input(press)
    var motion = InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.position = world.ORIGIN+Vector2(3.5,4.5)*world.TILE
    world._drag_input(motion)
    press.pressed = false
    press.position = motion.position
    world._drag_input(press)
    check(probe.actions.size() == 1 and probe.actions[0].payload.to == [4,3],"Black drag uses unchanged protocol coordinates")
    world.online = null
    stage.open_home()
    stage._open_online()
    check(stage.online.join_tab.visible and not stage.online.create_tab.visible,"Online starts on invitation entry tab")
    stage.online.room_input.text = "ABC"
    stage.online.connect_room({"type":"join","room":"ABC"})
    check("6" in stage.online.menu_info.text and not stage.online.online_mode,"Online validates code without connecting")
    stage.return_to_home()
    check(stage.mode == "home","Online navigation preserved")
    var audio = stage.get_node("GameAudio")
    for cue in audio.streams:
        check(audio.streams[cue] != null and audio.streams[cue].get_length() > 0.05,"audio loads "+cue)
    stage._start_local()
    # alguns quadros para o GameAudio registrar a partida nova antes do 1º lance (um jogador nunca lança no mesmo quadro)
    for _i in 4: await process_frame
    click(world.square_center(Vector2i(4,6)))
    click(world.square_center(Vector2i(4,4)))
    # o som chega no _process do GameAudio: espera alguns quadros (no celular o som da promoção anterior ainda podia ser o último)
    for _i in 30:
        await process_frame
        if audio.last_cue == "metal": break
    check(audio.last_cue == "metal","new move triggers theme sound")
    stage.open_home()
    check(hub.league_profile.snapshot() == before,"tested games leave competitive profile unchanged")
    stage.queue_free()
    await process_frame
    print("V025 CHECKS=",checks," FAILURES=",failures)
    quit(0 if failures == 0 else 1)
