extends SceneTree
## R96 · topo da Home: RANKING (troféu), CHAT GLOBAL (balão) e painel de VOLUME (música + efeitos).
## Sem rede: as respostas do servidor são simuladas pelo sinal server_message da conta.
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path . -s tests/home_top_buttons_shots.gd [-- --mobile-test]
var stage
var hub
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

func find_named(n: Node, prefix: String) -> Array:
	var out := []
	if n.name.begins_with(prefix) and n is Control and n.is_visible_in_tree(): out.append(n)
	for c in n.get_children(): out.append_array(find_named(c, prefix))
	return out

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
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	hub = stage.get_node("MainHub")
	var acc = stage.account
	acc.user_id = "u-me"
	acc.access_token = "teste"
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	hub.show_page("main")
	await frames(10)
	check(find_named(root, "TrophyTopButton").size() >= 1, "botão RANKING (troféu) no topo da Home")
	check(find_named(root, "ChatTopButton").size() >= 1, "botão CHAT GLOBAL (balão) no topo da Home")
	await shot("home")

	# ---- RANKING
	hub.open_leaderboard()
	await frames(4)
	var rows := []
	var names := ["ReiDoBlitz", "LadyTorre", "Cavalo_Louco", "Gabriel", "Bispo_Veloz", "PeaoDeFerro", "Dama_Negra", "Roque_Longo"]
	for i in names.size():
		rows.append({"pos": i + 1, "user_id": "u-me" if names[i] == "Gabriel" else "u%d" % i, "nickname": names[i], "wins": 40 - i * 3, "losses": 8 + i, "draws": i % 3,
			"matches": 48 + i, "rate": 83.3 - i * 4.1, "league": 9 - i, "pl": 80 - i * 7})
	acc.server_message.emit({"type": "leaderboard", "board": "ranked_3min", "available": true, "min_matches": 5, "rows": rows,
		"me": {"pos": 4, "user_id": "u-me", "wins": 31, "losses": 11, "draws": 0, "matches": 42, "rate": 73.8}})
	await frames(6)
	check(hub.leaderboard_ui.is_open() and hub.leaderboard_ui.list.get_child_count() >= names.size(), "RANKING abre e mostra as linhas do XADREZ (Relâmpago)")
	check(hub.leaderboard_ui.chess_row.visible, "XADREZ tem as 4 filas")
	await shot("ranking_xadrez")
	hub.leaderboard_ui.set_tab("xeque")
	acc.server_message.emit({"type": "leaderboard", "board": "xeque", "available": false, "min_matches": 5, "rows": [], "me": null})
	await frames(6)
	check(not hub.leaderboard_ui.chess_row.visible and hub.leaderboard_ui.status.text.contains("em breve"), "XEQUE sem a 0009: 'em breve', sem as filas do xadrez")
	await shot("ranking_xeque_em_breve")
	hub.leaderboard_ui.set_tab("marcha")
	acc.server_message.emit({"type": "leaderboard", "board": "marcha", "available": true, "min_matches": 5, "rows": rows.slice(0, 3),
		"me": {"pos": 0, "user_id": "u-me", "wins": 1, "losses": 1, "draws": 0, "matches": 2, "rate": 50.0, "missing": 3}})
	await frames(6)
	check(hub.leaderboard_ui.me_label.text.contains("Faltam 3"), "fora do placar: mostra quantas partidas faltam")
	await shot("ranking_marcha")
	hub.leaderboard_ui.close()

	# ---- CHAT GLOBAL
	hub.open_global_chat()
	await frames(4)
	acc.server_message.emit({"type": "gchat_history", "can_send": true, "online": 12, "messages": [
		{"id": 1, "user_id": "u1", "nickname": "LadyTorre", "text": "Boa tarde, pessoal! Alguém pra uma Marcha?", "ts": "2026-10-14T18:01:00.000Z"},
		{"id": 2, "user_id": "u2", "nickname": "Cavalo_Louco", "text": "Bora! Me chama no convite.", "ts": "2026-10-14T18:01:30.000Z"},
		{"id": 3, "user_id": "u-me", "nickname": "Gabriel", "text": "Quem topa XEQUE depois?", "ts": "2026-10-14T18:02:10.000Z"}]})
	await frames(6)
	check(hub.global_chat_ui.is_open() and hub.global_chat_ui.list.get_child_count() == 3 and hub.global_chat_ui.input_row.visible, "CHAT GLOBAL abre com histórico e campo para escrever")
	hub.global_chat_ui.selected = 1
	hub.global_chat_ui._rebuild()
	await shot("chat_global")
	# R104.1 · VER PERFIL de quem escreveu
	var gp = hub.global_chat_ui.list.find_child("GchatProfile", true, false)
	check(gp != null, "CHAT GLOBAL: tocar na mensagem mostra VER PERFIL")
	if gp != null:
		gp.pressed.emit()
		await frames(6)
		check(not hub.global_chat_ui.is_open() and stage.social_ui.is_open() and stage.social_ui.profile_id == "u1", "VER PERFIL abre o perfil do jogador em AMIGOS")
		stage.social_ui.profile = {"user_id": "u1", "nickname": "LadyTorre", "avatar_id": "warrior", "presence": "online", "highest_league": 0, "relation": "none", "ranked": {}}
		stage.social_ui._show("profile")
		await shot("chat_global_perfil")
		stage.social_ui.close()
		hub.open_global_chat()
		await frames(4)
		acc.server_message.emit({"type": "gchat_history", "can_send": true, "online": 12, "messages": [
			{"id": 1, "user_id": "u1", "nickname": "LadyTorre", "text": "Boa tarde, pessoal! Alguém pra uma Marcha?", "ts": "2026-10-14T18:01:00.000Z"},
			{"id": 2, "user_id": "u2", "nickname": "Cavalo_Louco", "text": "Bora! Me chama no convite.", "ts": "2026-10-14T18:01:30.000Z"},
			{"id": 3, "user_id": "u-me", "nickname": "Gabriel", "text": "Quem topa XEQUE depois?", "ts": "2026-10-14T18:02:10.000Z"}]})
		await frames(4)
	acc.server_message.emit({"type": "gchat_msg", "id": 4, "user_id": "u1", "nickname": "LadyTorre", "text": "Topo!", "ts": "2026-10-14T18:02:30.000Z"})
	await frames(4)
	check(hub.global_chat_ui.list.get_child_count() == 4, "mensagem nova aparece")
	hub.global_chat_ui.muted["u1"] = true
	hub.global_chat_ui._rebuild()
	await frames(4)
	check(hub.global_chat_ui.list.get_child_count() == 2, "SILENCIAR esconde as mensagens daquela pessoa")
	acc.server_message.emit({"type": "gchat_history", "can_send": false, "online": 3, "messages": []})
	await frames(4)
	check(not hub.global_chat_ui.input_row.visible and hub.global_chat_ui.guest_label.visible, "convidado: só lê")
	hub.global_chat_ui.close()
	await frames(4)
	check(not hub.global_chat_ui.is_open(), "CHAT GLOBAL fecha")

	# ---- VOLUME da Home: duas barras
	hub.set_sound_muted(true)
	hub.open_home_volume(hub.sound_button if is_instance_valid(hub.sound_button) and hub.sound_button.is_visible_in_tree() else null)
	await frames(6)
	var pop = hub.get_meta("volume_popover")
	check(pop.visible and pop.kind == "both" and not hub.sound_muted, "som da Home abre MÚSICA + EFEITOS (e tira o mudo geral)")
	await shot("volume")
	hub.set_mode_volume("music", 0.0)
	hub.set_mode_volume("fx", 0.0)
	check(hub.home_sound_off(), "música e efeitos no zero: ícone de som desligado")
	hub.set_mode_volume("music", 0.6)
	hub.set_mode_volume("fx", 0.8)
	check(not hub.home_sound_off(), "subir uma barra: ícone ligado")
	pop.close()
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
