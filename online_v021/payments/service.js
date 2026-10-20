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
//   FRAIHA_FOUNDER_UNTIL    = R103 · data em que o Pacote Fundador sai de venda (ex.: 2026-12-31). Vazio = à venda.
//   FRAIHA_FOUNDER_LIMIT    = vagas do Fundador (OBRIGATÓRIO para vender: inteiro positivo. Ausente, vazio, 0, negativo
//                             ou texto = Fundador FECHADO — não existe "Fundador ilimitado". R172 fail-closed)
//   FRAIHA_FOUNDER_WHATSAPP_URL = link do grupo dos Fundadores (só vai para quem é Fundador de verdade)
const crypto = require('crypto');

// R103 · preço por forma de pagamento: PIX com 10% de desconto (arredondado para ,90). amount_cents = preço do cartão.
const PRODUCTS = {
  founder:        { kind: 'one_time', amount_cents: 4990,  pix_cents: 4490,  title: 'Pacote Fundador FRAIHA', founder: true },
  founder_legend: { kind: 'one_time', amount_cents: 9990,  pix_cents: 8990,  title: 'Pacote Fundador Lendário FRAIHA', founder: true },
  club_monthly:   { kind: 'pass',     amount_cents: 1990,  pix_cents: 1790,  title: 'Club FRAIHA (30 dias)' },
  club_yearly:    { kind: 'pass',     amount_cents: 14990, pix_cents: 13490, title: 'Club FRAIHA (1 ano)' },
};
const priceOf = (product, method) => (method === 'pix' ? product.pix_cents : product.amount_cents);
const OPEN_ORDER_MS = 30 * 60 * 1000;   // PIX vale 30 min: um Fundador em aberto bloqueia outro pedido de Fundador
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
    // R172 · fail-closed: só um inteiro positivo explícito abre o Fundador (ausente/vazio/0/negativo/texto = fechado)
    const rawLimit = String(env.FRAIHA_FOUNDER_LIMIT == null ? '' : env.FRAIHA_FOUNDER_LIMIT).trim();
    this.founderLimitValid = /^[1-9][0-9]{0,6}$/.test(rawLimit);
    this.founderLimit = this.founderLimitValid ? Number(rawLimit) : 0;
    if (!this.founderLimitValid) console.error('[pagamentos] FRAIHA_FOUNDER_LIMIT ausente ou inválido (' + JSON.stringify(rawLimit) + '): Pacote Fundador FECHADO (precisa ser um inteiro positivo)');
    const until = String(env.FRAIHA_FOUNDER_UNTIL || '').trim();
    this.founderUntil = until && !isNaN(Date.parse(until)) ? new Date(until.length <= 10 ? until + 'T23:59:59-03:00' : until).toISOString() : null;
    // R103 · encerrar a venda do Fundador quando o dono decidir: FRAIHA_FOUNDER_OPEN=0 (ou false/nao) no Render.
    this.founderClosedByEnv = /^(0|false|nao|não|off|fechado|encerrado)$/i.test(String(env.FRAIHA_FOUNDER_OPEN || '').trim());
    this.now = () => Date.now();
    this.founderGroup = String(env.FRAIHA_FOUNDER_WHATSAPP_URL || '').trim();
    this.lastPoll = new Map();
    // R171 · SEC-009: devolver automaticamente quem pagou depois de as vagas acabarem (só com FRAIHA_FOUNDER_AUTO_REFUND=1)
    this.autoRefund = /^(1|true|sim)$/i.test(String(env.FRAIHA_FOUNDER_AUTO_REFUND || '').trim());
    // o banco passa a conhecer o limite (a entrega confere vaga lá dentro, sob lock).
    // R171b/R172 · SEC-009 (reteste Orca): até o limite estar CONFIRMADO no banco, o Fundador fica FECHADO (fail-closed):
    // nada de reserva, entrega por webhook/JÁ PAGUEI/cartão nem reconciliação. Ver capacityReady().
    this.capacity = { state: 'pending', promise: null, retryAt: 0 };
    this.capacityWaitMs = Math.max(50, Number(env.FRAIHA_FOUNDER_CAPACITY_WAIT_MS) || 3000);
    if (backend && backend.store) void this.capacityReady();
    if (this.provider.name !== 'none' && this.provider.ready && !this.provider.ready()) console.warn('[pagamentos] provedor ' + this.provider.name + ' sem configuração completa: ' + (this.provider.missing ? this.provider.missing().join(', ') : ''));
  }
  get store() { return this.backend.store; }
  // R172 · SEC-009 (reteste Orca): founder_ready começa FALSE. Só vira true quando (1) o banco tem a capacidade
  // (migração 0023), (2) o servidor gravou o limite e (3) o banco devolveu EXATAMENTE o FRAIHA_FOUNDER_LIMIT.
  // Qualquer outra coisa — sem 0023, erro de SQL, resposta vazia ou valor diferente — deixa o Fundador FECHADO
  // (nunca "sem limite"); o resto do jogo segue normal. Erro: tenta de novo na próxima operação (no máximo a cada 5 s).
  get founderReady() { return this.capacity.state === 'ready'; }
  async capacityReady() {
    const c = this.capacity;
    if (c.state === 'ready') return true;
    if (c.state === 'closed') return false;
    if (c.promise) return this.within(c.promise);
    if (c.state === 'error' && Date.now() < c.retryAt) return false;
    if (!this.founderLimitValid) { c.state = 'closed'; return false; }   // R172: sem limite positivo válido → fechado, nem consulta o banco
    const st = this.backend && this.backend.store;
    if (!st || !st.founderSetLimit) { c.state = 'error'; c.retryAt = Date.now() + 60e3; return false; }
    c.promise = (async () => {
      try {
        const r = await st.founderSetLimit(this.founderLimit);
        if (r && r.missing) {
          console.error('[pagamentos] migração 0023 não aplicada: Pacote Fundador FECHADO até aplicar');
          c.state = 'error'; c.retryAt = Date.now() + 60e3; return false;
        }
        const got = Array.isArray(r) ? Number(r[0]) : Number(r);
        if (r === null || r === undefined || !Number.isFinite(got) || got <= 0 || got !== this.founderLimit) {
          console.error('[pagamentos] limite do Fundador não confirmado (banco devolveu ' + JSON.stringify(r) + ', esperado ' + this.founderLimit + '): Fundador FECHADO');
          c.state = 'error'; c.retryAt = Date.now() + 5e3; return false;
        }
        c.state = 'ready';
        console.log('[pagamentos] founder_ready: limite de vagas confirmado no banco = ' + this.founderLimit);
        return true;
      } catch (e) {
        console.error('[pagamentos] founderSetLimit falhou — Fundador fechado até confirmar o limite', e && e.message);
        c.state = 'error'; c.retryAt = Date.now() + 5e3; return false;
      } finally { c.promise = null; }
    })();
    return this.within(c.promise);
  }
  // espera a confirmação no máximo alguns segundos; passou disso, responde "ainda não" (fechado) e segue tentando
  within(p) {
    let t; const wait = new Promise(r => { t = setTimeout(() => r(false), this.capacityWaitMs || 3000); });
    return Promise.race([p, wait]).finally(() => clearTimeout(t));
  }
  capacityError() { const e = new Error('founder_capacity_not_ready'); e.code = 'founder_capacity_not_ready'; return e; }
  fail(ws, message, code) { this.send(ws, { type: 'payment_error', message, code }); }
  ready() { return this.provider.name !== 'none' && (!this.provider.ready || this.provider.ready()); }

  async foundersCount() {
    // R171 · SEC-009: vagas ocupadas = Fundadores + reservas vivas (0023); sem a 0023, só Fundadores
    try {
      if (this.store.founderTaken) { const n = await this.store.founderTaken(); if (n !== null && n !== undefined) return n; }
      return this.store.countFounders ? await this.store.countFounders() : 0;
    } catch (e) { console.error('countFounders', e && e.message); return 0; }
  }
  // R103 · Fundador à venda? (prazo e, se configurado, vagas)
  async founderOpen() {
    if (this.founderClosedByEnv) return { open: false, reason: 'closed', message: 'O Pacote Fundador saiu de venda. Obrigado a todos que apoiaram o começo do reino!' };
    if (this.founderUntil && this.now() > Date.parse(this.founderUntil)) return { open: false, reason: 'closed', message: 'O Pacote Fundador saiu de venda. Obrigado a todos que apoiaram o começo do reino!' };
    if (!this.founderLimitValid) return { open: false, reason: 'unavailable', message: 'As vendas do Pacote Fundador estão temporariamente indisponíveis.' };   // R172
    if (this.founderLimit > 0 && await this.foundersCount() >= this.founderLimit) return { open: false, reason: 'sold_out', message: 'As vagas do Pacote Fundador se esgotaram.' };
    return { open: true };
  }
  // O que a loja mostra: provedor pronto?, preços (PIX e cartão), prazo do Fundador, situação do jogador.
  async offer(ws) {
    const ent = await this.store.getEntitlements(ws.user.id).catch(() => ({}));
    const sold = this.founderLimit > 0 ? await this.foundersCount() : 0;
    const fo = await this.founderOpen();
    const prices = {}, prices_pix = {};
    for (const [id, p] of Object.entries(PRODUCTS)) { prices[id] = p.amount_cents; prices_pix[id] = p.pix_cents; }
    return { type: 'payment_offer', ready: this.ready(), methods: METHODS.slice(),
      founder_open: fo.open, founder_until: this.founderUntil, founder_limit: this.founderLimit,
      founder_remaining: this.founderLimit > 0 ? Math.max(0, this.founderLimit - sold) : null,
      is_founder: !!(ent && ent.is_founder), founder_tier: (ent && ent.founder_tier) || null, founder_number: (ent && ent.founder_number) || null,
      club_active: !!(ent && ent.club_active), club_expires_at: (ent && ent.club_expires_at) || null,
      prices, prices_pix };
  }
  // Extras só para quem é Fundador de verdade (o link do grupo nunca fica no Godot).
  founderPerks(ent) { return ent && ent.is_founder && this.founderGroup ? { whatsapp_url: this.founderGroup } : null; }

  // R109 · SALÃO DOS FUNDADORES: número, nome e nível de cada Fundador (público, cache de 60 s).
  async founders() {
    const now = this.now();
    if (this._founders && now - this._founders.at < 60000) return this._founders.list;
    let list = [];
    try { list = this.store.listFounders ? await this.store.listFounders() : []; } catch (e) { console.error('[fundadores] lista', e && e.message); list = this._founders ? this._founders.list : []; }
    this._founders = { at: now, list };
    return list;
  }
  async handle(ws, m) {
    const a = String(m.type || '');
    if (a === 'payment_founders') return this.send(ws, { type: 'payment_founders', founders: await this.founders(), open: (await this.founderOpen()).open });
    if (!ws.user || !ws.profile) return this.fail(ws, 'Entre na sua conta para assinar ou comprar.', 'auth_required');
    if (a === 'payment_offer') return this.send(ws, await this.offer(ws));
    if (a === 'payment_create') {
      const productId = String(m.product_id || ''), method = String(m.method || '');
      const product = PRODUCTS[productId];
      if (!product || !METHODS.includes(method)) return this.fail(ws, 'Produto ou forma de pagamento inválidos.', 'bad_request');
      if (!this.ready()) return this.fail(ws, 'Pagamento real ainda não configurado neste servidor.', 'provider_not_configured');
      if (!ws.user.email) return this.fail(ws, 'Sua conta precisa de um e-mail para o recibo do pagamento.', 'email_required');
      if (product.founder) {
        if (!(await this.capacityReady())) return this.fail(ws, 'As vendas do Pacote Fundador estão temporariamente indisponíveis. Tente de novo em instantes.', 'founder_unavailable');
        const ent = await this.store.getEntitlements(ws.user.id).catch(() => ({}));
        if (ent && ent.founder_tier === 'legend') return this.fail(ws, 'Você já é Fundador Lendário. Obrigado!', 'already_founder');
        if (ent && ent.is_founder && productId === 'founder') return this.fail(ws, 'Você já é Fundador do Reino. Obrigado!', 'already_founder');
        const fo = await this.founderOpen();
        // R171 · quem já é Fundador e vira Lendário não ocupa vaga nova: "esgotado" não bloqueia o upgrade
        const upgrade = !!(ent && ent.is_founder) && productId === 'founder_legend';
        if (!fo.open && !(upgrade && fo.reason === 'sold_out')) return this.fail(ws, fo.message, fo.reason === 'sold_out' ? 'founder_sold_out' : 'founder_closed');
        // dois PIX de Fundador abertos ao mesmo tempo poderiam ser pagos os dois
        const open = this.store.findOpenPayment ? await this.store.findOpenPayment(ws.user.id, ['founder', 'founder_legend'], OPEN_ORDER_MS).catch(() => null) : null;
        if (open) return this.fail(ws, 'Você já tem um pagamento de Fundador em aberto. Conclua esse pagamento ou aguarde 30 minutos para começar outro.', 'order_open');
      }
      const ref = crypto.randomUUID(), amount = priceOf(product, method);
      try {
        // R171 · SEC-009: pedido de Fundador só nasce com vaga reservada, conferida dentro do banco (lock)
        let reserved = false;
        if (product.founder && this.founderLimit > 0 && this.store.founderReserve) {
          const r = await this.store.founderReserve({ user_id: ws.user.id, product_id: productId, method, provider: this.provider.name, provider_ref: ref,
            amount_cents: amount, limit: this.founderLimit, hold_s: Math.round(OPEN_ORDER_MS / 1000) });
          if (r && r.ok === false && r.reason === 'closed') return this.fail(ws, 'As vendas do Pacote Fundador estão temporariamente indisponíveis. Tente de novo em instantes.', 'founder_unavailable');   // R172
          if (r && r.ok === false) return this.fail(ws, 'As vagas do Pacote Fundador se esgotaram.', 'founder_sold_out');
          if (r && r.missing) {   // R171b: sem a 0023 não vende Fundador limitado (nunca o caminho antigo sem lock)
            console.error('[pagamentos] migração 0023 ausente: venda de Fundador limitada FECHADA');
            this.capacity.state = 'error'; this.capacity.retryAt = Date.now() + 60e3;
            return this.fail(ws, 'As vendas do Pacote Fundador estão temporariamente indisponíveis. Tente de novo em instantes.', 'founder_unavailable');
          }
          reserved = true;
        }
        if (!reserved && this.store.createPayment) await this.store.createPayment({ user_id: ws.user.id, product_id: productId, method, provider: this.provider.name, provider_ref: ref, amount_cents: amount, status: 'pending' });
        const charge = await this.provider.createCharge({ ref, userId: ws.user.id, productId, method, amountCents: amount, title: product.title, email: ws.user.email });
        return this.send(ws, { type: 'payment_charge', charge: { ...charge, id: ref, product_id: productId, amount_cents: amount } });
      } catch (e) {
        if (this.store.markPayment) await this.store.markPayment(this.provider.name, ref, 'failed').catch(() => {});
        if (e.code === 'provider_not_configured') return this.fail(ws, 'Pagamento real ainda não configurado neste servidor.', 'provider_not_configured');
        console.error('payment_create', e && e.message);
        return this.fail(ws, 'Não foi possível iniciar o pagamento agora. Tente novamente em instantes.', 'server_error');
      }
    }
    if (a === 'payment_card_pay') return this.cardPay(ws, m);
    if (a === 'payment_history') {   // R103 · minhas compras (perfil)
      const rows = this.store.listPayments ? await this.store.listPayments(ws.user.id, 30).catch(() => []) : [];
      return this.send(ws, { type: 'payment_history', items: rows.filter(r => r.status !== 'failed').map(r => ({ product_id: r.product_id, title: (PRODUCTS[r.product_id] || {}).title || r.product_id,
        method: r.method, amount_cents: r.amount_cents, status: r.status, created_at: r.created_at, paid_at: r.paid_at || null })) });
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
      try { await this.apply(ev); }
      catch (e) { console.error('payment_card_pay apply', e && e.message); return reply('error', { message: 'Pagamento aprovado, mas a confirmação ainda não chegou. Aguarde alguns segundos: a vantagem aparece sozinha.' }); }
      const after = await this.store.getPayment(this.provider.name, ref);
      if (after && after.status === 'paid') return reply('approved');
      if (after && after.status === 'sold_out') return reply('sold_out', { message: 'As vagas do Pacote Fundador acabaram no exato momento do seu pagamento. Você NÃO recebeu o pacote e o valor será devolvido integralmente.' });   // R171 · SEC-009
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
      changed = await this.payAndGrant(ref, row.product_id);
      if (changed && changed.status === 'sold_out') return this.soldOut(changed, ref, ev);   // R171 · SEC-009
      if (changed && this.backend.referrals) this.backend.referrals.onPurchase(changed.user_id);   // R105 · +30 dias para quem convidou
      if (changed && this.backend.creators) this.backend.creators.onPurchase({ ref, user_id: changed.user_id, product_id: row.product_id, amount_cents: amount });   // R121
    } else if (ev.status === 'cancelled') {
      changed = await this.store.markPayment(this.provider.name, ref, 'cancelled');
    } else if (ev.status === 'refunded') {
      changed = this.store.markRefund ? await this.store.markRefund(this.provider.name, ref) : null;
      if (changed && this.backend.creators) this.backend.creators.onRefund(ref);   // R121 · comissão não paga é cancelada
      if (changed && changed.was === 'sold_out') console.log('[pagamentos] reembolso concluído de pagamento sem vaga (sold_out)', ref);
      else if (changed && this.store.revokeEntitlement) {
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

  // R171 · SEC-009: pagamento aprovado quando as vagas já tinham acabado. NADA silencioso:
  //   • o pagamento fica 'sold_out' (pago, sem vantagem) — aparece no Admin → Pagamentos e no MINHAS COMPRAS;
  //   • o jogador recebe na hora o aviso de que as vagas acabaram e que o valor será devolvido integralmente;
  //   • log de ERRO no servidor com a referência;
  //   • com FRAIHA_FOUNDER_AUTO_REFUND=1 o servidor já pede o estorno ao provedor; quando o provedor confirmar,
  //     o pagamento vira 'refunded'. Sem a variável, o reembolso é feito pelo dono (painel do Mercado Pago).
  async soldOut(row, ref, ev) {
    console.error('[pagamentos] VAGAS DO FUNDADOR ESGOTADAS no momento do pagamento — pago SEM vantagem, reembolso necessário', ref, row.user_id);
    let refund = 'manual';
    if (this.autoRefund && this.provider.refund && ev && ev.providerPaymentId) {
      try { await this.provider.refund(ev.providerPaymentId); refund = 'requested'; }
      catch (e) { refund = 'failed'; console.error('[pagamentos] estorno automático falhou — fazer manualmente', ref, e && e.message); }
    }
    const msg = 'As vagas do Pacote Fundador acabaram no exato momento do seu pagamento. Você NÃO recebeu o pacote e o valor será devolvido integralmente' +
      (refund === 'requested' ? ' (estorno já solicitado ao Mercado Pago).' : ' (o FRAIHA vai estornar pelo Mercado Pago; se tiver dúvida, fale com o suporte).');
    for (const ws of this.backend.socketsOf(row.user_id)) {
      this.send(ws, { type: 'payment_update', charge: { id: ref, status: 'sold_out', product_id: row.product_id }, message: msg, refund });
      this.send(ws, { type: 'payment_error', code: 'founder_sold_out_paid', message: msg });
    }
    return { ok: true, changed: true, sold_out: true, refund };
  }
  // R103 · marca pago E entrega a vantagem juntos. Se a entrega falhar, o pedido continua pendente e a próxima
  // notificação (ou o JÁ PAGUEI) tenta de novo — nunca fica "pago sem vantagem".
  async payAndGrant(ref, productId) {
    const prov = this.provider.name;
    // R171b · SEC-009: Fundador só é entregue com o limite confirmado no banco; senão erro (webhook → 500 e o provedor
    // repete; JÁ PAGUEI/cartão → "aguarde"), e o pagamento continua pendente — nada é perdido, nada passa do limite.
    if (productId === undefined && this.store.getPayment) { const row = await this.store.getPayment(prov, ref).catch(() => null); productId = row ? row.product_id : 'founder'; }
    if (PRODUCTS[productId] && PRODUCTS[productId].founder && !(await this.capacityReady())) throw this.capacityError();
    if (this.store.payAndGrant) {
      const r = await this.store.payAndGrant(prov, ref, prov);
      if (!r || !r.missing) return r || null;
    }
    // banco sem a 0012: caminho antigo, desfazendo o "pago" se a entrega falhar
    const changed = await this.store.markPayment(prov, ref, 'paid');
    if (!changed) return null;
    try { if (this.store.grantEntitlement) await this.store.grantEntitlement(changed.user_id, changed.product_id, prov); }
    catch (e) {
      console.error('[pagamentos] entrega falhou — pedido volta para pendente', ref, e && e.message);
      if (this.store.revertPaid) await this.store.revertPaid(prov, ref).catch(() => {});
      throw e;
    }
    return changed;
  }
  // R103 · entrega o que ficou pago sem vantagem (pedidos antigos). Chamado ao iniciar e de hora em hora.
  async reconcile() {
    if (!this.store.grantPaidMissing) return null;
    // R171b · SEC-009: sem limite confirmado, a reconciliação espera (no banco ela também pula Fundador sem configuração)
    if (!(await this.capacityReady())) { console.error('[pagamentos] reconciliação adiada: limite do Fundador ainda não confirmado'); return null; }
    try {
      const r = await this.store.grantPaidMissing();
      if (r && r.granted) console.log('[pagamentos] entregues ' + r.granted + ' pagamento(s) que estavam sem vantagem');
      if (r && r.sold_out) console.error('[pagamentos] ' + r.sold_out + ' pagamento(s) de Fundador sem vaga na reconciliação (sold_out) — reembolso necessário');
      return r;
    }
    catch (e) { console.error('[pagamentos] reconciliação', e && e.message); return null; }
  }

  // Webhook HTTP do provedor: valida, consulta o pagamento na API e aplica.
  async webhook(req, rawBody) {
    const ev = await this.provider.verifyWebhook(req, rawBody);
    if (!ev) return { status: 401, body: 'invalid' };
    if (ev.busy) return { status: 503, body: 'busy' };   // R170 · SEC-006: limite de avisos sem assinatura
    if (ev.ignore) return { status: 200, body: 'ignored' };
    // R171 · SEC-006: o aviso só conta como processado se a aplicação deu certo; erro → 500 e o provedor tenta de novo
    let ok = false;
    try { await this.apply(ev); ok = true; }
    finally { if (ev.unsignedId && this.provider.webhookSettled) this.provider.webhookSettled(ev.unsignedId, ok); }
    return { status: 200, body: 'ok' };
  }
}

module.exports = { Payments, PRODUCTS, METHODS, createProvider, priceOf };
