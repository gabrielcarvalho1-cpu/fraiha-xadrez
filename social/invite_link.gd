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
