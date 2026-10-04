# Pagamentos reais — Mercado Pago (PIX + cartão) · R39

## Como funciona
1. O jogador escolhe Pacote Fundador ou Club FRAIHA e a forma de pagamento (PIX ou cartão).
2. O **servidor** cria a cobrança no Mercado Pago com o Access Token (que só existe no Render):
   - **PIX**: `POST /v1/payments` → QR Code + PIX Copia e Cola (validade de 30 min por padrão).
   - **Cartão**: Checkout Pro (`POST /checkout/preferences`) → o jogo abre a página segura do Mercado Pago.
3. O Mercado Pago avisa o servidor em `POST /webhooks/payments`. O servidor confere a assinatura
   (`x-signature`), **consulta o pagamento na API** e só libera se status = aprovado, valor e moeda (BRL)
   iguais ao preço. Se o aviso atrasar, o botão **JÁ PAGUEI** faz o servidor consultar o Mercado Pago.
4. Liberado → tabela `entitlements` (Supabase) → o jogo recebe na hora (`acct_state`) e mostra as boas-vindas.

O jogo nunca vê chave, segredo nem dado de cartão. O cliente nunca confirma pagamento sozinho.

## Regras
| Situação | O que acontece |
|---|---|
| PIX/cartão aprovado | Fundador: selo, título, avatar, moldura, universo + 30 dias de Club. Club: +30 dias (somados ao que resta). |
| Mesmo aviso repetido | Nada muda (cada pagamento libera uma vez só). |
| Cartão recusado | O pedido continua aberto (o jogador pode tentar outro cartão no mesmo checkout). |
| PIX expirado/cancelado | Pedido fica `cancelled`; nada liberado. |
| Reembolso ou contestação (chargeback) | Pedido vira `refunded` e o direito é **retirado** (precisa da migração **0010**). |
| Valor diferente do preço | **Não** libera (fica registrado no log do servidor). |
| Fundador já comprado | Não compra de novo. |
| Vagas de Fundador | `FRAIHA_FOUNDER_LIMIT` (padrão 100); o jogo mostra "RESTAM X VAGAS" e "VAGAS ESGOTADAS". |
| Club | 30 dias por compra, **sem renovação automática**; o jogo avisa quando faltam ≤ 5 dias e tem RENOVAR · +30 DIAS. |

## Configurar (uma vez)
### 1. Mercado Pago (painel de desenvolvedor: Suas integrações)
1. Crie uma aplicação (produto: **Pagamentos online / Checkout Pro + Checkout Transparente**).
2. **Credenciais de produção** → copie o **Access Token** (`APP_USR-…`). Para testar antes, use as **credenciais de teste**.
3. **Webhooks** → URL: `https://<seu-servidor-render>/webhooks/payments` → evento **Pagamentos** →
   salve e copie a **Assinatura secreta**.
4. Habilite o PIX na conta (chave PIX cadastrada) — sem chave PIX o Mercado Pago recusa cobranças PIX.

### 2. Render (serviço do servidor → Environment). **Nunca** cole estes valores no chat nem no código.
| Variável | Valor |
|---|---|
| `FRAIHA_PAYMENT_PROVIDER` | `mercadopago` |
| `FRAIHA_MP_ACCESS_TOKEN` | Access Token (produção ou teste) |
| `FRAIHA_MP_WEBHOOK_SECRET` | Assinatura secreta dos Webhooks |
| `FRAIHA_PUBLIC_URL` | `https://<seu-servidor-render>` (sem barra no fim) |
| `FRAIHA_GAME_URL` | `https://jogar.fraihaxadrez.com` (volta do checkout do cartão) |
| `FRAIHA_FOUNDER_LIMIT` | `100` (opcional) |
| `FRAIHA_FOUNDER_WHATSAPP_URL` | link do grupo dos Fundadores (só vai para quem é Fundador) |
| `FRAIHA_PIX_MINUTES` | `30` (opcional) |

### 3. Supabase
Migrações necessárias: **0005** (entitlements/payments), **0007** (liberar direito) e **0010** (reembolso).
Aplicar só com autorização — o banco é o mesmo de staging e produção.

## Testar sem dinheiro de verdade
- `node tests/server/mercadopago_test.cjs` — servidor contra um Mercado Pago falso (27 verificações).
- `tests/run_payment_client.sh` — o jogo com pagamento real contra o Mercado Pago falso.
- Com as **credenciais de teste** do Mercado Pago no Render de staging, dá para pagar com os usuários e
  cartões de teste do próprio Mercado Pago.

## Modo do jogo
- Build publicada (export RELEASE): **pagamento real**.
- Editor / testes (build de depuração): simulação (botões "SIMULAR…", R$ 0,00).
- Forçar: `FRAIHA_PAYMENT_MODE=real|mock` ou `--pagamento-real` / `--pagamento-teste`.
