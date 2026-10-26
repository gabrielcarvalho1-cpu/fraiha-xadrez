extends Node
## R194 · COMPRAS PELO GOOGLE PLAY no app Android da Play Store (Club e Pacote Fundador). Só existe na build "play"
## (preset "Android Play", stage.gd cria). O APK do site continua sem compras; o site continua com o Mercado Pago.
## Caminho de cada compra (igual ao do iPhone, monetization/apple_store.gd):
##   buy() → janela do Google Play → "purchased" (token) → payment_google ao servidor → o servidor confere no Google e
##   entrega → payment_google_result → finish: Club é consumido (pode comprar de novo); Fundador o servidor confirma.
##   Sem resposta a compra fica no Google e é reenviada (ao abrir, ao entrar na conta e a cada 30 s): nada se perde.
## Nada de cartão, e-mail ou senha passa por aqui; só ids de produto e o token da compra.

signal prices_changed
signal purchase_finished(product_id: String, ok: bool, message: String)

## produto do FRAIHA → produto cadastrado na Play Console (mesmos ids do servidor, online_v021/payments/google.js)
const GOOGLE_IDS := {
	"club_monthly": "club.mensal",
	"club_yearly": "club.anual",
	"founder": "fundador",
	"founder_legend": "fundador.lendario",
}
const RETRY_S := 30.0

static var instance: Node = null
var account
var plugin = null
var prices := {}
var _waiting := {}      # token → { product: id do FRAIHA, google: id do Google, sent_at }
var _buying := ""
var _retry := 0.0

static func available() -> bool:
	return instance != null and instance.plugin != null

func _ready():
	instance = self
	name = "GoogleStore"
	if Engine.has_singleton("FraihaVoice"):
		var n = Engine.get_singleton("FraihaVoice")
		if n.has_signal("billing_event"):
			plugin = n
			plugin.connect("billing_event", _on_billing)
	if plugin == null: return
	if account != null:
		account.server_message.connect(_on_server)
		account.changed.connect(_on_account_changed)
	plugin.billingProducts(PackedStringArray(GOOGLE_IDS.values()))
	plugin.billingPending()

func _exit_tree():
	if instance == self: instance = null

static func fraiha_id(google_id: String) -> String:
	for k in GOOGLE_IDS:
		if GOOGLE_IDS[k] == google_id: return k
	return ""

func price(product_id: String) -> String:
	return String(prices.get(product_id, ""))

func buy(product_id: String) -> bool:
	if plugin == null or not GOOGLE_IDS.has(product_id): return false
	if account == null or not account.has_profile() or String(account.user_id).is_empty():
		purchase_finished.emit(product_id, false, "Entre na sua conta para comprar.")
		return false
	_buying = product_id
	plugin.billingBuy(GOOGLE_IDS[product_id], String(account.user_id))
	return true

## "restaurar": pede de novo ao Google o que ainda não foi entregue
func restore() -> void:
	if plugin != null: plugin.billingPending()

func _on_account_changed() -> void:
	if plugin != null and account != null and account.has_profile(): plugin.billingPending()
	_flush()

func _on_billing(json: String) -> void:
	var d = JSON.parse_string(json)
	if not d is Dictionary: return
	match String(d.get("ev", "")):
		"products":
			for it in d.get("items", []):
				var pid := fraiha_id(String(it.get("id", "")))
				if pid != "": prices[pid] = String(it.get("price", ""))
			prices_changed.emit()
		"purchased":
			var tok := String(d.get("purchase_token", ""))
			var gid := String(d.get("product_id", ""))
			if tok.is_empty() or _waiting.has(tok): return
			_waiting[tok] = {"product": fraiha_id(gid), "google": gid, "sent_at": -1.0e9}
			_flush()
		"pending":
			_buying = ""
			purchase_finished.emit(fraiha_id(String(d.get("product_id", ""))), false, "Pagamento pendente no Google Play. A compra é entregue assim que for aprovada.")
		"failed":
			var pid2 := _buying if _buying != "" else fraiha_id(String(d.get("product_id", "")))
			_buying = ""
			var code := String(d.get("code", ""))
			if bool(d.get("cancelled", false)): purchase_finished.emit(pid2, false, "")
			elif code == "PRODUCT": purchase_finished.emit(pid2, false, "Este item ainda não está à venda no Google Play.")
			elif code == "OWNED": purchase_finished.emit(pid2, false, "Você já tem este item. Estamos confirmando na sua conta.")
			else: purchase_finished.emit(pid2, false, "O Google Play não concluiu a compra. Nada foi cobrado.")

func _flush() -> void:
	if account == null or not account.has_profile(): return
	var now := Time.get_ticks_msec() / 1000.0
	for tok in _waiting.keys():
		var w: Dictionary = _waiting[tok]
		if now - float(w.sent_at) < RETRY_S: continue
		w.sent_at = now
		account.send_server({"type": "payment_google", "product_id": w.google, "purchase_token": tok})

func _process(delta: float) -> void:
	if _waiting.is_empty(): return
	_retry += delta
	if _retry >= 5.0:
		_retry = 0.0
		_flush()

func _on_server(msg: Dictionary) -> void:
	if String(msg.get("type", "")) != "payment_google_result": return
	var tok := String(msg.get("purchase_token", ""))
	if not _waiting.has(tok): return
	var w: Dictionary = _waiting[tok]
	var pid := String(w.product)
	if bool(msg.get("finish", false)):
		plugin.billingFinish(tok, bool(msg.get("consume", false)))
		_waiting.erase(tok)
		var ok := bool(msg.get("ok", false))
		var text := String(msg.get("message", ""))
		if ok and not bool(msg.get("already", false)): text = "Compra confirmada! Já está na sua conta FRAIHA."
		if ok or not text.is_empty(): purchase_finished.emit(pid, ok, text)
	else:
		w.sent_at = Time.get_ticks_msec() / 1000.0
		if _buying == pid:
			_buying = ""
			purchase_finished.emit(pid, false, String(msg.get("message", "Recebemos a compra; ela será entregue em instantes.")))
