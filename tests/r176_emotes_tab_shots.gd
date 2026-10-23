extends SceneTree
## R176.8 · Perfil: aba EMOTES (PC) e seção SEUS EMOTES (celular) + Molduras sem "Da liga".
var fails := 0
func _initialize(): call_deferred("run")
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func frames(n := 3):
	for i in n: await process_frame
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(d.path_join(OS.get_environment("SHOT_TAG") + name + ".png"))
func run():
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	for i in 20: await process_frame
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	await create_timer(0.8).timeout
	var hub = stage.hub
	hub.show_page("profile")
	await create_timer(0.5).timeout
	check(not ("liga" in preload("res://profile/frame_gallery.gd").options()), "Molduras: sem 'Da liga'")
	if size.x > size.y:
		hub.set_profile_tab("frames")
		await shot("perfil_molduras")
		hub.set_profile_tab("emotes")
		check(hub.emote_gallery != null and hub.emote_gallery.cards.size() == 25, "aba EMOTES com os 25 emotes")
		await shot("perfil_emotes")
		hub.emote_gallery.cards["emote_uau"].pressed.emit()
		await shot("perfil_emote_bloqueado")
		check(hub.avatar_detail.apply.text == "VER NA LOJA", "emote bloqueado: VER NA LOJA")
		hub.set_cosmetic("title", "auto")   # estado salvo de rodadas anteriores
		hub.set_profile_tab("titles")
		check(hub.title_gallery != null and hub.title_gallery.cards.size() == 15, "aba TÍTULOS com 15 opções")
		await shot("perfil_titulos")
		hub.title_gallery.cards["estrategista"].pressed.emit()
		await shot("perfil_titulo_bloqueado")
		check(hub.avatar_detail.apply.text == "VER NA LOJA", "título da loja bloqueado: VER NA LOJA")
		await frames(3)
		preload("res://profile/premium_cosmetics.gd").shop_owned = ["estrategista"]
		hub._inspect_title("estrategista")
		check(hub.avatar_detail.apply.text == "USAR TÍTULO", "título comprado: USAR TÍTULO (%s · %s · %s)" % [hub.avatar_detail.apply.text, hub.title_gallery.state_of("estrategista"), str(preload("res://profile/premium_cosmetics.gd").shop_owned)])
		hub.inspected_title = "estrategista"
		check(hub.apply_inspected() and hub.cosmetic_pref("title") == "estrategista", "aplica o título")
		await frames(4)
		await shot("perfil_titulo_em_uso")
		hub.show_page("main")
		await frames(10)
		await shot("lobby_titulo")
		hub.set_cosmetic("title", "auto")
	else:
		check(root.find_child("TitleGalleryMobile", true, false) != null, "celular: SEU TÍTULO")
		var g = root.find_child("EmoteGalleryMobile", true, false)
		check(g != null, "celular: SEUS EMOTES")
		if g != null:
			var sc = g.get_parent()
			while sc != null and not (sc is ScrollContainer): sc = sc.get_parent()
			if sc != null:
				await process_frame
				sc.scroll_vertical = int(g.position.y) - 80
		await shot("perfil_emotes_celular")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
