extends SceneTree
## R171 · SEC-009 (cliente): Fundador pago no instante em que a última vaga acabou ("sold_out").
## O jogo mostra o aviso de reembolso (nunca "aprovado" nem "aguardando"), fecha o formulário de cartão e o
## MINHAS COMPRAS lista o pagamento como VAGAS ESGOTADAS · REEMBOLSO.
## Rodar: godot --headless --path . -s tests/payment_sold_out_r171_test.gd
var checks := 0
var failures := 0

func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

class FakeAccount extends Node:
	signal server_message(msg)
	var sent: Array = []
	func send_server(m: Dictionary) -> bool:
		sent.append(m)
		return true

class FakeMain extends Node:
	var account: FakeAccount

class FakeHub extends Control:
	var main_hub: FakeMain
	var view := Vector2(1280, 720)
	var k := 1.0
	var narrow := false
	var url_opener: Callable
	var closed := false
	var confirmed := ""
	func fs(n: float) -> int: return int(n)
	func close_modal(): closed = true
	func payment_confirmed(pid: String): confirmed = pid

class FakeCard extends Node:
	signal submitted(data)
	signal failed(reason)
	signal closed
	var is_open := true
	var ok_calls := 0
	var rejected := ""
	func resolve_ok(): ok_calls += 1
	func resolve_reject(t: String): rejected = t
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
	hub.add_child(ui)
	ui.setup(hub, product)
	return [hub, ui]

func labels_text(n: Node) -> String:
	var out := ""
	for c in n.find_children("*", "Label", true, false): out += String(c.text) + "\n"
	return out

func run():
	# --- PIX: chega payment_update sold_out (e depois o payment_error do servidor) ---
	var a := make("founder")
	var hub: FakeHub = a[0]
	var ui = a[1]
	ui.step = "pix"
	ui.charge = {"id": "ref-1", "method": "pix", "status": "pending"}
	ui.poll.start()
	var msg := "As vagas do Pacote Fundador acabaram no exato momento do seu pagamento. Você NÃO recebeu o pacote e o valor será devolvido integralmente."
	hub.main_hub.account.server_message.emit({"type": "payment_update", "charge": {"id": "ref-1", "status": "sold_out", "product_id": "founder"}, "message": msg})
	await process_frame
	check(ui.step == "error" and ui.error_code == "founder_sold_out_paid", "PIX: sold_out vira tela de aviso (não fica 'aguardando')")
	check(ui.poll.is_stopped(), "PIX: para de consultar o servidor")
	check(labels_text(ui).contains("devolvido integralmente"), "PIX: o aviso diz que o valor será devolvido")
	check(hub.confirmed == "", "PIX: nada de 'compra confirmada'")
	hub.main_hub.account.server_message.emit({"type": "payment_error", "code": "founder_sold_out_paid", "message": msg})
	await process_frame
	check(ui.step == "error", "PIX: aviso repetido do servidor não muda nada")

	# --- CARTÃO: resposta "sold_out" do pagamento com cartão ---
	var b := make("founder")
	var hub2: FakeHub = b[0]
	var ui2 = b[1]
	ui2.step = "card"
	ui2.charge = {"id": "ref-2", "method": "card", "status": "pending"}
	var card := FakeCard.new()
	ui2.card_form = card
	ui2.add_child(card)
	hub2.main_hub.account.server_message.emit({"type": "payment_card_result", "charge_id": "ref-2", "status": "sold_out", "message": msg})
	await process_frame
	check(not card.is_open and card.ok_calls == 1 and card.rejected == "", "cartão: formulário fecha (não mostra 'recusado')")
	check(ui2.step == "error" and ui2.error_code == "founder_sold_out_paid", "cartão: tela de aviso de reembolso")
	check(hub2.confirmed == "", "cartão: nada de 'compra confirmada'")

	# --- MINHAS COMPRAS ---
	var P = load("res://monetization/purchases_ui.gd")
	var items := [{"status": "sold_out", "product_id": "founder", "created_at": "2020-01-01T00:00:00Z"}, {"status": "failed", "product_id": "founder"}]
	var vis: Array = P.visible_items(items)
	check(vis.size() == 1 and String(vis[0].status) == "sold_out", "MINHAS COMPRAS: pagamento sem vaga aparece (antigo ou não)")
	check(String(P.STATUS["sold_out"][0]).contains("REEMBOLSO"), "MINHAS COMPRAS: rótulo VAGAS ESGOTADAS · REEMBOLSO")

	print("RESULT %s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures > 0 else 0)
