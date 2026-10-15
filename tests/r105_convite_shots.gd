extends SceneTree
## R105 · CONVIDAR AMIGOS (link, WhatsApp, prêmio) na tela de AMIGOS + avisos de convite e de prêmio.
var fails := 0
var stage
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
func run():
	var size := Vector2i(1672, 941)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui != null: stage.account_ui.hide_ui()
	var s = stage.social_ui
	var acc = stage.account
	acc.user_id = "u-me"; acc.access_token = "teste"; acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	s.data = {"friends": [{"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior", "presence": "online"}], "received": [], "sent": [], "blocked": []}
	s.has_list = true
	s.open()
	await frames(6)
	s._show("list")
	await frames(6)
	check(s.panel.find_child("OpenReferral", true, false) != null, "AMIGOS tem CONVIDAR AMIGOS")
	await shot("01_amigos_convidar")
	s.open_ref()
	acc.server_message.emit({"type": "ref_info", "available": true, "code": "K7QM2XA", "rules": {"games": 5, "friend_days": 7, "purchase_days": 30, "cap": 10},
		"invited": 3, "playing": 1, "qualified": 2, "rewarded_month": 2, "purchases": 0})
	await frames(6)
	var link = s.panel.find_child("RefLink", true, false)
	check(link != null and String(link.text).ends_with("?convite=K7QM2XA"), "link com o código")
	check(s.panel.find_child("RefWhatsApp", true, false) != null and s.panel.find_child("RefCopy", true, false) != null, "WhatsApp e copiar")
	await shot("02_convidar")
	var wa := preload("res://social/invite_link.gd").whatsapp_url("K7QM2XA")
	check(wa.begins_with("https://wa.me/?text=") and wa.contains("convite%3DK7QM2XA"), "mensagem do WhatsApp leva o link")
	s.close()
	stage.hub.show_notice("VOCÊ FOI CONVIDADO!", "Um amigo te chamou para o FRAIHA Xadrez.\n\nCrie sua conta e termine 5 partidas online: você e ele ganham 7 dias de Club FRAIHA.")
	await shot("03_convidado")
	stage.hub.notice_modal.close()
	acc.server_message.emit({"type": "ref_reward", "message": "Um amigo que você convidou completou 5 partidas: você ganhou 7 dias de Club FRAIHA!"})
	await frames(4)
	check(stage.hub.notice_modal.is_open(), "prêmio da indicação aparece")
	await shot("04_premio")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
