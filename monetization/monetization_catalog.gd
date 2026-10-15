extends RefCounted
## MONETIZAÇÃO V1 — catálogo central (Fundador + Club FRAIHA).
##
## Tudo o que muda entre "teste" e "comercial" fica AQUI: modo de pagamento, métodos,
## preços planejados, limite de Fundadores e link do grupo. A interface só lê estes valores.
##
## FRAIHA NÃO É PAY-TO-WIN: nada deste catálogo pode alterar PL, matchmaking, tempo,
## regras, resultado ou chances de vitória. Só identidade, cosméticos, comunidade,
## treinamento, análise, estatísticas, conveniência e conteúdo.

# ---------------------------------------------------------------------------
# Pagamento
# ---------------------------------------------------------------------------
## R39 · "real" = Mercado Pago (PIX + cartão) pelo servidor; "mock" = simulação local de desenvolvimento.
## A build publicada (export RELEASE) é SEMPRE "real"; o editor e os testes (build de depuração) usam "mock".
## Para forçar: variável FRAIHA_PAYMENT_MODE=real|mock ou argumento --pagamento-real / --pagamento-teste.
## Em "real" a interface NÃO ativa nada localmente: quem libera benefício é o servidor (webhook do provedor).
static func payment_mode() -> String:
    var env := OS.get_environment("FRAIHA_PAYMENT_MODE").strip_edges().to_lower()
    if env in ["real", "mock"]: return env
    var args := OS.get_cmdline_user_args()
    if "--pagamento-real" in args: return "real"
    if "--pagamento-teste" in args: return "mock"
    return "mock" if OS.is_debug_build() else "real"
## Ordem de exibição: PIX sempre primeiro (método principal do FRAIHA).
const PAYMENT_METHODS := ["pix", "card"]
const PAYMENT_PIX_ENABLED := true
const PAYMENT_CARD_ENABLED := true
## Ferramentas de desenvolvimento (Resetar monetização, Desativar Club) só existem no modo mock.
static func dev_tools_enabled() -> bool:
    return payment_mode() == "mock"

static func is_mock() -> bool:
    return payment_mode() == "mock"

static func method_enabled(method: String) -> bool:
    if method == "pix": return PAYMENT_PIX_ENABLED
    if method == "card": return PAYMENT_CARD_ENABLED
    return false

static func enabled_methods() -> Array:
    var out := []
    for m in PAYMENT_METHODS:
        if method_enabled(m): out.append(m)
    return out

# ---------------------------------------------------------------------------
# Fundador
# ---------------------------------------------------------------------------
## R103 · Fundador é por TEMPO LIMITADO (sem limite de vagas). O servidor é a autoridade
## (FRAIHA_FOUNDER_UNTIL) e informa no payment_offer: founder_open, founder_until e o número do Fundador.
## R39 · o link do grupo de WhatsApp dos Fundadores só vem do servidor, para quem é Fundador de verdade.
## Dias de Club inclusos em cada pacote (o servidor é quem entrega).
const FOUNDER_CLUB_DAYS := 90
const LEGEND_CLUB_DAYS := 365
## Desconto no PIX (texto). Os valores reais estão em pix_price_cents e no servidor.
const PIX_DISCOUNT_PCT := 10

# ---------------------------------------------------------------------------
# Preços (centavos). TEST = cobrado na simulação; PLANNED = cartão; PIX = com desconto.
# ---------------------------------------------------------------------------
const PRODUCTS := {
    "founder": {
        "name": "PACOTE FUNDADOR",
        "kind": "one_time",
        "club_days": 90,
        "test_price_cents": 0,
        "planned_price_cents": 4990,
        "pix_price_cents": 4490,
    },
    "founder_legend": {
        "name": "FUNDADOR LENDÁRIO",
        "kind": "one_time",
        "club_days": 365,
        "test_price_cents": 0,
        "planned_price_cents": 9990,
        "pix_price_cents": 8990,
    },
    "club_monthly": {
        "name": "CLUB FRAIHA · MENSAL",
        "kind": "pass",
        "club_days": 30,
        "test_price_cents": 0,
        "planned_price_cents": 1990,
        "pix_price_cents": 1790,
    },
    "club_yearly": {
        "name": "CLUB FRAIHA · ANUAL",
        "kind": "pass",
        "club_days": 365,
        "test_price_cents": 0,
        "planned_price_cents": 14990,
        "pix_price_cents": 13490,
    },
}

static func product(id: String) -> Dictionary:
    return PRODUCTS.get(id, {})

static func club_days(id: String) -> int:
    return int(product(id).get("club_days", 0))

## R$ 49,90
static func brl(cents: int) -> String:
    return "R$ %d,%02d" % [cents / 100, cents % 100]

## Preço cobrado agora (teste no modo mock).
static func charge_price(id: String) -> String:
    var p := product(id)
    return brl(int(p.get("test_price_cents", 0)) if is_mock() else int(p.get("planned_price_cents", 0)))

## Preço no cartão.
static func planned_price(id: String) -> String:
    return brl(int(product(id).get("planned_price_cents", 0)))

## Preço no PIX (com desconto).
static func pix_price(id: String) -> String:
    var p := product(id)
    return brl(int(p.get("pix_price_cents", p.get("planned_price_cents", 0))))

static func price_for(id: String, method: String) -> String:
    if is_mock(): return charge_price(id)
    return pix_price(id) if method == "pix" else planned_price(id)

## "R$ 13,490 / ano = R$ 11,24 por mês" → só o valor mensal equivalente do anual no PIX.
static func monthly_equiv(id: String) -> String:
    var p := product(id)
    return brl(int(round(float(p.get("pix_price_cents", 0)) / 12.0)))

## "14/12" (horário de Brasília) a partir de um ISO do servidor (2026-12-15T02:59:59.000Z ou com -03:00).
static func short_date(iso: String) -> String:
    if iso.length() < 10: return ""
    if iso.length() < 19: return "%s/%s" % [iso.substr(8, 2), iso.substr(5, 2)]
    var t := Time.get_unix_time_from_datetime_string(iso.substr(0, 19))
    var tail := iso.substr(19)
    var dot := tail.find(".")
    if dot == 0:
        var i := 1
        while i < tail.length() and tail[i] >= "0" and tail[i] <= "9": i += 1
        tail = tail.substr(i)
    if tail.length() >= 6 and (tail[0] == "+" or tail[0] == "-"):
        var off := int(tail.substr(1, 2)) * 3600 + int(tail.substr(4, 2)) * 60
        t -= off if tail[0] == "+" else -off
    var brt := Time.get_datetime_dict_from_unix_time(t - 3 * 3600)
    return "%02d/%02d" % [brt.day, brt.month]
