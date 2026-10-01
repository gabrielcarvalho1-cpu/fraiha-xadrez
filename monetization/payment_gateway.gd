extends RefCounted
## MONETIZAÇÃO V1 — ponto único entre a interface e o pagamento.
##
## A interface chama sempre complete(product_id, method). Hoje (PAYMENT_MODE = "mock")
## isso só liga a flag dev_mock_* local. Na V2 ("real") este arquivo passa a criar o
## pedido no backend (PIX: QR + Copia e Cola; Cartão: checkout do provedor) e quem
## confirma é o webhook no servidor — o cliente nunca libera benefício real sozinho.
const Catalog := preload("res://monetization/monetization_catalog.gd")

var state

func _init(monetization_state):
    state = monetization_state

## Retorna {"ok": bool, "mock": bool, "error": String}
func complete(product_id: String, method: String) -> Dictionary:
    if not Catalog.method_enabled(method):
        return {"ok": false, "mock": Catalog.is_mock(), "error": "method_disabled"}
    if not Catalog.is_mock():
        # V2: iniciar checkout real no backend. Não implementado nesta fase.
        return {"ok": false, "mock": false, "error": "real_payment_not_implemented"}
    var ok := false
    match product_id:
        "founder": ok = state.mock_activate_founder()
        "club_monthly": ok = state.mock_activate_club()
    return {"ok": ok, "mock": true, "error": "" if ok else "unknown_product"}
