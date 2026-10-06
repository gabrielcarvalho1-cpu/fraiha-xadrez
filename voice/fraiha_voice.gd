extends Node
## FRAIHA Voice v1 · módulo ÚNICO de voz do jogo (Xadrez Casual/Ranked/amigos, Marcha Real e XEQUE online).
## Camadas: modo de jogo → FraihaVoice (este) → VoiceProvider → Agora. Nenhum modo chama a Agora direto.
##
## Regras (não negociáveis):
## - Só ÁUDIO, só entre HUMANOS, só em partida ONLINE ativa. Bots, offline, treino e análise: nunca.
## - Voz nunca é autoridade: falha de RTC não pausa, não encerra e não altera a partida (este módulo não
##   toca em lance, relógio, resultado, ranking nem matchmaking — só lê o match_id que o modo informa).
## - O servidor decide quem entra (voice_join → token curto); o cliente nunca gera token.
## - Entrar é idempotente e serializado (seq); sair sempre limpa tudo; nada de RTC é salvo em disco.
##   Só a preferência "entrar mudo" fica salva (user://voice.cfg).
## - Logs sem token, sem segredo, sem áudio.
signal changed

const PREF_FILE := "user://voice.cfg"
const T_PERMISSION := 45.0    # tempo para o jogador responder ao pedido do microfone
const T_TOKEN := 12.0         # resposta do servidor (voice_granted / voice_denied)
const T_JOIN := 20.0          # SDK + canal + publicação
const T_RECONNECT := 30.0     # Agora tentando reconectar sozinha
const T_LEAVE_GRACE := 3.0

const STATES := ["DISCONNECTED", "REQUESTING_PERMISSION", "CONNECTING", "CONNECTED", "MUTED", "RECONNECTING", "ERROR"]

var state := "DISCONNECTED"
var message := ""              # texto curto para a UI (erro / dica)
var account = null             # account_service (send_server + server_message)
var provider = null
var ctx := {}                  # {kind, match_id} da partida online ATUAL (vazio = fora de PvP)
var participants := {}         # uid(int) -> nome público (vem do servidor)
var remote: Array = []         # uids remotos conectados no canal agora
var speaking: Array = []       # uids falando (inclui o meu, uid local = my_uid)
var peers_waiting := {}        # uid -> nome: quem entrou na voz enquanto eu ainda não entrei
var my_uid := 0
var muted_pref := false
var autoplay_blocked := false

var _seq := 0
var _deadline := 0.0
var _deadline_state := ""
var _granted_once := false
var _sent_join := false

func _ready():
    name = "FraihaVoice"
    _load_pref()
    if provider == null:
        provider = preload("res://voice/agora_voice_provider.gd").new()
    if provider.get_parent() == null: add_child(provider)
    provider.event.connect(_on_provider)

## Testes / troca de provedor: substitui o provedor (sai da voz antes).
func use_provider(p) -> void:
    if active(): leave("provider_switch")
    if provider != null:
        if provider.event.is_connected(_on_provider): provider.event.disconnect(_on_provider)
        if provider.get_parent() == self: provider.queue_free()
    provider = p
    if provider.get_parent() == null: add_child(provider)
    provider.event.connect(_on_provider)
    changed.emit()

func setup(account_service) -> void:
    account = account_service
    if account != null:
        account.server_message.connect(_on_server)
        account.changed.connect(_on_account_changed)

## Voz existe neste aparelho/navegador? (desktop nativo e HTTP sem TLS: não)
func available() -> bool:
    return provider != null and provider.unsupported_reason() == ""

func in_match() -> bool:
    return not ctx.is_empty()

func active() -> bool:
    return state in ["REQUESTING_PERMISSION", "CONNECTING", "CONNECTED", "MUTED", "RECONNECTING"]

# ------------------------------------------------------------------ API dos modos
## O modo avisa: "estou numa partida online contra humano(s)". kind: ranked|casual|marcha|xeque.
func enter_match(kind: String, match_id: String) -> void:
    if match_id.is_empty(): return
    if ctx.get("match_id", "") == match_id and ctx.get("kind", "") == kind: return
    if active(): leave("switch_match")
    ctx = {"kind": kind, "match_id": match_id}
    participants.clear()
    peers_waiting.clear()
    _to("DISCONNECTED", "")
    _log("match kind=%s match=%s" % [kind, match_id.left(8)])

## Fim/saída da partida, abandono, voltar à Home, logout: sai da voz e esquece a partida.
func exit_match(reason := "match_end") -> void:
    if ctx.is_empty() and not active(): return
    leave(reason)
    ctx = {}
    participants.clear()
    peers_waiting.clear()
    _to("DISCONNECTED", "")

## Botão do microfone: entra (se fora), muda/desmuda (se dentro). Chamado num gesto do jogador
## (clique/toque) — o navegador exige isso para o microfone e para tocar o áudio.
func press() -> void:
    match state:
        "CONNECTED": set_muted(true)
        "MUTED": set_muted(false)
        "DISCONNECTED", "ERROR": join()
        _: pass   # pedindo permissão / conectando / reconectando: ignora (sem join duplicado)

func join() -> void:
    if active(): return                         # idempotente
    if ctx.is_empty():
        _to("ERROR", "Voz só funciona durante a partida online.")
        return
    var why: String = provider.unsupported_reason()
    if why != "":
        _to("ERROR", _support_text(why))
        return
    if account == null or not account.has_profile():
        _to("ERROR", "Entre na sua conta para usar a voz.")
        return
    _seq += 1
    _granted_once = false
    _sent_join = false
    remote.clear()
    speaking.clear()
    autoplay_blocked = false
    _to("REQUESTING_PERMISSION", "Permita o microfone no navegador.", T_PERMISSION)
    _log("join requested seq=%d" % _seq)
    provider.prepare(_seq)

func leave(reason := "user") -> void:
    var was := active() or state == "ERROR"
    _seq += 1
    _deadline = 0.0
    if was:
        provider.leave(_seq, reason)
        if _sent_join and account != null and not ctx.is_empty():
            account.send_server({"type": "voice_leave", "match_id": ctx.match_id, "reason": reason})
        _log("leave reason=%s" % reason)
    _sent_join = false
    _granted_once = false
    remote.clear()
    speaking.clear()
    my_uid = 0
    autoplay_blocked = false
    _to("DISCONNECTED", "")

func set_muted(on: bool) -> void:
    muted_pref = on
    _save_pref()
    if state in ["CONNECTED", "MUTED"]:
        provider.set_muted(on)
        _to("MUTED" if on else "CONNECTED", "")
        _log("mute=%s" % on)

# ------------------------------------------------------------------ texto para a UI
func status_text() -> String:
    match state:
        "DISCONNECTED":
            if not peers_waiting.is_empty(): return "%s está na voz — toque no microfone" % _names(peers_waiting.values())
            return "Voz desligada"
        "REQUESTING_PERMISSION": return "Permita o microfone…"
        "CONNECTING": return "Conectando a voz…"
        "RECONNECTING": return "Reconectando a voz…"
        "ERROR": return message if message != "" else "Voz indisponível"
    var others: Array = []
    for u in remote: others.append(String(participants.get(int(u), "Jogador")))
    var who := ("com " + _names(others)) if not others.is_empty() else "aguardando os outros"
    if autoplay_blocked: return "Toque na tela para ouvir"
    return ("Mudo · " if state == "MUTED" else "Na voz · ") + who

func is_speaking(uid: int) -> bool:
    return speaking.has(uid)

static func _names(list: Array) -> String:
    var out: Array = []
    for n in list: out.append(String(n))
    return ", ".join(out)

static func _support_text(why: String) -> String:
    match why:
        "not_web": return "Voz disponível só no navegador."
        "insecure": return "Voz precisa de conexão segura (https)."
        "no_media", "no_webrtc": return "Este navegador não suporta voz."
    return "Voz indisponível neste aparelho."

static func error_text(code: String) -> String:
    match code:
        "PERMISSION_DENIED": return "Microfone bloqueado. Libere no cadeado da barra de endereço."
        "DEVICE_NOT_FOUND": return "Nenhum microfone encontrado."
        "NOT_SUPPORTED": return "Microfone indisponível ou bloqueado neste navegador."
        "NOT_READABLE": return "Microfone em uso por outro programa."
        "SDK_LOAD", "BRIDGE_LOAD": return "Não foi possível carregar a voz. Verifique a internet."
        "unsupported", "insecure", "no_media", "no_webrtc": return _support_text(code)
        "UID_CONFLICT": return "Você entrou na voz em outra aba."
        "CAN_NOT_GET_GATEWAY_SERVER", "NETWORK_ERROR", "NETWORK_TIMEOUT": return "Sem conexão com o servidor de voz."
        "INVALID_TOKEN", "TOKEN_EXPIRE", "expired": return "Acesso de voz expirou."
        "timeout": return "A voz demorou demais para conectar."
    return "Falha na voz. Toque para tentar de novo."

# ------------------------------------------------------------------ eventos do servidor
func _on_server(msg: Dictionary):
    var type := String(msg.get("type", ""))
    if not type.begins_with("voice_") and type != "link_lost": return
    if type == "link_lost": return   # RTC é independente do WebSocket do jogo; renovação espera reconectar
    var mid := String(msg.get("match_id", ""))
    if ctx.is_empty() or mid != String(ctx.match_id):
        return                       # resposta de outra partida (antiga): ignora
    match type:
        "voice_peer":
            var u := int(msg.get("uid", 0))
            participants[u] = String(msg.get("name", participants.get(u, "Jogador")))
            if bool(msg.get("joined", false)): peers_waiting[u] = participants[u]
            else: peers_waiting.erase(u)
            changed.emit()
        "voice_granted":
            participants.clear()
            for p in msg.get("participants", []):
                if p is Dictionary: participants[int(p.get("uid", 0))] = String(p.get("name", ""))
            if bool(msg.get("renew", false)):
                if state in ["CONNECTED", "MUTED", "RECONNECTING"]:
                    provider.renew(String(msg.get("token", "")))
                    _log("token renewed")
                return
            if state != "CONNECTING" or _granted_once: return
            _granted_once = true
            my_uid = int(msg.get("uid", 0))
            _log("token granted kind=%s seat=%d ttl=%d" % [String(msg.get("kind", "")), my_uid, int(msg.get("ttl", 0))])
            _arm(T_JOIN, "CONNECTING")
            provider.join(_seq, {"app_id": String(msg.get("app_id", "")), "channel": String(msg.get("channel", "")),
                "token": String(msg.get("token", "")), "uid": my_uid, "muted": muted_pref})
        "voice_denied":
            var code := String(msg.get("code", ""))
            _log("token rejected code=%s renew=%s" % [code, bool(msg.get("renew", false))])
            if bool(msg.get("renew", false)):
                if active():
                    leave("renew_denied")
                    if code != "match_over": _to("ERROR", String(msg.get("message", "Voz encerrada.")))
                return
            if state != "CONNECTING": return
            _fail(String(msg.get("message", "Voz indisponível.")), "denied")

func _on_account_changed():
    if account != null and not account.has_profile() and not account.account_pending():
        if in_match() or active(): exit_match("logout")

# ------------------------------------------------------------------ eventos do provedor
func _on_provider(d: Dictionary):
    var ev := String(d.get("ev", ""))
    var seq := int(d.get("seq", _seq))
    var global_ev := ev in ["muted", "renewed", "autoplay_blocked", "autoplay_ok", "device_changed", "sdk_loading", "sdk_ready"]
    if not global_ev and seq != _seq and seq != -1: return     # evento de tentativa antiga
    match ev:
        "permission":
            if state == "REQUESTING_PERMISSION": _arm(T_PERMISSION, "REQUESTING_PERMISSION")
        "mic_ready":
            if state != "REQUESTING_PERMISSION": return
            _to("CONNECTING", "", T_TOKEN)
            if account == null or not account.send_server({"type": "voice_join", "kind": ctx.kind, "match_id": ctx.match_id}):
                _fail("Sem conexão com o servidor do jogo.", "no_socket")
                return
            _sent_join = true
            _log("token requested")
        "joined":
            if state != "CONNECTING": return
            remote = _ints(d.get("uids", []))
            for u in remote: peers_waiting.erase(u)
            _to("MUTED" if bool(d.get("muted", false)) else "CONNECTED", "")
            _log("joined seat=%d remote=%s" % [my_uid, str(remote)])
        "remote":
            remote = _ints(d.get("uids", []))
            for u in remote: peers_waiting.erase(u)
            _log("participants=%s" % str(remote))
            changed.emit()
        "speaking":
            var s := _ints(d.get("uids", []))
            # volume local pode vir como uid 0 ou como o meu uid; mudo nunca aparece "falando"
            if s.has(0):
                s.erase(0)
                if not s.has(my_uid): s.append(my_uid)
            if state != "CONNECTED": s.erase(my_uid)
            s.sort()
            if s != speaking:
                speaking = s
                changed.emit()
        "state":
            var now := String(d.get("now", ""))
            if now == "RECONNECTING" and state in ["CONNECTED", "MUTED"]:
                _to("RECONNECTING", "", T_RECONNECT)
                _log("reconnecting reason=%s" % String(d.get("reason", "")))
            elif now == "CONNECTED" and state == "RECONNECTING":
                _to("MUTED" if muted_pref else "CONNECTED", "")
                _log("reconnected")
            elif now == "DISCONNECTED" and state in ["CONNECTED", "MUTED", "RECONNECTING"]:
                var why := String(d.get("reason", ""))
                _log("disconnected reason=%s" % why)
                _fail("Você saiu da voz em outra aba." if why == "UID_BANNED" or why == "UID_CONFLICT" else "A voz caiu. Toque para entrar de novo.", "rtc_" + why.to_lower())
        "will_expire":
            if account != null and not ctx.is_empty():
                account.send_server({"type": "voice_renew", "match_id": ctx.match_id})
                _log("token renew requested")
        "expired":
            _fail(error_text("expired"), "expired")
        "muted":
            if state in ["CONNECTED", "MUTED"]: _to("MUTED" if bool(d.get("muted", false)) else "CONNECTED", "")
        "mic_lost":
            # permissão revogada / microfone desconectado: continua OUVINDO, fica mudo
            if state in ["CONNECTED", "MUTED", "RECONNECTING"]:
                provider.set_muted(true)
                _to("MUTED", "Microfone perdido. Toque para tentar de novo.")
                _log("mic lost code=%s" % String(d.get("code", "")))
        "autoplay_blocked":
            autoplay_blocked = true
            changed.emit()
        "autoplay_ok":
            autoplay_blocked = false
            changed.emit()
        "error":
            var code := String(d.get("code", ""))
            _log("error stage=%s code=%s" % [String(d.get("stage", "")), code])
            if bool(d.get("soft", false)):
                if String(d.get("stage", "")) == "mic" and state in ["CONNECTED", "MUTED"]:
                    _to("MUTED", error_text(code))
                return
            if active(): _fail(error_text(code), code)
        "left":
            pass

func _ints(a) -> Array:
    var out: Array = []
    if a is Array:
        for v in a: out.append(int(v))
    out.sort()
    return out

func _fail(text: String, code: String) -> void:
    # sai de tudo (microfone, canal, listeners) e mostra o erro; o jogo segue normal
    var keep := text
    leave("error_" + code.left(24).to_lower())
    _to("ERROR", keep)

# ------------------------------------------------------------------ estado / timeout
func _to(s: String, msg := "", timeout := 0.0) -> void:
    state = s
    message = msg
    if timeout > 0.0: _arm(timeout, s)
    elif not s in ["REQUESTING_PERMISSION", "CONNECTING", "RECONNECTING"]: _deadline = 0.0
    changed.emit()

func _arm(t: float, s: String) -> void:
    _deadline = Time.get_ticks_msec() / 1000.0 + t
    _deadline_state = s

func _process(_delta):
    if _deadline <= 0.0: return
    if Time.get_ticks_msec() / 1000.0 < _deadline: return
    _deadline = 0.0
    if state == _deadline_state:
        _log("timeout state=%s" % state)
        _fail(error_text("timeout") if state != "REQUESTING_PERMISSION" else "O microfone não foi liberado a tempo.", "timeout")

# ------------------------------------------------------------------ preferência local (só mudo)
func _load_pref():
    var f := ConfigFile.new()
    if f.load(PREF_FILE) == OK: muted_pref = bool(f.get_value("voice", "muted", false))

func _save_pref():
    var f := ConfigFile.new()
    f.set_value("voice", "muted", muted_pref)
    f.save(PREF_FILE)

func _log(s: String) -> void:
    print("[voice] " + s)
