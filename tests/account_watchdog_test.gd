extends SceneTree
## Android 02 · prova que um WebSocket aberto e sem respostas é abandonado pelo watchdog.

const AccountService = preload("res://account/account_service.gd")
var failures := 0
var service
var link_lost_count := 0

func check(ok: bool, label: String):
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1

func _initialize():
	call_deferred("run")

func wait_until(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await process_frame
	return condition.call()

func run():
	service = AccountService.new()
	root.add_child(service)
	service.server_message.connect(func(msg):
		if String(msg.get("type", "")) == "link_lost": link_lost_count += 1)
	service.access_token = "local-test-token"
	service.user_id = "local-test-user"
	service.server_url = OS.get_environment("FRAIHA_SERVER_URL")
	service._connect()
	check(await wait_until(func(): return service.socket_open, 3000), "WebSocket local silencioso abre")
	service.rx_at = Time.get_ticks_msec() - AccountService.LINK_DEAD_MS - 1
	check(await wait_until(func(): return link_lost_count == 1, 1000), "watchdog emite link_lost sem resposta")
	check(service.socket == null and not service.socket_open and service.retry_in > 0.0,
		"watchdog abandona o socket e agenda reconexão")
	print("account_watchdog_test: 3 checks, %d failures" % failures)
	quit(0 if failures == 0 else 1)
