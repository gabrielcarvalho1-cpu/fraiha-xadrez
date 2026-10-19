extends SceneTree
## R150 · FOTO DOS AMIGOS. A foto (avatar_url) de outro jogador aparece na lista de amigos, no perfil, na mesa
## e no adversário; quando o amigo troca a foto (friend_profile do servidor) a nova aparece sem sair e entrar.
## Precisa de um servidor HTTP local servindo PHOTO_BASE/a.png, b.png, b2.png (tests/run_foto_amigos.sh).
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
func same_tex(a, b) -> bool:
	if a == b: return true
	return a is AtlasTexture and b is AtlasTexture and a.atlas == b.atlas and a.region == b.region
## foto na lista: a MESMA imagem recortada em círculo (canto transparente, centro igual)
func is_photo(t: Texture2D, photo: Texture2D) -> bool:
	if t == null or photo == null or t.get_width() != photo.get_width(): return false
	var a: Image = t.get_image(); var b: Image = photo.get_image()
	return a.get_pixel(1, 1).a < 0.1 and a.get_pixel(80, 80).is_equal_approx(b.get_pixel(80, 80))
func wait_peer(hub, uid: String, ms := 8000) -> bool:
	var got := [false]
	var cb := func(u): if u == uid: got[0] = true
	hub.peer_avatar_ready.connect(cb)
	var t0 := Time.get_ticks_msec()
	while not got[0] and Time.get_ticks_msec() - t0 < ms: await process_frame
	hub.peer_avatar_ready.disconnect(cb)
	return got[0]
func run():
	var sz := OS.get_environment("SHOT_SIZE")
	if sz != "":
		var p := sz.split("x")
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(int(p[0]), int(p[1])); root.content_scale_size = root.size
		await process_frame
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var base := OS.get_environment("PHOTO_BASE")
	# cache limpo (as fotos dos amigos ficam em user://avatars/p_<id>.webp)
	for f in ["p_u-namorada", "p_u-amigo2"]:
		for ext in [".webp", ".url"]:
			if FileAccess.file_exists("user://avatars/" + f + ext): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://avatars/" + f + ext))
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	var acc = stage.account
	acc.user_id = "u-eu"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u-eu", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.send_hook = func(_m): pass
	var nam := {"user_id": "u-namorada", "nickname": "Namorada", "avatar_id": "archer", "avatar_url": base + "/b.png", "presence": "online"}
	# 1) sem foto ainda: mostra o avatar do catálogo e começa a baixar
	var t0: Texture2D = hub.avatar_texture_for(nam)
	check(same_tex(t0, hub.avatar_texture("archer")), "enquanto a foto baixa: avatar do catálogo")
	check(await wait_peer(hub, "u-namorada"), "foto da amiga baixada")
	var t1: Texture2D = hub.avatar_texture_for(nam)
	check(t1 != null and t1.get_width() == 160, "depois: a FOTO da amiga (160 px, cache próprio)")
	check(hub.custom_avatar() == null, "a foto da amiga não vira a minha foto")
	# 2) sem avatar_url: avatar do catálogo
	check(same_tex(hub.avatar_texture_for({"user_id": "u-x", "avatar_id": "mage"}), hub.avatar_texture("mage")), "sem foto: avatar do catálogo")
	# 3) lista de amigos com a foto
	var soc = stage.social_ui
	soc.data = {"friends": [nam, {"user_id": "u-amigo2", "nickname": "Amigo2", "avatar_id": "mage", "avatar_url": null, "presence": "offline"}], "received": [], "sent": [], "blocked": []}
	soc.has_list = true
	soc.open()
	soc.data = {"friends": [nam, {"user_id": "u-amigo2", "nickname": "Amigo2", "avatar_id": "mage", "avatar_url": null, "presence": "offline"}], "received": [], "sent": [], "blocked": []}
	soc.has_list = true
	soc._show("list")
	await frames(6)
	var rects: Array = soc.find_children("*", "TextureRect", true, false).filter(func(n): return n.has_meta("peer_uid") and n.get_meta("peer_uid") == "u-namorada")
	check(rects.size() > 0 and is_photo(rects[0].texture, t1), "lista de amigos mostra a foto da amiga (redonda)")
	await shot("lista_amigos_foto")
	# 4) a amiga troca a foto: o servidor avisa (friend_profile) → nova foto aparece sem reabrir
	soc._on_message({"type": "friend_profile", "profile": {"user_id": "u-namorada", "nickname": "Namorada", "avatar_id": "archer", "avatar_url": base + "/b2.png"}})
	check(await wait_peer(hub, "u-namorada"), "foto NOVA da amiga baixada após o aviso")
	await frames(4)
	rects = soc.find_children("*", "TextureRect", true, false).filter(func(n): return n.has_meta("peer_uid") and n.get_meta("peer_uid") == "u-namorada")
	var t2: Texture2D = hub.avatar_texture_for({"user_id": "u-namorada", "avatar_url": base + "/b2.png"})
	check(t2 != null and t2 != t1 and rects.size() > 0 and is_photo(rects[0].texture, t2), "lista troca para a foto nova na hora")
	var ia: Image = t2.get_image()
	check(ia.get_pixel(5, 5).g > ia.get_pixel(5, 5).r, "é mesmo a foto nova (fundo verde)")
	await shot("lista_amigos_foto_nova")
	# 5) a amiga tira a foto: volta ao avatar do catálogo
	soc._on_message({"type": "friend_profile", "profile": {"user_id": "u-namorada", "nickname": "Namorada", "avatar_id": "archer", "avatar_url": null}})
	await frames(3)
	rects = soc.find_children("*", "TextureRect", true, false).filter(func(n): return n.has_meta("peer_uid") and n.get_meta("peer_uid") == "u-namorada")
	check(rects.size() > 0 and same_tex(rects[0].texture, hub.avatar_texture("archer")), "sem foto: volta ao avatar do catálogo")
	soc.hide()
	# 6) retrato público (mesa / adversário / convites)
	var pp = preload("res://profile/player_portrait.gd").make(hub, {"user_id": "u-namorada", "avatar_id": "archer", "avatar_url": base + "/b2.png"}, 64.0)
	root.add_child(pp)
	await frames(2)
	check(pp.avatar_rect.texture == t2, "retrato público (mesa/adversário) usa a foto")
	pp.queue_free()
	print("FAILS ", failures)
	quit(1 if failures else 0)
