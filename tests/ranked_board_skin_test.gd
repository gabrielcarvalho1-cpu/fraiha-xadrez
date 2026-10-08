extends SceneTree
## R49 · Pele do tabuleiro Ranked Madeira: a arte de referência por baixo, os controles de sempre por cima — e o
## jogo continua igual. Partida REAL (servidor local + adversário automático). PC e (-- --mobile-test) celular.
## Confere: grid alinhado às casas da arte (clique cai na casa certa), lance de verdade, relógio/nome/liga vivos,
## chat (enviar), botões fantasmas (opções, música), DESISTIR, subida de liga (botões), troca de tema e saída
## (tudo volta ao normal). Rodar: tests/run_ranked_board_skin.sh [mob]
var failures = 0
var stage
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func wait_until(cond: Callable, seconds: float) -> bool:
    var end = Time.get_ticks_msec() + int(seconds * 1000)
    while Time.get_ticks_msec() < end:
        if cond.call(): return true
        await process_frame
    return cond.call()
func frames(n: int):
    for i in n: await process_frame
func click(at: Vector2):
    for pressed in [true, false]:
        var ev := InputEventMouseButton.new()
        ev.button_index = MOUSE_BUTTON_LEFT
        ev.pressed = pressed
        ev.position = at
        ev.global_position = at
        root.push_input(ev, true)
        await frames(2)
## centro da casa (coluna, linha NA TELA) medido na arte
func cell_screen(skin, col: int, row: int) -> Vector2:
    var b: Rect2 = (skin.MOB if skin.kind == "mob" else skin.PC).board
    return skin.P(b.position + Vector2((col + 0.5) * b.size.x / 8.0, (row + 0.5) * b.size.y / 8.0))

func tap(c: Control):
    var at := c.get_global_rect().get_center()
    for pressed in [true, false]:
        var ev := InputEventScreenTouch.new()
        ev.index = 0
        ev.position = at
        ev.pressed = pressed
        Input.parse_input_event(ev)
        await frames(2)

## R53 · celular: HUD novo com partida REAL (servidor local + adversário automático).
func mobile_hud_flow(skin, acc):
    var hud = stage.mobile_hud
    var g = stage.game
    check(not skin.on and hud.on and hud.orient == "p", "celular: pele do PC desligada, HUD da partida ligado")
    check(hud.bg.visible and not stage.forest.visible, "arte da referência no fundo (Madeira)")
    var board := Rect2(g.position + g.ORIGIN * g.scale, Vector2.ONE * g.BOARD * g.scale.x)
    var at := func(cell: Vector2i) -> Vector2: return board.position + (Vector2(g.display_cell(cell)) + Vector2(0.5, 0.5)) * board.size.x / 8.0
    var me: String = stage.ranked.human_color
    check(await wait_until(func(): return stage.ranked.can_interact() or g.turn != me, 6.0), "tabuleiro pronto")
    if me == "w":
        await click(at.call(Vector2i(4, 6)))
        await click(at.call(Vector2i(4, 4)))
        check(await wait_until(func(): return g.move_count >= 1 and g.pieces.get(Vector2i(4, 4), "") == "wP", 6.0), "lance e2-e4 por toque no tabuleiro do HUD, aceito pelo servidor")
    else:
        print("SKIP lance (o servidor sorteou PRETAS para o cliente)")
    var top: Dictionary = stage.ranked_ui.strips.top
    var bot: Dictionary = stage.ranked_ui.strips.bottom
    check(String(bot.name.text) == "Você" and String(top.name.text).begins_with("Peer"), "nomes vivos (%s / %s)" % [top.name.text, bot.name.text])
    check("MADEIRA" in String(bot.sub.text) and "PL" in String(bot.sub.text), "liga/PL vivos: " + String(bot.sub.text))
    check(String(top.clock.label.text).contains(":") and top.clock.bare, "relógio vivo, só os dígitos (" + String(top.clock.label.text) + ")")
    # chat pelo botão CHAT da barra
    var chat = stage.match_chat
    await tap(hud.nav_buttons.chat)
    check(chat.open_mobile and chat.panel.visible, "CHAT da barra abre o chat")
    chat.input.text = "boa partida"
    chat.send_button.pressed.emit()
    check(await wait_until(func(): return chat.list.get_child_count() > 0, 6.0), "chat: mensagem enviada e listada")
    await tap(hud.nav_buttons.chat)
    check(not chat.open_mobile, "CHAT fecha o chat")
    # AÇÕES → MÚSICA (preferência real)
    var ms = preload("res://ui_v022/mode_sound.gd")
    var was: bool = ms.music_muted(stage.hub)
    await tap(hud.nav_buttons.actions)
    check(hud.is_open(), "AÇÕES abre")
    await tap(hud.panel.find_child("Action_music", true, false))
    check(ms.music_muted(stage.hub) != was, "AÇÕES: Música liga/desliga")
    ms.toggle_music(stage.hub)
    hud.close_actions()
    # outro tema: o HUD continua (cenário do tema); Madeira de novo: arte de volta
    g.set_visual_theme("iron")
    stage._layout()
    await frames(3)
    check(hud.on and not hud.wood, "tema Ferro: HUD continua")
    check(g.piece_override.is_empty(), "tema Ferro: peças do tema (sem os sprites da Madeira)")
    g.set_visual_theme("wood")
    stage._layout()
    await frames(3)
    check(hud.on and hud.wood and g.piece_override.size() == 12, "Madeira de novo: arte e peças da Madeira")
    # DESISTIR pelo painel AÇÕES (a partida termina de verdade no servidor)
    await tap(hud.nav_buttons.actions)
    await tap(hud.panel.find_child("Action_resign", true, false))
    var confirm = null
    for b in stage.ranked_ui.box.find_children("*", "Button", true, false):
        if String(b.text).strip_edges() == "DESISTIR": confirm = b
    check(confirm != null and not hud.is_open(), "Desistir: confirmação de sempre (AÇÕES fechou)")
    if confirm: confirm.pressed.emit()
    check(await wait_until(func(): return not stage.ranked.last_result.is_empty() and String(stage.ranked.last_result.get("match_id", "")) == String(stage.ranked.match_id), 15.0), "resultado oficial chegou (desistência)")
    stage.ranked_ui.close_panel()
    stage.open_home()
    await frames(6)
    check(not hud.on and not hud.bg.visible and not hud.layer.visible, "Home: HUD desligado")
    check(g.piece_override.is_empty() and not top.name.top_level and not top.clock.bare and not stage.material_hud.skin and not stage.game.hide_status, "controles devolvidos ao layout normal")

func run():
    var mobile := "--mobile-test" in OS.get_cmdline_user_args()
    if mobile:
        root.size = Vector2i(390, 844)
        root.content_scale_size = root.size
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await frames(6)
    stage.account_ui.hide_ui()
    var acc = stage.account
    acc.access_token = "dev:Skin%d" % (Time.get_ticks_msec() % 100000)
    acc.user_id = "pending"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada")
    if acc.needs_nickname: acc.create_profile("Skin%d" % (Time.get_ticks_msec() % 10000))
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    var skin = stage.board_skin
    check(not skin.on, "Home: pele desligada")
    stage._open_ranked()
    await wait_until(func(): return stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false) != null, 4.0)
    stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false).pressed.emit()
    check(await wait_until(func(): return stage.mode == "ranked" and stage.ranked.status == "playing", 40.0), "partida Ranked começou")
    await frames(4)
    if mobile:
        # R53 · contrato novo: no celular a partida Ranked usa o HUD da partida (ranked/mobile_match_hud.gd),
        # não mais a pele do R49 (que continua no PC). Mesmo roteiro com servidor real, pelo HUD novo.
        await mobile_hud_flow(skin, acc)
        print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
        quit(failures)
        return
    check(skin.on and skin.kind == ("mob" if mobile else "pc"), "pele ligada na partida Ranked Madeira (%s)" % skin.kind)
    check(skin.bg.visible and not stage.forest.visible and not stage.game.get_node("ForestEnvironment").visible, "arte da referência no fundo; cenário pintado do tema escondido")
    # 1) grid alinhado: o centro de cada casa da arte cai na casa certa do tabuleiro
    var g = stage.game
    var ok_grid := true
    for col in [0, 3, 7]:
        for row in [0, 4, 7]:
            var local: Vector2 = g.get_global_transform().affine_inverse() * cell_screen(skin, col, row)
            var cell: Vector2i = g.cell_at(local)
            if g.display_cell(cell) != Vector2i(col, row): ok_grid = false
    check(ok_grid, "casas da arte = casas do jogo (clique cai na casa certa)")
    # 2) lance de verdade pelo clique (se for a minha vez)
    var me: String = stage.ranked.human_color
    check(await wait_until(func(): return stage.ranked.can_interact() or g.turn != me, 6.0), "tabuleiro pronto")
    if me == "w":
        var from: Vector2i = g.display_cell(Vector2i(4, 6))
        var to: Vector2i = g.display_cell(Vector2i(4, 4))
        await click(cell_screen(skin, from.x, from.y))
        await click(cell_screen(skin, to.x, to.y))
        check(await wait_until(func(): return g.move_count >= 1 and g.pieces.get(Vector2i(4, 4), "") == "wP", 6.0), "lance e2-e4 pelo clique na arte, aceito pelo servidor")
    else:
        print("SKIP lance (o servidor sorteou PRETAS para o cliente)")
    # 3) cartões vivos
    var top: Dictionary = stage.ranked_ui.strips.top
    var bot: Dictionary = stage.ranked_ui.strips.bottom
    check(String(bot.name.text) == "Você" and String(top.name.text).begins_with("Peer"), "nomes vivos (%s / %s)" % [top.name.text, bot.name.text])
    check("MADEIRA" in String(bot.sub.text) and "PL" in String(bot.sub.text), "liga/PL vivos: " + String(bot.sub.text))
    check(String(top.clock.label.text).contains(":") and top.clock.bare, "relógio vivo, só os dígitos (" + String(top.clock.label.text) + ")")
    var card: Rect2 = skin.R(skin.MOB.card if mobile else skin.PC.card)
    check(card.grow(4).encloses(top.name.get_global_rect()) and card.grow(4).encloses(top.clock.get_global_rect()), "nome e relógio dentro do cartão da arte %s %s %s" % [card, top.name.get_global_rect(), top.clock.get_global_rect()])
    check(stage.material_hud.skin, "material no cartão da arte")
    # 4) chat
    var chat = stage.match_chat
    if mobile:
        skin.mob_buttons.chatbar.pressed.emit()
        await frames(3)
        check(chat.open_mobile and chat.panel.visible, "barra CHAT abre o chat")
    chat.input.text = "boa partida"
    chat.send_button.pressed.emit()
    check(await wait_until(func(): return chat.list.get_child_count() > 0, 6.0), "chat: mensagem enviada e listada")
    if mobile:
        skin.mob_buttons.chatbar.pressed.emit()
        await frames(3)
        check(not chat.open_mobile, "barra CHAT fecha o chat")
    # 5) botões por cima da arte disparam as mesmas ações
    var ms = preload("res://ui_v022/mode_sound.gd")
    var was: bool = ms.music_muted(stage.hub)
    if mobile:
        skin.toggle_menu()
        await frames(3)
        var items: Array = skin.menu.get_node("Items").get_children().map(func(b): return b.text)
        check(items.has("DESISTIR") and items.any(func(t): return String(t).begins_with("MÚSICA")), "menu ⋮: " + str(items))
        for b in skin.menu.get_node("Items").get_children():
            if String(b.text).begins_with("MÚSICA"): b.pressed.emit()
        check(ms.music_muted(stage.hub) != was, "menu: MÚSICA liga/desliga")
        ms.toggle_music(stage.hub)
    else:
        stage.desk_music.pressed.emit()
        check(ms.music_muted(stage.hub) != was, "botão da música (sobre o ícone da arte) liga/desliga")
        stage.desk_music.pressed.emit()
        stage.desk_gear.pressed.emit()
        check(g.settings_open, "engrenagem abre as opções da partida")
        stage.desk_gear.pressed.emit()
        check(stage.home_button.get_global_rect().is_equal_approx(skin.R(skin.PC.home)), "INÍCIO sobre o botão da arte")
    # 7a) outro tema: a pele sai; Madeira de novo: volta
    g.set_visual_theme("iron")
    stage._layout()
    await frames(3)
    check(not skin.on and stage.forest.visible and stage.home_button.self_modulate.a > 0.99, "tema Ferro: pele desligada e tudo como antes")
    check(g.piece_override.is_empty(), "R50: tema Ferro usa as peças do tema (sem os sprites da Madeira)")
    g.set_visual_theme("wood")
    stage._layout()
    await frames(3)
    check(skin.on, "Madeira de novo: pele religada [mode=%s visible=%s theme=%s]" % [stage.mode, g.visible, g.visual_theme])
    check(g.piece_override.size() == 12 and g.piece_override.has("wK") and g.piece_override.has("bQ"), "R50: as 12 peças novas no Ranked Madeira")
    # 7) DESISTIR (a partida termina de verdade)
    if mobile:
        skin.toggle_menu()
        await frames(3)
        var rb = skin.menu.get_node("Items").find_child("MenuResign", true, false)
        check(rb != null, "DESISTIR no menu")
        if rb: rb.pressed.emit()
    else:
        stage.ranked_ui.resign_button.pressed.emit()
    await frames(3)
    var confirm = null
    for b in stage.ranked_ui.box.find_children("*", "Button", true, false):
        if String(b.text).strip_edges() == "DESISTIR": confirm = b
    check(confirm != null, "confirmação de desistência")
    if confirm: confirm.pressed.emit()
    check(await wait_until(func(): return not stage.ranked.last_result.is_empty() and String(stage.ranked.last_result.get("match_id", "")) == String(stage.ranked.match_id), 15.0), "resultado oficial chegou (desistência)")
    # 6) subida de liga (mesma mensagem do servidor) → botões
    var fake := {"type": "ranked_result", "match_id": stage.ranked.match_id, "mode": "ranked_3min", "mode_name": "Relâmpago", "you": me,
        "outcome": "win", "reason": "resign", "reason_text": "Desistência", "pl_change": 3, "league_before": 0, "pl_before": 97,
        "league_after": 1, "pl_after": 0, "promoted": true, "stats": {"league": 1, "pl": 0, "highest_league": 1}, "saved": true}
    var keep: Dictionary = stage.ranked.last_result
    stage.ranked.last_result = fake
    stage.ranked_ui._show("result")
    await frames(3)
    check(stage.ranked_ui.promo.visible and not stage.ranked_ui.panel.visible, "VOCÊ SUBIU DE LIGA! (arte) no lugar do painel")
    check(int(acc.ranked.get("ranked_3min", {}).get("league", 0)) == 1, "stats novos guardados na conta")
    stage.ranked_ui.promo.back.pressed.emit()
    await frames(3)
    check(not stage.ranked_ui.promo.visible and stage.ranked_ui.screen == "modes", "VOLTAR AO RANKED volta para os ritmos")
    stage.ranked_ui.close_panel()
    stage.ranked.last_result = keep
    # 9) saída para a Home: tudo volta
    stage.ranked_ui.close_panel()
    stage.open_home()
    await frames(6)
    check(not skin.on and not skin.bg.visible, "Home: pele desligada")
    check(g.piece_override.is_empty(), "R50: fora do Ranked as peças voltam a ser as do tema")
    check(not top.name.top_level and not top.clock.bare and not stage.material_hud.skin and not stage.game.hide_status, "controles devolvidos ao layout normal")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
