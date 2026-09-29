extends SceneTree
## Regra: convidado/conta nova = só Madeira; desbloqueio = maior highest_league dos 4 modos Ranked.
var failures = 0
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ",label)
    if not ok: failures += 1
func _saved() -> String:
    var c = ConfigFile.new(); c.load("user://visual_theme.cfg")
    return String(c.get_value("visual","theme",""))
func _initialize(): call_deferred("run")
func run():
    var viewport = SubViewport.new()
    viewport.size = Vector2i(1600,900)
    root.add_child(viewport)
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    viewport.add_child(stage)
    await process_frame
    var tm = stage.theme_manager
    var acc = stage.account
    # 1+5. convidado com tema antigo salvo (silver) abre em Madeira e regrava Madeira
    check(tm.active_theme == "wood", "convidado abre em Madeira (salvo antigo ignorado)")
    check(_saved() == "wood", "tema salvo inválido regravado como Madeira")
    # 3. ligas bloqueadas não mudam cenário nem salvam
    for id in ["ferro","bronze","prata","ouro","platina"]:
        stage.hub._select_league(id)
        stage.hub._preview_league()
        check(tm.active_theme == "wood" and _saved() == "wood", id+" bloqueada não aplica")
    check(not tm.apply_theme("iron") and not tm.apply_piece_set("iron"), "apply direto de Ferro recusado")
    check(stage.hub.league_details.text.begins_with("Bloqueada · alcance esta liga no Ranked"), "texto de bloqueio")
    # 4. Madeira e peças clássicas sempre disponíveis
    stage.hub._select_league("madeira")
    check(tm.active_theme == "wood", "Madeira selecionável")
    check(tm.apply_piece_set("classic"), "peças clássicas disponíveis")
    # 2. conta nova (0 PL, highest 0)
    acc.access_token = "t"; acc.user_id = "u"; acc.server_ready = true
    acc.profile = {"nickname":"Teste"}
    acc.ranked = {"ranked_3min":{"highest_league":0},"ranked_5min":{"highest_league":0},"ranked_10min":{"highest_league":0},"ranked_20min":{"highest_league":0}}
    stage._sync_theme_unlocks()
    check(tm.active_theme == "wood" and not tm.apply_theme("iron"), "conta nova só Madeira")
    # conta com highest_league Bronze (2) em um modo, liga atual menor: libera até Bronze
    acc.ranked["ranked_10min"] = {"league":1,"highest_league":2}
    stage._sync_theme_unlocks()
    check(tm.apply_theme("iron") and tm.apply_theme("bronze"), "highest_league Bronze libera Ferro e Bronze")
    check(not tm.apply_theme("silver"), "Prata continua bloqueada")
    check(_saved() == "bronze", "tema liberado é salvo")
    # 6. logout volta para Madeira
    acc._clear_session()
    stage._sync_theme_unlocks()
    check(tm.active_theme == "wood" and _saved() == "wood", "logout volta para Madeira")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
