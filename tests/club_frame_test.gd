extends SceneTree
## Club na Home: fita CLUB FRAIHA (inativa/ativa) abre a página do Club; moldura Club aparece
## no cartão de perfil, no Perfil e no cartão do jogador quando dev_mock_club liga, e some ao desligar.
## Separação: dev_mock_club (simulação) ≠ club_active (servidor) — entitlements.apply_server.
var failures := 0
var checks := 0
func check(ok: bool, label: String):
    checks += 1
    print(("PASS " if ok else "FAIL ") + label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func frames_on(node: Node) -> int:
    var n := 0
    for f in node.find_children("ClubFrame", "", true, false): if f.is_visible_in_tree(): n += 1
    return n
func mobile_card_frame(hub) -> bool:
    for c in hub.find_children("*", "", true, false):
        if c.get_class() == "Button" and c.get_node_or_null("ClubFrame") != null and c.get_node("ClubFrame").visible: return true
    return false
func run():
    var mobile := "--mobile-test" in OS.get_cmdline_user_args()
    root.size = Vector2i(390, 844) if mobile else Vector2i(1920, 1080)
    root.content_scale_size = root.size
    await process_frame
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 8: await process_frame
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    var hub = stage.hub
    var state = hub.monetization_state
    state.mock_reset()
    for i in 2: await process_frame
    var entry = hub.find_child("ClubHomeEntryMobile" if mobile else "ClubHomeEntry", true, false)
    check(entry != null and entry.is_visible_in_tree(), "Home tem a entrada CLUB FRAIHA (separada do menu)")
    check(entry != null and not entry.active and entry.text == "CLUB FRAIHA", "inativo: 'CLUB FRAIHA'")
    check(frames_on(hub) == 0, "sem Club: nenhuma moldura Club")
    entry.pressed.emit()
    for i in 2: await process_frame
    check(hub.premium != null and hub.premium.visible and hub.premium.page == "club", "clicar abre direto a página do Club")
    hub.premium.close()
    # ativa pela simulação (mesmo caminho do botão ATIVAR CLUB)
    state.mock_activate_club()
    for i in 3: await process_frame
    check(entry.active and entry.text == "CLUB ATIVO", "ativo: '♛ CLUB ATIVO'")
    check(hub.club_active() and hub.entitlements.club_source() == "mock", "entitlements: Club ativo via simulação (mock)")
    check(frames_on(hub) >= 1 or (mobile and mobile_card_frame(hub)), "moldura Club aparece na Home imediatamente")
    hub.show_page("profile")
    for i in 2: await process_frame
    check(frames_on(hub) >= 1 or mobile, "moldura Club no Perfil")
    var choices = hub.find_children("*", "BaseButton", true, false).filter(func(b): return b.has_meta("no_club_frame"))
    check(choices.size() > 0 and choices.all(func(b): return b.get_node_or_null("ClubFrame") == null), "avatares de escolha não recebem a moldura")
    hub.show_page("main")
    stage._start_bot("easy", "w")
    for i in 3: await process_frame
    if mobile:
        check(frames_on(stage) >= 1, "cartão do jogador na partida (celular) tem a moldura")
    stage.return_to_home()
    for i in 3: await process_frame
    if not hub.is_home_visible(): stage.open_home()
    for i in 3: await process_frame
    entry = hub.find_child("ClubHomeEntryMobile" if mobile else "ClubHomeEntry", true, false)   # celular reconstrói a Home
    # desliga
    state.mock_deactivate_club()
    for i in 3: await process_frame
    check(not entry.active and frames_on(hub) == 0, "desativar: fita volta a 'CLUB FRAIHA' e molduras somem")
    # reativa
    state.mock_activate_club()
    for i in 3: await process_frame
    check(entry.active and frames_on(hub) >= 1, "reativar: tudo volta")
    state.mock_reset()
    for i in 2: await process_frame
    # servidor (club_active real) manda, mesmo sem simulação
    hub.entitlements.apply_server({"is_founder": false, "club_active": true, "club_expires_at": "2026-12-01T00:00:00Z"})
    for i in 3: await process_frame
    check(hub.club_active() and hub.entitlements.club_source() == "server" and entry.active, "club_active do servidor ativa a moldura sem dev_mock_club")
    check(not state.dev_mock_club, "dev_mock_club continua false (não se misturam)")
    hub.entitlements.clear_server()
    for i in 3: await process_frame
    check(not hub.club_active() and not entry.active, "servidor limpa → inativo")
    print("CLUB_FRAME_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit()
