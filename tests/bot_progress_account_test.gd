extends SceneTree
## Regressão da race "vitória contra bot vira progresso LOCAL em vez de ir ao servidor":
## o 1º acct_state emite bot_progress_changed ANTES de changed. Usa o account_service REAL;
## só o envio pelo WebSocket é capturado.
const Progress = preload("res://bot/bot_progress.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String):
    checks += 1
    if not ok: failures += 1
    print(("PASS " if ok else "FAIL ") + label)

class FakeAccount extends "res://account/account_service.gd":
    var sent: Array = []
    var send_ok := true
    func _send(msg: Dictionary) -> bool:
        sent.append(msg)
        return send_ok
    func types() -> Array:
        return sent.map(func(m): return String(m.get("type", "")))

const SCHOLAR := ["e2e4","e7e5","d1h5","b8c6","f1c4","g8f6","h5f7"]

func _initialize(): call_deferred("run")

func fresh(logged := true):
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.FILE))
    var acc := FakeAccount.new()
    acc.set_process(false)
    root.add_child(acc)
    var bp = Progress.new()
    root.add_child(bp)
    bp.setup(acc)
    if logged:
        # Identidade preenchida SEM emitir changed: o BotProgress ainda está em key="local" quando o
        # 1º acct_state chegar (pior caso da race original).
        acc.access_token = "tok"
        acc.user_id = "u-123"
        acc.socket_open = true
    var grants: Array = []
    bp.reward_unlocked.connect(func(b, _r): grants.append(b))
    return [acc, bp, grants]

## Queda do socket exatamente como o account_service faz em _process (STATE_CLOSED).
func drop(acc):
    acc.socket_open = false
    acc.server_ready = false
    acc.changed.emit()

func state(acc, bots):
    var msg := {"type": "acct_state", "user_id": "u-123", "profile": {"nickname": "Teste"}, "ranked": {}, "persistent": true}
    if bots != null: msg["bots"] = bots
    acc._receive(msg)

func run():
    # ---------- 1) a race exata ----------
    var t = fresh()
    var acc = t[0]; var bp = t[1]; var grants: Array = t[2]
    check(bp.key == "local", "BotProgress começa com key=local")
    var order: Array = []
    acc.bot_progress_changed.connect(func(_d): order.append("bot_progress_changed"))
    acc.changed.connect(func(): order.append("changed"))
    state(acc, {"available": true, "defeated": []})
    check(order.size() >= 2 and order[0] == "bot_progress_changed" and order.find("changed") > 0, "ordem real dos sinais: bot_progress_changed chega ANTES de changed")
    check(bp.key == "u-123", "o 1º acct_state basta: key = user_id")
    check(bp.server_available and bp.server_known, "o 1º acct_state basta: server_available = true")
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    var claim: Array = acc.sent.filter(func(m): return m.type == "bot_victory")
    check(claim.size() == 1 and claim[0].bot_id == "madeira" and claim[0].moves.size() == 7, "report_victory envia bot_victory ao servidor")
    check(not bp.is_defeated("madeira") and grants.is_empty() and bp.status("ferro") == "locked", "nada é concedido localmente antes da confirmação")
    acc._receive({"type": "bot_progress", "available": true, "defeated": ["madeira"], "new_bot": "madeira"})
    check(bp.is_defeated("madeira") and bp.status("ferro") == "available" and grants == ["madeira"], "confirmação do servidor: MADEIRA derrotado, FERRO liberado, recompensa 1×")
    check(bp.avatar_unlocked("mage") and not bp.avatar_unlocked("paladin"), "avatar Mago liberado pela vitória confirmada; Paladino continua bloqueado")
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    # R29: revanche também é validada pelo servidor (para abrir o painel pós-partida), mas nunca dá recompensa nova
    check(acc.sent.filter(func(m): return m.type == "bot_victory").size() == 2, "revanche é enviada ao servidor para validar")
    acc._receive({"type": "bot_progress", "available": true, "defeated": ["madeira"], "new_bot": null})
    check(grants == ["madeira"], "revanche confirmada (new_bot=null) NÃO repete a recompensa")

    # ---------- 2) acct_state SEM o campo bots (estado desconhecido): pergunta antes de decidir ----------
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, null)
    check(bp.key == "u-123" and not bp.server_known, "sem 'bots' no acct_state: estado do servidor desconhecido")
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    check(acc.types() == ["bot_progress"] and not bp.is_defeated("madeira") and grants.is_empty(), "vitória NÃO vira progresso local: consulta bot_progress uma vez")
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    check(acc.types().count("bot_progress") == 1, "sem consulta duplicada para a mesma vitória")
    acc._receive({"type": "bot_progress", "available": true, "defeated": [], "new_bot": null})
    check(acc.types().count("bot_victory") == 1 and not bp.is_defeated("madeira"), "resposta available=true → envia bot_victory (e ainda espera confirmação)")
    acc._receive({"type": "bot_progress", "available": true, "defeated": [], "new_bot": null})
    check(acc.types().count("bot_victory") == 1, "nova resposta de progresso não reenvia (sem loop)")

    # ---------- 3) servidor sem 0006 (not_configured): fallback local previsto ----------
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": false, "defeated": []})
    check(bp.server_known and not bp.server_available, "servidor informa progresso indisponível (0006 ausente)")
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    check(bp.is_defeated("madeira") and grants == ["madeira"] and acc.types().count("bot_victory") == 0, "0006 ausente confirmada → fallback local (como antes)")
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": true, "defeated": []})
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    acc._receive({"type": "bot_error", "code": "not_configured", "message": "x", "bot_id": "madeira"})
    check(bp.is_defeated("madeira") and grants == ["madeira"], "servidor responde not_configured à vitória → fallback local (como antes)")
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, null)
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    acc._receive({"type": "bot_progress", "available": false, "defeated": [], "new_bot": null})
    check(bp.is_defeated("madeira") and grants == ["madeira"], "consulta responde available=false → fallback local")

    # ---------- 4) falhas: nunca concede local por erro temporário ----------
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, null)
    var notes: Array = []
    bp.notice.connect(func(n): notes.append(n))
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    acc._receive({"type": "bot_error", "code": "auth_required", "message": "Entre na sua conta.", "bot_id": ""})
    check(not bp.is_defeated("madeira") and grants.is_empty() and notes.size() == 1, "consulta falhou → avisa, não concede local")
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": true, "defeated": []})
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    acc._receive({"type": "bot_error", "code": "bot_game_invalid", "message": "Partida inválida.", "bot_id": "madeira"})
    check(not bp.is_defeated("madeira") and grants.is_empty(), "servidor recusa a partida → nada concedido")

    # ---------- 5) convidado continua local ----------
    t = fresh(false); acc = t[0]; bp = t[1]; grants = t[2]
    check(bp.key == "local", "convidado: key=local")
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    check(bp.is_defeated("madeira") and grants == ["madeira"] and acc.sent.is_empty(), "convidado: vitória local imediata, nada enviado")
    acc._receive({"type": "bot_progress", "available": true, "defeated": [], "new_bot": null})
    check(bp.is_defeated("madeira"), "convidado ignora respostas de progresso do servidor")
    bp.report_victory("bronze", "w", PackedStringArray(SCHOLAR))
    check(not bp.is_defeated("bronze") and bp.status("ferro") == "available", "ordem da escada mantida (BRONZE bloqueado antes de FERRO)")

    # ---------- 6) troca de conta zera o que se sabia do servidor ----------
    t = fresh(); acc = t[0]; bp = t[1]
    state(acc, {"available": true, "defeated": []})
    acc._clear_session()
    check(bp.key == "local" and not bp.server_available and not bp.server_known, "logout: volta a local e esquece o estado do servidor")

    # ---------- 7) CONTA sem conexão: nada local ----------
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": true, "defeated": []})
    var notes7: Array = []
    bp.notice.connect(func(n): notes7.append(n))
    drop(acc)
    check(bp.is_account() and bp.key == "u-123", "socket caiu: continua sendo CONTA (key = user_id, não vira convidado)")
    check(not acc.has_profile(), "(has_profile() fica falso com o socket caído — por isso não é usado para detectar conta)")
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    check(not bp.is_defeated("madeira") and grants.is_empty(), "conta + socket caído: vitória NÃO gera _grant local")
    check(bp.status("ferro") == "locked" and not bp.avatar_unlocked("mage"), "conta + socket caído: FERRO continua bloqueado, sem recompensa")
    check(notes7 == [Progress.OFFLINE_MSG], "conta + socket caído: mensagem clara de falta de conexão")
    check(acc.types().count("bot_victory") == 0, "conta + socket caído: nada enviado")
    # server_ready=false com socket ainda aberto (antes do acct_state)
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": true, "defeated": ["madeira"]})
    acc.server_ready = false
    bp.report_victory("ferro", "w", PackedStringArray(SCHOLAR))
    check(not bp.is_defeated("ferro") and grants.is_empty() and acc.types().count("bot_victory") == 0, "conta + server_ready=false: nada local, nada enviado")
    check(bp.is_defeated("madeira") and bp.status("ferro") == "available", "conta sem conexão: progresso existente preservado (MADEIRA derrotado, FERRO disponível)")
    # conta autenticada que nunca conectou (socket nunca abriu)
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    acc.socket_open = false
    acc.changed.emit()
    check(bp.is_account() and bp.key == "u-123", "conta autenticada sem nenhum acct_state ainda: é conta, não convidado")
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    check(not bp.is_defeated("madeira") and grants.is_empty(), "conta sem servidor desde o início: sem _grant local")
    # available=false explícito continua com fallback (conectado)
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": false, "defeated": []})
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    check(bp.is_defeated("madeira") and grants == ["madeira"], "available=false explícito (conectado): fallback local mantido")

    # ---------- 8) reconexão: sem recompensa fantasma ----------
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": true, "defeated": []})
    drop(acc)
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    acc.socket_open = true
    state(acc, {"available": true, "defeated": []})
    check(not bp.is_defeated("madeira") and grants.is_empty(), "reconexão depois de vitória offline: nenhuma recompensa fantasma")
    # vitória enviada, socket caiu antes da resposta; servidor TINHA gravado → reconexão mostra a recompensa 1×
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": true, "defeated": []})
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    check(acc.types().count("bot_victory") == 1 and grants.is_empty(), "vitória enviada; resposta ainda não chegou")
    drop(acc)
    check(not bp.is_defeated("madeira") and grants.is_empty(), "socket caiu antes da resposta: nada concedido")
    acc.socket_open = true
    state(acc, {"available": true, "defeated": ["madeira"]})
    check(bp.is_defeated("madeira") and grants == ["madeira"], "reconexão: servidor confirma pela lista → recompensa 1×")
    state(acc, {"available": true, "defeated": ["madeira"]})
    check(grants == ["madeira"], "novo acct_state não repete a recompensa")
    # servidor NÃO gravou: reconexão não concede
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": true, "defeated": []})
    bp.report_victory("madeira", "w", PackedStringArray(SCHOLAR))
    drop(acc)
    acc.socket_open = true
    state(acc, {"available": true, "defeated": []})
    check(not bp.is_defeated("madeira") and grants.is_empty(), "servidor não gravou: reconexão não concede nada")
    # bot que já estava derrotado no servidor não gera recompensa
    t = fresh(); acc = t[0]; bp = t[1]; grants = t[2]
    state(acc, {"available": true, "defeated": ["madeira"]})
    state(acc, {"available": true, "defeated": ["madeira"], "new_bot": "madeira"})
    check(grants.is_empty(), "bot já derrotado antes: sem recompensa repetida")

    print("BOT_PROGRESS_ACCOUNT_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit(1 if failures else 0)
