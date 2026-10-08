extends SceneTree
## Home pública: sem JOGAR LOCAL, com AMIGOS, 11 ações sem buraco (R32: + MARCHA REAL e HISTÓRICO DE PARTIDAS; R33: + XEQUE).
var failures = 0
func check(ok: bool, label: String):
    print("PASS " if ok else "FAIL ", label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func run():
    var mobile = "--mobile-test" in OS.get_cmdline_user_args()
    if mobile and not "--landscape" in OS.get_cmdline_user_args():
        root.size = Vector2i(390, 844)   # celular em pé (R47: Home da referência)
        root.content_scale_size = root.size
        await process_frame
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(3): await process_frame
    var hub = stage.hub
    var titles = hub.menu_buttons.map(func(b): return hub.title_of(b))
    check(titles == ["JOGAR CONTRA O COMPUTADOR","JOGAR ONLINE","JOGAR RANQUEADO","LIGAS E RANKING","MARCHA REAL","XEQUE","AMIGOS","CONFIGURAÇÕES","CONHEÇA O FRAIHA","HISTÓRICO DE PARTIDAS","SAIR"], "ordem da Home pública: " + str(titles))
    check(not "JOGAR LOCAL" in titles, "JOGAR LOCAL fora da Home")
    # R47: cada ação fica sobre o botão DESENHADO na arte da referência (3 linhas + grade 2×3 + CONFIGURAÇÕES/SAIR)
    for i in range(hub.menu_buttons.size()):
        var r: Rect2 = hub.menu_buttons[i].get_rect()
        check(r.is_equal_approx(hub.PC_MENU[i]), "botão %d sobre o desenho da arte (%s)" % [i, r])
        for j in range(i):
            check(not r.grow(-1).intersects(hub.menu_buttons[j].get_rect().grow(-1)), "botões %d e %d não se sobrepõem" % [i, j])
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
        # R47: em pé, a Home é a da referência; CONFIGURAÇÕES / CONHEÇA / SAIR ficam no MAIS da barra de baixo
        if hub.mobile_ui.use_ref_home():
            check(hub.mobile_ui.ref_home != null and hub.mobile_ui.ref_home.visible, "mobile em pé: Home da referência")
            for t in ["JOGAR RANQUEADO", "JOGAR ONLINE", "JOGAR CONTRA O COMPUTADOR", "MARCHA REAL", "XEQUE", "LIGAS E RANKING", "HISTÓRICO DE PARTIDAS", "INÍCIO", "AMIGOS", "MINHA CONTA", "MAIS"]:
                check(t in buttons, "mobile em pé tem " + t)
            hub.mobile_ui.ref_home.buttons["MAIS"].pressed.emit()
            await process_frame
            # R53 · MAIS = painel da referência do celular (VOLTAR / CONFIGURAÇÕES / CONHEÇA O FRAIHA / SAIR)
            var more = hub.mobile_ui.ref_page.find_children("*","Button",true,false).map(func(b): return b.text)
            check(hub.mobile_ui.ref_page.visible and "CONFIGURAÇÕES" in more and "CONHEÇA O FRAIHA" in more and "SAIR" in more and "VOLTAR" in more, "MAIS: " + str(more))
            var fired = [false]
            hub.ranked_requested.connect(func(): fired[0] = true)
            hub.show_page("main")
            await process_frame
            hub.mobile_ui.ref_home.buttons["JOGAR RANQUEADO"].pressed.emit()
            check(fired[0], "mobile: JOGAR RANQUEADO dispara a mesma ação da Home")
            # girar o celular: deitado volta a lista de antes; em pé volta a Home da referência
            root.size = Vector2i(844, 390)
            root.content_scale_size = root.size
            for i in range(4): await process_frame
            check(not hub.mobile_ui.ref_home.visible and hub.mobile_ui.scroll.visible, "deitado: lista (sem a arte em pé)")
            root.size = Vector2i(390, 844)
            root.content_scale_size = root.size
            for i in range(4): await process_frame
            check(hub.mobile_ui.ref_home.visible and not hub.mobile_ui.scroll.visible, "em pé de novo: Home da referência")
    print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
    quit(failures)
