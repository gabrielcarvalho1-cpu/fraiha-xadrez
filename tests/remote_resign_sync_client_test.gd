extends SceneTree
## R53 · Bug real: Ranked celular × PC; o PC desistiu e o celular ficou preso na partida "em andamento"
## (sem vitória, relógio correndo) até sair na mão. O fim da partida tem de chegar SEMPRE ao outro jogador:
##   1. conectado: o adversário desiste → VITÓRIA na hora;
##   2. link do celular morto na hora do fim (rede trocou / tela bloqueada): o cliente percebe o link morto
##      (sem resposta do servidor), reconecta, pede a sincronia da partida e recebe o estado FINAL + VITÓRIA.
## Também confere: relógio parado, tabuleiro bloqueado, resultado por cima do painel AÇÕES aberto.
## Rodar com o servidor de teste + adversário automático (ver tests/run_remote_resign_sync.sh).
var failures := 0
var stage
var shown: Array = []

func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _initialize(): call_deferred("run")

func wait_until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call(): return true
		await process_frame
	return cond.call()

func _watch():
	var was := false
	while true:
		await process_frame
		if stage == null or stage.result_overlay == null: continue
		var now: bool = stage.result_overlay.is_showing()
		if now and not was: shown.append({"result": String(stage.result_overlay.result), "match": String(stage.ranked.match_id)})
		was = now

func queue():
	await wait_until(func(): return stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false) != null, 6.0)
	stage.ranked_ui.box.find_child("Queue_ranked_3min", true, false).pressed.emit()

func finish_checks(n: int, mid: String, label: String):
	var ctrl = stage.ranked
	check(await wait_until(func(): return String(ctrl.last_result.get("match_id", "")) == mid, 25.0), "%d · %s: resultado oficial chegou ao cliente" % [n, label])
	check(String(ctrl.last_result.get("outcome", "")) == "win" and String(ctrl.last_result.get("reason", "")) == "resign", "%d · VITÓRIA por desistência (%s/%s)" % [n, ctrl.last_result.get("outcome", "-"), ctrl.last_result.get("reason", "-")])
	check(ctrl.status == "finished" and stage.game.game_over and not ctrl.can_interact(), "%d · partida encerrada: tabuleiro bloqueado" % n)
	check(await wait_until(func(): return shown.size() > 0 and shown[-1].match == mid and shown[-1].result == "victory", 3.0), "%d · tela de VITÓRIA aparece" % n)
	var a := int(ctrl.clock.remaining_ms(ctrl.human_color)) if ctrl.clock.has_method("remaining_ms") else -1
	for i in 40: await process_frame
	var b := int(ctrl.clock.remaining_ms(ctrl.human_color)) if ctrl.clock.has_method("remaining_ms") else -1
	check(a == b, "%d · relógio parado (%d → %d)" % [n, a, b])

func run():
	var args := OS.get_cmdline_user_args()
	var size := Vector2i(390, 844)
	var i := args.find("--size")
	if i >= 0:
		var p := args[i + 1].split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	root.size = size
	root.content_scale_size = size
	stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	for k in 8: await process_frame
	stage.account_ui.hide_ui()
	_watch()
	var acc = stage.account
	var nick := "Cel%d" % (Time.get_ticks_msec() % 100000)
	acc.access_token = "dev:" + nick
	acc.user_id = "pending"
	acc._server_auth()
	check(await wait_until(func(): return acc.server_ready, 8.0), "conta conectada")
	if acc.needs_nickname: acc.create_profile(nick)
	check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
	stage._open_ranked()
	# ---- 1 · conectado: o adversário (PC) desiste
	await queue()
	check(await wait_until(func(): return stage.mode == "ranked" and stage.ranked.status == "playing", 40.0), "1 · partida começou")
	var mid := String(stage.ranked.match_id)
	var hud = stage.get("mobile_hud")
	if "--actions-open" in args and hud != null and hud.on:
		hud.open()
		await process_frame
		check(hud.is_open(), "1 · painel AÇÕES aberto quando o adversário desiste")
	await finish_checks(1, mid, "conectado")
	if "--actions-open" in args and hud != null:
		check(not hud.is_open(), "1 · painel AÇÕES fechou: o resultado tem prioridade")
	stage.result_overlay.hide_result()
	await wait_until(func(): return not stage.result_overlay.visible, 3.0)
	var back: Button = null
	for b in stage.ranked_ui.box.find_children("*", "Button", true, false):
		if String(b.text).strip_edges() == "VOLTAR AO RANKED": back = b
	if back: back.pressed.emit()
	# ---- 2 · link do cliente morto na hora do fim
	await queue()
	check(await wait_until(func(): return stage.mode == "ranked" and stage.ranked.status == "playing", 40.0), "2 · partida começou")
	mid = String(stage.ranked.match_id)
	if "rx_at" in acc:
		acc.rx_at = Time.get_ticks_msec() - 60000      # nada chega do servidor há 1 min: link morto
		await wait_until(func(): return acc.socket == null, 2.0)
		check(acc.socket == null and not acc.server_ready, "2 · cliente percebe o link morto sozinho (sem resposta do servidor)")
	else:
		acc.socket.close()                              # código antigo (sem vigia do link): queda comum
		await wait_until(func(): return acc.socket == null, 3.0)
	acc.retry_in = 4.5                                   # fica fora enquanto o adversário desiste (≈2 s) e o resultado é gravado
	check(stage.ranked.in_match(), "2 · ainda na partida enquanto está sem conexão")
	await finish_checks(2, mid, "reconectado depois do fim")
	print("RESULT ", "OK" if failures == 0 else "FALHAS=%d" % failures)
	quit(0 if failures == 0 else 1)
