'use strict';
// PAGAMENTOS (arquitetura preparada — V2). Nenhum provedor está configurado nesta fase.
//
// Fluxo real:
//   Godot  --payment_create-->  este serviço  --createCharge-->  provedor (PIX/cartão)
//   Godot  <--payment_charge--  (QR + Copia e Cola / URL do checkout; NUNCA chaves)
//   provedor  --webhook HTTP /webhooks/payments-->  verifyWebhook  --> entitlements (Supabase)
//   Godot  <--acct_entitlements--  (club_active / is_founder vindos do banco)
//
// Regras: o cliente nunca confirma pagamento; nenhuma credencial fica no Godot; nada de número
// de cartão/CVV passa pelo FRAIHA (checkout hospedado do provedor). Provedor via env:
//   FRAIHA_PAYMENT_PROVIDER = "" (nenhum) | "mercadopago" | "stripe" | "pagarme" | ...
//   + as chaves do provedor em env (nunca no repositório).
const PRODUCTS = {
  founder:      { kind: 'one_time',  amount_cents: 4990,  title: 'Pacote Fundador FRAIHA' },
  club_monthly: { kind: 'subscription', amount_cents: 1990, title: 'Club FRAIHA (mensal)' },
};
const METHODS = ['pix', 'card'];

class NoProvider {
  constructor() { this.name = 'none'; }
  async createCharge() { const e = new Error('Nenhum provedor de pagamento configurado (FRAIHA_PAYMENT_PROVIDER).'); e.code = 'provider_not_configured'; throw e; }
  async verifyWebhook() { return null; }
}

// Interface que um provedor real deve implementar (ver docs/PAGAMENTOS.md):
//   createCharge({ userId, productId, method, amountCents, title })
//     → { id, method, status:'pending', qr_code?, copy_paste?, checkout_url?, expires_at? }
//   verifyWebhook(req, rawBody) → { providerRef, status:'paid'|'failed'|'refunded'|'cancelled', userId?, productId? } | null
function createProvider(env = process.env) {
  const name = String(env.FRAIHA_PAYMENT_PROVIDER || '').toLowerCase();
  if (!name) return new NoProvider();
  try { return require('./providers/' + name).create(env); }
  catch (e) { if (e.code === 'MODULE_NOT_FOUND') return new NoProvider(); throw e; }
}

class Payments {
  constructor({ send, backend, env = process.env }) {
    this.send = send; this.backend = backend; this.provider = createProvider(env);
  }
  get store() { return this.backend.store; }
  fail(ws, message, code) { this.send(ws, { type: 'payment_error', message, code }); }
  async handle(ws, m) {
    const a = String(m.type || '');
    if (!ws.user || !ws.profile) return this.fail(ws, 'Entre na sua conta para assinar ou comprar.', 'auth_required');
    if (a === 'payment_create') {
      const productId = String(m.product_id || ''), method = String(m.method || '');
      const product = PRODUCTS[productId];
      if (!product || !METHODS.includes(method)) return this.fail(ws, 'Produto ou forma de pagamento inválidos.', 'bad_request');
      try {
        const charge = await this.provider.createCharge({ userId: ws.user.id, productId, method, amountCents: product.amount_cents, title: product.title });
        if (this.store.createPayment) await this.store.createPayment({ user_id: ws.user.id, product_id: productId, method, provider: this.provider.name, provider_ref: charge.id, amount_cents: product.amount_cents, status: 'pending' });
        return this.send(ws, { type: 'payment_charge', charge: { ...charge, product_id: productId } });
      } catch (e) {
        if (e.code === 'provider_not_configured') return this.fail(ws, 'Pagamento real ainda não configurado neste servidor.', 'provider_not_configured');
        console.error('payment_create', e && e.message);
        return this.fail(ws, 'Erro ao iniciar o pagamento. Tente novamente.', 'server_error');
      }
    }
    if (a === 'payment_status') {
      const ref = String(m.charge_id || '');
      const row = this.store.getPayment ? await this.store.getPayment(this.provider.name, ref) : null;
      return this.send(ws, { type: 'payment_update', charge: row ? { id: ref, status: row.status, product_id: row.product_id } : { id: ref, status: 'unknown' } });
    }
    return this.fail(ws, 'Ação de pagamento desconhecida.', 'bad_request');
  }
  // Webhook HTTP do provedor. Verifica a assinatura (provedor), marca o pagamento e libera o direito.
  async webhook(req, rawBody) {
    const ev = await this.provider.verifyWebhook(req, rawBody);
    if (!ev) return { status: 400, body: 'invalid' };
    if (this.store.markPayment) {
      const paid = await this.store.markPayment(this.provider.name, ev.providerRef, ev.status);
      if (paid && ev.status === 'paid' && this.store.grantEntitlement) await this.store.grantEntitlement(paid.user_id, paid.product_id, this.provider.name);
      if (paid) for (const ws of this.backend.socketsOf(paid.user_id)) await this.backend.state(ws);
    }
    return { status: 200, body: 'ok' };
  }
}

module.exports = { Payments, PRODUCTS, METHODS, createProvider };
