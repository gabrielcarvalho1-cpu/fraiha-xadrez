extends SceneTree
## Home pública: sem JOGAR LOCAL, com AMIGOS, 11 ações sem buraco (R32: + MARCHA REAL e HISTÓRICO DE PARTIDAS; R33: + XEQUE).
var failures = 0
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func run():
    var mobile = "--mobile-test" in OS.get_cmdline_user_args()
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(3): await process_frame
    var hub = stage.hub
    var titles = hub.menu_buttons.map(func(b): return hub.title_of(b))
    check(titles == ["JOGAR CONTRA O COMPUTADOR","JOGAR ONLINE","JOGAR RANQUEADO","LIGAS E RANKING","MARCHA REAL","XEQUE","AMIGOS","CONFIGURAÇÕES","CONHEÇA O FRAIHA","HISTÓRICO DE PARTIDAS","SAIR"], "ordem da Home pública: " + str(titles))
    check(not "JOGAR LOCAL" in titles, "JOGAR LOCAL fora da Home")
    for i in range(hub.menu_buttons.size()):
        var row: Vector2 = hub.MENU_ROWS[i]
        check(hub.menu_buttons[i].position == Vector2(hub.MENU_X, row.x) and (i == 0 or row.x - (hub.MENU_ROWS[i - 1].x + hub.MENU_ROWS[i - 1].y) < 12.0), "sem buraco no layout %d" % i)
    var all_text = hub.root.find_children("*","Label",true,false).map(func(l): return l.text)
    check(not all_text.any(func(t): return "Duas pessoas no mesmo computador" in t), "texto do Local fora da Home")
    check(stage.has_method("_start_local"), "modo Local interno preservado")
    var opened = [false]
    hub.friends_requested.connect(func(): opened[0] = true)
    hub.menu_buttons[6].pressed.emit()
    check(opened[0], "AMIGOS emite friends_requested")
    if mobile:
        check(is_instance_valid(hub.mobile_ui), "Home mobile ativa")
        hub.show_page("main")
        await process_frame
        var buttons = hub.mobile_ui.find_children("*","Button",true,false).map(func(b): return b.text)
        check(not "JOGAR LOCAL" in buttons and "AMIGOS" in buttons and "JOGAR ONLINE" in buttons, "mobile: botões " + str(buttons))
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
