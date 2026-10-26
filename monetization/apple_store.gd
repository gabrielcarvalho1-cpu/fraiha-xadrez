extends Node
## R192 · COMPRAS PELA APPLE no app de iPhone (Club e Pacote Fundador). Só existe no iPhone (stage.gd cria).
## No site e no Android continua o Mercado Pago; aqui a Apple cobra pelo StoreKit (plugin nativo FraihaVoice).
## Caminho de cada compra:
##   buy() → janela da Apple → "purchased" (transação) → payment_apple ao servidor → o servidor confere com a Apple e
##   entrega → payment_apple_result → finish: o app avisa a Apple que entregou (iapFinish). Sem resposta do servidor a
##   compra fica na fila da Apple e é reenviada (ao abrir o app, ao entrar na conta e a cada 30 s): nada se perde.
## Nada de cartão, e-mail ou senha passa por aqui; só ids de produto e de transação.

signal prices_changed
signal purchase_finished(product_id: String, ok: bool, message: String)

## produto do FRAIHA → produto cadastrado na App Store Connect (mesmos ids do servidor, online_v021/payments/apple.js)
const APPLE_IDS := {
	"club_monthly": "com.fraihaxadrez.app.club.mensal",
	"club_yearly": "com.fraihaxadrez.app.club.anual",
	"founder": "com.fraihaxadrez.app.fundador",
	"founder_legend": "com.fraihaxadrez.app.fundador.lendario",
}
const RETRY_S := 30.0

static var instance: Node = null
var account
var plugin = null
var prices := {}          # produto FRAIHA → preço da Apple já formatado ("R$ 19,90")
var _waiting := {}        # id que vai ao servidor → { local: id da transação na fila da Apple, product, sent_at }
var _buying := ""
var _retry := 0.0

static func available() -> bool:
	return instance != null and instance.plugin != null

func _ready():
	instance = self
	name = "AppleStore"
	if Engine.has_singleton("FraihaVoice"):
		var n = Engine.get_singleton("FraihaVoice")
		if n.has_signal("iap_event"):
			plugin = n
			plugin.connect("iap_event", _on_iap)
	if plugin == null: return
	if account != null:
		account.server_message.connect(_on_server)
		account.changed.connect(_flush)
	plugin.iapProducts(PackedStringArray(APPLE_IDS.values()))
	plugin.iapPending()

func _exit_tree():
	if instance == self: instance = null

static func fraiha_id(apple_id: String) -> String:
	for k in APPLE_IDS:
		if APPLE_IDS[k] == apple_id: return k
	return ""

func price(product_id: String) -> String:
	return String(prices.get(product_id, ""))

## Abre a janela de compra da Apple. Precisa de conta (convidado não compra: a compra fica presa à conta).
func buy(product_id: String) -> bool:
	if plugin == null or not APPLE_IDS.has(product_id): return false
	if account == null or not account.has_profile() or String(account.user_id).is_empty():
		purchase_finished.emit(product_id, false, "Entre na sua conta para comprar.")
		return false
	if not plugin.iapCanPay():
		purchase_finished.emit(product_id, false, "As compras estão bloqueadas neste iPhone (Ajustes › Tempo de Uso).")
		return false
	_buying = product_id
	plugin.iapBuy(APPLE_IDS[product_id], String(account.user_id))
	return true

func restore() -> void:
	if plugin != null: plugin.iapRestore()

func _on_iap(json: String) -> void:
	var d = JSON.parse_string(json)
	if not d is Dictionary: return
	match String(d.get("ev", "")):
		"products":
			for it in d.get("items", []):
				var pid := fraiha_id(String(it.get("id", "")))
				if pid != "": prices[pid] = String(it.get("price", ""))
			prices_changed.emit()
		"purchased":
			var server_id := String(d.get("server_id", ""))
			if server_id.is_empty(): return
			_waiting[server_id] = {"local": String(d.get("transaction_id", "")), "product": fraiha_id(String(d.get("product_id", ""))), "sent_at": -1.0e9}
			_flush()
		"failed":
			var pid2 := fraiha_id(String(d.get("product_id", "")))
			_buying = ""
			if bool(d.get("cancelled", false)): purchase_finished.emit(pid2, false, "")
			elif String(d.get("code", "")) == "PRODUCT": purchase_finished.emit(pid2, false, "Este item ainda não está à venda na App Store.")
			else: purchase_finished.emit(pid2, false, "A Apple não concluiu a compra. Nada foi cobrado.")
		"deferred":
			_buying = ""
			purchase_finished.emit(fraiha_id(String(d.get("product_id", ""))), false, "Compra aguardando a aprovação do responsável.")
		"restore_done":
			if _waiting.is_empty(): purchase_finished.emit("", true, "Suas compras já estão na sua conta FRAIHA.")
		"restore_failed":
			purchase_finished.emit("", false, "Não foi possível restaurar agora. Tente de novo.")

## manda ao servidor o que a Apple já cobrou e ainda não foi confirmado (no máximo 1 vez a cada 30 s por compra)
func _flush() -> void:
	if account == null or not account.has_profile(): return
	var now := Time.get_ticks_msec() / 1000.0
	for sid in _waiting.keys():
		var w: Dictionary = _waiting[sid]
		if now - float(w.sent_at) < RETRY_S: continue
		w.sent_at = now
		account.send_server({"type": "payment_apple", "transaction_id": sid})

func _process(delta: float) -> void:
	if _waiting.is_empty(): return
	_retry += delta
	if _retry >= 5.0:
		_retry = 0.0
		_flush()

func _on_server(msg: Dictionary) -> void:
	if String(msg.get("type", "")) != "payment_apple_result": return
	var sid := String(msg.get("transaction_id", ""))
	if not _waiting.has(sid): return
	var w: Dictionary = _waiting[sid]
	var pid := String(msg.get("product_id", w.product))
	if bool(msg.get("finish", false)):
		plugin.iapFinish(String(w.local))
		_waiting.erase(sid)
		var ok := bool(msg.get("ok", false))
		var text := String(msg.get("message", ""))
		if ok and not bool(msg.get("already", false)): text = "Compra confirmada! Já está na sua conta FRAIHA."
		if ok or not text.is_empty(): purchase_finished.emit(pid, ok, text)
	else:
		# ainda não deu (servidor sem a chave, Apple fora do ar, outra conta): a compra continua guardada na Apple
		w.sent_at = Time.get_ticks_msec() / 1000.0
		if _buying == pid:
			_buying = ""
			purchase_finished.emit(pid, false, String(msg.get("message", "Recebemos a compra; ela será entregue em instantes.")))
