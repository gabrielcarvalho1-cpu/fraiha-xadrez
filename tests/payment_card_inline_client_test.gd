extends SceneTree
## R40 · Cartão DENTRO do jogo (lógica do Godot) contra servidor local + Mercado Pago FALSO.
## O formulário do navegador (card_form_web.gd) é trocado por um falso com a mesma interface; o JS
## de verdade é testado no Chromium (tests/web/card_form_e2e.py).
## Rodar: tests/run_payment_client.sh --card [--shots]
const Catalog := preload("res://monetization/monetization_catalog.gd")
var checks := 0
var failures := 0
var pr
var shots := OS.get_environment("PAY_SHOTS") != ""

class FakeForm extends Node:
    signal form_ready
    signal submitted(data: Dictionary)
    signal closed
    signal failed(reason: String)
    var is_open := false
    var opened := []
    var resolved := 0
    var rejected := []
    var flog := {"closed": 0}   # sobrevive ao formulário ser liberado junto com a janela
    func open(pk: String, amount_cents: int, email: String, title: String, price: String):
        is_open = true
        opened.append({"pk": pk, "amount": amount_cents, "email": email, "title": title, "price": price})
    func resolve_ok(): resolved += 1
    func resolve_reject(m: String): rejected.append(m)
    func show_message(_t: String, _k := "info"): pass
    func close():
        if is_open: flog.closed += 1
        is_open = false

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
    root.get_texture().get_image().save_png("/tmp/claude-0/sc/card_%s.png" % name)

func run():
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = root.size
    check(Catalog.payment_mode() == "real", "modo de pagamento REAL")
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in 6: await process_frame
    stage.account_ui.hide_ui()
    var acc = stage.account
    acc.access_token = "dev:Cartao%d" % (Time.get_ticks_msec() % 100000)
    acc.user_id = "pending"
    acc.email = "cartao@teste.local"
    acc._server_auth()
    check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada ao servidor dev")
    if acc.needs_nickname: acc.create_profile("Cartao%d" % (Time.get_ticks_msec() % 100000))
    check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
    var hub = stage.hub
    hub.open_premium("club")
    pr = hub.premium
    var opened_urls := []
    pr.url_opener = func(u): opened_urls.append(u)
    await process_frame
    check(press("SubscribeClub"), "ATIVAR CLUB FRAIHA abre a escolha da forma de pagamento")
    var ui = pr.modal.find_child("PaymentReal", true, false)
    var form := FakeForm.new()
    var flog: Dictionary = form.flog
    ui.card_form_factory = func(): return form
    ui._show("choose")
    await process_frame
    var desc_ok := false
    for l in node("OptionCard").find_children("*", "Label", true, false):
        if String(l.text).contains("aqui mesmo no jogo"): desc_ok = true
    check(desc_ok, "opção CARTÃO avisa que o pagamento é aqui mesmo no jogo")
    await shot("1_escolha")
    var probe := LineEdit.new()
    probe.name = "FocusProbe"
    root.add_child(probe)
    probe.grab_focus()
    await process_frame
    check(probe.has_focus(), "(preparo) um campo de texto do jogo está com o foco")
    check(press("ChooseCard"), "escolheu CARTÃO")
    check(await wait_until(func(): return form.is_open, 8.0), "o formulário seguro do Mercado Pago abre sozinho por cima do jogo")
    var o: Dictionary = form.opened[0] if form.opened.size() > 0 else {}
    check(o.get("pk", "") == "APP_USR-public-key-teste" and int(o.get("amount", 0)) == 1990 and o.get("email", "") == "cartao@teste.local" and String(o.get("price", "")).begins_with("R$ 19,90"), "formulário recebe a Public Key, R$ 19,90 e o e-mail da conta (nada secreto)")
    check(not probe.has_focus() and root.gui_get_focus_owner() == null, "ao abrir o formulário, nenhum campo do jogo fica com o foco (o teclado vai só para o formulário)")
    probe.queue_free()
    check(node("CardOpenForm") != null and node("CardOpenCheckout") != null and node("PaymentCheck") != null, "por trás: PREENCHER DADOS DO CARTÃO, opção da página do Mercado Pago e JÁ PAGUEI")
    await shot("2_cartao")
    # ---- recusado por saldo ----
    form.submitted.emit({"token": "tok-reject-cli-1", "payment_method_id": "master", "issuer_id": "24", "id_type": "CPF", "id_number": "12345678909", "device_id": "dev-x"})
    check(await wait_until(func(): return form.rejected.size() == 1, 8.0), "cartão recusado → o formulário volta a aceitar dados")
    check(form.rejected.size() == 1 and String(form.rejected[0]).contains("Saldo ou limite insuficiente"), "motivo da recusa em português aparece no formulário")
    check(String(node("CardFormNote").text).contains("Saldo"), "o motivo também aparece no jogo")
    check(not hub.club_active(), "recusado: Club NÃO liberado")
    # ---- fechar e reabrir ----
    form.close()
    form.closed.emit()
    check(String(node("CardFormNote").text).contains("Formulário fechado"), "fechar o formulário avisa como continuar")
    check(press("CardOpenForm") and form.is_open and form.opened.size() == 2, "PREENCHER DADOS DO CARTÃO reabre o formulário")
    # ---- aprovado ----
    form.submitted.emit({"token": "tok-approve-cli-2", "payment_method_id": "master", "issuer_id": "24", "id_type": "CPF", "id_number": "12345678909", "device_id": "dev-x"})
    check(await wait_until(func(): return hub.club_active() and node("WelcomeModal") != null, 10.0), "cartão aprovado → Club liberado na hora + tela de boas-vindas")
    check(flog.closed >= 2 and (not is_instance_valid(form) or not form.is_open), "o formulário some depois da aprovação")
    var welcomes := 0
    for n in pr.root.find_children("WelcomeModal", "", true, false): welcomes += 1
    check(welcomes == 1, "uma tela de boas-vindas só (sem duplicar)")
    check(opened_urls.is_empty(), "nenhuma página externa foi aberta")
    await shot("3_aprovado")
    press("ConfirmCancel")
    await process_frame
    # ---- formulário não carregou → página do Mercado Pago ----
    hub.open_premium("founder")
    pr = hub.premium
    pr.url_opener = func(u): opened_urls.append(u)
    await process_frame
    check(press("BecomeFounder"), "TORNAR-SE FUNDADOR")
    ui = pr.modal.find_child("PaymentReal", true, false)
    var form2 := FakeForm.new()
    ui.card_form_factory = func(): return form2
    check(press("ChooseCard") and await wait_until(func(): return form2.is_open, 8.0), "Fundador no cartão: formulário abre")
    form2.close()
    form2.failed.emit("timeout")
    await process_frame
    check(node("CardOpenForm") == null and node("CardOpenCheckout") != null, "se o formulário não carregar: cai na página segura do Mercado Pago")
    check(press("CardOpenCheckout") and opened_urls.size() == 1 and String(opened_urls[0]).contains("pref_id="), "ABRIR PAGAMENTO COM CARTÃO abre o checkout do Mercado Pago (como no R39)")
    await shot("4_fallback")
    pr.close()
    print("RESULT %d/%d" % [checks - failures, checks], " OK" if failures == 0 else " FALHAS=%d" % failures)
    quit(failures)
