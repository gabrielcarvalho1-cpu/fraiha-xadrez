extends Node
## R180 · conta ao servidor em que TELA o jogador está (Admin → Sessões). Só o NOME da tela (ex.: "Loja de Coroas"),
## nada de texto digitado nem posição de clique. Manda quando a tela muda e fica pelo menos 0,6 s nela.
## Também manda uma vez por conexão o aparelho (celular/computador, sistema, navegador, tamanho da tela, versão).
## in_game(): verdadeiro em partida (xadrez, XEQUE, MARCHA, sala online) — o aviso de atualização usa para não atrapalhar.
## R181 · CORREÇÃO: na R180 o envio nunca começava (esperava acct_state/guest_state pelo sinal server_message, que o
## serviço de conta não repassa) → nenhuma tela chegava ao painel. Agora, na Web, telas e CLIQUES vão pelo script do
## site (web/telemetry/fraiha-track.js → POST /t), desde o carregamento e SEM login. Fora da Web: conexão do jogo.
## Cliques: todo botão tocado (nome do botão + tela). Nome = texto do botão; sem texto, a dica ou o nome do nó.
## Nunca o texto digitado (campos de texto não são botões) — e o servidor só aceita nomes que existem no jogo.

const POLL := 0.4
const STABLE := 0.6
const HOME_MODAL := "res://ui_v022/home_modal.gd"
const MOBILE_PAGE := "res://ui_v022/mobile_ref_page.gd"
const ACCOUNT_UI := "res://account/account_ui.gd"
const RESULT_OVERLAY := "res://presentation_v019/game_result_overlay.gd"
const WebTrack := preload("res://telemetry/web_track.gd")
## R181 · telas da conta (pela página aberta)
const ACCOUNT_PAGES := { "login": "Entrada / Login", "signup": "Criar conta", "recover": "Recuperar senha", "new_password": "Nova senha",
	"set_password": "Senha da conta", "nickname": "Escolher apelido", "account": "Sua conta", "waiting": "Conectando conta",
	"unavailable": "Contas indisponíveis", "inapp": "Quase lá (Google no Instagram)" }
const RESULT_NAMES := { "victory": "Vitória", "defeat": "Derrota", "draw": "Empate" }
## telas por script (o caminho do .gd); GAME = é jogo (não interromper)
const LABELS := {
	"res://account/account_ui.gd": "Login / Conta",
	"res://analysis/analysis_ui.gd": "Análise de partida",
	"res://analysis/training_ui.gd": "Treino",
	"res://marcha/marcha_ui.gd": "Marcha Real",
	"res://xeque/xeque_ui.gd": "Xeque",
	"res://ui_v022/party_online_ui.gd": "Mesa online",
	"res://presentation_v019/game_result_overlay.gd": "Resultado da partida",
	"res://bot/reward_modal.gd": "Prêmio do bot",
	"res://monetization/premium_hub.gd": "Seja Membro (Premium)",
	"res://monetization/club_ui.gd": "Clube",
	"res://monetization/my_club_ui.gd": "Meu Clube",
	"res://monetization/founder_ui.gd": "Pacote Fundador",
	"res://monetization/founders_hall_ui.gd": "Salão dos Fundadores",
	"res://monetization/payment_real_ui.gd": "Pagamento",
	"res://monetization/payment_mock_ui.gd": "Pagamento (teste)",
	"res://monetization/personalize_ui.gd": "Personalizar",
	"res://monetization/purchases_ui.gd": "Minhas compras",
	"res://economy/crown_store_ui.gd": "Loja de Coroas",
	"res://economy/crowns_ui.gd": "Coroas",
	"res://economy/missions_ui.gd": "Missões",
	"res://economy/season_pass_ui.gd": "Passe da Temporada",
	"res://economy/tournament_ui.gd": "Torneios",
	"res://economy/creator_ui.gd": "Apoie um Criador",
	"res://social/social_ui.gd": "Amigos",
	"res://social/direct_chat_ui.gd": "Chat Exclusivo",
	"res://social/support_ui.gd": "Suporte",
	"res://profile/avatar_editor.gd": "Editar avatar",
	"res://ui_v022/leaderboard_ui.gd": "Ranking",
	"res://ui_v022/legal_ui.gd": "Termos / Privacidade",
	"res://ui_v022/news_ui.gd": "Novidades",
	"res://ui_v022/global_chat_ui.gd": "Chat global",
	"res://ui_v022/board_colors_ui.gd": "Tabuleiro e peças",
}
const GAME := ["Marcha Real", "Xeque", "Mesa online", "Prêmio do bot"]
const MODES := { "bot": "Partida contra o computador", "local": "Partida local (2 no aparelho)", "online": "Partida online (sala)",
	"online_menu": "Jogar online (sala)", "ranked": "Partida Ranqueada", "ranked_lobby": "Ranqueado (fila)", "casual": "Partida Casual",
	"casual_lobby": "Casual (fila)" }
const MATCH_MODES := ["bot", "local", "online", "ranked", "casual"]
const PAGES := { "main": "Home (Início)", "profile": "Perfil", "settings": "Configurações", "bot": "Escolher bot", "bot_side": "Escolher bot (lado)",
	"history": "Histórico", "ranking": "Ligas", "about": "Conheça o FRAIHA" }

var stage
var account
var _nodes: Array = []      # [WeakRef, ordem]
var _order := 0
var _acc := 0.0
var _sent := ""             # última tela aceita pelo servidor nesta conexão
var _cand := ""
var _cand_t := 0.0
var current := ""           # tela atual (mesmo sem servidor)
var _ready_id := false      # conexão com identidade (acct_state com perfil / guest_state)

func setup(p_stage, p_account):
	WebTrack.boot()
	stage = p_stage
	account = p_account
	get_tree().node_added.connect(_on_node)
	_scan(get_tree().root)
	if account != null and account.has_signal("server_message"):
		account.server_message.connect(_on_server)

func _scan(n: Node):
	_on_node(n)
	for c in n.get_children(): _scan(c)

func _script_path(n: Node) -> String:
	var s = n.get_script()
	return s.resource_path if s is Script else ""

func _is_modal(n: Node) -> bool:
	var s = n.get_script()
	while s is Script:
		if s.resource_path == HOME_MODAL: return true
		s = s.get_base_script()
	return false

func _on_node(n: Node):
	if n is BaseButton and not n.has_meta("fx_track"):   # R181 · cliques
		n.set_meta("fx_track", true)
		(n as BaseButton).pressed.connect(_on_click.bind(weakref(n)))
	var p := _script_path(n)
	if p.is_empty(): return
	if LABELS.has(p) or p == MOBILE_PAGE or p == ACCOUNT_UI or p == RESULT_OVERLAY or _is_modal(n):
		_order += 1
		_nodes.append([weakref(n), _order])

static func shown(n: Node) -> bool:
	var x: Node = n
	while x != null:
		if x is CanvasItem and not (x as CanvasItem).visible: return false
		if x is CanvasLayer and not (x as CanvasLayer).visible: return false
		x = x.get_parent()
	return true

## aberta de verdade: muitas telas são CanvasLayer sempre "visível" com o conteúdo escondido
func open_now(n: Node) -> bool:
	if not n.is_inside_tree() or not shown(n): return false
	if n.has_method("is_open"): return bool(n.is_open())
	if n is CanvasLayer:
		for c in n.get_children():
			if c is CanvasItem and (c as CanvasItem).visible: return true
		return false
	return true

func _layer(n: Node) -> int:
	var x: Node = n
	while x != null:
		if x is CanvasLayer: return (x as CanvasLayer).layer
		x = x.get_parent()
	return 0

func _label_of(n: Node) -> String:
	var p := _script_path(n)
	if p == ACCOUNT_UI: return ACCOUNT_PAGES.get(String(n.get("page")), "Login / Conta")
	if p == RESULT_OVERLAY: return RESULT_NAMES.get(String(n.get("result")), "Resultado da partida")
	if LABELS.has(p): return LABELS[p]
	if p == MOBILE_PAGE:
		var id := String(n.get("page_id"))
		return PAGES.get(id, id.capitalize()) if not id.is_empty() else ""
	var t = n.get("title_label")
	if t is Label and not (t as Label).text.strip_edges().is_empty():
		return "Janela: " + (t as Label).text.strip_edges().capitalize()
	return ""

## a tela em cima de tudo agora
func compute() -> String:
	var best := ""
	var best_key := -INF
	var keep: Array = []
	for e in _nodes:
		var n = e[0].get_ref()
		if n == null or not is_instance_valid(n): continue
		keep.append(e)
		if not open_now(n): continue
		var l := _label_of(n)
		if l.is_empty(): continue
		var key := float(_layer(n)) * 100000.0 + float(e[1])
		if key > best_key:
			best_key = key
			best = l
	_nodes = keep
	var mode := String(stage.get("mode")) if stage != null else "home"
	if MATCH_MODES.has(mode):
		# em partida: a janela de cima só entra como detalhe (ex.: "Partida Ranqueada · Resultado da partida")
		var base: String = MODES.get(mode, mode)
		return base + (" · " + best if not best.is_empty() and best != base else "")
	if not best.is_empty(): return best
	if MODES.has(mode): return MODES[mode]
	var hub = stage.get("hub") if stage != null else null
	if hub != null and hub.get("page") != null:
		var pg := String(hub.get("page"))
		return PAGES.get(pg, pg.capitalize())
	return "Início"

## em partida ou numa mesa (XEQUE / MARCHA / sala online): não interromper
func in_game() -> bool:
	var mode := String(stage.get("mode")) if stage != null else "home"
	if mode != "home": return true
	var c := compute()
	for g in GAME:
		if c.begins_with(g): return true
	return false

func _process(delta):
	_acc += delta
	if _acc < POLL: return
	var dt := _acc
	_acc = 0.0
	var now := compute()
	if now != _cand:
		_cand = now
		_cand_t = 0.0
		return
	_cand_t += dt
	if _cand_t < STABLE: return
	if now != current: WebTrack.screen(now)   # R181 · Web: vai pelo site, com ou sem login
	current = now
	if WebTrack.site_tracking(): return   # R182 · Web e app Android: pelo rastreador da visita (/t)
	var ready_now: bool = account != null and (bool(account.get("server_ready")) or bool(account.get("guest_ready")))
	if ready_now and not _ready_id:   # R181 · antes esperava um sinal que nunca vinha
		_ready_id = true
		_sent = ""
		account.send_server(device_info())
	elif not ready_now: _ready_id = false
	if _ready_id and now != _sent:
		if account != null and account.send_server({"type": "ui_screen", "name": now}): _sent = now

## R181 · nome do botão tocado (texto; sem texto, a dica; sem dica, o nome do nó). Nunca campo de texto.
static func button_label(b: Node) -> String:
	var t := ""
	if b is Button: t = String((b as Button).text)
	t = t.replace("\n", " ").strip_edges()
	if t.is_empty() and b is Control: t = String((b as Control).tooltip_text).strip_edges()
	return t.left(60)

var last_button := ""
func _on_click(ref: WeakRef):
	var b = ref.get_ref()
	if b == null or not is_instance_valid(b): return
	var label := button_label(b)
	var id := String(b.name)
	if id.begins_with("@"): id = ""
	if label.is_empty() and id.is_empty(): return
	last_button = label if not label.is_empty() else id
	WebTrack.click(label, id, current if not current.is_empty() else compute())

func _on_server(msg: Dictionary):
	var t := String(msg.get("type", ""))
	var ok: bool = (t == "acct_state" and msg.get("profile") is Dictionary) or (t == "guest_state" and not msg.get("account", false))
	if not ok: return
	_ready_id = true
	_sent = ""   # conexão nova: o servidor recebe de novo a tela atual
	account.send_server(device_info())

func device_info() -> Dictionary:
	var d := {"type": "ui_hello", "platform": OS.get_name(), "version": _version()}
	var vs := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
	var win := DisplayServer.window_get_size()
	d["w"] = win.x if win.x > 0 else int(vs.x)
	d["h"] = win.y if win.y > 0 else int(vs.y)
	d["mobile"] = stage.mobile_hud_on() if stage != null and stage.has_method("mobile_hud_on") else false
	if OS.has_feature("web"):
		var ua = JavaScriptBridge.eval("navigator.userAgent || ''", true)
		var ua_s := String(ua) if ua != null else ""
		d["device"] = _device(ua_s)
		d["browser"] = _browser(ua_s)
		d["lang"] = String(JavaScriptBridge.eval("navigator.language || ''", true))
		var iw = JavaScriptBridge.eval("window.innerWidth || 0", true)
		var ih = JavaScriptBridge.eval("window.innerHeight || 0", true)
		if iw != null and int(iw) > 0: d["w"] = int(iw)
		if ih != null and int(ih) > 0: d["h"] = int(ih)
		if not d["mobile"]: d["mobile"] = ua_s.contains("Mobi") or ua_s.contains("Android") or ua_s.contains("iPhone") or ua_s.contains("iPad")
	else:
		d["device"] = OS.get_name()
	return d

static func _device(ua: String) -> String:
	if ua.contains("iPhone"): return "iPhone"
	if ua.contains("iPad"): return "iPad"
	if ua.contains("Android"): return "Android"
	if ua.contains("Windows"): return "Windows"
	if ua.contains("Mac OS"): return "Mac"
	if ua.contains("CrOS"): return "Chromebook"
	if ua.contains("Linux"): return "Linux"
	return "?"

static func _browser(ua: String) -> String:
	if ua.contains("Instagram"): return "Instagram (navegador do app)"
	if ua.contains("FBAN") or ua.contains("FBAV"): return "Facebook (navegador do app)"
	if ua.contains("TikTok") or ua.contains("musical_ly"): return "TikTok (navegador do app)"
	if ua.contains("SamsungBrowser"): return "Samsung Internet"
	if ua.contains("Edg/"): return "Edge"
	if ua.contains("OPR/") or ua.contains("Opera"): return "Opera"
	if ua.contains("Firefox/") or ua.contains("FxiOS"): return "Firefox"
	if ua.contains("CriOS") or ua.contains("Chrome/"): return "Chrome"
	if ua.contains("Safari/"): return "Safari"
	return "?"

func _version() -> String:
	var hub = stage.get("hub") if stage != null else null
	if hub != null and hub.get_script() is Script:
		return String(hub.get_script().get_script_constant_map().get("APP_VERSION", ""))
	return ""

## testes: todas as telas registradas que estão visíveis agora (camada, rótulo, nó)
func debug_visible() -> Array:
	var out := []
	for e in _nodes:
		var n = e[0].get_ref()
		if n == null or not is_instance_valid(n) or not open_now(n): continue
		out.append([_layer(n), _label_of(n), str(n.get_path()), n.get_class()])
	return out
