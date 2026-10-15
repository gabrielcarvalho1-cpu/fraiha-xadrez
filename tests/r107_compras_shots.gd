extends SceneTree
## R107 · MINHAS COMPRAS (Premium): lista vinda do servidor, situação de cada pedido e ajuda de reembolso.
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 8):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func iso(ago_s: int) -> String:
	return Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - ago_s) + ".000Z"
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
	await frames(20)
	if stage.account_ui != null: stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u-me"; acc.access_token = "teste"; acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	var hub = stage.get_node("MainHub")
	hub.entitlements.apply_server({"is_founder": true, "club_active": true, "club_expires_at": "2027-01-13T12:00:00Z", "founder_tier": "founder", "founder_number": 37})
	hub.open_premium("purchases")
	await frames(6)
	var pr = hub.premium
	check(pr.page == "purchases", "abre MINHAS COMPRAS")
	acc.server_message.emit({"type": "payment_history", "items": [
		{"product_id": "club_monthly", "method": "card", "amount_cents": 1990, "status": "paid", "created_at": iso(86400 * 2), "paid_at": iso(86400 * 2)},
		{"product_id": "founder", "method": "pix", "amount_cents": 4490, "status": "paid", "created_at": iso(86400 * 9), "paid_at": iso(86400 * 9)},
		{"product_id": "club_yearly", "method": "pix", "amount_cents": 13490, "status": "pending", "created_at": iso(300), "paid_at": null},
		{"product_id": "club_monthly", "method": "pix", "amount_cents": 1790, "status": "pending", "created_at": iso(86400), "paid_at": null},
		{"product_id": "founder_legend", "method": "card", "amount_cents": 9990, "status": "refunded", "created_at": iso(86400 * 20), "paid_at": iso(86400 * 20)}]})
	await frames(6)
	var list = pr.root.find_child("PurchasesList", true, false)
	var rows := 0
	for c in list.find_children("Purchase_*", "", true, false): rows += 1
	check(rows == 4, "mostra 4 pedidos (PIX vencido some) — %d" % rows)
	check(pr.root.find_child("PurchasesRefundHelp", true, false) != null, "ajuda de reembolso com o e-mail")
	await shot("01_compras")
	acc.server_message.emit({"type": "payment_history", "items": []})
	await frames(4)
	check(pr.root.find_child("PurchasesEmpty", true, false) != null, "sem compras: mensagem")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
