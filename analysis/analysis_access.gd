extends Node
## Acesso à análise: 3 análises completas por dia para quem não tem Club; Club = ilimitado.
## O LIMITE É DO SERVIDOR (analysis_request → analysis_granted/denied, dia UTC, relógio do
## servidor). Este nó só guarda o último estado informado e pede a autorização.
## Sem conta / sem servidor: modo DEV local (só para testar a interface; marcado como teste).
signal state_changed
signal granted(unlimited: bool)
signal denied(code: String, message: String)

const Catalog := preload("res://monetization/monetization_catalog.gd")
const DEV_FILE := "user://dev_analysis_quota.cfg"
const FREE_PER_DAY := 3

var account = null
var entitlements = null
var used := 0
var limit := FREE_PER_DAY
var unlimited := false
var resets_at := ""
var known := false            # já recebeu estado do servidor?
var dev_local := false        # cota local de desenvolvimento (sem servidor)
var _waiting := false

func setup(acc, ent):
    account = acc
    entitlements = ent
    if account != null:
        account.server_message.connect(_on_server)
        account.changed.connect(_on_account_changed)
    if entitlements != null: entitlements.changed.connect(func(): state_changed.emit())
    _on_account_changed()

func _on_account_changed():
    if account != null and account.has_profile() and account.server_ready:
        account.send_server({"type": "analysis_status"})
    else:
        _load_dev()

func _on_server(msg: Dictionary):
    var t := String(msg.get("type", ""))
    if t == "analysis_state":
        _apply(msg)
        dev_local = false
        known = true
        state_changed.emit()
    elif t == "analysis_granted":
        _apply(msg)
        known = true
        _waiting = false
        state_changed.emit()
        granted.emit(bool(msg.get("unlimited", false)))
    elif t == "analysis_denied":
        if msg.has("used"): _apply(msg)
        _waiting = false
        state_changed.emit()
        denied.emit(String(msg.get("code", "")), String(msg.get("message", "")))

func _apply(msg: Dictionary):
    unlimited = bool(msg.get("unlimited", false))
    used = int(msg.get("used", 0))
    limit = int(msg.get("limit", FREE_PER_DAY)) if not unlimited else 0
    var r = msg.get("resets_at")
    resets_at = String(r) if r != null else ""

## Club ativo para fins de interface (servidor OU simulação). O servidor continua mandando
## no limite real: com dev_mock_club, o pedido ao servidor pode ser negado — e a interface
## mostra isso. Em modo DEV local (sem servidor), a simulação libera.
func club_unlimited() -> bool:
    if unlimited: return true
    return dev_local and entitlements != null and entitlements.club_active()

func remaining() -> int:
    if club_unlimited(): return 999
    return maxi(0, limit - used)

## Texto do botão/estado: "2 ANÁLISES GRATUITAS RESTANTES HOJE" | "♛ CLUB · ILIMITADO" | "0 / 3".
func status_line() -> String:
    if club_unlimited(): return "CLUB · ILIMITADO"
    var n := remaining()
    if n == 0: return "VOCÊ USOU SUAS %d ANÁLISES GRATUITAS DE HOJE" % limit
    return "%d %s GRATUITA%s RESTANTE%s HOJE" % [n, "ANÁLISE" if n == 1 else "ANÁLISES", "" if n == 1 else "S", "" if n == 1 else "S"]

func counter_text() -> String:
    if club_unlimited(): return "ILIMITADO"
    return "%d / %d" % [used, limit]

## Hora local da renovação ("amanhã às 21:00").
func reset_text() -> String:
    if resets_at.is_empty(): return "renova à meia-noite (UTC)"
    var unix := Time.get_unix_time_from_datetime_string(resets_at)
    if unix <= 0: return "renova à meia-noite (UTC)"
    var local := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
    return "renova às %02d:%02d" % [int(local.hour), int(local.minute)]

## Pede UMA análise. Responde por `granted`/`denied`.
func request():
    if _waiting: return
    if account != null and account.has_profile() and account.server_ready and not dev_local:
        _waiting = true
        if not account.send_server({"type": "analysis_request"}):
            _waiting = false
            denied.emit("offline", "Sem conexão com o servidor. Tente novamente.")
        return
    # DEV local (sem conta/servidor): simula a cota do dia só para testar a interface.
    _load_dev()
    if club_unlimited():
        granted.emit(true)
        return
    if used >= limit:
        denied.emit("quota", "Você usou suas %d análises gratuitas de hoje." % limit)
        return
    used += 1
    _save_dev()
    state_changed.emit()
    granted.emit(false)

# ----- cota DEV local (só sem servidor) -----
func _load_dev():
    dev_local = true
    var cfg := ConfigFile.new()
    var today := Time.get_date_string_from_system(true)
    used = 0
    limit = FREE_PER_DAY
    unlimited = false
    resets_at = ""
    if cfg.load(DEV_FILE) == OK and String(cfg.get_value("dev", "day", "")) == today:
        used = int(cfg.get_value("dev", "used", 0))
    known = true
    state_changed.emit()

func _save_dev():
    var cfg := ConfigFile.new()
    cfg.set_value("dev", "day", Time.get_date_string_from_system(true))
    cfg.set_value("dev", "used", used)
    cfg.save(DEV_FILE)

## RESET DEV (ferramentas de desenvolvimento).
func dev_reset():
    used = 0
    _save_dev()
    state_changed.emit()
