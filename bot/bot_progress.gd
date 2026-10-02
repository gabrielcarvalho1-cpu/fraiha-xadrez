extends Node
## Progresso da escada de bots + avatares desbloqueados.
##   • Conta logada com o servidor pronto e migração 0006 aplicada: o SERVIDOR é a autoridade.
##     A vitória é enviada (lances UCI) e só vira progresso/recompensa quando o servidor confirma
##     (online_v021/bots/service.js refaz a partida). Aparece em qualquer aparelho da conta.
##   • Convidado, ou servidor sem 0006: progresso LOCAL deste aparelho (user://bot_progress.cfg),
##     separado por conta. Nunca é enviado depois como "prova" — o servidor só aceita partidas.
##   • Conta = sessão autenticada (access_token + user_id), mesmo com o socket caído. Conta sem
##     conexão NÃO ganha progresso local: a vitória não é registrada e o jogador é avisado.
signal changed
signal reward_unlocked(bot_id: String, reward: Dictionary)
signal notice(text: String)

const Ladder = preload("res://bot/bot_ladder.gd")
const FILE := "user://bot_progress.cfg"
const INITIAL_AVATARS := ["warrior", "archer"]
const OFFLINE_MSG := "Sem conexão com o servidor. A vitória não pôde ser registrada na sua conta."

var key := "local"             # "local" (convidado) ou user_id da conta
var defeated := {}             # bot_id -> unix (1ª vitória)
var server_available := false  # conta com progresso no servidor (0006)
var server_known := false      # já chegou resposta do servidor (bots) para ESTA conta?
var account                    # account/account_service.gd
var _pending := {}             # bot_id aguardando confirmação do servidor
var _deferred := {}            # vitória à espera de saber se o servidor tem progresso (bot_id -> [cor, lances])

func setup(acc):
    account = acc
    if account != null:
        account.changed.connect(_on_account_changed)
        account.bot_progress_changed.connect(_on_server_progress)
        account.bot_progress_failed.connect(_on_server_failed)
    _on_account_changed()

func _on_account_changed():
    _sync_key()

## Chave atual a partir da conta. Chamada no `changed` E no início de _on_server_progress:
## a ordem dos sinais do account_service (bot_progress_changed antes de changed) não importa.
## Há uma conta autenticada? Baseado na IDENTIDADE (sessão + user_id), não em has_profile():
## has_profile() fica falso quando o socket cai, e a conta não pode "virar convidado" por isso.
func is_account() -> bool:
    return account != null and account.signed_in()

func _sync_key():
    var k := String(account.user_id) if is_account() else "local"
    if k != key or defeated.is_empty():
        if k != key:
            # outra conta (ou saiu): o que se sabia do servidor era da conta anterior
            server_available = false
            server_known = false
            _deferred.clear()
        key = k
        _load()
        changed.emit()

func _load():
    defeated.clear()
    var cfg := ConfigFile.new()
    if cfg.load(FILE) != OK: return
    for id in Ladder.ids():
        if cfg.has_section_key(key, id): defeated[id] = int(cfg.get_value(key, id))

func _save():
    var cfg := ConfigFile.new()
    cfg.load(FILE)
    for id in Ladder.ids():
        if defeated.has(id): cfg.set_value(key, id, defeated[id])
        elif cfg.has_section_key(key, id): cfg.erase_section_key(key, id)
    cfg.save(FILE)

# ---------------------------------------------------------------- consultas
func is_defeated(id: String) -> bool:
    return defeated.has(id)

func is_unlocked(id: String) -> bool:
    var i := Ladder.index_of(id)
    if i < 0: return false
    return i == 0 or is_defeated(Ladder.ids()[i - 1])

## "defeated" | "available" | "locked"
func status(id: String) -> String:
    if is_defeated(id): return "defeated"
    return "available" if is_unlocked(id) else "locked"

func next_bot() -> String:
    for id in Ladder.ids():
        if not is_defeated(id): return id
    return ""

## Bot cuja 1ª vitória dá este avatar ("" = avatar inicial ou desconhecido).
static func unlock_bot_for_avatar(avatar_id: String) -> String:
    for b in Ladder.bots():
        var r: Dictionary = b.get("reward", {})
        if String(r.get("type", "")) == "avatar" and String(r.get("id", "")) == avatar_id: return String(b.id)
    return ""

func avatar_unlocked(avatar_id: String) -> bool:
    if avatar_id in INITIAL_AVATARS: return true
    var bot := unlock_bot_for_avatar(avatar_id)
    return not bot.is_empty() and is_defeated(bot)

func unlock_hint(avatar_id: String) -> String:
    var bot := unlock_bot_for_avatar(avatar_id)
    if bot.is_empty(): return ""
    return "Derrote o " + String(Ladder.bot(bot).get("name", "bot"))

func storage_label() -> String:
    if key == "local": return "Progresso salvo neste aparelho (entre na conta para salvar em todos)."
    return "Progresso salvo na sua conta." if server_available else "Progresso salvo neste aparelho (servidor ainda sem progresso de bots)."

# ---------------------------------------------------------------- vitória
## Chamado ao fim de uma partida GANHA contra um bot da escada (xeque-mate do bot).
func report_victory(bot_id: String, human_color: String, moves: PackedStringArray):
    if not is_unlocked(bot_id) or is_defeated(bot_id): return
    _sync_key()
    if not is_account():
        _grant(bot_id)   # convidado: progresso local deste aparelho
        return
    if not (account.server_ready and account.socket_open):
        # Conta sem conexão: nada local (senão a vitória "some" quando o servidor responder).
        notice.emit(OFFLINE_MSG)
        return
    if not server_known:
        # Ainda não se sabe se o servidor guarda o progresso: pergunta UMA vez antes de decidir.
        if _deferred.has(bot_id): return
        _deferred[bot_id] = [human_color, moves]
        if not account.send_server({"type": "bot_progress"}):
            _deferred.erase(bot_id)
            notice.emit(OFFLINE_MSG)
        return
    if server_available:
        _claim(bot_id, human_color, moves)
        return
    # O servidor respondeu explicitamente que NÃO guarda progresso de bots (0006 ausente): fallback local.
    _grant(bot_id)

func _claim(bot_id: String, human_color: String, moves: PackedStringArray):
    if _pending.has(bot_id): return
    _pending[bot_id] = true
    if not account.claim_bot_victory(bot_id, human_color, moves):
        _pending.erase(bot_id)
        notice.emit(OFFLINE_MSG)

func _grant(bot_id: String):
    if is_defeated(bot_id): return
    defeated[bot_id] = int(Time.get_unix_time_from_system())
    _save()
    changed.emit()
    reward_unlocked.emit(bot_id, Ladder.reward(bot_id))

func _on_server_progress(data: Dictionary):
    _sync_key()   # corrige a race: o 1º acct_state emite isto ANTES de account.changed
    if key == "local": return
    server_known = true
    server_available = bool(data.get("available", false))
    if not server_available:
        changed.emit()
        _resolve_deferred()
        return
    var list: Array = data.get("defeated", [])
    var before := defeated.duplicate()
    defeated.clear()
    for id in list:
        if Ladder.is_bot_id(String(id)): defeated[String(id)] = int(before.get(String(id), Time.get_unix_time_from_system()))
    _save()
    changed.emit()
    # Recompensa só para vitória CONFIRMADA pelo servidor e ainda não mostrada nesta sessão:
    # new_bot (resposta ao bot_victory) ou um envio pendente que aparece na lista depois de uma
    # reconexão (a resposta se perdeu com o socket). Nunca para bots que já estavam derrotados.
    var confirmed: Array = []
    var nb = data.get("new_bot")
    if nb != null and not String(nb).is_empty(): confirmed.append(String(nb))
    for id in _pending.keys():
        if defeated.has(String(id)) and not before.has(String(id)) and String(id) not in confirmed: confirmed.append(String(id))
    for id in confirmed:
        _pending.erase(id)
        if defeated.has(id) and not before.has(id): reward_unlocked.emit(id, Ladder.reward(id))
    _resolve_deferred()

## Vitórias que esperavam a resposta do servidor: envia (servidor com progresso) ou guarda local
## (servidor confirmou que não tem). Cada uma é tratada uma única vez.
func _resolve_deferred():
    if _deferred.is_empty(): return
    var items := _deferred.duplicate()
    _deferred.clear()
    for id in items:
        if is_defeated(String(id)) or not is_unlocked(String(id)): continue
        if server_available: _claim(String(id), String(items[id][0]), items[id][1])
        else: _grant(String(id))

func _on_server_failed(code: String, message: String, bot_id: String):
    if bot_id.is_empty() and not _deferred.is_empty():
        # a consulta de progresso falhou (ex.: sessão caiu): não concede local, só avisa
        _deferred.clear()
        notice.emit("Vitória não registrada: " + message)
        return
    if not _pending.has(bot_id): return
    _pending.erase(bot_id)
    if code == "not_configured":
        server_available = false
        _grant(bot_id)   # servidor sem 0006: guarda neste aparelho
    else:
        notice.emit("Vitória não registrada: " + message)
