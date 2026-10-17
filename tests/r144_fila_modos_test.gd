extends SceneTree
## R144 · XEQUE e MARCHA REAL: JOGAR AGORA pergunta CONTRA BOTS / JOGAR ONLINE; online entra na fila (party_queue);
## tela de busca com tempo, contagem, JOGAR CONTRA BOTS depois de 30 s sozinho e CANCELAR; party_start fecha.
## Sem servidor: as mensagens do servidor são simuladas (o servidor tem tests/server/party_queue_test.cjs).
var failures := 0
func check(ok: bool, label: String):
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func shot(name: String):
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "": return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var sz := OS.get_environment("SHOT_SIZE")
	if sz != "":
		var p := sz.split("x")
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(int(p[0]), int(p[1])); root.content_scale_size = root.size
		await process_frame
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	var po = stage.party_online
	var acc = stage.account
	var sent: Array = []
	# conta logada (sem servidor): captura o que seria enviado
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.send_hook = func(m): sent.append(m)
	# ---------- XEQUE ----------
	await hub.open_xeque()
	await frames(10)
	var x = hub.xeque
	x._on_hit("tut_play")
	await frames(4)
	check(po.is_open() and po.screen == "choose" and x.mode == "tutorial", "XEQUE: JOGAR AGORA abre a escolha (não começa direto)")
	check(root.find_child("PartyChoiceBots", true, false) != null and root.find_child("PartyChoiceOnline", true, false) != null, "escolha: CONTRA BOTS e JOGAR ONLINE")
	await shot("xeque_escolha")
	root.find_child("PartyChoiceBots", true, false).pressed.emit()
	await frames(6)
	check(not po.is_open() and x.mode == "game" and not x.online, "CONTRA BOTS: partida com bots começa")
	x.close()
	await frames(4)
	await hub.open_xeque()
	await frames(6)
	x._on_hit("tut_play")
	await frames(3)
	po._choose_online()
	await frames(3)
	var q = sent.filter(func(m): return String(m.get("type", "")) == "party_queue")
	check(po.screen == "search" and q.size() >= 1 and String(q[-1].get("game", "")) == "xeque", "JOGAR ONLINE: entra na fila do XEQUE (party_queue)")
	acc.server_message.emit({"type": "party_queue_status", "game": "xeque", "waiting": 3, "group": 1, "waited_ms": 4000, "fill_ms": 20000})
	await frames(3)
	check(po.count_label.text.begins_with("2 pessoas"), "busca: mostra quantas pessoas estão na fila (%s)" % po.count_label.text)
	await shot("xeque_busca")
	acc.server_message.emit({"type": "party_queue_status", "game": "xeque", "waiting": 1, "group": 1})
	po.since_ms -= 31000
	await frames(4)
	check(po.alone_box.visible, "sozinho há 30 s: aparece JOGAR CONTRA BOTS")
	await shot("xeque_busca_sozinho")
	root.find_child("PartySearchCancel", true, false).pressed.emit()
	await frames(3)
	check(not po.is_open() and sent.filter(func(m): return String(m.get("type", "")) == "party_queue_cancel").size() >= 1, "CANCELAR BUSCA sai da fila")
	# party_start fecha a busca
	po.open_search("xeque", 1, 1)
	po.on_message({"type": "party_start", "game": "xeque", "room_id": "r1"})
	await frames(3)
	check(not po.is_open(), "mesa encontrada (party_start): a busca fecha")
	x.close()
	await frames(4)
	# R145 · botões CONTRA BOTS / JOGAR ONLINE direto na tela do XEQUE
	await hub.open_xeque()
	await frames(8)
	x._redraw()
	await frames(3)
	check(x.hits.any(func(h): return h.id == "tut_bots") and x.hits.any(func(h): return h.id == "tut_online"), "XEQUE: CONTRA BOTS e JOGAR ONLINE na tela do Como jogar")
	await shot("xeque_tela_botoes")
	sent.clear()
	x._on_hit("tut_online")
	await frames(3)
	check(po.screen == "search" and sent.any(func(mm): return String(mm.get("type", "")) == "party_queue"), "XEQUE: JOGAR ONLINE da tela entra na fila")
	po._cancel_search()
	x._on_hit("tut_bots")
	await frames(4)
	check(x.mode == "game" and not x.online, "XEQUE: CONTRA BOTS da tela começa contra bots")
	x.close()
	await frames(4)
	# ---------- MARCHA ----------
	await hub.open_marcha()
	await frames(10)
	var m = hub.marcha
	await frames(20)
	m.tut_page = -1   # o Como jogar abre sozinho na 1ª vez
	m.gate_info = {"can_play": true, "label": "FASE DE TESTES · PARTIDAS LIVRES"}
	m._redraw()
	await frames(4)
	check(m.hits.any(func(h): return h.id == "lobby_bots") and m.hits.any(func(h): return h.id == "lobby_online"), "MARCHA: CONTRA BOTS e JOGAR ONLINE na tela de entrada")
	await shot("marcha_tela_botoes")
	m._on_hit("lobby_play")
	await frames(4)
	check(po.is_open() and po.screen == "choose" and m.mode == "lobby", "MARCHA: JOGAR AGORA abre a escolha")
	await shot("marcha_escolha")
	po._choose_online()
	await frames(3)
	acc.server_message.emit({"type": "party_queue_status", "game": "marcha", "waiting": 2, "group": 2})
	await frames(3)
	check(po.screen == "search" and po.group == 2, "MARCHA: busca em dupla (convite JOGAR ONLINE)")
	await shot("marcha_busca_dupla")
	acc.server_message.emit({"type": "party_queue_cancelled", "game": "marcha", "by_friend": true})
	await frames(3)
	check(po.screen == "choose" and "amigo" in po.error_label.text, "amigo saiu da fila: volta para a escolha com aviso")
	po.close()
	# ---------- CONVIDAR AMIGO: com bots ou online ----------
	var so = stage.social_ui
	so.open_invite_picker("marcha")
	await frames(3)
	so._picker_invite("f1", {"user_id": "f1", "nickname": "Amigo", "avatar_id": "warrior"})
	await frames(4)
	var tb: Button = so.find_child("InviteTable_bots", true, false)
	var to: Button = so.find_child("InviteTable_online", true, false)
	check(so.screen == "invite_table" and tb != null and to != null, "convite: escolher VOCÊS + BOTS ou JOGAR ONLINE JUNTOS")
	await shot("convite_escolha")
	sent.clear()
	to.pressed.emit()
	await frames(3)
	var inv = sent.filter(func(mm): return String(mm.get("type", "")) == "invite_send")
	check(inv.size() == 1 and String(inv[0].get("table", "")) == "online" and String(inv[0].get("game", "")) == "marcha", "convite ONLINE vai com table=online")
	so.close()
	print("FAILS ", failures)
	quit()
