extends SceneTree
## R177e · emotes contra os bots no XEQUE e na MARCHA (chat local da mesa): botão CHAT aparece, emote mostra a
## faixa no cartão de quem mandou e o bot responde.
var fails := 0
func _initialize(): call_deferred("run")
func frames(n := 3):
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
	var size := Vector2i(1600, 900)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	preload("res://social/emote_prefs.gd").set_enabled(true)
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	var pc = stage.party_chat
	# XEQUE contra bots
	await hub.open_xeque()
	await frames(6)
	var xu = hub.xeque
	xu.start_game()
	for i in 6: xu._process(3.0)
	await frames(10)
	check(pc.local and pc.visible and pc.toggle.visible, "XEQUE bots: botão CHAT da mesa")
	seed(1)
	pc.send_emote("emote_ola")
	await frames(4)
	check(pc.bubble_layer != null and pc.bubble_layer.get_node_or_null("PartyEmote_0") != null, "XEQUE bots: faixa do meu emote")
	await create_timer(2.2).timeout
	var bot_any := false
	for c in pc.bubble_layer.get_children(): if String(c.name) != "PartyEmote_0": bot_any = true
	check(bot_any or pc.messages.size() >= 2, "XEQUE bots: bot responde com emote")
	await shot("xeque_bots_emotes")
	# R178i · todos mandam ao mesmo tempo: cada faixa do tamanho do próprio cartão
	for st in [0, 1, 2, 3]: pc.show_emote({"from_seat": st, "text": "Boa jogada!", "emote": "emote_boa_jogada", "nickname": "Bot %d" % st})
	await frames(12)
	await shot("xeque_todos_emotes")
	xu.view.set("hand_zoom", 1.0)
	await frames(6)
	await shot("xeque_zoom_mao")
	xu.close()
	await frames(6)
	check(not pc.local and not pc.visible, "fechar o XEQUE desliga o chat local")
	# MARCHA contra bots
	hub.monetization_state.mock_reset()
	hub.menu_buttons[4].pressed.emit()
	await frames(6)
	var mu = hub.marcha
	mu.tut_page = -1
	await mu.start_game()
	await frames(10)
	check(pc.local and pc.visible, "MARCHA bots: chat da mesa ligado")
	pc.send_emote("emote_boa_sorte")
	await frames(6)
	check(pc.bubble_layer.get_node_or_null("PartyEmote_0") != null, "MARCHA bots: faixa do meu emote")
	await shot("marcha_bots_emotes")
	for st in [0, 1, 2, 3]: pc.show_emote({"from_seat": st, "text": "Parabéns!", "emote": "emote_parabens", "nickname": "Bot %d" % st})
	await frames(12)
	await shot("marcha_todos_emotes")
	print("RESULT ", "OK" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
