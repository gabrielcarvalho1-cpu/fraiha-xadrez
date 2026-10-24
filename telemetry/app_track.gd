extends Node
## R182 · RASTREAMENTO NO APP ANDROID — o mesmo que web/telemetry/fraiha-track.js faz no site, em GDScript.
## Admin → Sessões/Funil vê o app igual ao site: visitante (código ALEATÓRIO do aparelho, sem dado pessoal), telas,
## cliques, carregamento, login escolhido, partidas, saída. Manda em lotes para POST /t (o mesmo servidor do jogo,
## https://<servidor>/t) com o cabeçalho "x-fraiha-app: android" (o app não tem Origin de navegador).
## Nada digitado: só nomes de tela/botão (o servidor ainda confere contra a lista de nomes do jogo), tempos e códigos.
## Pixel da Meta: não existe no app (sem SDK do Facebook) → px() é ignorado.

const SAVE := "user://fraiha_track.cfg"
const BATCH_S := 4.0
const NEW_VISIT_AFTER_S := 30 * 60     # parado em segundo plano mais que isso = visita nova
const MAX_QUEUE := 200
const MAX_PER_SEND := 40

static var _inst: Node = null

## R184 · app instalado (não navegador): "android" (APK) ou "windows" (executável do PC). "" = Web/editor/testes.
static func platform() -> String:
	if OS.has_feature("editor") or OS.has_feature("web"): return ""
	if OS.has_feature("android"): return "android"
	if OS.has_feature("windows") and OS.has_feature("template"): return "windows"
	return ""

var url := ""
var vid := ""
var sid := ""
var queue: Array = []
var sent_first := false
var last_screen := ""
var last_button := ""
var loaded := false
var gone := false
var paused_at := 0.0
var t0 := 0
var _timer := -1.0
var _busy := false
var _http: HTTPRequest
var _hb := 0.0

## o rastreador do app (cria na 1ª chamada). null fora do Android.
static func get_instance() -> Node:
	if platform().is_empty(): return null
	if _inst != null and is_instance_valid(_inst): return _inst
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return null
	_inst = load("res://telemetry/app_track.gd").new()
	_inst.name = "AppTrack"
	tree.root.add_child.call_deferred(_inst)
	_inst._start()
	return _inst

static func track_url_from(server: String) -> String:
	var s := server.strip_edges()
	if s.begins_with("wss://"): s = "https://" + s.substr(6)
	elif s.begins_with("ws://"): s = "http://" + s.substr(5)
	else: return ""
	var slash := s.find("/", s.find("//") + 2)
	if slash > 0: s = s.substr(0, slash)
	return s + "/t"

static func _hex(n: int) -> String:
	var c := Crypto.new()
	return c.generate_random_bytes(n).hex_encode()

func _start():
	t0 = Time.get_ticks_msec()
	var Endpoint = load("res://online_v020/endpoint.gd")
	url = track_url_from(String(Endpoint.server_url()))
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	vid = String(cfg.get_value("track", "vid", ""))
	if not _is_hex32(vid):
		vid = _hex(16)
		cfg.set_value("track", "vid", vid)
		cfg.save(SAVE)
	sid = _hex(16)
	push({"k": "load", "n": "start"})

static func _is_hex32(s: String) -> bool:
	if s.length() != 32: return false
	for ch in s:
		if not ch in "0123456789abcdef": return false
	return true

func _ready():
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(func(_r, _c, _h, _b): _busy = false; if not queue.is_empty() and _timer < 0.0: _timer = 0.3)
	process_mode = Node.PROCESS_MODE_ALWAYS

func now_ms() -> int:
	return Time.get_ticks_msec() - t0

func push(ev: Dictionary) -> void:
	if ev.is_empty(): return
	ev = ev.duplicate()
	ev["t"] = now_ms()
	var k := String(ev.get("k", ""))
	if k == "screen":
		if String(ev.get("n", "")) == last_screen: return
		last_screen = String(ev.get("n", ""))
	if k == "click":
		last_button = String(ev.get("n", "")) if not String(ev.get("n", "")).is_empty() else String(ev.get("id", ""))
		if String(ev.get("s", "")).is_empty(): ev["s"] = last_screen
	queue.append(ev)
	if queue.size() > MAX_QUEUE: queue = queue.slice(queue.size() - MAX_QUEUE)
	if _timer < 0.0: _timer = 0.05 if k in ["load", "exit"] else BATCH_S

func done() -> void:
	if loaded: return
	loaded = true
	push({"k": "load", "n": "done", "v": snappedf(now_ms() / 1000.0, 0.1)})

func ids() -> Dictionary:
	return {"sid": sid, "vid": vid}

func last() -> Dictionary:
	return {"s": last_screen, "b": last_button}

func body() -> String:
	var n := mini(queue.size(), MAX_PER_SEND)
	var b := {"sid": sid, "vid": vid, "st": now_ms(), "e": queue.slice(0, n)}
	queue = queue.slice(n)
	if not sent_first:
		var size := DisplayServer.window_get_size()
		b["u"] = {"s": "", "c": "", "m": "", "fb": false}
		b["d"] = {"w": size.x, "h": size.y, "lang": OS.get_locale_language(), "app": platform(),
			"os": OS.get_version().get_slice(".", 0), "v": String(ProjectSettings.get_setting("application/config/version", ""))}
	return JSON.stringify(b)

func send() -> void:
	if url.is_empty() or queue.is_empty() or _busy or _http == null: return
	var data := body()
	sent_first = true
	_busy = true
	var err := _http.request(url, PackedStringArray(["content-type: text/plain", "x-fraiha-app: " + platform()]), HTTPClient.METHOD_POST, data)
	if err != OK: _busy = false

func _process(delta: float) -> void:
	if _timer >= 0.0:
		_timer -= delta
		if _timer < 0.0: send()
	_hb += delta
	if _hb >= 60.0:
		_hb = 0.0
		push({"k": "hb"})

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if gone: return
		gone = true
		paused_at = Time.get_unix_time_from_system()
		push({"k": "exit", "s": last_screen, "b": last_button})
		_timer = -1.0
		send()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if not gone: return
		gone = false
		if Time.get_unix_time_from_system() - paused_at > NEW_VISIT_AFTER_S:
			sid = _hex(16)   # visita nova (o servidor já fechou a anterior)
			sent_first = false
			t0 = Time.get_ticks_msec()
			push({"k": "load", "n": "start"})
		else:
			push({"k": "back"})
