extends SceneTree
## R171 · SEC-004 (cliente): o pedido de análise diz QUAL partida (match_id + modo) para o servidor ligar a liberação a ela.
var checks := 0
var failures := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

class FakeAccount extends Node:
	signal server_message(msg)
	signal changed
	var server_ready := true
	var sent: Array = []
	func has_profile() -> bool: return true
	func send_server(m: Dictionary) -> bool:
		sent.append(m)
		return true

func _initialize():
	var Access = load("res://analysis/analysis_access.gd")
	var acc := FakeAccount.new()
	root.add_child(acc)
	var a = Access.new()
	root.add_child(a)
	a.setup(acc, null)
	a.request({"match_id": "abc-123", "mode": "casual"})
	var m: Dictionary = acc.sent.back() if acc.sent.size() > 0 else {}
	check(String(m.get("type", "")) == "analysis_request", "pede analysis_request ao servidor")
	check(String(m.get("match_id", "")) == "abc-123" and String(m.get("mode", "")) == "casual", "leva match_id e modo da partida")
	var t = Access.new("train")
	root.add_child(t)
	t.setup(acc, null)
	t.request()
	var m2: Dictionary = acc.sent.back()
	check(String(m2.get("type", "")) == "train_request" and not m2.has("match_id"), "treino continua igual (sem partida)")
	var src := FileAccess.get_file_as_string("res://analysis/analysis_ui.gd")
	check(src.contains("access.request({\"match_id\": String(record.match_id), \"mode\": String(record.mode)})"), "tela de análise manda a partida analisada")
	print("RESULT %s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures > 0 else 0)
