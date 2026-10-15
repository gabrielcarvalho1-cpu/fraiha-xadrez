extends SceneTree
## R103 · Vitrine do FRAIHA PREMIUM: Fundador (+ Lendário, por tempo limitado) e Club (30 dias / 1 ano),
## preço PIX com desconto + cartão. Prints em SHOT_DIR (use FRAIHA_PAYMENT_MODE=real para preços reais).
var fails := 0
var pr
func _initialize(): call_deferred("run")
func frames(n := 8):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func node(n: String) -> Node:
	return pr.root.find_child(n, true, false)
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func scroll_to(n: String):
	var c = node(n)
	if c == null: return
	await frames(3)
	pr.scroll.scroll_vertical = int(c.global_position.y - pr.column.global_position.y) - 10
	await frames(3)
func run():
	var size := Vector2i(1672, 941)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui != null and stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.get_node("MainHub")
	hub.open_premium()
	await frames(6)
	pr = hub.premium
	pr.offer = {"type": "payment_offer", "founder_open": true, "founder_until": "2026-12-14T23:59:59-03:00"}
	pr._rebuild()
	await frames(8)
	check(node("FounderShowcase") != null and node("ClubShowcase") != null, "vitrine com arena do Fundador e do Club")
	check(node("BecomeFounder") != null and node("BecomeLegend") != null, "dois pacotes de Fundador")
	check(node("SubscribeClub") != null and node("SubscribeClubYearly") != null, "Club 30 dias e 1 ano")
	var dl = node("FounderDeadline")
	check(dl != null and "14/12" in String(dl.text), "prazo do Fundador vindo do servidor")
	await shot("01_hub_topo")
	pr.open_preview("fundador")
	await frames(8)
	check(node("PreviewModal") != null, "EXPERIMENTAR abre a prévia do tabuleiro")
	await shot("10_experimentar_fundador")
	pr.open_preview("club")
	await frames(8)
	await shot("11_experimentar_club")
	pr.close_modal()
	await frames(4)
	await scroll_to("FounderPlans")
	await shot("02_hub_fundador_planos")
	await scroll_to("ClubShowcase")
	await shot("03_hub_club")
	await scroll_to("ClubPlans")
	await shot("04_hub_club_planos")
	pr.show_page("founder")
	await frames(8)
	await shot("05_fundador_topo")
	await scroll_to("FounderPlans")
	await shot("06_fundador_planos")
	pr.show_page("club")
	await frames(8)
	await shot("07_club_topo")
	pr.open_payment("club_yearly")
	await frames(10)
	check(node("PaymentRefundNote") != null or OS.get_environment("FRAIHA_PAYMENT_MODE") != "real", "tela de pagamento com aviso de arrependimento")
	await shot("09_pagamento_escolha")
	pr.close_modal()
	await frames(4)
	# oferta encerrada
	pr.offer = {"type": "payment_offer", "founder_open": false, "founder_until": "2026-12-14T23:59:59-03:00"}
	pr.show_page("hub")
	await frames(8)
	check(node("BecomeFounder") == null and node("BecomeFounderOff") != null, "oferta encerrada: botão desligado")
	await scroll_to("FounderShowcase")
	await shot("08_fundador_encerrado")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
