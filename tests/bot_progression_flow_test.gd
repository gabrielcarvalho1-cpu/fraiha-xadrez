extends SceneTree
## Painel de PROGRESSÃO pós-vitória (R29) no stage real:
## só depois da vitória CONFIRMADA e da animação de VITÓRIA; AVANÇAR abre o próximo bot da escada
## (ordem do bot_ladder.json); VOLTAR leva à Home; derrota/empate sem painel; falha de confirmação
## mostra erro sem desbloqueio; Challenger mostra o estado final; progresso sobrevive a recarga/relogin.
## Rodar: FRAIHA_SERVER_URL=ws://127.0.0.1:9 xvfb-run -a godot --path . -s tests/bot_progression_flow_test.gd
const Progress = preload("res://bot/bot_progress.gd")
const Ladder = preload("res://bot/bot_ladder.gd")
const Modal = preload("res://bot/reward_modal.gd")
var checks := 0
var failures := 0
var stage

class FakeAccount extends "res://account/account_service.gd":
    var sent: Array = []
    func _send(msg: Dictionary) -> bool:
        sent.append(msg)
        return true
    func _server_auth(): pass   # sem rede: o teste entrega as respostas do servidor
    func _connect(): pass
    func types() -> Array:
        return sent.map(func(m): return String(m.get("type", "")))

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize(): call_deferred("run")

func frames(n := 3):
    for i in n: await process_frame

func record(result: String, reason := "MATE") -> Dictionary:
    return {"human_color": "w", "result": result, "mode": "bot", "result_reason": reason, "start_fen": "", "moves": PackedStringArray(["f2f3", "e7e5", "g2g4", "d8h4"])}

## Simula o fim de partida contra `bot_id` exatamente pelo caminho do stage (_on_match_finished).
func finish(bot_id: String, result: String, reason := "MATE"):
    stage._start_bot(bot_id, "w")
    stage.bot_controller.stop()
    await frames(2)
    stage._on_match_finished(record(result, reason))
    await frames(2)

## Fecha a animação de VITÓRIA/DERROTA como o jogador (clique) e espera o fade terminar.
func dismiss_overlay():
    stage.result_overlay.hide_result()
    for i in 60:
        if not stage.result_overlay.visible: break
        await process_frame
    await frames(3)

func panel_text() -> String:
    var t := ""
    if not stage.reward_modal.is_open(): return t
    for n in stage.reward_modal.root.find_children("*", "", true, false):
        if n is Label or n is Button: t += String(n.text) + "\n"
    return t

func run():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.FILE))
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await frames(30)
    var hub = stage.hub
    var bp = hub.bot_progress
    var modal = stage.reward_modal

    # ---------- ordem oficial ----------
    var ids: Array = Array(Ladder.ids())
    check(Modal.next_of("madeira") == "ferro" and Modal.next_of("ferro") == "bronze", "próximo bot vem da ordem do bot_ladder.json")
    check(Modal.next_of(ids[ids.size() - 1]) == "", "depois do último (Challenger) não há próximo")

    # ---------- convidado: vitória → animação → painel ----------
    await finish("madeira", "win")
    check(bp.is_defeated("madeira"), "convidado: vitória no MADEIRA registrada (local)")
    check(stage.result_overlay.is_showing(), "animação de VITÓRIA está na tela")
    check(not modal.is_open(), "painel NÃO abre durante a animação de vitória")
    await dismiss_overlay()
    check(modal.is_open(), "painel abre depois que a animação termina")
    var txt := panel_text()
    check(txt.contains("VITÓRIA!") and txt.contains("BOT MADEIRA DERROTADO"), "painel: VITÓRIA! / BOT MADEIRA DERROTADO")
    check(txt.contains("BOT FERRO") and txt.contains("AVANÇAR PARA O BOT FERRO"), "painel: próximo bot e botão AVANÇAR PARA O BOT FERRO")
    check(txt.contains("VOLTAR PARA O INÍCIO"), "painel: botão VOLTAR PARA O INÍCIO")
    check(txt.contains("Recompensa") and txt.contains("Mago"), "painel: recompensa (avatar Mago)")
    check(modal.buttons.advance.custom_minimum_size.y >= 48 and modal.buttons.home.custom_minimum_size.y >= 48, "botões grandes para toque (>= 48 px)")
    # AVANÇAR
    modal.buttons.advance.pressed.emit()
    await frames(3)
    check(not modal.is_open(), "AVANÇAR fecha o painel")
    check(stage.mode == "bot" and String(stage.bot_controller.bot_id) == "ferro", "AVANÇAR abre direto o BOT FERRO")
    check(stage.bot_level_name == "BOT FERRO", "partida mostra BOT FERRO")
    stage.bot_controller.stop()

    # ---------- VOLTAR PARA O INÍCIO ----------
    await finish("ferro", "win")
    await dismiss_overlay()
    check(modal.is_open() and panel_text().contains("AVANÇAR PARA O BOT BRONZE"), "vitória no FERRO → painel com AVANÇAR PARA O BOT BRONZE")
    modal.buttons.home.pressed.emit()
    await frames(5)
    check(not modal.is_open(), "VOLTAR fecha o painel")
    check(hub.visible and hub.page == "main", "VOLTAR PARA O INÍCIO leva à Home")

    # ---------- derrota e empate: sem painel ----------
    await finish("bronze", "loss", "MATE")
    await dismiss_overlay()
    check(not modal.is_open() and not bp.is_defeated("bronze"), "derrota: sem painel e sem progresso")
    await finish("bronze", "draw", "AFOGAMENTO")
    await frames(5)
    check(not modal.is_open() and not bp.is_defeated("bronze"), "empate: sem painel e sem progresso")
    # vitória que não é xeque-mate (ex.: tempo) não conta para a escada
    await finish("bronze", "win", "TEMPO")
    await dismiss_overlay()
    check(not modal.is_open() and not bp.is_defeated("bronze"), "vitória sem xeque-mate: sem painel")
    stage.open_home()
    await frames(3)

    # ---------- conta: painel só com a confirmação do servidor ----------
    var acc := FakeAccount.new()
    acc.set_process(false)
    root.add_child(acc)
    acc.access_token = "tok"
    acc.user_id = "u-flow"
    acc.socket_open = true
    acc.server_ready = true
    bp.setup(acc)
    acc._receive({"type": "acct_state", "user_id": "u-flow", "profile": {"nickname": "Teste"}, "ranked": {}, "persistent": true, "bots": {"available": true, "defeated": ["madeira"]}})
    await frames(2)
    check(bp.is_account() and bp.server_available and bp.is_defeated("madeira") and not bp.is_defeated("ferro"), "conta: estado vem do servidor (só MADEIRA)")
    await finish("ferro", "win")
    await dismiss_overlay()
    check("bot_victory" in acc.types(), "conta: vitória enviada ao servidor (bot_victory)")
    check(not bp.is_defeated("ferro") and not modal.is_open(), "conta: SEM painel e sem desbloqueio antes da confirmação")
    acc._receive({"type": "bot_progress", "available": true, "defeated": ["madeira", "ferro"], "new_bot": "ferro"})
    await frames(3)
    check(bp.is_defeated("ferro") and modal.is_open() and panel_text().contains("AVANÇAR PARA O BOT BRONZE"), "conta: confirmação do servidor → painel com o próximo bot")
    modal.buttons.home.pressed.emit()
    await frames(3)

    # ---------- falha na confirmação: erro, sem desbloqueio, sem avançar ----------
    await finish("bronze", "win")
    acc._receive({"type": "bot_error", "code": "bot_game_invalid", "message": "Partida inválida.", "bot_id": "bronze"})
    await frames(2)
    check(not modal.is_open(), "falha: aviso espera a animação terminar")
    await dismiss_overlay()
    var etxt := panel_text()
    check(modal.is_open() and etxt.contains("VITÓRIA NÃO REGISTRADA"), "falha: painel de erro visível")
    check(not etxt.contains("AVANÇAR") and not modal.buttons.has("advance"), "falha: sem botão AVANÇAR")
    check(not bp.is_defeated("bronze") and not bp.is_unlocked("prata"), "falha: nada desbloqueado (BRONZE não derrotado, PRATA bloqueado)")
    modal.buttons.ok.pressed.emit()
    await frames(3)
    check(not modal.is_open(), "falha: OK fecha o aviso")
    # conta sem conexão: mesmo comportamento
    acc.socket_open = false
    acc.server_ready = false
    await finish("bronze", "win")
    await dismiss_overlay()
    check(modal.is_open() and panel_text().contains("VITÓRIA NÃO REGISTRADA") and not bp.is_defeated("bronze"), "sem conexão: erro e nenhum desbloqueio local")
    modal.close()
    acc.socket_open = true
    acc.server_ready = true

    # ---------- relogin / F5: progresso vem de novo do servidor ----------
    var bp2 = Progress.new()
    root.add_child(bp2)
    var acc2 := FakeAccount.new()
    acc2.set_process(false)
    root.add_child(acc2)
    bp2.setup(acc2)
    acc2.access_token = "tok"
    acc2.user_id = "u-flow"
    acc2.socket_open = true
    acc2._receive({"type": "acct_state", "user_id": "u-flow", "profile": {"nickname": "Teste"}, "ranked": {}, "persistent": true, "bots": {"available": true, "defeated": ["madeira", "ferro"]}})
    await frames(2)
    check(bp2.is_defeated("ferro") and bp2.is_unlocked("bronze") and not bp2.is_unlocked("prata"), "relogin: FERRO derrotado e BRONZE liberado (do servidor)")
    # convidado (F5): o arquivo local do convidado continua com MADEIRA e FERRO
    var bp3 = Progress.new()
    root.add_child(bp3)
    bp3.setup(null)
    check(bp3.key == "local" and bp3.is_defeated("madeira") and bp3.is_defeated("ferro"), "F5 como convidado: progresso local preservado")

    # ---------- Challenger: estado final ----------
    var last := String(ids[ids.size() - 1])
    modal.show_progress(last, Ladder.reward(last))
    await frames(2)
    var ftxt := panel_text()
    check(ftxt.contains("DESAFIO DAS LIGAS CONCLUÍDO"), "Challenger: DESAFIO DAS LIGAS CONCLUÍDO")
    check(modal.buttons.has("replay") and modal.buttons.has("home") and not modal.buttons.has("advance"), "Challenger: JOGAR NOVAMENTE + VOLTAR PARA O INÍCIO, sem AVANÇAR")
    var replayed := []
    modal.replay_requested.connect(func(b): replayed.append(b))
    modal.buttons.replay.pressed.emit()
    await frames(3)
    check(replayed == [last] and String(stage.bot_controller.bot_id) == last, "JOGAR NOVAMENTE abre o Challenger de novo")
    stage.bot_controller.stop()

    DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.FILE))
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
