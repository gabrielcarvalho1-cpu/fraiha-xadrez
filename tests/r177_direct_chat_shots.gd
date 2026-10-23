extends SceneTree
## R177 · CHAT EXCLUSIVO: a janela abre quando o servidor manda dchat_open (o dono aciona no Admin), mostra as
## mensagens do administrador e do jogador, PRESENTE (Coroas / item), mensagens rápidas (+), emotes, fechar (X) e
## mensagem nova reabrindo. PC e celular. Sem rede (mensagens do servidor simuladas).
var fails := 0
var sent: Array = []
func _initialize(): call_deferred("run")
func frames(n := 8):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(6)
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
	var acc = stage.account
	var dc = stage.direct_chat
	check(dc != null and not dc.visible, "chat exclusivo pronto e escondido")
	# intercepta o envio ao servidor
	dc.account = FakeAcc.new(sent)
	var t0 := "2026-10-22T17:28:00.000Z"
	acc.server_message.emit({"type": "dchat_open", "chat": {"open": true, "admin_name": "Fraiha", "messages": [
		{"id": 1, "from": "admin", "text": "Olá!\nComo posso ajudar você hoje?", "ts": t0},
		{"id": 2, "from": "player", "text": "Oi Fraiha!\nTenho uma dúvida sobre o jogo...", "ts": "2026-10-22T17:29:00.000Z"},
		{"id": 3, "from": "admin", "text": "Claro! Pode me dizer o que você precisa?", "ts": "2026-10-22T17:30:00.000Z"},
		{"id": 4, "from": "player", "text": "Gostaria de saber sobre um evento especial.", "ts": "2026-10-22T17:31:00.000Z"}]}})
	await frames(10)
	check(dc.visible and dc.list.get_child_count() == 4, "dchat_open abre a janela com as 4 mensagens")
	acc.server_message.emit({"type": "dchat_msg", "msg": {"id": 5, "from": "admin", "text": "Perfeito! Vou te passar todas as informações. E um presente para você!", "ts": "2026-10-22T17:31:30.000Z",
		"gift": {"kind": "crowns", "amount": 500, "name": "500 Coroas"}}})
	await frames(10)
	check(dc.list.get_child_count() == 5 and dc.list.find_child("DirectChatGift", true, false) != null, "presente de Coroas aparece no balão")
	await shot("chat_exclusivo")
	acc.server_message.emit({"type": "dchat_msg", "msg": {"id": 6, "from": "admin", "text": "E uma moldura nova também.", "ts": "2026-10-22T17:32:00.000Z",
		"gift": {"kind": "item", "item": "estrategista", "item_kind": "title", "name": "Estrategista", "kind_label": "Título"}}})
	await frames(10)
	await shot("chat_exclusivo_presente_item")
	# enviar
	dc.input.text = "Muito obrigado!!"
	dc.send_current()
	check(sent.size() == 1 and sent[0].type == "dchat_send" and sent[0].text == "Muito obrigado!!" and dc.input.text == "", "ENVIAR manda dchat_send e limpa o campo")
	# mensagens rápidas
	dc.hits.plus.pressed.emit()
	await frames(6)
	check(dc.pop != null and dc.pop.visible, "+ abre MENSAGENS RÁPIDAS")
	await shot("chat_exclusivo_rapidas")
	var qb: Button = null
	for b in dc.pop.find_children("*", "Button", true, false): if b.text == "Obrigado!": qb = b
	if qb != null: qb.pressed.emit()
	check(sent.size() == 2 and sent[1].text == "Obrigado!" and not dc.pop.visible, "mensagem rápida enviada")
	dc.hits.emoji.pressed.emit()
	await frames(6)
	check(dc.pop.visible, "emotes abrem")
	await shot("chat_exclusivo_emotes")
	dc._close_pop()
	if not dc.portrait:
		dc.hits.profile.pressed.emit()
		await frames(6)
		check(dc.info != null and dc.info.visible, "VER PERFIL mostra sobre o administrador")
		await shot("chat_exclusivo_ver_perfil")
		dc.info.hide()
	# fechar e reabrir com mensagem nova
	dc.hits.close.pressed.emit()
	await frames(4)
	check(not dc.visible and sent[-1].type == "dchat_hide", "X fecha e avisa o servidor (dchat_hide)")
	acc.server_message.emit({"type": "dchat_open", "chat": {"open": true, "admin_name": "Fraiha", "messages": [{"id": 1, "from": "admin", "text": "Ainda está aí?", "ts": t0}]}})
	await frames(6)
	check(dc.visible, "mensagem nova do administrador reabre")
	acc.server_message.emit({"type": "dchat_closed"})
	await frames(6)
	check(not dc.input.editable, "encerrado pelo administrador: campo travado")
	await shot("chat_exclusivo_encerrado")
	print("RESULT ", "OK" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)

class FakeAcc:
	var out: Array
	func _init(a): out = a
	func send_server(m): out.append(m)
