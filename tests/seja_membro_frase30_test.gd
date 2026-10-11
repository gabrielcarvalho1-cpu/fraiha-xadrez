extends SceneTree
## R63 · SEJA MEMBRO + FRASE DO PERFIL (30).
## Botão do topo da Home: texto "SEJA MEMBRO" e abre a página geral FRAIHA PREMIUM (Fundador e Club), não o Club
## direto; Fundador e Club abrem a partir dela e o VOLTAR volta para ela; VOLTAR na geral fecha.
## Frase do perfil (só na Home do PC): campo limita a 30, contador "/30", não salva acima de 30, frase antiga
## longa aparece inteira (sem corte silencioso) e só pode encolher.
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/seja_membro_frase30_test.gd -- [--mobile-test --size 390x844] [--shots <pasta>]
var failures := 0
var shots := ""
var tag := ""

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func frames(n := 3):
	for i in n: await process_frame

func shot(name: String):
	if shots.is_empty(): return
	await frames(4)
	var img := root.get_texture().get_image()
	img.save_png(shots.path_join("%s_%s.png" % [tag, name]))

## toque/clique de verdade no centro do controle
func tap(c: Control, mobile: bool):
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		if mobile:
			var e := InputEventScreenTouch.new()
			e.index = 0; e.position = p; e.pressed = down
			Input.parse_input_event(e)
		else:
			var m := InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTON_LEFT; m.position = p; m.global_position = p; m.pressed = down
			Input.parse_input_event(m)
		await frames(2)

func cta(prem, label: String) -> Button:
	for b in prem.find_children("*", "Button", true, false):
		if b.text == label and b.is_visible_in_tree(): return b
	return null

func type_text(le: LineEdit, s: String):
	for ch in s: le.insert_text_at_caret(ch)

func run():
	var args := OS.get_cmdline_user_args()
	var mobile := "--mobile-test" in args
	var size := Vector2i(1920, 1080)
	var i := args.find("--size")
	if i >= 0 and i + 1 < args.size():
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	elif mobile: size = Vector2i(390, 844)
	i = args.find("--shots")
	if i >= 0 and i + 1 < args.size(): shots = args[i + 1]
	tag = ("mobile_%dx%d" % [size.x, size.y]) if mobile else "pc"
	OS.set_environment("FRAIHA_SERVER_URL", "")
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = size
	await process_frame
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(20)
	if stage.account_ui.is_open(): stage.account_ui.hide_ui()
	var hub = stage.hub
	hub.monetization_state.mock_reset()
	await frames(4)

	# ---------- 1/2 · SEJA MEMBRO → FRAIHA PREMIUM ----------
	var entry: Control = null
	for n in ["ClubHomeEntryMobile", "ClubHomeEntry"]:
		for c in hub.find_children(n, "", true, false):
			if c.is_visible_in_tree(): entry = c
		if entry != null: break
	check(entry != null and entry.text == "SEJA MEMBRO" and not entry.active, "[%s] botão do topo: 'SEJA MEMBRO'" % tag)
	check(entry != null and root.get_visible_rect().grow(1).encloses(entry.get_global_rect()), "[%s] botão inteiro na tela" % tag)
	await shot("1_home")
	if entry == null:
		print("RESULT FALHAS=%d" % failures); quit(1); return
	await tap(entry, mobile)
	await frames(4)
	var prem = hub.premium
	check(prem != null and prem.visible and prem.page == "hub", "[%s] SEJA MEMBRO abre FRAIHA PREMIUM (geral)" % tag)
	var bf := cta(prem, "CONHECER PACOTE FUNDADOR") if prem != null else null
	var bc := cta(prem, "CONHECER CLUB FRAIHA") if prem != null else null
	check(bf != null and bc != null, "[%s] FRAIHA PREMIUM mostra Fundador e Club" % tag)
	await shot("2_premium")
	if bf != null:
		bf.pressed.emit(); await frames(4)
		check(prem.page == "founder" and prem.visible, "[%s] Fundador abre os detalhes do Pacote Fundador" % tag)
		await shot("3_fundador")
		prem.back_button.pressed.emit(); await frames(4)
		check(prem.visible and prem.page == "hub", "[%s] VOLTAR do Fundador volta para FRAIHA PREMIUM" % tag)
	bc = cta(prem, "CONHECER CLUB FRAIHA")
	if bc != null:
		prem.scroll.ensure_control_visible(bc); await frames(2)
		bc.pressed.emit(); await frames(4)
		check(prem.page == "club" and prem.visible, "[%s] Club FRAIHA abre os detalhes do Club" % tag)
		await shot("4_club")
		prem.back_button.pressed.emit(); await frames(4)
		check(prem.visible and prem.page == "hub", "[%s] VOLTAR do Club volta para FRAIHA PREMIUM" % tag)
	prem.back_button.pressed.emit(); await frames(4)
	check(not prem.visible, "[%s] VOLTAR na FRAIHA PREMIUM fecha e volta à Home" % tag)
	# Club ativo: continua 'CLUB ATIVO' e abre a mesma página geral
	hub.monetization_state.mock_activate_club(); await frames(4)
	check(entry.active and entry.text == "CLUB ATIVO", "[%s] Club ativo: 'CLUB ATIVO'" % tag)
	await tap(entry, mobile); await frames(4)
	check(prem.visible and prem.page == "hub", "[%s] Club ativo: abre FRAIHA PREMIUM" % tag)
	prem.close()
	hub.monetization_state.mock_reset(); await frames(3)

	# ---------- 3 · FRASE DO PERFIL (editor só existe na Home do PC) ----------
	if not mobile:
		var acc = stage.account
		check(acc.STATUS_MAX == 30, "STATUS_MAX = 30")
		acc.access_token = "t"; acc.user_id = "u1"
		acc._receive({"type": "acct_state", "user_id": "u1", "profile": {"user_id": "u1", "nickname": "SextoSentro", "avatar_id": "warrior", "status": ""}, "ranked": {}})
		await frames(3)
		var too_long := []
		acc.status_failed.connect(func(code, _m): if code == "status_too_long": too_long.append(code))
		for n in [29, 30, 31]:
			hub.open_status_editor(); await frames(2)
			var le: LineEdit = hub.status_input
			le.text = ""
			le.grab_focus()
			type_text(le, "a".repeat(n))
			hub._status_count(); await frames(1)
			var want := mini(n, 30)
			check(le.text.length() == want and hub.status_count.text == "%d / 30" % want and not hub.status_save.disabled,
				"digitar %d: campo fica com %d, contador '%s'" % [n, want, hub.status_count.text])
			if n == 30: await shot("5_frase30")
			hub.close_status_editor()
		too_long.clear()
		check(not acc.set_status("b".repeat(31)) and too_long.size() == 1, "salvar 31 é recusado (status_too_long)")
		too_long.clear()
		acc.set_status("c".repeat(30))
		check(too_long.is_empty(), "salvar 30 passa na validação")
		# salvar e reabrir (resposta do servidor = como ao recarregar)
		var s30 := "Rumo ao Diamante com foco 2026"
		check(s30.length() == 30, "frase de teste tem 30")
		acc._receive({"type": "acct_status_saved", "status": s30}); await frames(2)
		check(hub.ref_status_label.text.replace("\n", " ") == "“%s”" % s30, "frase de 30 aparece inteira no painel")
		hub.open_status_editor(); await frames(2)
		check(hub.status_input.text == s30 and hub.status_count.text == "30 / 30", "reabrir: editor com a frase salva (30 / 30)")
		hub.close_status_editor()
		# frase antiga (até 80, salva antes do R63): sem corte silencioso
		var old := "Frase antiga salva antes do limite novo, com cinquenta"
		acc._receive({"type": "acct_status_saved", "status": old}); await frames(2)
		check(acc.profile_status() == old and "antiga" in hub.ref_status_label.text, "frase antiga longa continua salva e aparece no painel")
		hub.open_status_editor(); await frames(2)
		var le2: LineEdit = hub.status_input
		check(le2.text == old and hub.status_save.disabled and "encurte" in hub.status_note.text and hub.status_count.text == "%d / 30" % old.length(),
			"editor: frase antiga inteira, SALVAR bloqueado, aviso para encurtar")
		await shot("6_frase_antiga")
		le2.caret_column = le2.text.length()
		le2.insert_text_at_caret("x"); await frames(1)
		check(le2.text == old, "frase antiga: não deixa crescer")
		le2.text = old.substr(0, 30); hub._status_count(); await frames(1)
		check(not hub.status_save.disabled and hub.status_note.text == "" and le2.max_length == 30, "encurtada para 30: SALVAR liberado, limite volta a 30")
		le2.insert_text_at_caret("y"); await frames(1)
		check(le2.text.length() == 30, "depois de encurtar: não passa de 30")
		hub.close_status_editor()
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
