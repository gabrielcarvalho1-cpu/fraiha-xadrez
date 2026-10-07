extends SceneTree
## Cartão do jogador na Home = liga/PL do RANKED da conta (servidor), não do perfil local (que nunca ganha PL).
## Bug: depois de subir de liga a Home continuava "Madeira · 0 / 100 PL". Uso: godot --headless -s tests/home_standing_test.gd [-- --mobile-test]
var failures = 0
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func run():
    var mobile := "--mobile-test" in OS.get_cmdline_user_args()
    if mobile:
        root.size = Vector2i(390, 844)
        root.content_scale_size = root.size
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(6): await process_frame
    var hub = stage.hub
    var acc = stage.account
    check(hub.best_ranked_standing({"ranked_3min": {"league": 1, "pl": 3, "highest_league": 1}, "ranked_5min": {"league": 0, "pl": 80}}).mode == "ranked_3min", "melhor ritmo = maior liga (Ferro 3 > Madeira 80)")
    check(hub.best_ranked_standing({"ranked_3min": {"league": 2, "pl": 10}, "ranked_10min": {"league": 2, "pl": 40}}).mode == "ranked_10min", "empate de liga → mais PL")
    check(hub.best_ranked_standing({}).is_empty(), "sem Ranked → vazio (Madeira 0)")
    # conta com perfil + Ranked vindo do servidor (acct_state)
    acc.user_id = "u1"
    acc.access_token = "teste"   # conta logada (sem rede: só o estado que o acct_state preencheria)
    acc.server_ready = true
    acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
    acc.ranked = {"ranked_3min": {"league": 0, "pl": 97, "highest_league": 0}}
    stage._sync_theme_unlocks()
    await process_frame
    var txt := func() -> String:
        if mobile and is_instance_valid(hub.mobile_ui) and is_instance_valid(hub.mobile_ui.ref_home): return String(hub.mobile_ui.ref_home.league_text.text)
        return String(hub.ref_league_label.text)
    check(txt.call() == "Madeira · 97 / 100 PL", "Home mostra o PL do Ranked (%s)" % txt.call())
    # fim de partida Ranked com promoção (mesma mensagem do servidor: ranked_result com stats)
    stage._on_online_result({"type": "ranked_result", "match_id": "m1", "mode": "ranked_3min", "outcome": "win", "promoted": true,
        "stats": {"league": 1, "pl": 0, "highest_league": 1, "matches": 9, "wins": 6, "losses": 3, "draws": 0}})
    for i in range(3): await process_frame
    check(txt.call() == "Ferro · 0 / 100 PL", "subiu de liga: Home atualiza na hora (%s)" % txt.call())
    check(hub.ranked_unlock_index == 1, "temas: liga Ferro liberada")
    if not mobile: check(is_equal_approx(hub.ref_league_fill.size.x, 0.0), "barra de PL reinicia na nova liga")
    stage._on_online_result({"type": "ranked_result", "match_id": "m2", "mode": "ranked_3min", "outcome": "win", "stats": {"league": 1, "pl": 6, "highest_league": 1}})
    for i in range(3): await process_frame
    check(txt.call() == "Ferro · 6 / 100 PL", "vitória seguinte soma PL (%s)" % txt.call())
    if not mobile: check(hub.ref_league_fill.size.x > 10.0, "barra de PL cresce")
    # sair da conta → volta a Madeira 0 (convidado)
    acc.profile = {}
    acc.ranked = {}
    acc.access_token = ""
    acc.user_id = ""
    acc.server_ready = false
    stage._sync_theme_unlocks()
    await process_frame
    check(txt.call() == "Madeira · 0 / 100 PL", "sem conta: Madeira 0 (%s)" % txt.call())
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
