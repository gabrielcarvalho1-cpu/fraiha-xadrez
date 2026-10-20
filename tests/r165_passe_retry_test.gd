extends SceneTree
## R165 · PASSE: se o pedido se perde (conexão ainda abrindo), a tela pede de novo sozinha e abre; sem resposta, mostra TENTAR DE NOVO.
var fails := 0
func check(ok: bool, l: String):
	print(("PASS " if ok else "FAIL ") + l)
	if not ok: fails += 1
func frames(n):
	for i in n: await process_frame
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(1280, 720)
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(30)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var acc = stage.account
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "Ana", "avatar_id": "warrior"}
	var asks := [0]
	acc.send_hook = func(m): if String(m.get("type", "")) == "pass_get": asks[0] += 1
	var cc = stage.hub.crowns_client()
	cc.open_pass()
	var ui = cc.pass_panel
	await create_timer(7.0).timeout
	check(asks[0] >= 3, "pediu o passe de novo sozinho (%d pedidos)" % asks[0])
	acc.server_message.emit({"type": "pass_state", "available": true, "season": "2026-10", "name": "Temporada de Outubro", "levels": 30, "xp_per_level": 150, "xp": 300, "level": 2, "club": false, "ends_in_s": 9000, "rewards": [], "xp_rules": {}})
	await frames(6)
	check(ui.head.find_child("PassName", true, false) != null, "resposta chegou: passe aberto")
	ui.close()
	ui.state = {}
	cc.open_pass()
	await create_timer(16.5).timeout
	check(ui.head.get_node_or_null("PassRetry") != null, "sem resposta: aparece TENTAR DE NOVO")
	print("FAILS ", fails)
	quit(1 if fails else 0)
