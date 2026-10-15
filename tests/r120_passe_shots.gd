extends SceneTree
## R120 · PASSE DA TEMPORADA: nível, barra de XP, faixa grátis × faixa Club; sem Club e com Club.
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
func rewards() -> Array:
	var out := []
	for l in range(1, 31):
		var free = {"crowns": 100} if l == 15 else ({"crowns": 200} if l == 30 else ({"crowns": 30} if l % 3 == 0 else null))
		var club = {"crowns": 60 if l % 5 == 0 else 20}
		if l == 10: club = {"item": "emote_lenda", "name": "Lenda!", "kind": "emote"}
		if l == 20: club = {"item": "gambito", "name": "Mestre do Gambito", "kind": "title"}
		if l == 30: club = {"item": "safira", "name": "Moldura Safira", "kind": "frame"}
		out.append({"level": l, "free": free, "club": club})
	return out
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
	acc.user_id = "u-me"; acc.access_token = "teste"; acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	hub.show_page("main")
	await frames(6)
	var cl = hub.crowns_client()
	cl.open_panel()
	await frames(6)
	check(find_named(root, "CrownsOpenPass").size() == 1, "painel COROAS com PASSE DA TEMPORADA")
	cl.open_pass()
	var st := {"type": "pass_state", "available": true, "season": "2026-10", "name": "Temporada de Outubro", "levels": 30, "xp_per_level": 150,
		"xp_rules": {"win": 30, "play": 10, "mission": 50, "daily": 20}, "ends_in_s": 16 * 86400 + 9 * 3600, "rewards": rewards(), "xp": 1310, "level": 8, "club": false}
	acc.server_message.emit(st)
	await frames(8)
	check(find_named(root, "PassLv_").size() == 30, "30 níveis na trilha")
	check(String(find_named(root, "PassLevel")[0].text) == "NÍVEL 8/30", "nível atual")
	check(find_named(root, "PassClubCta").size() == 1, "sem Club: convite para o Club")
	await shot("01_passe_sem_club")
	st.club = true
	acc.server_message.emit(st)
	await frames(8)
	check(find_named(root, "PassClubCta").is_empty(), "com Club: faixa ativa")
	await shot("02_passe_com_club")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
