extends Node
## R189 · TESTE AUTOMÁTICO DO APP no iPhone virtual (Codemagic), onde ninguém toca na tela.
## Só existe quando o app abre com "-- --fx-teste-modos" (stage.gd); fora disso este nó nem é criado.
## Roteiro: entra como convidado → Home → xadrez contra o computador → MARCHA REAL (partida jogando sozinha)
## → XEQUE (partida jogando sozinha) → Online Casual (conexão com o servidor de staging) → Home.
## Tira os prints pelo próprio jogo (user://teste/NN_nome.jpg) e escreve um diário curto (user://teste/diario.txt)
## só com passos, tempos e estados (nada digitado, nenhum dado pessoal). No fim escreve "FIM" no diário.

const DIR := "user://teste"
var stage
var _t0 := 0
var _n := 0

func _ready():
	_t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + "/diario.txt", FileAccess.WRITE)
	if f != null: f.close()
	_run.call_deferred()

func note(s: String) -> void:
	var f := FileAccess.open(DIR + "/diario.txt", FileAccess.READ_WRITE)
	if f == null: return
	f.seek_end()
	f.store_line("[%5.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, s])
	f.close()

func wait_s(s: float) -> void:
	await get_tree().create_timer(s).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null: return
	var w := 360
	img.resize(w, int(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_BILINEAR)
	_n += 1
	img.save_jpg(DIR + "/%02d_%s.jpg" % [_n, name], 0.6)
	note("print %s · tela=%s" % [name, String(stage.mode)])

func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		if cond.call(): return true
		await wait_s(0.5)
		t += 0.5
	return false

func _run() -> void:
	note("inicio · plataforma=%s · servidor=%s" % [OS.get_name(), "sim" if preload("res://online_v020/endpoint.gd").server_url() != "" else "nao"])
	# 1) Home (o convidado entra sozinho pela tela de login)
	var home := await _until(func(): return stage.mode == "home" and not stage.account_ui.is_open(), 60.0)
	if not home and stage.account_ui.is_open():
		note("login ainda aberto: entrando como convidado")
		stage.account_ui.play_as_guest()
		home = await _until(func(): return stage.mode == "home" and not stage.account_ui.is_open(), 20.0)
	note("home=%s" % home)
	await wait_s(3.0)
	await shot("home")

	# 2) Xadrez contra o computador (o computador joga de brancas e começa)
	stage._start_bot("easy", "b")
	note("xadrez bot: modo=%s" % stage.mode)
	await wait_s(2.0)
	await shot("xadrez_inicio")
	await wait_s(8.0)
	await shot("xadrez_computador_jogou")
	stage.open_home()
	await wait_s(2.0)

	# 3) MARCHA REAL: pula o tutorial, começa e joga sozinha
	await stage.hub.open_marcha()
	var m = stage.hub.marcha
	note("marcha aberta=%s" % (m != null))
	if m != null:
		var guard := 0
		while m.tut_page >= 0 and guard < 15:
			m._on_hit("tut_next")
			guard += 1
			await wait_s(0.2)
		await wait_s(1.0)
		await shot("marcha_salao")
		await m.start_game()
		await wait_s(5.0)
		await shot("marcha_partida")
		var t := 0.0
		while t < 25.0 and m.mode == "game":
			if m.g != null and m.awaiting_play() and m.g.turn == 0: m._auto_play()
			await wait_s(0.5)
			t += 0.5
		note("marcha depois de 25s: modo=%s" % m.mode)
		await shot("marcha_jogando")
		m.close()
		await wait_s(2.0)

	# 4) XEQUE: começa e joga sozinha
	await stage.hub.open_xeque()
	var x = stage.hub.xeque
	note("xeque aberto=%s" % (x != null))
	if x != null:
		await wait_s(1.0)
		await shot("xeque_como_jogar")
		x._on_hit("tut_bots")   # CONTRA BOTS (o "Jogar" abre a escolha bots × online)
		await wait_s(6.0)
		await shot("xeque_partida")
		var t2 := 0.0
		while t2 < 25.0 and x.mode == "game":
			if x.phase != "": x.skip_presentation()
			elif x.g != null and x.g.state == x.Rules.TURN_WAITING and x.g.turn == 0:
				x.toggle_card(0)
				x.human_play()
			await wait_s(0.5)
			t2 += 0.5
		note("xeque depois de 25s: modo=%s" % x.mode)
		await shot("xeque_jogando")
		x.close()
		await wait_s(2.0)

	# 5) Online Casual: só a conexão com o servidor (não entra na fila)
	stage._open_casual()
	await _until(func(): return stage.account.online_ready(), 20.0)
	await wait_s(3.0)
	note("online: identidade_pronta=%s modo=%s" % [stage.account.online_ready(), stage.mode])
	await shot("online_casual")
	stage.open_home()
	await wait_s(2.0)
	await shot("home_final")
	note("FIM")
