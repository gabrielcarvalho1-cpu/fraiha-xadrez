extends Node
## R161 · NOVIDADES: o que o dono publica no Admin (atualizações, notícias, campeonatos, eventos) e a frase
## do "outdoor" embaixo da logo da Home. Vem do servidor por HTTP (GET /news, público: convidado também vê).
## Sem servidor / sem a tabela: a faixa mostra a frase original da arte e a tela diz que não há novidades.
signal changed

const KINDS := [["atualizacao", "ATUALIZAÇÕES"], ["noticia", "NOTÍCIAS"], ["campeonato", "CAMPEONATOS"], ["evento", "EVENTOS"]]
const DEFAULT_BANNER := "ESTRATÉGIA PARA IR MAIS LONGE"
const REFRESH_S := 300.0

var items: Array = []          # [{id, kind, title, body, published_at, button_label, button_action, pinned}]
var banners: Array = []        # frases do outdoor (na ordem); vazio = frase da arte
var loaded := false
var _http: HTTPRequest
var _left := 0.0
var _busy := false

func _ready():
	name = "NewsFeed"
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	add_child(_http)
	_http.request_completed.connect(_done)
	fetch()

func _process(d: float):
	_left -= d
	if _left <= 0.0: fetch()

static func http_base() -> String:
	var u := String(preload("res://online_v020/endpoint.gd").server_url())
	if u.is_empty(): return ""
	u = u.replace("wss://", "https://").replace("ws://", "http://")
	while u.ends_with("/"): u = u.substr(0, u.length() - 1)
	return u

func fetch():
	_left = REFRESH_S
	if _busy: return
	var base := http_base()
	if base.is_empty(): return
	_busy = true
	if _http.request(base + "/news") != OK: _busy = false

func _done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary: return
	apply(d)

## Também usado pelos testes (sem rede).
func apply(d: Dictionary):
	items = (d.get("items", []) as Array).filter(func(x): return x is Dictionary) if d.get("items") is Array else []
	banners = []
	if d.get("banners") is Array:
		for b in d.banners:
			var t := String(b).strip_edges()
			if not t.is_empty(): banners.append(t)
	loaded = true
	changed.emit()

func banner_texts() -> Array:
	return banners if not banners.is_empty() else [DEFAULT_BANNER]

func of_kind(kind: String) -> Array:
	return items.filter(func(x): return String(x.get("kind", "")) == kind)

## Data "2026-10-20T..." → "20/10/2026"
static func date_br(iso: String) -> String:
	if iso.length() < 10: return ""
	return "%s/%s/%s" % [iso.substr(8, 2), iso.substr(5, 2), iso.substr(0, 4)]
