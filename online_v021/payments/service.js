'use strict';
// PAGAMENTOS (R39: Mercado Pago, PIX + cartão).
//
// Fluxo real:
//   Godot  --payment_create-->  este serviço  --createCharge-->  provedor (PIX/cartão)
//   Godot  <--payment_charge--  (QR + Copia e Cola / link do checkout; NUNCA chaves)
//   provedor  --webhook HTTP /webhooks/payments-->  consulta o pagamento na API  --> entitlements (Supabase)
//   Godot  <--payment_update + acct_state--  (club_active / is_founder vindos do banco)
//
// Regras: o cliente nunca confirma pagamento; nenhuma credencial fica no Godot; nada de número
// de cartão/CVV passa pelo FRAIHA (checkout hospedado do provedor). Provedor via env:
//   FRAIHA_PAYMENT_PROVIDER = "" (nenhum) | "mercadopago"   (+ chaves em env, ver providers/mercadopago.js)
//   FRAIHA_FOUNDER_LIMIT    = vagas do Pacote Fundador (padrão 100)
//   FRAIHA_FOUNDER_WHATSAPP_URL = link do grupo dos Fundadores (só vai para quem é Fundador de verdade)
const crypto = require('crypto');

const PRODUCTS = {
  founder:      { kind: 'one_time',  amount_cents: 4990,  title: 'Pacote Fundador FRAIHA' },
  club_monthly: { kind: 'subscription', amount_cents: 1990, title: 'Club FRAIHA (30 dias)' },
};
const METHODS = ['pix', 'card'];
const STATUS_POLL_MS = 8000;     // consulta ao provedor quando o jogador pergunta (no máximo 1x a cada 8 s por pedido)

class NoProvider {
  constructor() { this.name = 'none'; }
  ready() { return false; }
  async createCharge() { const e = new Error('Nenhum provedor de pagamento configurado (FRAIHA_PAYMENT_PROVIDER).'); e.code = 'provider_not_configured'; throw e; }
  async verifyWebhook() { return null; }
}

// Interface de um provedor:
//   ready() → bool
//   createCharge({ ref, userId, productId, method, amountCents, title, email })
//     → { id: ref, method, status:'pending', copy_paste?, qr_code_base64?, ticket_url?, checkout_url?, expires_at? }
//   verifyWebhook(req, rawBody) → { ignore:true } | null (inválido) | { providerRef, status, amountCents, currency, providerPaymentId }
//   findByRef(ref) → evento | null   (opcional)
function createProvider(env = process.env) {
  const name = String(env.FRAIHA_PAYMENT_PROVIDER || '').toLowerCase();
  if (!name) return new NoProvider();
  try { return require('./providers/' + name).create(env); }
  catch (e) { if (e.code === 'MODULE_NOT_FOUND') return new NoProvider(); throw e; }
}

class Payments {
  constructor({ send, backend, env = process.env }) {
    this.send = send; this.backend = backend; this.provider = createProvider(env);
    this.founderLimit = Math.max(0, Number(env.FRAIHA_FOUNDER_LIMIT) || 100);
    this.founderGroup = String(env.FRAIHA_FOUNDER_WHATSAPP_URL || '').trim();
    this.lastPoll = new Map();
    if (this.provider.name !== 'none' && this.provider.ready && !this.provider.ready()) console.warn('[pagamentos] provedor ' + this.provider.name + ' sem configuração completa: ' + (this.provider.missing ? this.provider.missing().join(', ') : ''));
  }
  get store() { return this.backend.store; }
  fail(ws, message, code) { this.send(ws, { type: 'payment_error', message, code }); }
  ready() { return this.provider.name !== 'none' && (!this.provider.ready || this.provider.ready()); }

  async foundersCount() {
    try { return this.store.countFounders ? await this.store.countFounders() : 0; } catch (e) { console.error('countFounders', e && e.message); return 0; }
  }
  // O que a loja mostra: provedor pronto?, vagas de Fundador, se já é Fundador.
  async offer(ws) {
    const ent = await this.store.getEntitlements(ws.user.id).catch(() => ({}));
    const sold = await this.foundersCount();
    return { type: 'payment_offer', ready: this.ready(), methods: METHODS.slice(),
      founder_limit: this.founderLimit, founder_remaining: Math.max(0, this.founderLimit - sold),
      is_founder: !!(ent && ent.is_founder), club_active: !!(ent && ent.club_active), club_expires_at: (ent && ent.club_expires_at) || null,
      prices: { founder: PRODUCTS.founder.amount_cents, club_monthly: PRODUCTS.club_monthly.amount_cents } };
  }
  // Extras só para quem é Fundador de verdade (o link do grupo nunca fica no Godot).
  founderPerks(ent) { return ent && ent.is_founder && this.founderGroup ? { whatsapp_url: this.founderGroup } : null; }

  async handle(ws, m) {
    const a = String(m.type || '');
    if (!ws.user || !ws.profile) return this.fail(ws, 'Entre na sua conta para assinar ou comprar.', 'auth_required');
    if (a === 'payment_offer') return this.send(ws, await this.offer(ws));
    if (a === 'payment_create') {
      const productId = String(m.product_id || ''), method = String(m.method || '');
      const product = PRODUCTS[productId];
      if (!product || !METHODS.includes(method)) return this.fail(ws, 'Produto ou forma de pagamento inválidos.', 'bad_request');
      if (!this.ready()) return this.fail(ws, 'Pagamento real ainda não configurado neste servidor.', 'provider_not_configured');
      if (!ws.user.email) return this.fail(ws, 'Sua conta precisa de um e-mail para o recibo do pagamento.', 'email_required');
      if (productId === 'founder') {
        const ent = await this.store.getEntitlements(ws.user.id).catch(() => ({}));
        if (ent && ent.is_founder) return this.fail(ws, 'Você já é Fundador do Reino. Obrigado!', 'already_founder');
        if (await this.foundersCount() >= this.founderLimit) return this.fail(ws, 'As vagas do Pacote Fundador se esgotaram.', 'founder_sold_out');
      }
      const ref = crypto.randomUUID();
      try {
        if (this.store.createPayment) await this.store.createPayment({ user_id: ws.user.id, product_id: productId, method, provider: this.provider.name, provider_ref: ref, amount_cents: product.amount_cents, status: 'pending' });
        const charge = await this.provider.createCharge({ ref, userId: ws.user.id, productId, method, amountCents: product.amount_cents, title: product.title, email: ws.user.email });
        return this.send(ws, { type: 'payment_charge', charge: { ...charge, id: ref, product_id: productId, amount_cents: product.amount_cents } });
      } catch (e) {
        if (this.store.markPayment) await this.store.markPayment(this.provider.name, ref, 'failed').catch(() => {});
        if (e.code === 'provider_not_configured') return this.fail(ws, 'Pagamento real ainda não configurado neste servidor.', 'provider_not_configured');
        console.error('payment_create', e && e.message);
        return this.fail(ws, 'Não foi possível iniciar o pagamento agora. Tente novamente em instantes.', 'server_error');
      }
    }
    if (a === 'payment_status') {
      const ref = String(m.charge_id || '');
      let row = this.store.getPayment ? await this.store.getPayment(this.provider.name, ref) : null;
      if (!row || row.user_id !== ws.user.id) return this.send(ws, { type: 'payment_update', charge: { id: ref, status: 'unknown' } });
      // Webhook atrasado/perdido: pergunta ao provedor (com limite de frequência).
      if (row.status === 'pending' && this.provider.findByRef && Date.now() - (this.lastPoll.get(ref) || 0) > STATUS_POLL_MS) {
        this.lastPoll.set(ref, Date.now());
        try { const ev = await this.provider.findByRef(ref); if (ev && ev.providerRef === ref) await this.apply(ev); }
        catch (e) { console.error('payment_status poll', e && e.message); }
        row = await this.store.getPayment(this.provider.name, ref) || row;
      }
      return this.send(ws, { type: 'payment_update', charge: { id: ref, status: row.status, product_id: row.product_id } });
    }
    return this.fail(ws, 'Ação de pagamento desconhecida.', 'bad_request');
  }

  // Aplica um evento do provedor (webhook ou consulta). Idempotente: cada transição acontece uma vez.
  //   pending → paid       : confere valor e moeda, libera o direito
  //   pending → cancelled  : PIX expirado / cobrança cancelada
  //   paid    → refunded   : reembolso ou contestação (chargeback): o direito é retirado
  //   rejected (cartão)    : continua pending (o jogador pode tentar outro cartão no mesmo checkout)
  async apply(ev) {
    const ref = String(ev.providerRef || '');
    if (!ref || !this.store.getPayment) return { ok: false, reason: 'no_ref' };
    const row = await this.store.getPayment(this.provider.name, ref);
    if (!row) { console.warn('[pagamentos] notificação sem pedido conhecido', ref); return { ok: false, reason: 'unknown_ref' }; }
    let changed = null;
    if (ev.status === 'paid') {
      const expected = PRODUCTS[row.product_id] ? PRODUCTS[row.product_id].amount_cents : -1;
      const amount = Number(row.amount_cents) || expected;
      if (ev.currency !== 'BRL' || Number(ev.amountCents) !== amount) {
        console.error('[pagamentos] valor/moeda não confere — direito NÃO liberado', ref, ev.amountCents, ev.currency, amount);
        return { ok: false, reason: 'amount_mismatch' };
      }
      changed = await this.store.markPayment(this.provider.name, ref, 'paid');
      if (changed && this.store.grantEntitlement) await this.store.grantEntitlement(changed.user_id, changed.product_id, this.provider.name);
    } else if (ev.status === 'cancelled') {
      changed = await this.store.markPayment(this.provider.name, ref, 'cancelled');
    } else if (ev.status === 'refunded') {
      changed = this.store.markRefund ? await this.store.markRefund(this.provider.name, ref) : null;
      if (changed && this.store.revokeEntitlement) {
        try { await this.store.revokeEntitlement(changed.user_id, changed.product_id); }
        catch (e) { console.error('[pagamentos] REEMBOLSO SEM RETIRAR DIREITO (aplique a migração 0010)', ref, e && e.message); }
      }
    }
    if (changed) {
      for (const ws of this.backend.socketsOf(changed.user_id)) {
        this.send(ws, { type: 'payment_update', charge: { id: ref, status: changed.status, product_id: changed.product_id } });
        await this.backend.state(ws);
      }
    }
    return { ok: true, changed: !!changed };
  }

  // Webhook HTTP do provedor: valida, consulta o pagamento na API e aplica.
  async webhook(req, rawBody) {
    const ev = await this.provider.verifyWebhook(req, rawBody);
    if (!ev) return { status: 401, body: 'invalid' };
    if (ev.ignore) return { status: 200, body: 'ignored' };
    await this.apply(ev);
    return { status: 200, body: 'ok' };
  }
}

module.exports = { Payments, PRODUCTS, METHODS, createProvider };
