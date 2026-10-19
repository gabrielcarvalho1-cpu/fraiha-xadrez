extends SceneTree
## R157 · aba XADREZ do TORNEIOS: entrar com código (tev_join), erro do servidor, lista com chaves e campeão.
## Sem servidor: mensagens simuladas (o servidor tem tests/server/eventos_r157_test.cjs).
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
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.get_node("MainHub")
	var acc = stage.account
	var sent: Array = []
	acc.user_id = "u-me"; acc.access_token = "teste"; acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.send_hook = func(m): sent.append(m)
	var cl = hub.crowns_client()
	cl.open_tournament()
	await frames(6)
	var tp = cl.tourn_panel
	check(tp.game == "chess" and tp.code_row.is_visible_in_tree(), "abre na aba XADREZ com o campo do código")
	check(sent.any(func(m): return String(m.get("type", "")) == "tev_list"), "pede os torneios do jogador")
	acc.server_message.emit({"type": "tev_state", "available": true, "events": []})
	await frames(4)
	await shot("torneio_xadrez_vazio")
	tp.code_input.text = "maringa26"
	tp._join()
	await frames(2)
	check(sent.any(func(m): return String(m.get("type", "")) == "tev_join" and String(m.get("code", "")) == "MARINGA26"), "ENTRAR manda o código (maiúsculo)")
	acc.server_message.emit({"type": "tev_error", "code": "not_found", "message": "Nenhum torneio com esse código."})
	await frames(2)
	check(tp.code_status.text.contains("Nenhum torneio"), "erro do servidor aparece")
	acc.server_message.emit({"type": "tev_state", "available": true, "joined_id": "e1", "events": [{"id": "e1", "name": "Torneio da Cidade", "status": "running", "status_text": "EM ANDAMENTO",
		"mode_name": "10 min", "players": 5, "max_players": 16, "starts_at": "2026-11-08T17:00:00Z", "notes": "Praça central · premiação em troféus", "joined": true, "entrants": [],
		"bracket": [[{"a": "Gabriel", "b": "Isabela_Godoy", "winner": "Gabriel", "mine": true}, {"a": "Ana", "b": null, "winner": "Ana"}, {"a": "Bruno", "b": "Caio", "winner": null}, {"a": "Duda", "b": null, "winner": "Duda"}],
			[{"a": "Gabriel", "b": "Ana", "winner": null, "mine": true}, {"a": null, "b": "Duda", "winner": null}], [{"a": null, "b": null, "winner": null}]], "champion": null}]})
	await frames(6)
	check(tp.code_status.text.contains("Inscrição feita"), "inscrição confirmada")
	check(tp.list.find_children("EventCard", "", true, false).size() == 1, "cartão do torneio com as chaves")
	await shot("torneio_xadrez_chaves")
	tp.set_game("xeque")
	await frames(3)
	check(not tp.code_row.visible, "XEQUE: sem o campo do código")
	print("FAILS ", fails)
	quit(1 if fails else 0)
