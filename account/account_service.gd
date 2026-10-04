extends Node
## Conta FRAIHA: Supabase Auth (senha e Google) + conexão autenticada com o servidor.
## Senhas vão direto para o Supabase e nunca são guardadas. Só o refresh token
## da sessão fica no navegador (como qualquer login web) para evitar novo login.
signal changed
signal notice(text: String, is_error: bool)
signal recovery_started
signal server_message(msg: Dictionary)
signal nickname_checked(nickname: String, available: bool, error: String)
signal nickname_changed(nickname: String, next_change_at: String)
signal nickname_failed(code: String, message: String, next_change_at: String)
signal avatar_saved(avatar_url: String)
signal avatar_failed(code: String, message: String)   # upload/remoção recusados pelo servidor
signal entitlements_changed(data: Dictionary)
signal bot_progress_changed(data: Dictionary)   # {available, defeated:[ids], new_bot}
signal bot_progress_failed(code: String, message: String, bot_id: String)
signal cosmetics_state(data: Dictionary)      # R31: {avatar_id, badge, title, frame} vindos do acct_state
signal cosmetics_saved(data: Dictionary)
signal cosmetics_failed(code: String, message: String, field: String)

const SESSION_FILE = "user://account_session.cfg"
const GUEST_FILE = "user://guest_session.cfg"
var supabase_url := ""
var public_key := ""
var site_url := ""
var server_url := ""
var access_token := ""
var refresh_token := ""
var expires_at := 0.0
var user_id := ""
var email := ""
var provider := ""
var profile: Dictionary = {}
var ranked: Dictionary = {}
var needs_nickname := false
var persistent_backend := false
var server_ready := false
var pending_nickname := ""
var after_login := ""
var redirect_pending := false
var busy := false
var socket: WebSocketPeer
var socket_open := false
var retry_in := 0.0
var retry_step := 0      # R35.1: reconexão rápida no 1º tropeço (celular troca de rede/antena), depois espaça
var ping_in := 10.0 # heartbeat: o servidor usa o ping para presença (silêncio de 45 s encerra a conexão)
var refresh_in := -1.0
# Convidado (Online Casual sem conta): identidade só no servidor, recuperável pelo token.
var guest_wanted := false
var guest_ready := false
var guest_token := ""
var guest_nickname := ""
var auth_retried := false # invalid_token: renova a sessão só uma vez (evita loop)

func _ready():
    var config = ConfigFile.new()
    if config.load("res://online.cfg") == OK:
        supabase_url = String(config.get_value("accounts", "supabase_url", "")).trim_suffix("/")
        public_key = String(config.get_value("accounts", "supabase_publishable_key", ""))
        site_url = String(config.get_value("accounts", "site_url", ""))
    # Servidor: resolvido em um só lugar (produção / staging no build beta / F5 / ambiente).
    server_url = preload("res://online_v020/endpoint.gd").server_url()
    _log("servidor: " + server_url)
    if OS.has_environment("FRAIHA_SUPABASE_URL"): supabase_url = OS.get_environment("FRAIHA_SUPABASE_URL")
    if OS.has_environment("FRAIHA_SUPABASE_KEY"): public_key = OS.get_environment("FRAIHA_SUPABASE_KEY")
    if OS.has_feature("web") and site_url.is_empty():
        site_url = str(JavaScriptBridge.eval("window.location.origin + window.location.pathname"))
    var guest = ConfigFile.new()
    if guest.load(GUEST_FILE) == OK: guest_token = String(guest.get_value("guest", "token", ""))
    if not configured():
        if not guest_token.is_empty(): ensure_online.call_deferred()
        return
    if OS.has_feature("web"):
        after_login = str(JavaScriptBridge.eval("(() => { const v = sessionStorage.getItem('fraiha_after_login') || ''; sessionStorage.removeItem('fraiha_after_login'); return v; })()"))
    if not _adopt_redirect_session():
        var saved = ConfigFile.new()
        if saved.load(SESSION_FILE) == OK:
            refresh_token = String(saved.get_value("session", "refresh_token", ""))
            if not refresh_token.is_empty(): _refresh_session()
    # Convidado com partida Casual em andamento: reconecta para retomá-la.
    if refresh_token.is_empty() and not redirect_pending and not guest_token.is_empty(): ensure_online.call_deferred()

func configured() -> bool:
    return not supabase_url.is_empty() and not public_key.is_empty()

func signed_in() -> bool:
    return not access_token.is_empty() and not user_id.is_empty()

func has_profile() -> bool:
    return signed_in() and server_ready and not profile.is_empty()

## Conta existe (ou está sendo restaurada), mas o servidor FRAIHA ainda não confirmou o perfil.
func account_pending() -> bool:
    return not has_profile() and (signed_in() or not refresh_token.is_empty() or redirect_pending)

func _log(text: String):
    # Diagnóstico no Output do editor; nunca registra tokens.
    if OS.is_debug_build(): print("[conta] ", text)

func nickname() -> String:
    return String(profile.get("nickname", ""))

## Identidade pronta para jogar online (conta com perfil ou convidado confirmado pelo servidor).
func online_ready() -> bool:
    return has_profile() or (guest_ready and not signed_in())

func display_name() -> String:
    return nickname() if has_profile() else guest_nickname

## Garante conexão com o servidor. Sem conta, entra como convidado (apenas Online Casual).
func ensure_online():
    if server_url.is_empty():
        notice.emit("Servidor FRAIHA não configurado.", true)
        return
    if signed_in():
        if socket == null: _connect()
        return
    guest_wanted = true
    if socket_open: _send_guest_auth()
    elif socket == null: _connect()

func _send_guest_auth():
    _send({"type": "guest_auth", "token": guest_token})

# ---------- Supabase Auth (REST) ----------
func _auth_request(method: int, path: String, body: Dictionary, done: Callable, bearer := ""):
    var http = HTTPRequest.new()
    add_child(http)
    var headers = PackedStringArray(["apikey: " + public_key, "Content-Type: application/json"])
    if not bearer.is_empty(): headers.append("Authorization: Bearer " + bearer)
    http.request_completed.connect(func(result, code, _h, data):
        http.queue_free()
        var parsed = JSON.parse_string(data.get_string_from_utf8()) if data.size() > 0 else {}
        if not parsed is Dictionary: parsed = {}
        if result != HTTPRequest.RESULT_SUCCESS: code = 0
        done.call(code, parsed))
    var err = http.request(supabase_url + path, headers, method, JSON.stringify(body) if method != HTTPClient.METHOD_GET else "")
    if err != OK:
        http.queue_free()
        done.call(0, {})

static func auth_error_text(code: int, body: Dictionary) -> String:
    if code == 0: return "Sem conexão com o serviço de contas. Tente novamente."
    var raw = String(body.get("error_code", body.get("code", ""))) + " " + String(body.get("msg", body.get("error_description", body.get("message", ""))))
    raw = raw.to_lower()
    if "invalid_credentials" in raw or "invalid login" in raw: return "E-mail ou senha incorretos."
    if "email_not_confirmed" in raw or "not confirmed" in raw: return "Confirme seu e-mail antes de entrar (veja sua caixa de entrada)."
    if "user_already_exists" in raw or "already registered" in raw: return "Já existe uma conta com este e-mail. Use ENTRAR."
    if "weak_password" in raw or "password should" in raw: return "Senha fraca: use pelo menos 8 caracteres, com letras e números."
    if "over_email_send_rate_limit" in raw or "rate limit" in raw: return "Muitas tentativas. Aguarde um pouco e tente de novo."
    if "validation_failed" in raw or "invalid format" in raw: return "Verifique o e-mail digitado."
    return "Não foi possível concluir (%d). Tente novamente." % code

static func valid_email(value: String) -> bool:
    var re = RegEx.create_from_string("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
    return re.search(value.strip_edges()) != null

func sign_up(mail: String, password: String, wanted_nickname: String):
    if busy or not configured(): return
    if not valid_email(mail): 
        notice.emit("Digite um e-mail válido.", true)
        return
    if password.length() < 8:
        notice.emit("A senha precisa ter pelo menos 8 caracteres.", true)
        return
    var nick_error = nickname_error(wanted_nickname)
    if not nick_error.is_empty(): 
        notice.emit(nick_error, true)
        return
    busy = true
    pending_nickname = wanted_nickname.strip_edges()
    var redirect = ("?redirect_to=" + site_url.uri_encode()) if not site_url.is_empty() else ""
    _auth_request(HTTPClient.METHOD_POST, "/auth/v1/signup" + redirect, {"email": mail.strip_edges(), "password": password}, func(code, body):
        busy = false
        if code >= 200 and code < 300:
            if body.has("access_token"): _adopt_session(body)
            else: notice.emit("Conta criada! Confirme pelo link enviado para %s e depois entre." % mail.strip_edges(), false)
        else:
            pending_nickname = ""
            notice.emit(auth_error_text(code, body), true))

func sign_in(mail: String, password: String):
    if busy or not configured(): return
    if not valid_email(mail) or password.is_empty(): 
        notice.emit("Digite e-mail e senha.", true)
        return
    busy = true
    _auth_request(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=password", {"email": mail.strip_edges(), "password": password}, func(code, body):
        busy = false
        if code == 200 and body.has("access_token"): _adopt_session(body)
        else: notice.emit(auth_error_text(code, body), true))

func sign_in_google(then_open := ""):
    if not configured(): return
    if not OS.has_feature("web"):
        notice.emit("Entrar com Google está disponível na versão Web do FRAIHA.", true)
        return
    # Fluxo de redirecionamento (sem popup): volta ao jogo com a sessão no endereço.
    if not then_open.is_empty(): JavaScriptBridge.eval("sessionStorage.setItem('fraiha_after_login', " + JSON.stringify(then_open) + ")")
    var url = supabase_url + "/auth/v1/authorize?provider=google&redirect_to=" + site_url.uri_encode()
    JavaScriptBridge.eval("window.location.assign(" + JSON.stringify(url) + ")")

func recover(mail: String):
    if busy or not configured(): return
    if not valid_email(mail): 
        notice.emit("Digite o e-mail da sua conta.", true)
        return
    busy = true
    var redirect = ("?redirect_to=" + site_url.uri_encode()) if not site_url.is_empty() else ""
    _auth_request(HTTPClient.METHOD_POST, "/auth/v1/recover" + redirect, {"email": mail.strip_edges()}, func(code, body):
        busy = false
        if code >= 200 and code < 300: notice.emit("Se existir uma conta com este e-mail, enviamos um link para criar uma nova senha.", false)
        else: notice.emit(auth_error_text(code, body), true))

func update_password(password: String):
    if busy or not signed_in(): return
    if password.length() < 8: 
        notice.emit("A senha precisa ter pelo menos 8 caracteres.", true)
        return
    busy = true
    _auth_request(HTTPClient.METHOD_PUT, "/auth/v1/user", {"password": password}, func(code, body):
        busy = false
        if code == 200: notice.emit("Senha alterada com sucesso.", false)
        else: notice.emit(auth_error_text(code, body), true), access_token)

func sign_out():
    var token = access_token
    if not token.is_empty() and configured():
        _auth_request(HTTPClient.METHOD_POST, "/auth/v1/logout", {}, func(_c, _b): pass, token)
    if socket_open: _send({"type": "acct_logout"})
    _clear_session()
    notice.emit("Você saiu da conta.", false)

func _refresh_session():
    if refresh_token.is_empty(): return
    _auth_request(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh_token}, func(code, body):
        if code == 200 and body.has("access_token"): _adopt_session(body)
        elif code == 0: refresh_in = 15.0 # sem rede: tenta de novo, mantém a sessão salva
        else: _clear_session())

func _adopt_session(body: Dictionary):
    access_token = String(body.get("access_token", ""))
    refresh_token = String(body.get("refresh_token", refresh_token))
    var ttl = float(body.get("expires_in", 3600))
    expires_at = Time.get_unix_time_from_system() + ttl
    refresh_in = maxf(30.0, ttl - 120.0)
    var user = body.get("user", {})
    if user is Dictionary and user.has("id"):
        user_id = String(user.id)
        email = String(user.get("email", ""))
        provider = String(user.get("app_metadata", {}).get("provider", "email"))
    var saved = ConfigFile.new()
    saved.set_value("session", "refresh_token", refresh_token)
    saved.save(SESSION_FILE)
    if user_id.is_empty():
        # Sessão vinda do redirecionamento: identifica o usuário pelo próprio token.
        _auth_request(HTTPClient.METHOD_GET, "/auth/v1/user", {}, func(code, u):
            if code == 200 and u.has("id"):
                user_id = String(u.id); email = String(u.get("email", ""))
                provider = String(u.get("app_metadata", {}).get("provider", "email"))
                _server_auth()
            else: _clear_session(), access_token)
    else:
        _server_auth()
    changed.emit()

func _clear_session():
    access_token = ""; refresh_token = ""; user_id = ""; email = ""; provider = ""
    profile = {}; ranked = {}; needs_nickname = false; server_ready = false; refresh_in = -1.0
    var saved = ConfigFile.new()
    saved.set_value("session", "refresh_token", "")
    saved.save(SESSION_FILE)
    guest_ready = false
    if guest_wanted and socket_open: _send_guest_auth.call_deferred()
    changed.emit()

func _adopt_redirect_session() -> bool:
    if not OS.has_feature("web"): return false
    var hash = str(JavaScriptBridge.eval("window.location.hash || ''"))
    if hash.length() < 2: return false
    var params = {}
    for pair in hash.substr(1).split("&"):
        var kv = pair.split("=", true, 1)
        if kv.size() == 2: params[kv[0]] = kv[1].uri_decode()
    if not params.has("access_token") and not params.has("error_description"): return false
    # Remove os tokens da barra de endereço imediatamente.
    JavaScriptBridge.eval("history.replaceState(null, '', window.location.pathname + window.location.search)")
    if params.has("error_description"):
        notice.emit.call_deferred("Login não concluído: " + String(params.error_description).replace("+", " "), true)
        return false
    redirect_pending = true
    _adopt_session.call_deferred({"access_token": params.access_token, "refresh_token": params.get("refresh_token", ""), "expires_in": params.get("expires_in", "3600")})
    if params.get("type", "") == "recovery": recovery_started.emit.call_deferred()
    return true

# ---------- Servidor FRAIHA (autoridade de perfil/Ranked) ----------
func _server_auth():
    server_ready = false
    if server_url.is_empty(): 
        notice.emit("Servidor FRAIHA não configurado.", true)
        return
    if socket_open:
        _log("acct_auth enviado")
        _send({"type": "acct_auth", "access_token": access_token})
    elif socket == null: _connect()

func _connect():
    socket = WebSocketPeer.new()
    # Padrão do Godot = 64 KB: a foto de perfil (até 400 KB em base64) não cabia e era descartada.
    socket.outbound_buffer_size = 1024 * 1024
    socket.inbound_buffer_size = 1024 * 1024
    socket_open = false
    if socket.connect_to_url(server_url) != OK:
        socket = null
        retry_in = 5.0

func _send(msg: Dictionary) -> bool:
    if socket == null or not socket_open: return false
    var err := socket.send_text(JSON.stringify(msg))
    if err != OK: _log("send falhou (%d) para %s" % [err, String(msg.get("type", ""))])
    return err == OK

func send_server(msg: Dictionary) -> bool:
    return _send(msg)

func create_profile(nick: String, avatar := "warrior"):
    var err = nickname_error(nick)
    if not err.is_empty(): 
        notice.emit(err, true)
        return
    if not _send({"type": "acct_create_profile", "nickname": nick.strip_edges(), "avatar_id": avatar}):
        notice.emit("Conectando ao servidor… tente novamente em instantes.", true)

## Limpeza igual à do servidor: remove invisíveis/controle/bidi e espaços nas pontas.
static func clean_nickname(nick: String) -> String:
    var out := ""
    for ch in nick:
        var c: int = ch.unicode_at(0)
        var invisible := c < 0x20 or (c >= 0x7F and c <= 0x9F) or c == 0xAD or c == 0x34F or c == 0x61C or c == 0x180E \
            or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F) \
            or (c >= 0xFE00 and c <= 0xFE0F) or c == 0xFEFF or c == 0x3164 or c == 0xFFA0
        if not invisible: out += ch
    return out.strip_edges()

## Regra do nome público (igual ao servidor): 3–20 caracteres, só letras, números e _.
static func nickname_error(nick: String) -> String:
    var n = clean_nickname(nick)
    if n.is_empty(): return "Digite um nome."
    if n.length() < 3 or n.length() > 20: return "O nome precisa ter entre 3 e 20 caracteres."
    var re = RegEx.create_from_string("^[A-Za-z0-9_]+$")
    if re.search(n) == null: return "Use apenas letras, números e _ (sem espaços nem acentos)."
    return ""

# ---------- Nome público (0004) ----------
## R31: avatar, ícone, título e moldura da conta (o servidor revalida pelos direitos).
func set_cosmetics(data: Dictionary) -> bool:
    if not has_profile(): return false
    var msg := {"type": "acct_set_cosmetics"}
    for k in ["avatar_id", "badge", "title", "frame"]:
        if data.has(k): msg[k] = String(data[k])
    return _send(msg)

func check_nickname(nick: String) -> bool:
    return _send({"type": "acct_check_nickname", "nickname": clean_nickname(nick)})

func change_nickname(nick: String) -> bool:
    var err = nickname_error(nick)
    if not err.is_empty():
        nickname_failed.emit("nickname_invalid", err, "")
        return false
    if not _send({"type": "acct_change_nickname", "nickname": clean_nickname(nick)}):
        nickname_failed.emit("offline", "Conectando ao servidor… tente novamente em instantes.", "")
        return false
    return true

## Data (do servidor) em que o nome pode ser trocado de novo; "" = pode trocar agora.
func nickname_next_change_at() -> String:
    var v = profile.get("nickname_next_change_at")
    return String(v) if v != null else ""

# ---------- Foto de perfil (0004): bytes já recortados (512x512, WebP/PNG) ----------
func upload_avatar(bytes: PackedByteArray) -> bool:
    if bytes.is_empty() or bytes.size() > 400 * 1024: return false
    return _send({"type": "acct_avatar_upload", "data": Marshalls.raw_to_base64(bytes)})

## Vitória contra um bot da escada: o servidor refaz a partida e decide (ver online_v021/bots/service.js).
func claim_bot_victory(bot_id: String, human_color: String, moves: PackedStringArray) -> bool:
    return _send({"type": "bot_victory", "bot_id": bot_id, "human_color": human_color, "moves": Array(moves)})

func clear_avatar() -> bool:
    return _send({"type": "acct_avatar_clear"})

func avatar_url() -> String:
    var v = profile.get("avatar_url")
    return String(v) if v != null else ""

## Voltou ao primeiro plano (aba/app): heartbeat imediato; a reconexão normal cuida do resto.
func _notification(what):
    if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
        ping_in = 0.0
        if socket == null and (signed_in() or guest_wanted): retry_in = 0.05   # reconecta já, sem esperar os 3 s

func _process(delta):
    if refresh_in > 0.0:
        refresh_in -= delta
        if refresh_in <= 0.0: _refresh_session()
    if retry_in > 0.0:
        retry_in -= delta
        if retry_in <= 0.0 and (signed_in() or guest_wanted) and socket == null: _connect()
        return
    if socket == null: return
    socket.poll()
    var state = socket.get_ready_state()
    if state == WebSocketPeer.STATE_OPEN:
        if not socket_open:
            socket_open = true
            retry_step = 0
            if signed_in():
                _log("acct_auth enviado")
                _send({"type": "acct_auth", "access_token": access_token})
            elif guest_wanted: _send_guest_auth()
        while socket.get_available_packet_count() > 0:
            var msg = JSON.parse_string(socket.get_packet().get_string_from_utf8())
            if msg is Dictionary: _receive(msg)
        ping_in -= delta
        if ping_in <= 0.0:
            ping_in = 10.0
            _send({"type": "ping"})
    elif state == WebSocketPeer.STATE_CLOSED:
        socket = null
        socket_open = false
        server_ready = false
        guest_ready = false
        retry_in = [0.6, 1.5, 3.0, 5.0][mini(retry_step, 3)]
        retry_step += 1
        server_message.emit({"type": "link_lost"})
        changed.emit()

func _receive(msg: Dictionary):
    var type = String(msg.get("type", ""))
    if type == "acct_state":
        server_ready = true
        auth_retried = false
        _log("acct_state recebido (perfil: %s, persistente: %s)" % [msg.get("profile") is Dictionary, bool(msg.get("persistent", false))])
        profile = msg.profile if msg.get("profile") is Dictionary else {}
        ranked = msg.ranked if msg.get("ranked") is Dictionary else {}
        needs_nickname = bool(msg.get("needs_nickname", false))
        persistent_backend = bool(msg.get("persistent", false))
        if msg.get("entitlements") is Dictionary:
            # R39 · extras do Fundador (link do grupo) chegam junto, só para quem é Fundador de verdade
            var ent: Dictionary = (msg.entitlements as Dictionary).duplicate()
            ent["founder_perks"] = msg.get("founder_perks") if msg.get("founder_perks") is Dictionary else {}
            entitlements_changed.emit(ent)
        if msg.get("bots") is Dictionary: bot_progress_changed.emit((msg.bots as Dictionary).merged({"new_bot": null}))
        if msg.get("cosmetics") is Dictionary: cosmetics_state.emit(msg.cosmetics)
        if needs_nickname and not pending_nickname.is_empty():
            var nick = pending_nickname
            pending_nickname = ""
            create_profile(nick)
        changed.emit()
    elif type == "acct_error":
        var code = String(msg.get("code", ""))
        _log("acct_error: " + code)
        if code == "invalid_token" and not refresh_token.is_empty() and not auth_retried:
            auth_retried = true
            _refresh_session()
        else: notice.emit(String(msg.get("message", "Erro de conta.")), true)
        if code.begins_with("nickname") or code == "profile_error": changed.emit()
        if code.begins_with("nickname"):
            var next_at = msg.get("next_change_at")
            nickname_failed.emit(code, String(msg.get("message", "")), String(next_at) if next_at != null else "")
        if code.begins_with("avatar") or code == "storage_error": avatar_failed.emit(code, String(msg.get("message", "")))
        if code == "auth_required": server_message.emit(msg)
    elif type == "acct_nickname_check":
        nickname_checked.emit(String(msg.get("nickname", "")), bool(msg.get("available", false)), String(msg.get("error", "")))
    elif type == "acct_nickname_changed":
        var next_at = msg.get("next_change_at")
        nickname_changed.emit(String(msg.get("nickname", "")), String(next_at) if next_at != null else "")
    elif type == "acct_avatar_saved":
        var url = msg.get("avatar_url")
        avatar_saved.emit(String(url) if url != null else "")
    elif type == "acct_cosmetics_saved":
        cosmetics_saved.emit(msg)
    elif type == "acct_cosmetics_error":
        cosmetics_failed.emit(String(msg.get("code", "")), String(msg.get("message", "")), String(msg.get("field", "")))
    elif type == "acct_entitlements":
        entitlements_changed.emit(msg.get("entitlements", {}) if msg.get("entitlements") is Dictionary else {})
    elif type == "bot_progress":
        bot_progress_changed.emit(msg)
    elif type == "bot_error":
        bot_progress_failed.emit(String(msg.get("code", "")), String(msg.get("message", "")), String(msg.get("bot_id", "")))
    elif type == "acct_logged_out":
        pass
    elif type == "guest_state":
        if not bool(msg.get("account", false)):
            guest_ready = true
            guest_nickname = String(msg.get("nickname", "Convidado"))
            var tok = String(msg.get("token", ""))
            if tok != guest_token:
                guest_token = tok
                var file = ConfigFile.new()
                file.set_value("guest", "token", guest_token)
                file.save(GUEST_FILE)
        changed.emit()
    elif type != "pong":
        server_message.emit(msg)
