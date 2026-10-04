extends SceneTree
## R39 · Pagamento REAL no jogo (FRAIHA_PAYMENT_MODE=real) contra servidor local + Mercado Pago FALSO:
## sem carimbos de teste, vagas de Fundador vindas do servidor, PIX (QR + Copia e Cola), "JÁ PAGUEI" →
## servidor consulta o Mercado Pago → Fundador liberado + boas-vindas; link do grupo vindo do servidor;
## renovar Club no cartão (checkout do Mercado Pago); sair da conta limpa as vantagens.
## Rodar: tests/run_payment_client.sh [--shots]
const Catalog := preload("res://monetization/monetization_catalog.gd")
var checks := 0
var failures := 0
var pr
var shots := OS.get_environment("PAY_SHOTS") != ""

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

func wait_until(f: Callable, secs: float) -> bool:
    var t0 := Time.get_ticks_msec()
    while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
        if f.call(): return true
        await process_frame
    return f.call()

func shot(name: String):
    if not shots: return
    for i in 4: await process_frame
    root.get_texture().get_image().save_png("/tmp/claude-0/sc/pay_%s.png" % name)

## Controle do Mercado Pago falso: aprova o pagamento daquela referência.
func approve(ref: String) -> bool:
    var http := HTTPRequest.new()
    root.add_child(http)
    var err := http.request(OS.get_environment("FAKE_MP") + "/__approve?ref=" + ref, [], HTTPClient.METHOD_POST, "")
    if err != OK: return false
    var res = await http.request_completed
    http.queue_free()
    return int(res[1]) == 200

func run():
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = root.size
    check(Catalog.payment_mode() == "real" and not Catalog.is_mock(), "modo de pagamento REAL (como na build publicada)")
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 6: await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    acc.access_token = "dev:Pagador%d" % (Time.get_ticks_msec() % 100000)
    acc.user_id = "pending"
    acc.email = "pagador@teste.local"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada ao servidor dev")
    if acc.needs_nickname: acc.create_profile("Pagador%d" % (Time.get_ticks_msec() % 100000))
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    var hub = stage.hub
    hub.open_premium("founder")
    pr = hub.premium
    var opened := []
    pr.url_opener = func(u): opened.append(u)
    check(await wait_until(func(): return pr.founder_remaining() == 2, 5.0), "vagas de Fundador vêm do servidor (restam 2)")
    await wait_until(func(): return node("FounderLimit") != null and String(node("FounderLimit").text).contains("RESTAM 2"), 2.0)
    check(String(node("FounderLimit").text).contains("RESTAM 2 VAGAS"), "página do Fundador mostra RESTAM 2 VAGAS")
    check(not node("HeaderTestStamp").visible and not node("TestBanner").visible and node("PlannedPrice") == null and node("PriceHow") != null, "sem MODO TESTE / simulação; preço real com PIX ou cartão")
    check(String(node("TestPrice").text) == "R$ 49,90", "preço real R$ 49,90")
    await shot("1_fundador")
    # ---------- PIX ----------
    check(press("BecomeFounder") and node("OptionPix") != null and node("OptionCard") != null and node("SimulatePix") == null, "TORNAR-SE FUNDADOR abre a escolha PIX / cartão (pagamento real, sem simulação)")
    await shot("2_escolha")
    check(press("ChoosePix"), "escolheu PIX")
    check(await wait_until(func(): return node("PixQr") != null, 8.0), "PIX gerado pelo servidor no Mercado Pago")
    var ui = pr.modal.find_child("PaymentReal", true, false)
    check(node("PixQr").texture != null, "QR Code (imagem do Mercado Pago) aparece")
    check(String(node("PixCopyPaste").text).begins_with("00020126"), "PIX Copia e Cola aparece")
    var copied := []
    ui.clipboard_writer = func(t): copied.append(t)
    check(press("PixCopy") and copied.size() == 1 and String(copied[0]).begins_with("00020126") and String(node("PixCopied").text).contains("copiado"), "COPIAR CÓDIGO PIX copia o código")
    check(press("PixOpenTicket") and opened.size() == 1 and String(opened[0]).contains("mercadopago.com.br"), "ABRIR NO MERCADO PAGO abre o link do PIX")
    check(node("PaymentWaiting") != null and String(node("PaymentCountdown").text).contains("vale por mais"), "aguardando pagamento, com a validade do código")
    await shot("3_pix")
    check(not hub.is_founder(), "antes de pagar: ainda não é Fundador")
    var ref := String(ui.charge.get("id", ""))
    check(await approve(ref), "pagamento aprovado no Mercado Pago (falso)")
    check(press("PaymentCheck"), "JÁ PAGUEI")
    check(await wait_until(func(): return hub.is_founder() and node("WelcomeModal") != null, 12.0), "servidor confirma com o Mercado Pago → Fundador liberado + tela de boas-vindas")
    check(String(node("ConfirmTitle").text).contains("FUNDADOR") and String(node("ConfirmBody").text).contains("30 dias de Club"), "boas-vindas lista o que foi liberado")
    check(hub.club_active() and bool(hub.entitlements.real.is_founder), "direito REAL do servidor (não simulação), com 30 dias de Club")
    await shot("4_boas_vindas")
    press("ConfirmCancel")
    await process_frame
    pr.show_page("founder")
    await process_frame
    check(node("BecomeFounder") == null and node("JoinFounderGroup") != null, "página do Fundador: comprado; botão do grupo aparece")
    check(press("JoinFounderGroup") and opened.back() == "https://chat.whatsapp.com/GRUPO-TESTE", "grupo dos Fundadores abre o link que veio do servidor")
    # ---------- Club: renovar no cartão ----------
    pr.show_page("club")
    await process_frame
    check(node("RenewClub") != null and String(node("ClubActiveText").text).contains("faltam"), "Club ativo mostra os dias restantes e RENOVAR · +30 DIAS")
    await shot("5_club")
    check(press("RenewClub") and press("ChooseCard"), "renovar com cartão")
    check(await wait_until(func(): return node("CardOpenCheckout") != null, 8.0), "checkout do cartão criado no Mercado Pago")
    check(press("CardOpenCheckout") and String(opened.back()).contains("checkout") and String(opened.back()).contains("pref_id="), "ABRIR PAGAMENTO COM CARTÃO abre o checkout seguro do Mercado Pago")
    await shot("6_cartao")
    ui = pr.modal.find_child("PaymentReal", true, false)
    check(await approve(String(ui.charge.get("id", ""))), "cartão aprovado no Mercado Pago (falso)")
    check(press("PaymentCheck"), "JÁ PAGUEI (cartão)")
    check(await wait_until(func(): return node("WelcomeModal") != null and String(node("ConfirmTitle").text).contains("CLUB"), 12.0), "Club renovado: boas-vindas do Club")
    check(hub.entitlements.club_days_left() >= 59 and hub.entitlements.club_days_left() <= 61, "Club somou +30 dias (%d dias)" % hub.entitlements.club_days_left())
    press("ConfirmCancel")
    # ---------- Fundador não compra de novo / sair limpa ----------
    pr.show_page("founder")
    await process_frame
    check(node("BecomeFounder") == null, "Fundador não vê o botão de comprar de novo")
    pr.close()
    acc.sign_out()
    check(await wait_until(func(): return not hub.is_founder() and not hub.club_active(), 4.0), "sair da conta: vantagens somem desta sessão")
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
