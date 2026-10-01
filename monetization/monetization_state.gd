extends RefCounted
## MONETIZAÇÃO V1 — estado de TESTE (simulação local).
##
## Guarda SOMENTE flags de desenvolvimento, num arquivo próprio e com prefixo dev_mock_:
##   dev_mock_founder, dev_mock_club, dev_mock_founder_club_trial
## Elas NUNCA representam compra real e não podem liberar benefício real.
##
## Os campos reais futuros (is_founder, club_active, club_expires_at) virão do
## backend/Supabase na Monetização V2. Este arquivo não os cria nem os lê; os
## métodos real_*() abaixo existem só para deixar a separação explícita.
signal changed

const Catalog := preload("res://monetization/monetization_catalog.gd")
const SAVE_PATH := "user://dev_monetization_mock.cfg"
const SECTION := "dev_mock"

var dev_mock_founder := false
var dev_mock_club := false
## Benefício simulado "30 dias de Club" recebido ao ativar o Fundador mock.
var dev_mock_founder_club_trial := false
var save_path := SAVE_PATH

func _init(path := SAVE_PATH):
    save_path = path
    load_state()

func load_state():
    var cfg := ConfigFile.new()
    if cfg.load(save_path) != OK:
        dev_mock_founder = false
        dev_mock_club = false
        dev_mock_founder_club_trial = false
        return
    dev_mock_founder = bool(cfg.get_value(SECTION, "dev_mock_founder", false))
    dev_mock_club = bool(cfg.get_value(SECTION, "dev_mock_club", false))
    dev_mock_founder_club_trial = bool(cfg.get_value(SECTION, "dev_mock_founder_club_trial", false))

func _save():
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, "dev_mock_founder", dev_mock_founder)
    cfg.set_value(SECTION, "dev_mock_club", dev_mock_club)
    cfg.set_value(SECTION, "dev_mock_founder_club_trial", dev_mock_founder_club_trial)
    cfg.save(save_path)
    changed.emit()

# ----- Simulação (só funciona em PAYMENT_MODE == "mock") -----
func mock_activate_founder() -> bool:
    if not Catalog.is_mock(): return false
    dev_mock_founder = true
    dev_mock_founder_club_trial = true
    _save()
    return true

func mock_activate_club() -> bool:
    if not Catalog.is_mock(): return false
    dev_mock_club = true
    _save()
    return true

func mock_deactivate_club() -> bool:
    if not Catalog.is_mock(): return false
    dev_mock_club = false
    _save()
    return true

## RESETAR MONETIZAÇÃO DE TESTE: limpa todas as flags dev_mock_*.
func mock_reset() -> bool:
    if not Catalog.dev_tools_enabled(): return false
    dev_mock_founder = false
    dev_mock_club = false
    dev_mock_founder_club_trial = false
    _save()
    return true

# ----- Leitura para a interface (estado de TESTE) -----
func founder_view() -> bool:
    return Catalog.is_mock() and dev_mock_founder

func club_subscription_view() -> bool:
    return Catalog.is_mock() and dev_mock_club

func founder_trial_view() -> bool:
    return Catalog.is_mock() and dev_mock_founder_club_trial

## "nenhum" | "fundador" | "club" | "fundador+club"
func summary() -> String:
    var f := founder_view()
    var c := club_subscription_view()
    if f and c: return "fundador+club"
    if f: return "fundador"
    if c: return "club"
    return "nenhum"

# ----- Reservado para a V2: fonte oficial = backend. Nunca derivar do mock. -----
func real_is_founder() -> bool:
    return false

func real_club_active() -> bool:
    return false
