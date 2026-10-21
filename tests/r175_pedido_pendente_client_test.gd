extends SceneTree
## R175 · PEDIDO PENDENTE (cliente): "pedido em aberto" com CONTINUAR / CANCELAR, CONTINUAR o mesmo pedido (PIX e
## cartão), "OUTRA FORMA DE PAGAMENTO" cancela o pedido antes, resposta do CANCELAR (cancelado / já pago / erro),
## cancelado em outra aba e MINHAS COMPRAS com estados + botões. Sem rede: as mensagens do servidor são simuladas.
## Capturas: SHOT_DIR=<pasta> (PC e celular em pé com SHOT_SIZE).
var checks := 0
var failures := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 6):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func iso(ago_s: int) -> String:
	return Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - ago_s) + ".000Z"

class FakeAccount extends Node:
	signal server_message(msg)
	var sent: Array = []
	var email := "ana@x.dev"
	func send_server(m: Dictionary) -> bool:
		sent.append(m)
		return true
	func has_profile() -> bool: return true
	func last(t: String) -> Dictionary:
		for i in range(sent.size() - 1, -1, -1):
			if String(sent[i].get("type", "")) == t: return sent[i]
		return {}

class FakeMain extends Node:
	var account: FakeAccount

class FakeHub extends Control:
	var main_hub: FakeMain
	var view := Vector2(1280, 720)
	var k := 1.0
	var narrow := false
	var url_opener: Callable
	var closed := 0
	var confirmed := ""
	func fs(n: float) -> int: return int(n)
	func close_modal(): closed += 1
	func payment_confirmed(pid: String): confirmed = pid

class FakeCard extends Node:
	signal submitted(data)
	signal failed(reason)
	signal closed
	var is_open := false
	var opens := 0
	func open(_pk, _amount, _email, _title, _price):
		is_open = true
		opens += 1
	func resolve_ok(): pass
	func resolve_reject(_t): pass
	func close(): is_open = false

func _initialize(): call_deferred("run")

func make(product: String) -> Array:
	var hub := FakeHub.new()
	hub.main_hub = FakeMain.new()
	hub.main_hub.account = FakeAccount.new()
	root.add_child(hub)
	hub.add_child(hub.main_hub)
	hub.main_hub.add_child(hub.main_hub.account)
	var ui = load("res://monetization/payment_real_ui.gd").new()
	ui.card_form_factory = func(): return FakeCard.new()
	hub.add_child(ui)
	ui.setup(hub, product)
	return [hub, ui, hub.main_hub.account]

func press(ui: Node, n: String) -> bool:
	var b = ui.find_child(n, true, false)
	if b == null: return false
	b.pressed.emit()
	return true

func run():
	await unit()
	await purchases_page()
	print("RESULT %s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures > 0 else 0)

func unit():
	# --- pedido de Fundador em aberto → CONTINUAR o mesmo pedido ---
	var r := make("founder")
	var hub: FakeHub = r[0]; var ui = r[1]; var acc: FakeAccount = r[2]
	ui.start("card")
	acc.server_message.emit({"type": "payment_error", "code": "order_open", "message": "x", "charge_id": "ref-A", "product_id": "founder", "method": "pix"})
	await frames()
	check(ui.step == "error" and ui.find_child("PaymentResumeOpen", true, false) != null and ui.find_child("PaymentCancelOpen", true, false) != null, "pedido em aberto: CONTINUAR PEDIDO e CANCELAR PEDIDO")
	check(String(ui.find_child("PaymentErrorText", true, false).text).contains("Continue esse pedido"), "texto novo (sem 'espere 30 minutos')")
	press(ui, "PaymentResumeOpen")
	check(acc.last("payment_resume").get("charge_id", "") == "ref-A" and ui.step == "creating", "CONTINUAR manda payment_resume do MESMO pedido")
	acc.server_message.emit({"type": "payment_charge", "charge": {"id": "ref-A", "method": "pix", "product_id": "founder", "copy_paste": "PIXQR-1", "amount_cents": 4490, "resumed": true, "expires_at": iso(-900)}})
	await frames()
	check(ui.step == "pix" and String(ui.find_child("PixCopyPaste", true, false).text) == "PIXQR-1", "PIX retomado: o mesmo Copia e Cola")
	check(String(ui.find_child("PaymentCountdown", true, false).text).begins_with("O código vale"), "validade do PIX retomado")
	# --- OUTRA FORMA DE PAGAMENTO cancela o pedido antes ---
	press(ui, "PaymentBack")
	check(acc.last("payment_cancel").get("charge_id", "") == "ref-A" and ui.step == "cancelling", "OUTRA FORMA: cancela o pedido aberto primeiro")
	acc.server_message.emit({"type": "payment_update", "charge": {"id": "ref-A", "status": "cancelled", "product_id": "founder"}, "reason": "user"})
	await frames()
	check(ui.step == "cancelling", "aviso de cancelado da própria janela não troca a tela")
	acc.server_message.emit({"type": "payment_cancel_result", "charge_id": "ref-A", "status": "cancelled", "product_id": "founder"})
	await frames()
	check(ui.step == "choose", "cancelado → volta para a escolha (PIX/cartão)")
	await shot("01_escolha_depois_de_cancelar")

	# --- CANCELAR de pedido que já tinha sido pago → entrega ---
	r = make("founder"); hub = r[0]; ui = r[1]; acc = r[2]
	ui.start("pix")
	acc.server_message.emit({"type": "payment_error", "code": "order_open", "message": "x", "charge_id": "ref-B", "product_id": "founder", "method": "pix"})
	await frames()
	press(ui, "PaymentCancelOpen")
	acc.server_message.emit({"type": "payment_cancel_result", "charge_id": "ref-B", "status": "paid", "product_id": "founder", "message": "já tinha sido pago"})
	await frames()
	check(hub.confirmed == "founder", "CANCELAR de pedido já pago → boas-vindas (vantagem entregue)")

	# --- CANCELAR sem confirmação do Mercado Pago → erro com TENTAR CANCELAR DE NOVO ---
	r = make("club_monthly"); hub = r[0]; ui = r[1]; acc = r[2]
	ui.start("pix")
	acc.server_message.emit({"type": "payment_charge", "charge": {"id": "ref-C", "method": "pix", "product_id": "club_monthly", "copy_paste": "Q", "amount_cents": 1790}})
	await frames()
	press(ui, "PaymentBack")
	acc.server_message.emit({"type": "payment_cancel_result", "charge_id": "ref-C", "status": "error", "code": "unverified", "message": "Não foi possível confirmar com o Mercado Pago agora. Nada foi alterado."})
	await frames()
	check(ui.step == "error" and ui.find_child("PaymentCancelRetry", true, false) != null, "falha ao conferir: aviso + TENTAR CANCELAR DE NOVO")
	var n0 := acc.sent.size()
	press(ui, "PaymentCancelRetry")
	check(acc.sent.size() == n0 + 1 and acc.last("payment_cancel").get("charge_id", "") == "ref-C", "tentar de novo manda outro payment_cancel")

	# --- cancelado em OUTRA aba enquanto este mostra o PIX ---
	r = make("club_monthly"); hub = r[0]; ui = r[1]; acc = r[2]
	ui.start("pix")
	acc.server_message.emit({"type": "payment_charge", "charge": {"id": "ref-D", "method": "pix", "product_id": "club_monthly", "copy_paste": "Q", "amount_cents": 1790}})
	await frames()
	acc.server_message.emit({"type": "payment_update", "charge": {"id": "ref-D", "status": "cancelled", "product_id": "club_monthly"}, "reason": "user"})
	await frames()
	check(ui.step == "expired" and ui.closed_by_user, "cancelado em outra aba → tela PEDIDO CANCELADO")
	await shot("02_cancelado_outra_aba")

	# --- CONTINUAR um pedido que já foi pago (resposta: payment_update paid) ---
	r = make("founder"); hub = r[0]; ui = r[1]; acc = r[2]
	ui.resume("ref-E", "pix")
	acc.server_message.emit({"type": "payment_update", "charge": {"id": "ref-E", "status": "paid", "product_id": "founder"}})
	await frames()
	check(hub.confirmed == "founder", "CONTINUAR pedido já pago → boas-vindas")

	# --- CONTINUAR expirado ---
	r = make("founder"); hub = r[0]; ui = r[1]; acc = r[2]
	ui.resume("ref-F", "pix")
	acc.server_message.emit({"type": "payment_error", "code": "order_expired", "message": "x", "charge_id": "ref-F"})
	await frames()
	check(ui.step == "error" and ui.find_child("PaymentNewOrder", true, false) != null, "expirado → COMEÇAR NOVO PEDIDO")

	# --- CONTINUAR cartão: o formulário abre de novo (token novo no novo envio), mesmo pedido ---
	r = make("founder"); hub = r[0]; ui = r[1]; acc = r[2]
	ui.resume("ref-G", "card")
	acc.server_message.emit({"type": "payment_charge", "charge": {"id": "ref-G", "method": "card", "product_id": "founder", "public_key": "PK", "checkout_url": "https://mp.test/x", "amount_cents": 4990, "resumed": true}})
	await frames()
	check(ui.step == "card" and ui.card_form != null and ui.card_form.opens == 1, "cartão retomado: formulário do Mercado Pago abre de novo")
	ui.card_form.submitted.emit({"token": "tokenNOVO_123", "payment_method_id": "visa"})
	var pay := acc.last("payment_card_pay")
	check(pay.get("charge_id", "") == "ref-G" and pay.get("token", "") == "tokenNOVO_123", "envio usa o MESMO pedido com o token novo do formulário")

	# --- MINHAS COMPRAS: regras ---
	var P = load("res://monetization/purchases_ui.gd")
	var items := [{"status": "pending", "state": "pending", "id": "a", "can_continue": true}, {"status": "cancelled", "state": "cancelled"},
		{"status": "cancelled"}, {"status": "pending", "created_at": iso(7200)}, {"status": "failed"}, {"status": "sold_out"}]
	var vis: Array = P.visible_items(items)
	check(vis.size() == 5, "MINHAS COMPRAS: tudo aparece menos tentativa falha (%d)" % vis.size())
	check(P.state_of(items[2]) == "expired" and P.state_of(items[3]) == "expired", "servidor antigo: cancelado/pendente velho = EXPIRADO")
	check(P.actionable(items[0]) and not P.actionable(items[1]) and not P.actionable(items[3]), "CONTINUAR/CANCELAR só no pedido aguardando")

func purchases_page():
	var size := Vector2i(1672, 941)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	for c in root.get_children(): if c is FakeHub: c.queue_free()
	await frames()
	OS.set_environment("FRAIHA_SERVER_URL", "")
	OS.set_environment("FRAIHA_PAYMENT_MODE", "real")   # MINHAS COMPRAS com o pagamento real (Mercado Pago pelo servidor)
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui != null: stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u-me"; acc.access_token = "teste"; acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	var sent: Array = []
	if acc.has_signal("sent_debug"): pass
	var hub = stage.get_node("MainHub")
	hub.open_premium("purchases")
	await frames(6)
	var pr = hub.premium
	var items := [
		{"id": "ref-P", "product_id": "founder", "method": "card", "amount_cents": 4990, "status": "pending", "state": "pending", "created_at": iso(240), "expires_at": iso(-1560), "can_continue": true, "can_cancel": true},
		{"id": "ref-X", "product_id": "club_monthly", "method": "pix", "amount_cents": 1790, "status": "cancelled", "state": "expired", "created_at": iso(86400)},
		{"id": "ref-Y", "product_id": "founder", "method": "pix", "amount_cents": 4490, "status": "cancelled", "state": "cancelled", "created_at": iso(86400 * 2)},
		{"id": "ref-Z", "product_id": "club_yearly", "method": "pix", "amount_cents": 13490, "status": "paid", "state": "paid", "created_at": iso(86400 * 3), "paid_at": iso(86400 * 3), "paid_after_cancel": true},
		{"id": "ref-W", "product_id": "founder_legend", "method": "card", "amount_cents": 9990, "status": "sold_out", "state": "sold_out", "created_at": iso(86400 * 5), "paid_at": iso(86400 * 5)}]
	acc.server_message.emit({"type": "payment_history", "items": items})
	await frames(6)
	var list = pr.root.find_child("PurchasesList", true, false)
	check(list != null, "MINHAS COMPRAS aberto")
	var conts: Array = pr.root.find_children("PurchaseContinue", "", true, false)
	var cancs: Array = pr.root.find_children("PurchaseCancel", "", true, false)
	check(conts.size() == 1 and cancs.size() == 1, "só o pedido aguardando tem CONTINUAR e CANCELAR")
	var txt := ""
	for l in pr.root.find_children("*", "Control", true, false):
		if l is Label or l.get("tone") != null: txt += String(l.get("text")) + "|"
	check(txt.contains("EXPIRADO") and txt.contains("CANCELADO") and txt.contains("AGUARDANDO PAGAMENTO") and txt.contains("PAGO"), "estados: aguardando, expirado, cancelado, pago")
	check(txt.contains("Vale até"), "aguardando mostra até quando vale")
	check(txt.contains("Pago depois do cancelamento"), "pago depois de cancelado: nota")
	await shot("03_minhas_compras")
	# CANCELAR → confirmação → payment_cancel
	var before_cancel: int = 0
	cancs[0].pressed.emit()
	await frames(4)
	check(pr.root.find_child("ConfirmModal", true, false) != null or hub.premium.modal != null, "CANCELAR pede confirmação")
	await shot("04_confirmar_cancelamento")
	var ok_btn = hub.premium.modal.find_child("ConfirmOk", true, false) if hub.premium.modal != null else null
	check(ok_btn != null, "botão CANCELAR PEDIDO na confirmação")
	if ok_btn != null: ok_btn.pressed.emit()
	await frames(4)
	# sem servidor neste teste: o envio falha → aviso claro de que NÃO cancelou
	check(not hub.premium.purchases_busy.has("ref-P") and String(hub.premium.purchases_note).contains("NÃO foi cancelado"), "sem conexão: avisa que o pedido NÃO foi cancelado")
	# com servidor: o pedido fica "cancelando" até a resposta
	hub.premium.purchases_note = ""
	hub.premium.purchases_busy["ref-P"] = true
	hub.premium._rebuild()
	await frames(4)
	check(hub.premium.purchases_busy.has("ref-P"), "pedido marcado como cancelando")
	var t2 := ""
	for l in pr.root.find_children("*", "Label", true, false): t2 += String(l.text) + "|"
	check(t2.contains("Cancelando…"), "mostra 'Cancelando…' no lugar dos botões")
	acc.server_message.emit({"type": "payment_cancel_result", "charge_id": "ref-P", "status": "cancelled", "product_id": "founder"})
	items[0] = {"id": "ref-P", "product_id": "founder", "method": "card", "amount_cents": 4990, "status": "cancelled", "state": "cancelled", "created_at": iso(240)}
	acc.server_message.emit({"type": "payment_history", "items": items})
	await frames(6)
	check(not hub.premium.purchases_busy.has("ref-P") and pr.root.find_child("PurchasesNote", true, false) != null, "cancelado: aviso no topo e lista atualizada")
	check(pr.root.find_children("PurchaseContinue", "", true, false).size() == 0, "sem botões depois de cancelado")
	await shot("05_depois_de_cancelar")
	# CONTINUAR abre o pagamento do MESMO pedido
	items[0] = {"id": "ref-Q", "product_id": "club_monthly", "method": "pix", "amount_cents": 1790, "status": "pending", "state": "pending", "created_at": iso(60), "expires_at": iso(-1740), "can_continue": true, "can_cancel": true}
	acc.server_message.emit({"type": "payment_history", "items": items})
	await frames(6)
	var c2: Array = pr.root.find_children("PurchaseContinue", "", true, false)
	check(c2.size() == 1, "novo pedido aguardando com CONTINUAR")
	if c2.size() == 1: c2[0].pressed.emit()
	await frames(4)
	var payui = hub.premium.modal.find_child("PaymentReal", true, false) if hub.premium.modal != null else null
	check(payui != null and payui.product_id == "club_monthly" and payui.resume_id == "ref-Q", "CONTINUAR abre o pagamento do pedido (Club mensal, mesmo id)")
	if payui != null:
		payui._show("creating")   # sem servidor neste teste: simula o envio aceito
		acc.server_message.emit({"type": "payment_charge", "charge": {"id": "ref-Q", "method": "pix", "product_id": "club_monthly", "copy_paste": "00020126PIXCOPIAECOLA-MESMO", "qr_code_base64": "", "amount_cents": 1790, "resumed": true, "expires_at": iso(-1740)}})
		await frames(6)
		check(payui.step == "pix", "PIX do mesmo pedido na tela")
		await shot("06_continuar_pix")
