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
    if logged:
        acc.access_token = "tok"
        acc.user_id = "u-123"
    var bp = Progress.new()
    root.add_child(bp)
    bp.setup(acc)
    var grants: Array = []
    bp.reward_unlocked.connect(func(b, _r): grants.append(b))
    return [acc, bp, grants]

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
    check(acc.sent.filter(func(m): return m.type == "bot_victory").size() == 1, "repetir a vitória não reenvia")

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

    print("BOT_PROGRESS_ACCOUNT_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit(1 if failures else 0)
