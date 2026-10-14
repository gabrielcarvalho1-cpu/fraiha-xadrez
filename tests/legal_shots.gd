extends SceneTree
## R97 · TERMOS E PRIVACIDADE, EXCLUIR CONTA, entrada nas Configurações e no cadastro, aviso de servidor acordando.
## Uso: SHOT_DIR=<pasta> SHOT_TAG=<p> SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path . -s tests/legal_shots.gd [-- --mobile-test]
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
	# Configurações com a nova placa
	hub.show_page("settings")
	await frames(10)
	await shot("configuracoes")
	hub.show_page("main")
	await frames(6)
	# Termos / Privacidade
	hub.open_legal("termos")
	await frames(8)
	check(hub.legal_ui.is_open() and hub.legal_ui.text.text.begins_with("TERMOS DE USO"), "TERMOS DE USO abre com o texto")
	await shot("termos")
	hub.legal_ui.set_tab("privacidade")
	await frames(6)
	check(hub.legal_ui.text.text.contains("LGPD"), "PRIVACIDADE mostra a política (LGPD)")
	await shot("privacidade")
	hub.legal_ui.set_tab("excluir")
	await frames(6)
	check(not hub.legal_ui.del_button.visible, "convidado: não há conta para excluir")
	hub.legal_ui.close()
	# conta (sem rede): simula perfil para a aba EXCLUIR
	acc.user_id = "u-me"
	acc.access_token = "teste"
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	acc.server_ready = true
	hub.open_legal("excluir")
	await frames(6)
	check(hub.legal_ui.del_button.visible and hub.legal_ui.del_button.disabled, "conta: botão de excluir travado até digitar o nome")
	hub.legal_ui.del_input.text = "gabriel"
	hub.legal_ui._refresh_delete()
	check(not hub.legal_ui.del_button.disabled, "nome digitado (sem diferenciar maiúsculas): libera o botão")
	await shot("excluir")
	acc.server_message.emit({"type": "acct_delete_error", "code": "in_match", "message": "Termine a partida em andamento antes de excluir a conta."})
	await frames(4)
	check(hub.legal_ui.del_status.text.contains("Termine"), "erro do servidor aparece na tela")
	hub.legal_ui.close()
	# cadastro com a frase de consentimento
	acc.profile = {}
	acc.access_token = ""
	acc.user_id = ""
	stage.account_ui.open("signup")
	await frames(8)
	await shot("cadastro")
	stage.account_ui.hide_ui()
	# servidor acordando (conta logada sem resposta do servidor)
	acc.access_token = "teste"
	acc.user_id = "u-me"
	acc.server_ready = false
	stage._waking_since = Time.get_ticks_msec() - 6000
	stage._sync_waking()
	await frames(6)
	check(stage.waking_server, "5 s sem conectar: 'Acordando o servidor…'")
	await shot("acordando")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
