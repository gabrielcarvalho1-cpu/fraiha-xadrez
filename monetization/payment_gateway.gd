extends RefCounted
## PAGAMENTOS — ponto único entre a interface e o pagamento (PaymentGateway).
##
## Provedores:
##   • MockPaymentProvider  (PAYMENT_MODE = "mock"): liga a flag dev_mock_* local. Só desenvolvimento.
##   • RealPaymentProvider  (PAYMENT_MODE = "real"): pede ao BACKEND FRAIHA que crie a cobrança no
##     provedor de pagamento (PIX: QR + Copia e Cola; Cartão: checkout hospedado). O cliente NUNCA
##     confirma sozinho: o webhook do provedor → backend → entitlements (Supabase) → acct_state.
##
## Fluxo real (V2):  Godot → payment_create (backend) → provedor → pagamento →
##                   webhook/backend → entitlements → acct_state/acct_entitlements → Godot.
## Nenhuma credencial, chave ou dado de cartão passa pelo Godot.
const Catalog := preload("res://monetization/monetization_catalog.gd")

var state
var account = null
var provider

## Resultado comum: {"ok": bool, "mock": bool, "error": String, "status": String,
##   "charge": {"id","method","qr_code","copy_paste","checkout_url","expires_at"} (real)}
func _init(monetization_state, account_service = null):
    state = monetization_state
    account = account_service
    provider = MockPaymentProvider.new(state) if Catalog.is_mock() else RealPaymentProvider.new(account)

## Inicia (mock: conclui) uma compra/assinatura.
func complete(product_id: String, method: String) -> Dictionary:
    if not Catalog.method_enabled(method):
        return {"ok": false, "mock": Catalog.is_mock(), "error": "method_disabled", "status": "error"}
    return provider.start(product_id, method)

## Estado atual de uma cobrança real (polling/acompanhamento). Mock: sempre "paid".
func status(charge_id: String) -> Dictionary:
    return provider.status(charge_id)

# ============================================================================ provedores
class MockPaymentProvider:
    var state
    func _init(s): state = s
    func start(product_id: String, method: String) -> Dictionary:
        var ok := false
        match product_id:
            "founder": ok = state.mock_activate_founder()
            "club_monthly": ok = state.mock_activate_club()
        return {"ok": ok, "mock": true, "error": "" if ok else "unknown_product", "status": "paid" if ok else "error", "method": method}
    func status(_charge_id: String) -> Dictionary:
        return {"ok": true, "mock": true, "status": "paid"}

class RealPaymentProvider:
    ## Pede ao backend FRAIHA a criação da cobrança. O backend conhece o provedor e as chaves;
    ## o Godot só recebe o que precisa mostrar (QR/Copia e Cola/URL do checkout) e o id.
    var account
    var last_charge := {}
    signal charge_created(charge: Dictionary)
    signal charge_updated(charge: Dictionary)
    func _init(acc):
        account = acc
        if account != null: account.server_message.connect(_on_server)
    func start(product_id: String, method: String) -> Dictionary:
        if account == null or not account.has_profile() or not account.server_ready:
            return {"ok": false, "mock": false, "error": "auth_required", "status": "error"}
        if not account.send_server({"type": "payment_create", "product_id": product_id, "method": method}):
            return {"ok": false, "mock": false, "error": "offline", "status": "error"}
        # Resposta assíncrona: payment_charge (charge_created) → payment_update (charge_updated).
        return {"ok": true, "mock": false, "error": "", "status": "pending", "method": method}
    func status(charge_id: String) -> Dictionary:
        if account != null: account.send_server({"type": "payment_status", "charge_id": charge_id})
        return last_charge if String(last_charge.get("id", "")) == charge_id else {"status": "unknown"}
    func _on_server(msg: Dictionary):
        var t := String(msg.get("type", ""))
        if t == "payment_charge":
            last_charge = msg.get("charge", {})
            charge_created.emit(last_charge)
        elif t == "payment_update":
            last_charge = msg.get("charge", {})
            charge_updated.emit(last_charge)
