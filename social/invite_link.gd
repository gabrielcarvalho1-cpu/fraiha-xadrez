extends RefCounted
## R105 · CONVITE POR LINK. https://jogar.fraihaxadrez.com/?convite=CODIGO
## • Ao abrir o jogo pelo link, o código fica guardado no aparelho (sobrevive ao login com Google, que sai da
##   página e volta) e vai junto na criação da conta (acct_create_profile.ref). O servidor decide se vale.
## • Quem convida: link com o próprio código para WhatsApp, copiar ou compartilhar (celular).
const FILE := "user://convite.cfg"
const SITE := "https://jogar.fraihaxadrez.com/"
const MAX_AGE_S := 30 * 86400
const CODE_RE := "^[A-HJ-NP-Z2-9]{7}$"

static func _valid(code: String) -> bool:
	var re := RegEx.new()
	re.compile(CODE_RE)
	return re.search(code) != null

## Lê ?convite= da página (só Web) e guarda. Chamado uma vez ao abrir o jogo.
static func capture() -> String:
	if not OS.has_feature("web"): return ""
	var raw = JavaScriptBridge.eval("(new URLSearchParams(location.search).get('convite') || '').trim().toUpperCase()", true)
	var code := String(raw if raw != null else "")
	if not _valid(code): return ""
	var cfg := ConfigFile.new()
	cfg.set_value("convite", "code", code)
	cfg.set_value("convite", "at", int(Time.get_unix_time_from_system()))
	cfg.save(FILE)
	return code

## Código guardado (vazio se não houver ou se tiver mais de 30 dias).
static func stored_code() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK: return ""
	var code := String(cfg.get_value("convite", "code", ""))
	var at := int(cfg.get_value("convite", "at", 0))
	if not _valid(code) or int(Time.get_unix_time_from_system()) - at > MAX_AGE_S: return ""
	return code

## R121 · LINK DE CRIADOR: ?criador=CODIGO (3 a 20 letras/números). Guardado como o convite (30 dias) e enviado na
## criação da conta (acct_create_profile.creator) ou, se já tiver conta, ao entrar (creator_set).
const CREATOR_FILE := "user://criador.cfg"
static func creator_clean(raw: String) -> String:
	var s := raw.strip_edges().to_upper()
	var out := ""
	for ch in s:
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"): out += ch
	return out if out.length() >= 3 and out.length() <= 20 else ""

static func capture_creator() -> String:
	if not OS.has_feature("web"): return ""
	var raw = JavaScriptBridge.eval("(new URLSearchParams(location.search).get('criador') || '')", true)
	var code := creator_clean(String(raw if raw != null else ""))
	if code.is_empty(): return ""
	var cfg := ConfigFile.new()
	cfg.set_value("criador", "code", code)
	cfg.set_value("criador", "at", int(Time.get_unix_time_from_system()))
	cfg.save(CREATOR_FILE)
	return code

static func stored_creator() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CREATOR_FILE) != OK: return ""
	var code := creator_clean(String(cfg.get_value("criador", "code", "")))
	if int(Time.get_unix_time_from_system()) - int(cfg.get_value("criador", "at", 0)) > MAX_AGE_S: return ""
	return code

static func clear_creator():
	if FileAccess.file_exists(CREATOR_FILE): DirAccess.remove_absolute(ProjectSettings.globalize_path(CREATOR_FILE))

static func clear():
	if FileAccess.file_exists(FILE): DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))

static func base_url() -> String:
	if OS.has_feature("web"):
		var o = JavaScriptBridge.eval("location.origin + location.pathname", true)
		var s := String(o if o != null else "")
		if s.begins_with("https://"): return s
	return SITE

static func link(code: String) -> String:
	return base_url() + "?convite=" + code

static func message(code: String) -> String:
	return "Bora jogar xadrez comigo no FRAIHA? Tem Ranqueada, XEQUE e Marcha Real, de graça no navegador. Entra pelo meu link: " + link(code)

static func whatsapp_url(code: String) -> String:
	return "https://wa.me/?text=" + message(code).uri_encode()

static func open_whatsapp(code: String):
	OS.shell_open(whatsapp_url(code))

static func copy(code: String):
	DisplayServer.clipboard_set(link(code))

## Compartilhar nativo do celular (Web). Devolve false se o navegador não tiver.
static func native_share(code: String) -> bool:
	if not OS.has_feature("web"): return false
	var ok = JavaScriptBridge.eval("(() => { if (!navigator.share) return false; navigator.share({ title: 'FRAIHA Xadrez', text: %s }).catch(() => {}); return true; })()" % JSON.stringify(message(code)), true)
	return bool(ok)
