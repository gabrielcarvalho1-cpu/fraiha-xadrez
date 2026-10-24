extends SceneTree
## R181 · LOGIN COM GOOGLE DENTRO DO INSTAGRAM: detecção dos navegadores embutidos, erro de "state" e a tela
## "ABRA NO NAVEGADOR" (Android e iPhone). Uso: SHOT_DIR=… SHOT_TAG=… SHOT_SIZE=412x915 xvfb-run godot -s tests/r181_google_instagram_shots.gd
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
	var A = load("res://account/account_service.gd")
	var ig_android := "Mozilla/5.0 (Linux; Android 13; SM-A135M Build/TP1A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/129.0 Mobile Safari/537.36 Instagram 352.0.0.0 Android"
	var ig_ios := "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 352.0.0 (iPhone14,5; iOS 17_5)"
	var fb := "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/128 Mobile Safari/537.36 [FB_IAB/FB4A;FBAV/470.0.0.0;]"
	var chrome := "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36"
	var safari := "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
	check(A.in_app_browser(ig_android) == "Instagram" and A.mobile_os(ig_android) == "android", "Instagram no Android detectado")
	check(A.in_app_browser(ig_ios) == "Instagram" and A.mobile_os(ig_ios) == "ios", "Instagram no iPhone detectado")
	check(A.in_app_browser(fb) == "Facebook", "Facebook detectado")
	check(A.in_app_browser(chrome) == "" and A.in_app_browser(safari) == "", "Chrome e Safari normais: Google liberado direto")
	check(A.is_state_error("OAuth state not found or expired") and A.is_state_error("", "bad_oauth_state"), "erro 'OAuth state not found or expired' reconhecido")
	check(not A.is_state_error("Email not confirmed"), "outros erros continuam com a mensagem normal")
	var size := Vector2i(412, 915)
	if OS.get_environment("SHOT_SIZE") != "":
		var p := OS.get_environment("SHOT_SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	root.content_scale_size = Vector2i.ZERO
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	var ui = stage.account_ui
	for os_name in ["android", "ios"]:
		stage.account.google_blocked.emit("Instagram", os_name)
		await frames(10)
		check(ui.page == "inapp" and ui.is_open(), "%s: Google dentro do Instagram abre a tela 'QUASE LÁ!' (abrir no navegador)" % os_name)
		var texts := []
		for b in ui.find_children("*", "Button", true, false): texts.append(String(b.text))
		var want := "ABRIR NO CHROME" if os_name == "android" else "ABRIR NO SAFARI"
		check(want in texts and "COPIAR LINK DO JOGO" in texts and "CRIAR CONTA COM E-MAIL" in texts, "%s: botões %s / copiar link / e-mail" % [os_name, want])
		await shot("inapp_" + os_name)
	ui.open("login")
	await frames(10)
	await shot("login")
	print("R181_GOOGLE_INSTAGRAM FAILS=", fails)
	quit(1 if fails else 0)
