extends SceneTree
## Cliente Godot no Online Casual (convidado) contra um adversário automático (tests/server/casual_peer.cjs).
var failures = 0
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
func run():
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(3): await process_frame
    stage.account_ui.hide_ui()
    stage.hub.play_online_requested.emit()
    check(stage.mode == "casual_lobby" and stage.casual_ui.panel_open() and stage.casual_ui.screen == "modes", "JOGAR ONLINE abre a escolha de modalidade Casual")
    check(await wait_until(func(): return stage.account.online_ready(), 8.0), "convidado conectado ao servidor")
    await process_frame
    var q = stage.casual_ui.box.find_child("Queue_casual_3min", true, false)
    check(q != null and not q.disabled, "botão ENTRAR NA FILA habilitado")
    check(stage.casual_ui.box.find_children("*","Label",true,false).any(func(l): return "Convidado" in l.text), "mostra que está jogando como convidado")
    q.pressed.emit()
    check(await wait_until(func(): return stage.casual_ui.screen == "searching", 4.0), "tela BUSCANDO ADVERSÁRIO")
    check(await wait_until(func(): return stage.mode == "casual", 20.0), "adversário encontrado: partida Casual aberta")
    check(await wait_until(func(): return stage.casual.status == "playing", 8.0), "partida começou")
    check(stage.casual_ui.hud.visible and not stage.ranked_ui.hud.visible, "HUD Casual visível (e não o do Ranked)")
    var c = stage.casual
    var chat = stage.match_chat
    check(chat.active() and chat.panel.visible, "chat da partida visível no desktop")
    var board = Rect2(stage.game.position + stage.game.ORIGIN * stage.game.scale.x, Vector2.ONE * stage.game.BOARD * stage.game.scale.x)
    check(not chat.panel.get_global_rect().intersects(board), "chat não cobre o tabuleiro")
    chat.input.text = "Olá, boa sorte!"
    chat.input.text_submitted.emit(chat.input.text)
    check(chat.input.text.is_empty(), "Enter envia e limpa o campo")
    var lines = func(): return chat.list.get_children().map(func(l): return l.text)
    check(await wait_until(func(): return lines.call().any(func(t): return t == "Você: Olá, boa sorte!"), 5.0), "minha mensagem aparece no chat")
    check(await wait_until(func(): return lines.call().any(func(t): return "eco: Olá, boa sorte!" in t), 5.0), "resposta do adversário chega em tempo real")
    chat.mute_button.pressed.emit()
    check(not lines.call().any(func(t): return "eco:" in t) and lines.call().any(func(t): return "silenciado" in t), "SILENCIAR esconde as mensagens do adversário")
    chat.mute_button.pressed.emit()
    check(lines.call().any(func(t): return "eco:" in t), "REATIVAR mostra de novo")
    chat.input.text = "x".repeat(250)
    check(chat.input.text.length() == 200, "campo limita a 200 caracteres")
    chat.input.text = ""
    check(c.clock.remaining_ms("w") <= 180000 and c.clock.remaining_ms("w") > 170000, "relógio de 3 min")
    var mine = [[Vector2i(4,6),Vector2i(4,4)],[Vector2i(6,7),Vector2i(5,5)]] if c.human_color == "w" else [[Vector2i(4,1),Vector2i(4,3)],[Vector2i(6,0),Vector2i(5,2)]]
    for pair in mine:
        check(await wait_until(func(): return c.can_interact(), 10.0), "minha vez")
        var before = c.rules.ply
        check(c.request_move(pair[0], pair[1]), "jogada enviada")
        check(await wait_until(func(): return c.rules.ply > before, 5.0), "servidor aplicou a jogada")
    check(stage.casual_ui.strips.top.name.text.length() > 0 and not "PL" in stage.casual_ui.strips.top.name.text, "faixa do adversário sem PL")
    check(await wait_until(func(): return stage.casual_ui.screen == "result", 15.0), "adversário desistiu: tela de resultado")
    var r = c.last_result
    check(String(r.get("outcome","")) == "win" and not bool(r.get("rated", true)) and int(r.get("pl_change", 1)) == 0, "vitória Casual sem PL")
    var texts = stage.casual_ui.box.find_children("*","Label",true,false).map(func(l): return l.text)
    check(texts.any(func(t): return "sem alteração de PL" in t), "resultado informa que não altera PL")
    check(not stage.account.guest_token.is_empty(), "token de convidado salvo para reconexão")
    stage.open_home()
    check(stage.mode == "home" and not stage.casual_ui.hud.visible and not stage.match_chat.panel.visible, "volta à Home (chat fechado)")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
