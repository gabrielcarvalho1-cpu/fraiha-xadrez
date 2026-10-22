extends SceneTree
## R176 · CHAT da partida: EMOTES no cabeçalho (ao lado de SILENCIAR), molduras também contra o computador,
## campo de mensagem com cursor piscando, faixa do emote (padrão da referência) AO LADO DA FOTO de quem mandou,
## e a chave EMOTES (opções da partida, AÇÕES do celular e Configurações). Sem rede.
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
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func wait(sec: float):
	await create_timer(sec).timeout
func run():
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	var mobile := size.y > size.x
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var Prefs = load("res://social/emote_prefs.gd")
	Prefs.set_enabled(true)
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	# ---- contra o computador
	stage._start_bot("easy", "w")
	await frames(12)
	var chat = stage.match_chat
	check(chat != null and chat.local_mode and chat.active(), "chat contra o bot ativo")
	if chat.minimized: chat.set_minimized(false)
	if mobile: chat.set_mobile_open(true)
	stage._layout()
	await frames(8)
	if not mobile:
		var eb: Button = chat.emote_button
		var mb: Button = chat.mute_button
		check(absf(eb.global_position.y - mb.global_position.y) < 4.0 and eb.global_position.x < mb.global_position.x, "EMOTES no cabeçalho, à esquerda de SILENCIAR")
		check(stage.board_skin.bg.chat_tex != null, "quadro do chat (molduras) desenhado contra o bot")
	await shot("01_bot_chat")
	chat._toggle_emotes()
	await shot("02_bot_emotes_abertos")
	chat._toggle_emotes()
	if mobile: chat.set_mobile_open(false)
	await frames(4)
	seed(3)   # o bot responde com um emote
	chat.send_emote("emote_boa_partida")
	await frames(4)
	var mine: Control = chat.bubble_layer.get_node_or_null("EmoteBubble_me")
	check(mine != null, "faixa do meu emote")
	if mine != null:
		var a: Rect2 = chat.avatar_rect.call(true)
		check(a.has_area() and mine.position.y >= a.position.y - 1.0 and mine.get_rect().end.y <= a.end.y + 1.0, "faixa ao lado da minha foto")
		var vs := Vector2(size)
		check(mine.size.y <= 100.0 and absf(mine.get_rect().get_center().x - vs.x / 2.0) > 1.0, "faixa pequena, fora do meio da tela")
	await wait(1.6)
	check(chat.bubble_layer.get_node_or_null("EmoteBubble_opp") != null, "faixa do emote do computador ao lado da foto dele")
	await shot("03_bot_faixas")
	# ---- chave EMOTES nas opções da partida
	if mobile:
		stage.mobile_hud.open()
		await shot("04_acoes_celular")
		stage.mobile_hud._do_action("emotes")
		check(not Prefs.enabled(), "AÇÕES: Emotes desliga")
		await shot("05_acoes_emotes_nao")
		stage.mobile_hud._do_action("emotes")
		stage.mobile_hud.close_actions()
	else:
		stage.game.toggle_settings()
		await shot("04_opcoes_partida")
		stage.board_skin.toggle_setting("emotes")
		check(not Prefs.enabled(), "opções da partida: Emotes desliga")
		await shot("05_opcoes_emotes_desligado")
		stage.board_skin.toggle_setting("emotes")
		stage.board_skin.close_settings()
	Prefs.set_enabled(false)
	chat.show_bubble("Olá!", false, "X", "emote_ola")
	check(chat.bubble_layer.get_node_or_null("EmoteBubble_opp") == null or chat.bubble_layer.get_node("EmoteBubble_opp").is_queued_for_deletion(), "desligado: nenhuma faixa")
	Prefs.set_enabled(true)
	# ---- Configurações (tela inicial)
	stage.bot_controller.stop()
	if chat.local_mode: chat.unbind()
	stage.open_home()
	await frames(10)
	stage.hub.show_page("settings")
	await frames(10)
	var sb = stage.hub.pages["settings"].find_child("SettingsEmotes", true, false)
	if mobile: sb = root.find_child("EmotesToggleMobile", true, false)
	check(sb != null and (mobile or String(sb.text).begins_with("Emotes")), "Configurações: chave Emotes")
	await shot("06_configuracoes")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
