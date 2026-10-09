extends SceneTree
## Android 02 · lifecycle sem rede externa: token, ressincronização e safe area no resume.

const AccountService = preload("res://account/account_service.gd")
const RankedController = preload("res://ranked/ranked_controller.gd")
const MobileLayout = preload("res://ui_v022/mobile_layout.gd")

var failures := 0
var checks := 0

class ResumeAccount extends "res://account/account_service.gd":
	var refresh_calls := 0
	func _refresh_session():
		if refresh_busy: return
		refresh_busy = true
		refresh_calls += 1

class FakeAccount extends Node:
	signal server_message(msg: Dictionary)
	signal changed
	var server_ready := false
	var sent: Array[Dictionary] = []
	func online_ready() -> bool: return server_ready
	func send_server(msg: Dictionary) -> bool:
		sent.append(msg.duplicate(true))
		return true

class FakeGame extends Node:
	var game_over := false
	var status := ""
	func queue_redraw(): pass

func check(ok: bool, label: String):
	checks += 1
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1

func _initialize():
	call_deferred("run")

func run():
	check(AccountService.session_refresh_due(1000.0, 1100.0), "token a menos de 120 s do vencimento exige refresh")
	check(not AccountService.session_refresh_due(1000.0, 1300.0), "token ainda válido não exige refresh antecipado")

	var resumed := ResumeAccount.new()
	root.add_child(resumed)
	resumed.access_token = "access"
	resumed.refresh_token = "refresh"
	resumed.user_id = "user"
	resumed.expires_at = Time.get_unix_time_from_system() - 1.0
	resumed._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	resumed._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(resumed.refresh_calls == 1, "resume renova token vencido uma vez, mesmo seguido por foco")
	resumed.queue_free()

	var account := FakeAccount.new()
	var game := FakeGame.new()
	var controller = RankedController.new()
	root.add_child(account)
	root.add_child(game)
	root.add_child(controller)
	controller.setup(account, game)
	controller.kind = "ranked"
	controller.match_id = "match-android-02"
	controller.mode = "ranked_3min"
	controller.mode_name = "3 MIN"
	controller.status = "playing"
	controller.active = true
	account.server_message.emit({"type": "link_lost"})
	check(controller.resync_pending, "queda durante partida agenda ressincronização")
	account.server_ready = true
	account.changed.emit()
	check(account.sent.size() == 1 and account.sent[0].get("type") == "ranked_sync" and account.sent[0].get("match_id") == controller.match_id,
		"reconexão envia ranked_sync da partida atual")
	account.server_message.emit({"type": "ranked_idle", "match_id": controller.match_id})
	check(controller.status == "finished" and game.game_over, "servidor sem a partida encerra o estado local preso")
	controller.queue_free()
	account.queue_free()
	game.queue_free()

	var layout = MobileLayout.new()
	root.add_child(layout)
	await process_frame
	MobileLayout._insets_dirty = false
	layout._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(MobileLayout._insets_dirty and bool(layout.get("_resize_pending")), "resume invalida safe area e agenda resize")
	layout.queue_free()

	print("android_lifecycle_test: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
