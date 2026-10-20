extends SceneTree
## R116 · LOJA DE COROAS: títulos (comprado, em uso, confirmar, faltam), abas em breve, painel COROAS com o botão da loja.
## Uso: SHOT_DIR=<pasta> SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path . -s tests/r116_loja_shots.gd [-- --mobile-test]
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
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(12)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.get_node("MainHub")
	var acc = stage.account
	acc.user_id = "u-me"
	acc.access_token = "teste"
	acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	hub.show_page("main")
	await frames(8)
	var items := []
	for it in preload("res://economy/crown_store_catalog.gd").ITEMS: items.append(it)
	acc.server_message.emit({"type": "crowns_state", "available": true, "balance": 1150, "streak": 3, "daily_claimed": true, "missions": [], "recent": [], "match_today": 20, "match_cap": 150, "rules": {}})
	acc.server_message.emit({"type": "store_state", "available": true, "items": items, "owned": ["estrategista", "rei_do_blitz"], "balance": 1150})
	await frames(4)
	check(hub.set_cosmetic("title", "rei_do_blitz"), "título comprado pode ser usado")
	check(not hub.set_cosmetic("title", "imperador"), "título não comprado não pode ser usado")
	var cl = hub.crowns_client()
	cl.open_panel()
	await frames(6)
	check(find_named(root, "CrownsOpenStore").size() == 1, "painel COROAS com ABRIR A LOJA")
	cl.panel.close()
	cl.open_store("title")
	await frames(8)
	check(find_named(root, "StoreItem_").size() == 10, "10 títulos na loja")
	var used = find_named(root, "StoreBtn_rei_do_blitz")
	check(used.size() == 1 and used[0].text == "EM USO", "título em uso marcado")
	var falta = find_named(root, "StoreBtn_imperador")
	check(falta.size() == 1 and falta[0].disabled, "sem saldo: FALTAM N")
	# nada sai da caixa da moldura (celular: a moldura é estreita)
	var box: Rect2 = cl.store_panel._body_rect.grow(1.0)
	var fora := []
	for n in find_named(root, "Store") + find_named(root, "StoreTab_"):
		var r: Rect2 = n.get_global_rect()
		if n.get_parent() is ScrollContainer or String(n.name).begins_with("StoreGrid"): continue
		if r.size.x > 0 and (r.position.x < box.position.x or r.end.x > box.end.x): fora.append(String(n.name))
	check(fora.is_empty(), "loja dentro da moldura (fora: %s)" % ", ".join(fora))
	check(cl.store_panel.body.size.x <= cl.store_panel._body_rect.size.x + 1.0, "corpo não alarga (%.0f de %.0f)" % [cl.store_panel.body.size.x, cl.store_panel._body_rect.size.x])
	await shot("01_loja_titulos")
	find_named(root, "StoreBtn_cavaleiro")[0].pressed.emit()
	await frames(4)
	check(find_named(root, "StoreBtn_cavaleiro")[0].text.begins_with("CONFIRMAR"), "comprar pede confirmação")
	await shot("02_confirmar")
	acc.server_message.emit({"type": "store_state", "available": true, "items": items, "owned": ["estrategista", "rei_do_blitz", "m_chama_eterna"], "balance": 1150})
	check(hub.set_cosmetic("frame", "m_chama_eterna"), "moldura comprada pode ser usada")
	cl.store_panel.set_tab("frame")
	await frames(6)
	check(find_named(root, "StoreItem_").size() == 2, "2 molduras na loja")
	var fu = find_named(root, "StoreBtn_m_chama_eterna")
	check(fu.size() == 1 and fu[0].text == "EM USO", "moldura em uso marcada")
	await shot("03_molduras")
	cl.store_panel.set_tab("emote")
	await frames(6)
	check(find_named(root, "StoreItem_emote_").size() == 8, "8 emotes na loja")
	await shot("04_emotes")
	cl.store_panel.close()
	await frames(2)
	hub.show_page("customize")
	await frames(8)
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
