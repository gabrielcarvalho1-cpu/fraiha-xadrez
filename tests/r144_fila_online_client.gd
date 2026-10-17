extends SceneTree
## R144 · fila online de verdade: cliente Godot + servidor local + 3 jogadores automáticos (queue_peers.cjs).
## XEQUE → JOGAR AGORA → JOGAR ONLINE → busca → mesa de 4 pessoas abre sozinha. Uso: tests/run_fila_online.sh
var failures := 0
func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _initialize(): call_deferred("run")
func wait_until(cond: Callable, seconds: float) -> bool:
	var end = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call(): return true
		await process_frame
	return cond.call()
func run():
	var stage = load("res://presentation_v019/stage.tscn").instantiate()
	root.add_child(stage)
	for k in range(3): await process_frame
	stage.account_ui.hide_ui()
	var acc = stage.account
	acc.access_token = "dev:GodotFila"
	acc.user_id = "pending"
	acc._server_auth()
	check(await wait_until(func(): return acc.server_ready, 8.0), "conectado com conta")
	if acc.needs_nickname: acc.create_profile("GodotFila")
	check(await wait_until(func(): return acc.has_profile(), 6.0), "perfil pronto")
	await stage.hub.open_xeque()
	for k in range(6): await process_frame
	var x = stage.hub.xeque
	x._on_hit("tut_play")
	var po = stage.party_online
	check(await wait_until(func(): return po.is_open() and po.screen == "choose", 3.0), "JOGAR AGORA → escolha")
	po._choose_online()
	check(await wait_until(func(): return po.screen == "search", 3.0), "JOGAR ONLINE → procurando jogadores")
	check(await wait_until(func(): return po.waiting >= 2, 15.0), "a contagem da fila sobe quando outros entram (%d)" % po.waiting)
	check(await wait_until(func(): return x.online and x.mode == "game", 20.0), "mesa encontrada: XEQUE online abre sozinho")
	check(not po.is_open(), "a busca fecha quando a mesa abre")
	var humans: int = x.players.filter(func(p): return not bool(p.get("bot", false))).size() if x.players is Array else -1
	check(humans == 4, "mesa de 4 pessoas (%d)" % humans)
	print("RESULT ", "OK" if failures == 0 else "FALHOU")
	quit()
