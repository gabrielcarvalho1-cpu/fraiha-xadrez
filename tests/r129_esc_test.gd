extends SceneTree
## R129 · ESC EM TUDO (PC): cada janela aberta fecha com ESC (só a de cima); sem janela, o ESC faz o de sempre.
## Tecla de verdade (Input.parse_input_event), como o jogador aperta.
## Uso: xvfb-run godot --rendering-driver opengl3 --path . -s tests/r129_esc_test.gd
const EscStack = preload("res://ui_v022/esc_stack.gd")
var failures := 0
var checks := 0
var stage
var hub
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func frames(n := 3):
	for i in n: await process_frame
func esc():
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE; e.physical_keycode = KEY_ESCAPE; e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var u := InputEventKey.new()
	u.keycode = KEY_ESCAPE; u.physical_keycode = KEY_ESCAPE; u.pressed = false
	Input.parse_input_event(u)
	await frames(6)
func _initialize(): call_deferred("run")
func run():
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	await frames(25)
	if stage.account_ui.is_open(): stage.account_ui.close()
	await frames(3)
	hub = stage.hub
	var acc_ui = stage.account_ui
	# ---- conta (o print do dono: SUA CONTA não fechava)
	acc_ui.open("login"); await frames(3)
	await esc()
	check(not acc_ui.is_open(), "Entrar no FRAIHA: ESC fecha (= Jogar como convidado)")
	acc_ui.open("signup"); await frames(3)
	await esc()
	check(acc_ui.is_open() and acc_ui.page == "login", "Criar conta: ESC volta para Entrar")
	await esc()
	check(not acc_ui.is_open(), "…e outro ESC fecha")
	acc_ui._show("account"); acc_ui.dim.show(); acc_ui.scroll.show(); await frames(3)
	await esc()
	check(not acc_ui.is_open(), "SUA CONTA: ESC fecha (= CONTINUAR)")
	# ---- painéis da Home
	hub.show_notice("AVISO", "Teste do ESC."); await frames(4)
	await esc()
	check(not hub.notice_modal.is_open(), "aviso: ESC fecha")
	hub.ask("COMUNIDADE", "Abrir o Discord?", "ABRIR DISCORD", "AGORA NÃO", func(): check(false, "ESC NÃO pode confirmar a pergunta")); await frames(4)
	await esc()
	check(not hub.notice_modal.is_open(), "pergunta (Discord): ESC = AGORA NÃO")
	hub.open_legal(); await frames(4)
	await esc()
	check(not hub.legal_ui.is_open(), "Termos e privacidade: ESC fecha")
	hub.open_leaderboard(); await frames(4)
	await esc()
	check(not hub.leaderboard_ui.is_open(), "Ranking: ESC fecha")
	hub.open_global_chat(); await frames(4)
	await esc()
	check(not hub.global_chat_ui.is_open(), "Chat geral: ESC fecha")
	hub.open_home_volume(null); await frames(4)
	var vol = EscStack.top(self)
	check(vol != null and String(vol.get_script().resource_path).ends_with("volume_popover.gd"), "volume aberto")
	await esc()
	check(EscStack.top(self) == null, "volume: ESC fecha")
	# ---- FRAIHA PREMIUM: detalhe → geral → fecha; aviso por cima fecha só o aviso
	hub.open_premium("founder"); await frames(6)
	await esc()
	check(hub.premium.visible and hub.premium.page == "hub", "Premium (Fundador): ESC volta para a página geral")
	hub.show_notice("AVISO", "Por cima do Premium."); await frames(4)
	await esc()
	check(not hub.notice_modal.is_open() and hub.premium.visible, "aviso por cima do Premium: ESC fecha SÓ o aviso")
	await esc()
	check(not hub.premium.visible, "Premium: ESC fecha")
	# ---- páginas da Home (comportamento de antes continua)
	hub.show_page("ranking"); await frames(4)
	await esc()
	check(hub.page == "main", "Sistema de Ligas: ESC volta para a Home (%s)" % hub.page)
	# ---- partida contra o bot: animação → painel → início
	stage._start_bot("bronze", "w")
	stage.bot_controller.stop()
	await frames(6)
	stage._on_match_finished({"human_color": "w", "result": "loss", "mode": "bot", "result_reason": "MATE", "start_fen": "", "moves": PackedStringArray(["f2f3", "e7e5", "g2g4", "d8h4"])})
	await frames(10)
	check(stage.result_overlay.is_showing(), "derrota: animação na tela")
	await esc()
	for i in 60:
		if stage.reward_modal.is_open(): break
		await process_frame
	check(not stage.result_overlay.is_showing() and stage.reward_modal.is_open(), "ESC pula a animação → painel de DERROTA")
	await esc()
	await frames(6)
	check(not stage.reward_modal.is_open() and stage.mode == "home", "painel de DERROTA: ESC = VOLTAR PARA O INÍCIO (%s)" % stage.mode)
	# ---- R132 · tela cheia: janela aberta fecha primeiro; sem nada aberto, o ESC tira a tela cheia
	var sm = stage.screen_mode
	sm.enter(); await frames(12)
	if sm.is_on():
		hub.show_notice("AVISO", "Na tela cheia."); await frames(4)
		await esc()
		check(not hub.notice_modal.is_open() and sm.is_on(), "tela cheia + aviso: ESC fecha o aviso e continua em tela cheia")
		hub.show_page("ranking"); await frames(4)
		await esc()
		check(hub.page == "main" and sm.is_on(), "tela cheia + página da Home: ESC volta para a Home primeiro")
		await esc()
		await frames(12)
		check(not sm.is_on(), "tela cheia sem nada aberto: ESC TIRA a tela cheia")
	else:
		print("PULADO: tela cheia indisponível neste ambiente")
	print("RESULT " + ("%d/%d OK" % [checks, checks] if failures == 0 else "%d FALHAS" % failures))
	quit(0 if failures == 0 else 1)
