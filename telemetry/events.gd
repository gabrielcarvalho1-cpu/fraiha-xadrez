extends RefCounted
## R181 · eventos de PRODUTO para a linha do tempo do Admin (Sessões): bot oferecido na fila, aceitou/recusou,
## 1º desafio, próximo desafio depois de vencer, resultado contra bot. Só nomes que o servidor conhece
## (online_v021/admin/sessions.js · UI_EVENTS); nada de dado pessoal.

static func send(account, name: String, extra := {}) -> void:
	if account == null or not account.has_method("send_server"): return
	var m := {"type": "ui_event", "name": name}
	m.merge(extra)
	account.send_server(m)
