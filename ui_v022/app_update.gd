extends Node
## R183 · APP ANDROID: aviso de ATUALIZAÇÃO. No site todo mundo recebe a versão nova sozinho; no app (APK) não.
## Pergunta ao servidor do jogo GET https://<servidor>/app-version → {android: {latest, min, name, url}}.
##   • versão deste app < min    → OBRIGATÓRIA: "Atualize o app" sempre que abrir/voltar (sem "Depois");
##   • versão deste app < latest → aviso com "ATUALIZAR" e "Depois" (1x por dia por versão nova).
## ATUALIZAR abre o link do APK novo no navegador do celular. Só no Android (Web e PC: nada).
## APP_CODE = version/code do preset "Android" (tests/r183_app_update_test.gd confere).

const APP_CODE := 2
const CHECK_EVERY_S := 6 * 3600
const NAG_FILE := "user://app_update.cfg"
const Endpoint := preload("res://online_v020/endpoint.gd")

var stage
var info := {}
var _http: HTTPRequest
var _checked_at := -1.0e12
var dialog: ConfirmationDialog
var _required := false

func _ready():
	name = "AppUpdate"
	if preload("res://telemetry/app_track.gd").platform().is_empty():
		return
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	add_child(_http)
	_http.request_completed.connect(_on_reply)
	check.call_deferred()

static func http_base(ws_url: String) -> String:
	var s := ws_url.strip_edges()
	if s.begins_with("wss://"): s = "https://" + s.substr(6)
	elif s.begins_with("ws://"): s = "http://" + s.substr(5)
	else: return ""
	var slash := s.find("/", s.find("//") + 2)
	return s.substr(0, slash) if slash > 0 else s

func check() -> void:
	if _http == null: return
	var base := http_base(Endpoint.server_url())
	if base.is_empty(): return
	_checked_at = Time.get_unix_time_from_system()
	_http.cancel_request()
	_http.request(base + "/app-version")

func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_RESUMED or _http == null: return
	if _required: _show()   # obrigatória: volta a pedir
	elif Time.get_unix_time_from_system() - _checked_at > CHECK_EVERY_S: check()

func _on_reply(result: int, code: int, _h, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var r = JSON.parse_string(body.get_string_from_utf8())
	var plat := String(preload("res://telemetry/app_track.gd").platform())
	if not r is Dictionary or not r.get(plat) is Dictionary: return
	info = r[plat]
	var d := decide(APP_CODE, info)
	if d == "": return
	_required = d == "required"
	if not _required and not _should_nag(int(info.get("latest", 0))): return
	_show()

## "" (em dia), "optional" ou "required"
static func decide(app_code: int, a: Dictionary) -> String:
	var latest := int(a.get("latest", 0))
	var minimum := int(a.get("min", 0))
	var url := String(a.get("url", ""))
	if not url.begins_with("https://"): return ""
	if app_code < minimum: return "required"
	if app_code < latest: return "optional"
	return ""

func _should_nag(latest: int) -> bool:
	var f := ConfigFile.new()
	f.load(NAG_FILE)
	var day := Time.get_date_string_from_system()
	if int(f.get_value("nag", "code", 0)) == latest and String(f.get_value("nag", "day", "")) == day: return false
	f.set_value("nag", "code", latest)
	f.set_value("nag", "day", day)
	f.save(NAG_FILE)
	return true

func _show() -> void:
	if not is_inside_tree(): return
	if dialog == null:
		dialog = ConfirmationDialog.new()
		dialog.name = "AppUpdateDialog"
		dialog.title = "FRAIHA XADREZ"
		dialog.ok_button_text = "ATUALIZAR"
		dialog.cancel_button_text = "Depois"
		dialog.exclusive = false
		if stage != null and stage.has_method("_medieval_dialog_theme"): dialog.theme = stage._medieval_dialog_theme()
		dialog.confirmed.connect(_open_download)
		dialog.canceled.connect(func(): if _required: _show.call_deferred())
		var label := dialog.get_label()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(dialog)
	var nome := String(info.get("name", ""))
	if _required:
		dialog.dialog_text = "Saiu uma versão nova do FRAIHA Xadrez e esta não funciona mais.\n\nToque em ATUALIZAR para baixar e instalar a nova."
	else:
		dialog.dialog_text = "Saiu uma versão nova do FRAIHA Xadrez" + (" (" + nome + ")" if not nome.is_empty() else "") + ".\n\nToque em ATUALIZAR para baixar e instalar."
	dialog.get_cancel_button().visible = not _required
	var vp := get_viewport().get_visible_rect().size
	dialog.min_size = Vector2i(int(minf(vp.x - 40.0, 620.0)), 0)
	dialog.popup_centered()

func _open_download() -> void:
	var url := String(info.get("url", ""))
	if url.begins_with("https://"): OS.shell_open(url)
	if _required: _show.call_deferred()
