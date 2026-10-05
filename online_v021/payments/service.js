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
const CARD_ATTEMPTS = 6;         // tentativas de cartão no jogo por pedido (cartão recusado → pode tentar outro)
// R40 · Motivos de recusa do cartão (status_detail do Mercado Pago) em português, para o jogador.
const CARD_REJECT = {
  cc_rejected_insufficient_amount: 'Saldo ou limite insuficiente neste cartão. Tente outro cartão ou pague com PIX.',
  cc_rejected_bad_filled_security_code: 'Código de segurança (CVV) incorreto. Confira e tente de novo.',
  cc_rejected_bad_filled_date: 'Data de validade incorreta. Confira e tente de novo.',
  cc_rejected_bad_filled_card_number: 'Número do cartão incorreto. Confira e tente de novo.',
  cc_rejected_bad_filled_other: 'Algum dado do cartão está incorreto. Confira e tente de novo.',
  cc_rejected_call_for_authorize: 'O banco pediu autorização para esta compra. Ligue para o banco do cartão ou pague com PIX.',
  cc_rejected_card_disabled: 'Este cartão está bloqueado ou inativo. Fale com o banco ou use outro cartão.',
  cc_rejected_duplicated_payment: 'Este pagamento já foi feito agora há pouco. Confira a sua conta antes de tentar de novo.',
  cc_rejected_high_risk: 'O pagamento foi recusado pela análise de segurança. Tente outro cartão ou pague com PIX.',
  cc_rejected_max_attempts: 'Muitas tentativas com este cartão. Use outro cartão ou pague com PIX.',
  cc_rejected_blacklist: 'Este cartão não pode ser usado. Tente outro cartão ou pague com PIX.',
  cc_rejected_card_type_not_allowed: 'Este tipo de cartão não é aceito. Tente outro cartão ou pague com PIX.',
};
const CARD_REJECT_DEFAULT = 'O cartão foi recusado pelo banco. Nada foi cobrado. Tente outro cartão ou pague com PIX.';

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
    if (a === 'payment_card_pay') return this.cardPay(ws, m);
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

  // R40 · Cartão no jogo: o navegador manda o TOKEN do formulário seguro do Mercado Pago; o servidor
  // cria o pagamento com o preço do servidor, no pedido (ref) que pertence a este jogador.
  async cardPay(ws, m) {
    const ref = String(m.charge_id || '');
    const reply = (status, extra = {}) => this.send(ws, { type: 'payment_card_result', charge_id: ref, status, ...extra });
    const row = this.store.getPayment ? await this.store.getPayment(this.provider.name, ref) : null;
    if (!row || row.user_id !== ws.user.id || (row.method && row.method !== 'card')) return reply('error', { message: 'Pedido de pagamento não encontrado. Feche e comece de novo.' });
    if (row.status === 'paid') return reply('approved');
    if (row.status !== 'pending') return reply('error', { message: 'Este pedido não está mais aberto. Feche e comece de novo.' });
    if (!this.provider.payCard) return reply('error', { message: 'Pagamento com cartão no jogo indisponível. Use a página do Mercado Pago.' });
    const token = String(m.token || ''), pm = String(m.payment_method_id || '');
    if (!/^[A-Za-z0-9_-]{8,128}$/.test(token) || !/^[a-z0-9_]{2,40}$/.test(pm)) return reply('rejected', { message: 'Dados do cartão incompletos. Confira e tente de novo.' });
    this.cardAttempts = this.cardAttempts || new Map();
    const n = (this.cardAttempts.get(ref) || 0) + 1;
    if (n > CARD_ATTEMPTS) return reply('rejected', { message: 'Muitas tentativas neste pedido. Feche e comece de novo, ou pague com PIX.' });
    this.cardAttempts.set(ref, n);
    const product = PRODUCTS[row.product_id];
    if (!product) return reply('error', { message: 'Produto inválido.' });
    const amountCents = Number(row.amount_cents) || product.amount_cents;
    let ev;
    try {
      ev = await this.provider.payCard({ ref, token, paymentMethodId: pm, issuerId: String(m.issuer_id || '').replace(/[^0-9]/g, '').slice(0, 12),
        amountCents, title: product.title, email: ws.user.email, idType: String(m.id_type || '').replace(/[^A-Za-z]/g, '').slice(0, 8),
        idNumber: String(m.id_number || '').replace(/[^0-9]/g, '').slice(0, 20), deviceId: String(m.device_id || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 120),
        userId: ws.user.id, productId: row.product_id });
    } catch (e) {
      if (e.status && e.status >= 400 && e.status < 500) { console.warn('payment_card_pay recusado pela API', e.message); return reply('rejected', { message: CARD_REJECT_DEFAULT }); }
      console.error('payment_card_pay', e && e.message);
      return reply('error', { message: 'O Mercado Pago não respondeu agora. Nada foi cobrado. Tente de novo em instantes.' });
    }
    if (ev.status === 'paid') {
      await this.apply(ev);
      const after = await this.store.getPayment(this.provider.name, ref);
      if (after && after.status === 'paid') return reply('approved');
      return reply('error', { message: 'Pagamento aprovado, mas a confirmação ainda não chegou. Aguarde alguns segundos: a vantagem aparece sozinha.' });
    }
    if (ev.status === 'pending') return reply('pending', { message: 'Pagamento em análise pelo Mercado Pago. Assim que for aprovado, a vantagem aparece sozinha.' });
    return reply('rejected', { detail: ev.detail || '', message: CARD_REJECT[ev.detail] || CARD_REJECT_DEFAULT });
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
