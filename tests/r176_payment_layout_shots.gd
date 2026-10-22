extends SceneTree
## R176 · telas de pagamento no celular: PIX (moldura inteira, borda dourada da direita visível) e cartão.
## Sem servidor: cobrança falsa só para desenhar. Rodar com SHOT_SIZE (ex.: 1170x2532) e -- --mobile-test.
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 6):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	hub.open_premium("founder")
	await frames(8)
	var pr = hub.premium
	var img := Image.create(33, 33, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in 33:
		for x in 33:
			if (x * 7 + y * 13) % 5 < 2: img.set_pixel(x, y, Color.BLACK)
	var ui = load("res://monetization/payment_real_ui.gd").new()
	pr._modal_host().add_child(ui)
	ui.setup(pr, "founder")
	ui.method = "pix"
	ui.charge = {"id": "t1", "qr_code_base64": Marshalls.raw_to_base64(img.save_png_to_buffer()),
		"copy_paste": "00020126580014br.gov.bcb.pix0136ad537313-99e9-45c1-b05a-3f2e1d0c9b8a5204000053039865406" + "44.905802BR5913FRAIHA XADREZ6009SAO PAULO62070503***6304ABCD",
		"ticket_url": "https://www.mercadopago.com.br/payments/1/ticket", "expires_at": ""}
	ui._show("pix")
	await frames(10)
	var f: Control = ui.find_child("PaymentPanel", true, false)
	var vs: Vector2 = root.get_visible_rect().size
	var gr: Rect2 = f.get_global_rect()
	var sc: Control = ui.panel
	var srect: Rect2 = sc.get_global_rect()
	print("view ", vs, " scroll ", srect, " frame ", gr)
	_dump(f, 0)
	check(gr.end.x <= srect.end.x + 0.5 and gr.end.x <= vs.x, "PIX: moldura cabe na largura (borda direita visível)")
	await shot("pix")
	ui._show("choose")
	await frames(10)
	f = ui.find_child("PaymentPanel", true, false)
	check(f.get_global_rect().end.x <= ui.panel.get_global_rect().end.x + 0.5, "escolha: moldura cabe na largura")
	await shot("escolha")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)

func _dump(n: Node, d: int):
	if d > 5: return
	if n is Control:
		var m: Vector2 = n.get_combined_minimum_size()
		if m.x > 250: print("  ".repeat(d), n.name, " ", n.get_class(), " min ", m)
	for c in n.get_children(): _dump(c, d + 1)
