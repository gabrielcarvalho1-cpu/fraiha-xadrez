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
## Edição limitada. O servidor é a autoridade (FRAIHA_FOUNDER_LIMIT) e informa as vagas restantes
## (payment_offer); este número é só o texto enquanto a resposta não chega.
const FOUNDER_LIMIT := 100
## R39 · o link do grupo de WhatsApp dos Fundadores NÃO fica mais no jogo: o servidor só o entrega a
## quem é Fundador de verdade (acct_state.founder_perks.whatsapp_url, env FRAIHA_FOUNDER_WHATSAPP_URL).
## Benefício do Fundador: dias de Club inclusos (na V1 apenas simulado).
const FOUNDER_CLUB_DAYS := 30

# ---------------------------------------------------------------------------
# Preços (centavos). TEST = cobrado na simulação; PLANNED = valor comercial futuro.
# ---------------------------------------------------------------------------
const PRODUCTS := {
    "founder": {
        "name": "PACOTE FUNDADOR FRAIHA",
        "kind": "one_time",
        "test_price_cents": 0,
        "planned_price_cents": 4990,
    },
    "club_monthly": {
        "name": "CLUB FRAIHA",
        "kind": "subscription_monthly",
        "test_price_cents": 0,
        "planned_price_cents": 1990,
    },
    # Só vitrine na V1 (não assinável ainda).
    "club_yearly": {
        "name": "CLUB FRAIHA · PLANO ANUAL",
        "kind": "subscription_yearly",
        "test_price_cents": 0,
        "planned_price_cents": 19990,
        "available": false,
    },
}

static func product(id: String) -> Dictionary:
    return PRODUCTS.get(id, {})

## R$ 49,90
static func brl(cents: int) -> String:
    return "R$ %d,%02d" % [cents / 100, cents % 100]

## Preço cobrado agora (teste na V1).
static func charge_price(id: String) -> String:
    var p := product(id)
    return brl(int(p.get("test_price_cents", 0)) if is_mock() else int(p.get("planned_price_cents", 0)))

static func planned_price(id: String) -> String:
    return brl(int(product(id).get("planned_price_cents", 0)))
