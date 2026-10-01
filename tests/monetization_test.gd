extends SceneTree
## Monetização V1 (Fundador + Club, SIMULAÇÃO): navegação, fluxos PIX/Cartão, confirmação,
## persistência, WhatsApp, reset e estados combinados. Usa um arquivo de estado próprio do teste.
const StateScript := preload("res://monetization/monetization_state.gd")
const HubScript := preload("res://monetization/premium_hub.gd")
const Catalog := preload("res://monetization/monetization_catalog.gd")
const TEST_PATH := "user://test_dev_monetization_mock.cfg"
var checks := 0
var failures := 0
var pr

func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

func _initialize(): call_deferred("run")

func node(n: String) -> Node:
    return pr.root.find_child(n, true, false)

func press(n: String) -> bool:
    var b = node(n)
    if b == null or not (b is BaseButton) or b.disabled: return false
    b.pressed.emit()
    return true

func settle():
    for i in 3: await process_frame

func no_inputs() -> bool:
    return pr.root.find_children("*", "LineEdit", true, false).is_empty() and pr.root.find_children("*", "TextEdit", true, false).is_empty()

func buy(product_page: String, start: String, method_button: String, simulate: String, ok_text: String) -> bool:
    pr.show_page(product_page)
    await settle()
    if not press(start): return false
    await settle()
    if not press(method_button): return false
    await settle()
    if not press(simulate): return false
    await settle()
    var okb = node("ConfirmOk")
    if okb == null or okb.text != ok_text: return false
    okb.pressed.emit()
    await settle()
    return true

func run():
    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
    # Celular: -- --mobile-test (retrato 390x844) ou -- --mobile-test --landscape (844x390).
    var mobile := "--mobile-test" in OS.get_cmdline_user_args()
    root.size = (Vector2i(844, 390) if "--landscape" in OS.get_cmdline_user_args() else Vector2i(390, 844)) if mobile else Vector2i(1920, 1080)
    root.content_scale_size = root.size
    await process_frame
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 10: await process_frame
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    var hub = stage.hub
    var state = StateScript.new(TEST_PATH)
    hub.premium = HubScript.new(state)
    hub.add_child(hub.premium)
    pr = hub.premium
    await settle()

    # ---------------- Catálogo / segurança
    check(Catalog.PAYMENT_MODE == "mock", "modo de pagamento = mock")
    check(Catalog.enabled_methods() == ["pix", "card"], "PIX é o primeiro método")
    check(Catalog.FOUNDER_LIMIT == 100, "FOUNDER_LIMIT = 100")
    check(Catalog.FOUNDER_WHATSAPP_URL == "", "URL do WhatsApp vazia (não inventada)")
    check(Catalog.planned_price("founder") == "R$ 49,90" and Catalog.planned_price("club_monthly") == "R$ 19,90", "preços planejados 49,90 / 19,90")
    check(Catalog.charge_price("founder") == "R$ 0,00" and Catalog.charge_price("club_monthly") == "R$ 0,00", "preço de teste R$ 0,00")

    # ---------------- HUB / navegação
    hub.show_page("settings")
    await settle()
    var entry = hub.find_child("PremiumEntry", true, false)   # no celular a página vive no menu mobile
    check(entry != null, "Configurações tem a entrada FRAIHA PREMIUM")
    check(entry != null and entry.show_new, "entrada com selo NOVO")
    entry.pressed.emit()
    await settle()
    check(pr.visible and pr.page == "hub", "abre o Hub Premium")
    check(node("HubFounderCard") != null and node("HubClubCard") != null, "Hub mostra os dois cartões")
    check(node("HeaderTestStamp") != null and node("TestBanner") != null, "MODO TESTE visível")
    check(press("OpenFounder") and pr.page == "founder", "abre Pacote Fundador")
    pr.back()
    await settle()
    check(pr.page == "hub", "Fundador → voltar → Hub")
    check(press("OpenClub") and pr.page == "club", "abre Club FRAIHA")
    var esc := InputEventKey.new()
    esc.keycode = KEY_ESCAPE
    esc.pressed = true
    pr._input(esc)
    await settle()
    check(pr.page == "hub" and pr.visible, "ESC no Club volta ao Hub")
    check(press("PremiumBack") and not pr.visible and hub.page == "settings", "Hub → voltar → Configurações")
    entry.pressed.emit()
    await settle()

    # ---------------- FUNDADOR
    pr.show_page("founder")
    await settle()
    check(state.summary() == "nenhum", "estado inicial: nenhum")
    check(node("BecomeFounder") != null, "botão TORNAR-SE FUNDADOR")
    check(node("JoinFounderGroup") == null, "sem botão do WhatsApp antes da compra")
    check(node("Benefit_COMUNIDADE_DOS_FUNDADORES") != null, "benefício Comunidade dos Fundadores listado")
    check(String(node("TestPrice").text) == "R$ 0,00", "preço exibido R$ 0,00")
    check("49,90" in String(node("PlannedPrice").text), "preço planejado exibido")
    check("100" in String(node("FounderLimit").text), "edição limitada: primeiros 100")
    check(press("BecomeFounder") and node("PaymentMock") != null, "abre escolha de pagamento")
    var pix = node("OptionPix")
    var card = node("OptionCard")
    check(pix != null and card != null and pix.get_index() < card.get_index(), "PIX antes do Cartão")
    check(node("PixRecommended") != null, "PIX marcado RECOMENDADO")
    check(no_inputs(), "nenhum campo de dado na escolha")
    check(press("PaymentCancel") and pr.modal == null and not state.dev_mock_founder, "cancelar na escolha")
    press("BecomeFounder")
    await settle()
    check(press("ChoosePix") and node("PixTitle") != null, "tela PIX · MODO TESTE")
    check("Nenhum pagamento" in String(node("PixNotice").text), "aviso PIX sem pagamento")
    check(node("QrPlaceholder") != null and no_inputs(), "PIX sem QR real e sem campos")
    check(press("SimulatePix") and node("ConfirmTitle") != null and String(node("ConfirmTitle").text) == "SIMULAR AQUISIÇÃO DO PACOTE FUNDADOR?", "confirmação Fundador")
    check(press("ConfirmCancel") and not state.dev_mock_founder, "cancelar na confirmação não ativa")
    press("BecomeFounder")
    await settle()
    press("ChooseCard")
    await settle()
    check(node("CardTitle") != null and "Nenhum dado de cartão" in String(node("CardNotice").text) and no_inputs(), "tela Cartão sem coleta de dados")
    check(press("PaymentBack") and node("OptionPix") != null, "voltar para escolher outra forma")
    press("PaymentCancel")
    await settle()
    check(await buy("founder", "BecomeFounder", "ChoosePix", "SimulatePix", "ATIVAR FUNDADOR") and state.dev_mock_founder, "ativar Fundador via PIX simulado")
    check(node("FounderOwnedTitle") != null and node("BecomeFounder") == null, "página muda para FUNDADOR FRAIHA")
    check(node("FounderReward") != null and node("JoinFounderGroup") != null, "recompensa: botão do grupo aparece depois")
    check(StateScript.new(TEST_PATH).dev_mock_founder, "Fundador persiste ao reabrir")
    check(press("JoinFounderGroup") and "ainda não configurado" in String(node("ConfirmBody").text), "WhatsApp sem URL mostra aviso")
    press("ConfirmOk")
    await settle()
    check(press("ResetMonetization") and press("ConfirmOk"), "resetar monetização de teste")
    await settle()
    check(state.summary() == "nenhum" and not state.dev_mock_founder_club_trial and not StateScript.new(TEST_PATH).dev_mock_founder, "reset limpa e persiste")
    pr.show_page("founder")
    await settle()
    check(node("JoinFounderGroup") == null and node("BecomeFounder") != null, "após reset volta ao estado de compra")
    check(await buy("founder", "BecomeFounder", "ChooseCard", "SimulateCard", "ATIVAR FUNDADOR") and state.dev_mock_founder, "comprar de novo via Cartão simulado")

    # ---------------- CLUB
    state.mock_reset()
    pr.show_page("club")
    await settle()
    check(node("SubscribeClub") != null and node("ClubActiveText") == null, "Club estado inicial")
    press("SubscribeClub")
    await settle()
    check(node("OptionPix").get_index() < node("OptionCard").get_index(), "Club: PIX primeiro")
    press("ChooseCard")
    await settle()
    check(node("SimulateCard") != null and String(node("SimulateCard").text) == "SIMULAR ASSINATURA VIA CARTÃO", "Club: tela Cartão")
    check(press("PaymentCancel") and not state.dev_mock_club, "Club: cancelar")
    press("SubscribeClub")
    await settle()
    press("ChoosePix")
    await settle()
    check(String(node("SimulatePix").text) == "SIMULAR ASSINATURA VIA PIX", "Club: tela PIX")
    press("SimulatePix")
    await settle()
    check(String(node("ConfirmTitle").text) == "SIMULAR ASSINATURA DO CLUB FRAIHA?" and String(node("ConfirmOk").text) == "ATIVAR CLUB", "Club: confirmação")
    press("ConfirmOk")
    await settle()
    check(state.dev_mock_club and node("ClubActiveText") != null, "Club ativo")
    check(StateScript.new(TEST_PATH).dev_mock_club, "Club persiste ao reabrir")
    check(press("DeactivateClub") and not state.dev_mock_club and node("SubscribeClub") != null, "desativar Club")
    check(await buy("club", "SubscribeClub", "ChooseCard", "SimulateCard", "ATIVAR CLUB") and state.dev_mock_club, "ativar Club de novo")

    # ---------------- ESTADOS
    state.mock_reset()
    check(state.summary() == "nenhum", "estado: nenhum")
    state.mock_activate_founder()
    check(state.summary() == "fundador" and state.founder_trial_view() and not state.club_subscription_view(), "estado: só Fundador (+30 dias simulados, sem assinatura)")
    pr.show_page("club")
    await settle()
    check(node("StatusBadge") != null and "BENEFÍCIO FUNDADOR" in String(node("StatusBadge").text) and node("SubscribeClub") != null, "Club mostra 30 dias como benefício Fundador (simulação)")
    state.mock_reset()
    state.mock_activate_club()
    check(state.summary() == "club", "estado: só Club")
    state.mock_activate_founder()
    check(state.summary() == "fundador+club", "estado: Fundador + Club")
    pr.show_page("hub")
    await settle()
    check(node("HubFounderCard").find_child("StatusBadge", true, false) != null and node("HubClubCard").find_child("StatusBadge", true, false) != null, "Hub mostra os dois ativos")

    # ---------------- Segurança do mock
    var cfg := ConfigFile.new()
    cfg.load(TEST_PATH)
    var keys := cfg.get_section_keys("dev_mock")
    var only_dev := true
    for key in keys: if not String(key).begins_with("dev_mock_"): only_dev = false
    check(only_dev and not cfg.has_section_key("dev_mock", "is_founder") and not cfg.has_section_key("dev_mock", "club_active"), "arquivo só com flags dev_mock_*")
    check(not state.real_is_founder() and not state.real_club_active(), "estado real nunca deriva do mock")
    pr.close()
    state.mock_reset()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
    print("MONETIZATION_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit()
