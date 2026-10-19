extends SceneTree
## R151 · trocar o NOME PÚBLICO: botão TROCAR NOME (no celular embaixo do campo), confirmação com as regras
## (3 a 20 caracteres, troca a cada 30 dias) e a frase de regras fora da tela. Sem servidor: respostas simuladas.
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
func run():
	var sz := OS.get_environment("SHOT_SIZE")
	if sz != "":
		var p := sz.split("x")
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(int(p[0]), int(p[1])); root.content_scale_size = root.size
		await process_frame
	OS.set_environment("FRAIHA_SERVER_URL", "")
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	var acc = stage.account
	var sent: Array = []
	acc.user_id = "u1"; acc.access_token = "t"; acc.server_ready = true
	acc.profile = {"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior"}
	acc.send_hook = func(m): sent.append(m)
	acc.changed.emit()
	await frames(4)
	hub.show_page("profile")
	await frames(10)
	var mobile: bool = "--mobile-test" in OS.get_cmdline_user_args()
	var eds: Array = root.find_children("NicknameEditor", "", true, false).filter(func(n): return n.is_visible_in_tree())
	check(eds.size() == 1, "editor do nome visível na página do Perfil")
	if eds.is_empty():
		print("FAILS ", failures); quit(1); return
	var ed = eds[0]
	check(not ed.hint.visible, "a frase de regras embaixo do campo saiu")
	var btn: Button = ed.save_button
	check(btn != null and btn.is_visible_in_tree() and btn.text == "TROCAR NOME", "botão TROCAR NOME aparece")
	if mobile: check(btn.name == "NicknameSaveMobile" and btn.get_global_rect().position.y > ed.input.get_global_rect().end.y, "celular: botão embaixo do campo")
	var sc = btn.get_parent()
	while sc != null and not (sc is ScrollContainer): sc = sc.get_parent()
	if sc != null:
		await frames(2)
		sc.ensure_control_visible(btn)
		await frames(4)
	await shot("perfil_nome")
	# nome igual: o botão explica
	if mobile:
		btn.pressed.emit()
		await frames(2)
		check(ed.status.text.contains("nome novo"), "tocar sem mudar o nome: pede o nome novo")
	# digita um nome novo → servidor diz disponível
	ed.input.text = "Gabriel_Novo"
	ed.input.text_changed.emit("Gabriel_Novo")
	ed._on_checked("Gabriel_Novo", true, "")
	await frames(2)
	check(not btn.disabled, "nome disponível: TROCAR NOME ativo")
	btn.pressed.emit()
	await frames(4)
	var nm = hub.notice_modal
	check(is_instance_valid(nm) and nm.visible and String(nm.text_label.text).contains("Gabriel_Novo") and String(nm.text_label.text).contains("30 dias") and String(nm.text_label.text).contains("3 a 20"), "confirmação com o nome novo e as regras (3 a 20 · 30 dias)")
	check(not sent.any(func(m): return String(m.get("type", "")) == "acct_change_nickname"), "nada é trocado antes de confirmar")
	await shot("perfil_nome_confirmar")
	nm.yes_button.pressed.emit()
	await frames(2)
	check(sent.any(func(m): return String(m.get("type", "")) == "acct_change_nickname" and String(m.get("nickname", "")) == "Gabriel_Novo"), "CONFIRMAR troca o nome no servidor")
	# CANCELAR não troca
	sent.clear()
	ed._on_checked("Gabriel_Novo", true, "")
	btn.pressed.emit()
	await frames(3)
	nm.ok_button.pressed.emit()
	await frames(2)
	check(not sent.any(func(m): return String(m.get("type", "")) == "acct_change_nickname"), "CANCELAR não troca")
	print("FAILS ", failures)
	quit(1 if failures else 0)
