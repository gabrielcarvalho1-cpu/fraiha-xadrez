extends RefCounted
## Direitos do jogador (Fundador / Club) — ÚNICA porta de leitura para a interface.
##
## Duas fontes, nunca misturadas:
##   • REAL  — vem do servidor (acct_state.entitlements): is_founder, club_active, club_expires_at.
##             O servidor é a autoridade; aqui só fica um cache da última resposta.
##   • MOCK  — flags dev_mock_* do monetization_state (só quando PAYMENT_MODE == "mock").
##
## club_active() responde "o que a interface deve mostrar": real OU (mock, em desenvolvimento).
## Nunca grave o resultado de club_active() como se fosse direito real.
signal changed

const Catalog := preload("res://monetization/monetization_catalog.gd")

var state                      # monetization_state (flags dev_mock_*)
var real := {"is_founder": false, "club_active": false, "club_expires_at": "", "founder_perks": {}}
var real_known := false        # já recebeu entitlements do servidor nesta sessão?

func _init(monetization_state):
    state = monetization_state
    if state != null and state.has_signal("changed"): state.changed.connect(func(): changed.emit())

## Chamado pela conta quando chega acct_state (ou acct_entitlements). Só o servidor alimenta isto.
func apply_server(data: Dictionary):
    real = {
        "is_founder": bool(data.get("is_founder", false)),
        "club_active": bool(data.get("club_active", false)),
        # o servidor manda null quando não há Club: String(null) quebrava e o direito não era aplicado
        "club_expires_at": "" if data.get("club_expires_at") == null else str(data.get("club_expires_at")),
        "founder_perks": data.get("founder_perks") if data.get("founder_perks") is Dictionary else {},
    }
    real_known = true
    changed.emit()

func clear_server():
    real = {"is_founder": false, "club_active": false, "club_expires_at": "", "founder_perks": {}}
    real_known = false
    changed.emit()

# ----- Leitura para a interface -----
func club_active() -> bool:
    if real.club_active: return true
    return Catalog.is_mock() and state != null and (state.club_subscription_view() or state.founder_trial_view())

func founder() -> bool:
    if real.is_founder: return true
    return Catalog.is_mock() and state != null and state.founder_view()

## "server" quando o direito vem do backend; "mock" quando é simulação; "" quando não há direito.
func club_source() -> String:
    if real.club_active: return "server"
    if club_active(): return "mock"
    return ""

func club_expires_at() -> String:
    return String(real.get("club_expires_at", ""))

## R39 · link do grupo dos Fundadores (vem do servidor só para Fundador de verdade; "" se não houver).
func founder_group_url() -> String:
    var perks = real.get("founder_perks", {})
    return String(perks.get("whatsapp_url", "")) if perks is Dictionary else ""

## R39 · dias de Club restantes (servidor); -1 se não houver data.
func club_days_left() -> int:
    var exp := club_expires_at()
    if exp.is_empty() or not real.club_active: return -1
    var unix := Time.get_unix_time_from_datetime_string(exp.substr(0, 19))
    return maxi(0, int(ceil((unix - Time.get_unix_time_from_system()) / 86400.0)))
