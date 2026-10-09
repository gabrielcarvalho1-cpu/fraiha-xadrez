extends SceneTree
## R55 · Painel de PERFIL da Home (PC) com STATUS editável. Confere: frase padrão sem status; status da
## conta no painel (acct_state, como ao recarregar / outro aparelho); lápis abre o editor; SALVAR manda ao
## servidor; resposta do servidor atualiza o painel e fecha; erro aparece no editor; convidado não salva;
## texto longo nunca passa de 2 linhas. A persistência no servidor é coberta por tests/server/profile_status_test.cjs.
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/home_status_test.gd
var failures := 0

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize(): call_deferred("run")

func frames(n := 6):
	for i in n: await process_frame

func run():
	root.size = Vector2i(1920, 1080)
	OS.set_environment("FRAIHA_SERVER_URL", "")
	await process_frame
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	var acc = stage.account
	check(hub.ref_mode and hub.ref_status_label.text == hub.STATUS_DEFAULT and hub.ref_status_author.visible, "sem status: frase padrão + autor")
	check(hub.ref_profile.button.get_node("RefProfileFrame") != null and hub.ref_badge.visible and hub.ref_badge.texture != null, "moldura nova e insígnia da liga (Madeira inclusive)")
	# convidado: o editor abre mas não salva
	hub.open_status_editor()
	await frames(2)
	check(hub.status_editor.visible and hub.status_save.disabled and not hub.status_input.editable and "Entre" in hub.status_note.text, "convidado: precisa entrar na conta para salvar")
	hub.close_status_editor()
	# conta com status (acct_state = recarregar a página / outro aparelho)
	acc.access_token = "t"; acc.user_id = "u1"     # já logado (o acct_state chega depois do login)
	acc._receive({"type": "acct_state", "user_id": "u1", "profile": {"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior", "status": "Rumo ao Diamante!"}, "ranked": {}})
	await frames(3)
	check(hub.ref_status_label.text == "“Rumo ao Diamante!”" and not hub.ref_status_author.visible, "status da conta aparece no painel")
	# lápis -> editor -> SALVAR (sem conexão: avisa)
	hub.ref_status_edit.pressed.emit()
	await frames(2)
	check(hub.status_editor.visible and hub.status_input.text == "Rumo ao Diamante!" and hub.status_input.editable, "lápis abre o editor com o status atual")
	check(hub.status_input.max_length == 80 and hub.status_count.text == "17 / 80", "limite de 80 e contador")
	hub.status_input.text = "  Foco   total\tno Ranked  "
	hub.save_status()
	check("conexão" in hub.status_note.text, "sem servidor: o editor avisa e não fecha")
	check(acc.clean_status("  Foco   total\tno Ranked  ") == "Foco total no Ranked", "limpeza igual à do servidor")
	# resposta do servidor: salvo
	acc._receive({"type": "acct_status_saved", "status": "Foco total no Ranked"})
	await frames(2)
	check(not hub.status_editor.visible and hub.ref_status_label.text == "“Foco total no Ranked”" and acc.profile_status() == "Foco total no Ranked", "salvo: painel atualizado e editor fechado")
	# erro do servidor aparece no editor
	hub.open_status_editor()
	acc._receive({"type": "acct_status_error", "code": "rate_limited", "message": "Aguarde um instante."})
	await frames(2)
	check(hub.status_editor.visible and hub.status_note.text == "Aguarde um instante.", "erro do servidor aparece no editor")
	hub.close_status_editor()
	# texto longo: no máximo 2 linhas, nunca estoura
	acc.profile.status = "W".repeat(80)
	hub.refresh_profile_status()
	var lines: PackedStringArray = hub.ref_status_label.text.split("\n")
	var f: Font = hub.PROFILE_STATUS_FONT
	var fs: int = hub.ref_status_label.get_theme_font_size("font_size")
	var widest := 0.0
	for l in lines: widest = maxf(widest, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	check(lines.size() <= 2 and widest <= hub.PROFILE_STATUS.size.x, "status de 80 letras sem espaço: 2 linhas, cabe no painel")
	# apagar o status volta ao padrão
	acc._receive({"type": "acct_status_saved", "status": ""})
	await frames(2)
	check(hub.ref_status_label.text == hub.STATUS_DEFAULT, "status vazio: volta a frase padrão")
	# outras páginas fecham o editor
	hub.open_status_editor()
	hub.show_page("profile")
	await frames(2)
	check(not hub.status_editor.visible, "abrir outra página fecha o editor")
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
