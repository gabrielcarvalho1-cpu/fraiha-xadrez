extends SceneTree
## R104 · DENUNCIAR no perfil do jogador e dentro da conversa privada (confirmação), e aviso de conta suspensa.
## SHOT_DIR=<pasta> SHOT_TAG=pc_ SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path . -s tests/r104_denuncia_shots.gd
var fails := 0
var stage
func _initialize(): call_deferred("run")
func frames(n := 8):
	for i in n: await process_frame
func check(ok: bool, msg: String):
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok: fails += 1
func shot(name: String):
	var d := OS.get_environment("SHOT_DIR")
	if d == "": return
	await frames(10)
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
	await frames(20)
	if stage.account_ui != null: stage.account_ui.hide_ui()
	var s = stage.social_ui
	var acc = stage.account
	acc.user_id = "u-me"; acc.access_token = "teste"; acc.server_ready = true
	acc.profile = {"user_id": "u-me", "nickname": "Gabriel", "avatar_id": "warrior"}
	s.data = {"friends": [{"user_id": "u1", "nickname": "BrunoChato", "avatar_id": "warrior", "presence": "online"}], "received": [], "sent": [], "blocked": []}
	s.has_list = true
	s.open()
	s.profile = {"user_id": "u1", "nickname": "BrunoChato", "avatar_id": "warrior", "presence": "online", "highest_league": 0, "relation": "friend", "ranked": {}}
	s.profile_id = "u1"
	s._show("profile")
	await frames(6)
	check(s.panel.find_child("ProfileReport", true, false) != null, "perfil tem DENUNCIAR")
	await shot("01_perfil_denunciar")
	s._ask("report", "u1", "DENUNCIAR JOGADOR?", "A equipe FRAIHA vai analisar o perfil de BrunoChato (nome e foto) e as mensagens privadas que ele te enviou. Use para ofensa, assédio, golpe ou nome impróprio. Denúncia falsa pode gerar punição.")
	await shot("02_perfil_confirmar")
	s.dm_id = "u1"
	s.dm_peer = {"nickname": "BrunoChato", "avatar_id": "warrior"}
	s.dm_messages = [{"sender_id": "u1", "body": "mensagem ofensiva de exemplo", "created_at": "2026-10-14T18:00:00Z"}]
	s.dm_can_send = true
	s._show("dm")
	await frames(6)
	check(s.panel.find_child("DmReport", true, false) != null, "conversa privada tem DENUNCIAR")
	await shot("03_conversa_denunciar")
	(s.panel.find_child("DmReport", true, false) as Button).pressed.emit()
	await frames(4)
	check(s.screen == "confirm" and String(s.confirm.get("action", "")) == "report_dm", "DENUNCIAR na conversa pede confirmação")
	await shot("04_conversa_confirmar")
	s.notice_text("Denúncia enviada. Obrigado! A equipe FRAIHA vai analisar.", Color("9fe0a8"))
	s._show("dm")
	s.notice_text("Denúncia enviada. Obrigado! A equipe FRAIHA vai analisar.", Color("9fe0a8"))
	await shot("05_denuncia_enviada")
	s.close()
	await frames(4)
	acc._receive({"type": "acct_suspended", "message": "Sua conta está suspensa até 21/10/2026, 18:00. Motivo: ofensas no chat. Se acha que foi um engano, fale com a gente pelo contato dos Termos de Uso.", "until": "2026-10-21T21:00:00Z"})
	await frames(8)
	check(stage.hub.notice_modal != null and stage.hub.notice_modal.is_open() and not acc.has_profile(), "suspensa: sai da conta e mostra o aviso CONTA SUSPENSA")
	await shot("06_conta_suspensa")
	print("RESULT %s" % ("OK" if fails == 0 else "%d FALHAS" % fails))
	quit(1 if fails else 0)
