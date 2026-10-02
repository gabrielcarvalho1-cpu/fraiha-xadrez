extends Node
## MARCHA REAL · acesso: Club FRAIHA = ilimitado; sem Club = 1 partida por dia para experimentar.
## Com conta e servidor: quem decide é o SERVIDOR (marcha_status / marcha_start, dia UTC, tabela
## marcha_usage da migração 0008). Sem conta, sem servidor ou com a 0008 ainda não aplicada: o limite
## é contado neste aparelho (user://marcha_daily.cfg, dia local). O tutorial nunca conta.
signal changed(info: Dictionary)

const LOCAL_FILE := "user://marcha_daily.cfg"
const SEEN_FILE := "user://marcha.cfg"
const FREE_PER_DAY := 1

var hub = null
var info := {}
var _waiting := false
var _reply := {}

func setup(p_hub):
    hub = p_hub
    var acc = _account()
    if acc != null and acc.has_signal("server_message"): acc.server_message.connect(_on_server)

func _account():
    return hub.account if hub != null and hub.get("account") != null else null

func _server_ok() -> bool:
    var acc = _account()
    return acc != null and acc.has_profile() and acc.server_ready

func _club() -> bool:
    return hub != null and hub.has_method("club_active") and hub.club_active()

static func today_local() -> String:
    return Time.get_date_string_from_system()

static func local_played_today(path := LOCAL_FILE) -> bool:
    var cfg := ConfigFile.new()
    if cfg.load(path) != OK: return false
    return String(cfg.get_value("daily", "day", "")) == today_local()

static func local_consume(path := LOCAL_FILE):
    var cfg := ConfigFile.new()
    cfg.load(path)
    cfg.set_value("daily", "day", today_local())
    cfg.save(path)

static func tutorial_seen() -> bool:
    var cfg := ConfigFile.new()
    if cfg.load(SEEN_FILE) != OK: return false
    return bool(cfg.get_value("tutorial", "seen", false))

static func mark_tutorial_seen():
    var cfg := ConfigFile.new()
    cfg.load(SEEN_FILE)
    cfg.set_value("tutorial", "seen", true)
    cfg.save(SEEN_FILE)

func _update(i: Dictionary):
    info = i
    changed.emit(info)

func _local_info() -> Dictionary:
    if _club(): return {"can_play": true, "unlimited": true, "label": "CLUB FRAIHA · PARTIDAS ILIMITADAS", "note": ""}
    var played := local_played_today()
    return {"can_play": not played, "unlimited": false,
        "label": "1 PARTIDA GRÁTIS HOJE" if not played else "PARTIDA GRÁTIS DE HOJE JÁ USADA",
        "note": "Membros do Club FRAIHA jogam sem limite. Sem Club: uma partida por dia para experimentar." if not played else "Volte amanhã para outra partida grátis, ou assine o Club FRAIHA para jogar sem limite."}

func _server_info(msg: Dictionary) -> Dictionary:
    if bool(msg.get("unlimited", false)): return {"can_play": true, "unlimited": true, "label": "CLUB FRAIHA · PARTIDAS ILIMITADAS", "note": ""}
    var left := maxi(0, int(msg.get("limit", FREE_PER_DAY)) - int(msg.get("used", 0)))
    return {"can_play": left > 0, "unlimited": false,
        "label": "1 PARTIDA GRÁTIS HOJE" if left > 0 else "PARTIDA GRÁTIS DE HOJE JÁ USADA",
        "note": "Membros do Club FRAIHA jogam sem limite. Sem Club: uma partida por dia para experimentar." if left > 0 else "Volte amanhã para outra partida grátis, ou assine o Club FRAIHA para jogar sem limite."}

## Atualiza o selo do lobby.
func refresh():
    if _server_ok():
        _update({"can_play": false, "label": "VERIFICANDO ACESSO…", "note": ""})
        var r := await _ask({"type": "marcha_status"})
        if r.is_empty() or String(r.get("code", "")) == "not_configured": _update(_local_info())
        else: _update(_server_info(r))
    else:
        _update(_local_info())

## Pede para começar uma partida (consome a do dia se não for Club). true = pode jogar.
func request_start() -> bool:
    if _server_ok():
        var r := await _ask({"type": "marcha_start"})
        var tp := String(r.get("type", ""))
        if tp == "marcha_granted":
            _update(_server_info({"unlimited": r.get("unlimited", false), "used": r.get("used", 1), "limit": r.get("limit", FREE_PER_DAY)}))
            return true
        if tp == "marcha_denied" and String(r.get("code", "")) != "not_configured":
            _update(_server_info({"unlimited": false, "used": 1, "limit": FREE_PER_DAY}))
            return false
        # servidor sem a 0008 ou sem resposta: limite do aparelho
    if _club():
        _update(_local_info())
        return true
    if local_played_today():
        _update(_local_info())
        return false
    local_consume()
    _update(_local_info())
    return true

func _ask(msg: Dictionary) -> Dictionary:
    var acc = _account()
    if acc == null: return {}
    _reply = {}
    _waiting = true
    if not acc.send_server(msg):
        _waiting = false
        return {}
    var t0 := Time.get_ticks_msec()
    while _waiting and Time.get_ticks_msec() - t0 < 6000:
        await get_tree().process_frame
    _waiting = false
    return _reply

func _on_server(msg: Dictionary):
    var tp := String(msg.get("type", ""))
    if tp in ["marcha_state", "marcha_granted", "marcha_denied"]:
        _reply = msg
        _waiting = false
