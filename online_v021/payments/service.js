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
const { AppleIAP } = require('./apple');   // R192 · compras pela Apple (app de iPhone)
const { GooglePlay } = require('./google');   // R194 · compras pelo Google Play (app da Play Store)

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
const CARD_ATTEMPTS = 6;
// R175d · erros da API de pagamentos que provam que a cobrança NÃO foi criada (validação antes de criar o pagamento).
// Qualquer outro erro HTTP (inclusive outros 4xx ou 400 sem causa reconhecida) = resultado INCERTO (fail closed).
//   401              credencial do servidor recusada: a requisição nem foi processada
//   400 + cause.code 2006 card token não encontrado · 2062 card token inválido · 3003 card_token_id inválido
//                    3034 validação do número do cartão · 2067 documento do pagador inválido
//                    3000 falta o nome do titular · 3001 falta o emissor · 4037 transaction_amount inválido
const DEFINITIVE_400_CAUSES = new Set(['2006', '2062', '3003', '3034', '2067', '3000', '3001', '4037']);
function definitiveNoCharge(e) {
  if (!e || !Number.isInteger(e.status)) return false;
  if (e.status === 401) return true;
  const causes = Array.isArray(e.causes) ? e.causes : [];
  return e.status === 400 && causes.length > 0 && causes.every(c => DEFINITIVE_400_CAUSES.has(String(c)));
}
const PROVIDER_STATES = ['paid', 'refunded', 'pending', 'failed', 'cancelled'];   // R175b · estados que o provedor pode devolver         // tentativas de cartão no jogo por pedido (cartão recusado → pode tentar outro)
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
    this.apple = new AppleIAP({ payments: this, env });   // R192 · iPhone: a Apple cobra, este servidor confere e entrega
    this.google = new GooglePlay({ payments: this, env });   // R194 · Play Store: o Google cobra, este servidor confere e entrega
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
    return { type: 'payment_offer', ready: this.ready(), methods: METHODS.slice(), apple_ready: this.apple.ready(), google_ready: this.google.ready(),
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
    if (a === 'payment_apple') return this.lock('user:' + ws.user.id, () => this.apple.handle(ws, m));   // R192
    if (a === 'payment_google') return this.lock('user:' + ws.user.id, () => this.google.handle(ws, m));   // R194
    // R175 · ações que mexem em pedido da conta: uma de cada vez por conta (duas abas / dois aparelhos esperam a vez)
    if (a === 'payment_create') return this.lock('user:' + ws.user.id, () => this.createOrder(ws, m));
    if (a === 'payment_card_pay') {
      const receivedAt = new Date(this.now()).toISOString();   // R175e · horário de RECEBIMENTO (síncrono, antes de qualquer await)
      // R175e · a geração da guarda de cartão da conta é lida NO RECEBIMENTO (antes de qualquer espera). Se outra tentativa
      // começar depois disso, esta requisição é antiga e o banco a recusa (fraiha_card_attempt_begin) — nunca "acorda" e cobra.
      let seen;
      try { seen = this.store.cardGuardGeneration ? await this.store.cardGuardGeneration(ws.user.id) : { missing: true }; }
      catch (e) { console.error('[pagamentos] guarda de cartão indisponível', e && e.message); seen = { error: true }; }
      return this.lock('user:' + ws.user.id, () => this.cardPay(ws, m, seen, receivedAt));
    }
    if (a === 'payment_history') return this.lock('user:' + ws.user.id, () => this.history(ws));
    if (a === 'payment_resume') return this.lock('user:' + ws.user.id, () => this.resumeOrder(ws, String(m.charge_id || '')));
    if (a === 'payment_cancel') return this.lock('user:' + ws.user.id, () => this.cancelOrder(ws, String(m.charge_id || '')));
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

  // R175 · fila por chave (conta ou pedido) dentro do processo: a próxima ação só começa quando a anterior terminar.
  async lock(key, fn) {
    this.locks = this.locks || new Map();
    const prev = this.locks.get(key) || Promise.resolve();
    let release; const mine = new Promise(r => { release = r; });
    const tail = prev.then(() => mine);
    this.locks.set(key, tail);
    await prev;
    try { return await fn(); }
    finally { release(); if (this.locks.get(key) === tail) this.locks.delete(key); }
  }

  async createOrder(ws, m) {
    const productId = String(m.product_id || ''), method = String(m.method || '');
    const product = PRODUCTS[productId];
    if (!product || !METHODS.includes(method)) return this.fail(ws, 'Produto ou forma de pagamento inválidos.', 'bad_request');
    if (!this.ready()) return this.fail(ws, 'Pagamento real ainda não configurado neste servidor.', 'provider_not_configured');
    if (!ws.user.email) return this.fail(ws, 'Sua conta precisa de um e-mail para o recibo do pagamento.', 'email_required');
    {   // R175d · cobrança de cartão incerta em outro pedido da conta (mesmo vencido) → nenhum pedido novo
      const g = await this.accountGate(ws.user.id, null);
      if (g) return this.send(ws, { type: 'payment_error', code: g.code, message: g.message, charge_id: g.charge_id });
    }
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
      // R175 · o aviso leva o pedido aberto: o jogo oferece CONTINUAR (o mesmo pedido) ou CANCELAR
      if (open) return this.send(ws, { type: 'payment_error', code: 'order_open',
        message: 'Você já tem um pedido de Fundador aguardando pagamento. Continue esse pedido ou cancele para começar outro.',
        charge_id: open.provider_ref || '', product_id: open.product_id || '', method: open.method || '' });
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

  // ---------------------------------------------------------------- R175 · pedidos pendentes
  // Um pedido vale OPEN_ORDER_MS (30 min = validade do PIX e da reserva de vaga do Fundador) a partir da criação.
  expiresAt(row) { const t = Date.parse(row && row.created_at); return Number.isFinite(t) ? t + OPEN_ORDER_MS : 0; }
  expired(row) { const e = this.expiresAt(row); return !!e && this.now() >= e; }
  // estado para o jogo: aguardando | expirado | cancelado | pago | reembolsado | sem vaga (sold_out)
  stateOf(row) {
    const st = String(row.status || '');
    if (st === 'pending') return this.expired(row) ? 'expired' : 'pending';
    if (st === 'cancelled') {   // pedidos antigos (sem motivo gravado) eram PIX vencidos
      const reason = row.raw && row.raw.cancel && row.raw.cancel.reason;
      return !reason || reason === 'expired' ? 'expired' : 'cancelled';
    }
    return st;
  }
  item(r) {
    const state = this.stateOf(r), exp = this.expiresAt(r);
    const raw = r.raw || {};
    return { id: r.provider_ref || '', product_id: r.product_id, title: (PRODUCTS[r.product_id] || {}).title || r.product_id,
      method: r.method, amount_cents: r.amount_cents, status: r.status, state, created_at: r.created_at, paid_at: r.paid_at || null,
      expires_at: state === 'pending' && exp ? new Date(exp).toISOString() : null,
      can_continue: state === 'pending', can_cancel: state === 'pending',
      paid_after_cancel: !!(raw.reopened && raw.reopened.length) };
  }
  notify(userId, ref, status, productId, extra = {}) {
    for (const ws of this.backend.socketsOf(userId)) this.send(ws, { type: 'payment_update', charge: { id: ref, status, product_id: productId }, ...extra });
  }

  // MINHAS COMPRAS: pedidos com estado; os vencidos (até 3 por consulta) são conferidos no provedor e fechados.
  async history(ws) {
    const list = () => this.store.listPayments ? this.store.listPayments(ws.user.id, 30).catch(() => []) : Promise.resolve([]);
    let rows = await list();
    let closed = 0;
    for (const r of rows) {
      if (closed >= 3) break;
      if (r.status === 'pending' && this.expired(r) && r.provider_ref) { closed++; await this.expireOrder(r).catch(e => console.error('[pagamentos] expirar pedido', r.provider_ref, e && e.message)); }
    }
    if (closed) rows = await list();
    return this.send(ws, { type: 'payment_history', items: rows.filter(r => r.status !== 'failed').map(r => this.item(r)) });
  }

  // R175b · resposta do provedor só vale se for INEQUIVOCAMENTE deste pedido: external_reference = ref, id do
  // pagamento presente e estado conhecido. Qualquer outra coisa é "inconclusivo".
  validEvent(ev, ref) {
    return !!ev && typeof ev === 'object' && String(ev.providerRef || '') === String(ref) && /^[A-Za-z0-9_-]{1,40}$/.test(String(ev.providerPaymentId || ''))
      && PROVIDER_STATES.includes(String(ev.status || ''));
  }
  // R175b · consulta AUTORITATIVA do pedido no provedor, para decidir se é seguro cobrar/cancelar:
  //   { state: 'none' }                 o provedor respondeu: nenhum pagamento neste pedido
  //   { state: <status>, ev }           pagamento deste pedido (paid | refunded | pending | failed | cancelled)
  //   { state: 'unknown', why }         falha, timeout, resposta inválida/incompleta ou de OUTRO pedido → em dúvida
  async providerCheck(ref) {
    if (!this.provider.findByRef) return { state: 'unknown', why: 'sem consulta no provedor' };
    let ev;
    try { ev = await this.provider.findByRef(ref); }
    catch (e) { return { state: 'unknown', why: (e && e.message) || 'erro na consulta' }; }
    if (ev === null) return { state: 'none' };
    if (!this.validEvent(ev, ref)) return { state: 'unknown', why: 'resposta inválida ou de outro pedido' };
    return { state: ev.status, ev };
  }

  // Pergunta ao provedor ANTES de fechar: aprovado → entrega; PIX ainda aberto → cancela lá; depois fecha aqui.
  // → 'paid' | 'closed' | 'open' (não foi possível confirmar: o pedido fica como está)
  async expireOrder(row) { return this.closeOrder(row, 'expired', null); }
  async closeOrder(row, reason, byUser) {
    const ref = row.provider_ref, prov = this.provider.name;
    // R175b · sem confirmação autoritativa do provedor (erro, timeout, resposta inválida ou de outro pedido) nada muda
    const chk = await this.providerCheck(ref);
    if (chk.state === 'unknown') { console.warn('[pagamentos] não deu para conferir o pedido no provedor antes de fechar', ref, chk.why); return { result: 'unverified' }; }
    let ev = chk.ev || null;
    if (ev && ev.status === 'paid') { await this.apply(ev); return { result: 'paid' }; }
    // R175c · tentativa de cartão incerta/em andamento: não fecha o pedido sem a confirmação dela
    if (this.attemptOf(row)) {
      const res = await this.resolveAttempt(row);
      if (res.paid) { await this.apply(res.paid); return { result: 'paid' }; }
      if (res.block) return { result: 'in_review' };
      row = res.row;
    }
    if (ev && ev.status === 'refunded') { console.error('[pagamentos] pedido pendente com pagamento estornado no provedor — conferir', ref); return { result: 'unverified' }; }
    if (ev && ev.status === 'pending') {
      if (row.method === 'pix' && this.provider.cancel) {
        let after = null;
        try { after = await this.provider.cancel(ev.providerPaymentId); }
        catch (e) {
          // pode ter sido pago no meio do caminho: confere de novo
          const again = await this.providerCheck(ref);
          if (again.state === 'paid') { await this.apply(again.ev); return { result: 'paid' }; }
          if (again.state !== 'cancelled' || again.ev.providerPaymentId !== ev.providerPaymentId) return { result: 'unverified' };
          after = again.ev;
        }
        // R175b · a resposta do cancelamento tem de ser DESTE pagamento e DESTE pedido; senão o pedido fica como está
        if (!this.validEvent(after, ref) || String(after.providerPaymentId) !== String(ev.providerPaymentId)) {
          console.error('[pagamentos] resposta de cancelamento NÃO confere com o pedido — nada alterado', ref, ev.providerPaymentId, after && after.providerRef, after && after.providerPaymentId);
          return { result: 'mismatch' };
        }
        if (after.status === 'paid') { await this.apply(after); return { result: 'paid' }; }
        if (after.status !== 'cancelled') return { result: 'unverified' };
        ev = after;
      } else if (row.method === 'card') {
        return { result: 'in_review' };   // cartão em análise no Mercado Pago: não dá para cancelar daqui
      } else return { result: 'unverified' };
    }
    const note = { reason, provider_status: ev ? ev.status : 'none', provider_payment_id: ev ? String(ev.providerPaymentId || '') : '' };
    if (byUser) note.by = byUser;
    const done = await this.lock('ref:' + ref, () => this.store.cancelPayment ? this.store.cancelPayment(prov, ref, note) : this.store.markPayment(prov, ref, 'cancelled'));
    if (!done) {
      const now = await this.store.getPayment(prov, ref);
      return { result: now && now.status === 'cancelled' ? 'closed' : (now && now.status === 'paid' ? 'paid' : 'changed'), row: now };
    }
    this.lastPoll.delete(ref);
    return { result: 'closed', row: done };
  }

  // CONTINUAR: o MESMO pedido (mesma reserva, mesmo id). PIX → o mesmo QR/Copia e Cola; cartão → o formulário de novo
  // (cada envio gera um token novo; o pedido no servidor é o mesmo e não cobra duas vezes).
  async resumeOrder(ws, ref) {
    const prov = this.provider.name;
    const row = this.store.getPayment ? await this.store.getPayment(prov, ref) : null;
    if (!row || row.user_id !== ws.user.id) return this.fail(ws, 'Pedido não encontrado.', 'order_not_found');
    const closed = (code, message) => this.send(ws, { type: 'payment_error', code, message, charge_id: ref, product_id: row.product_id });
    if (row.status === 'paid') return this.send(ws, { type: 'payment_update', charge: { id: ref, status: 'paid', product_id: row.product_id } });
    if (row.status !== 'pending') return closed('order_closed', 'Este pedido não está mais aberto. Nada foi cobrado por ele. Comece um novo pedido.');
    if (!this.ready()) return this.fail(ws, 'Pagamento real ainda não configurado neste servidor.', 'provider_not_configured');
    if (this.expired(row)) {
      const r = await this.expireOrder(row);
      if (r.result === 'paid') { const now = await this.store.getPayment(prov, ref); return this.send(ws, { type: 'payment_update', charge: { id: ref, status: now ? now.status : 'paid', product_id: row.product_id } }); }
      return closed('order_expired', 'Este pedido expirou. Nada foi cobrado. Comece um novo pedido.');
    }
    const product = PRODUCTS[row.product_id];
    if (!product) return this.fail(ws, 'Produto inválido.', 'bad_request');
    {   // R175d · não reabre pagamento (PIX ou cartão) com cobrança incerta em outro pedido da conta
      const g = await this.accountGate(ws.user.id, ref);
      if (g) return this.send(ws, { type: 'payment_error', code: g.code, message: g.message, charge_id: g.charge_id });
    }
    const amount = Number(row.amount_cents) || priceOf(product, row.method);
    const sendCharge = (charge) => this.send(ws, { type: 'payment_charge', charge: { ...charge, id: ref, product_id: row.product_id, amount_cents: amount, resumed: true,
      order_expires_at: new Date(this.expiresAt(row)).toISOString() } });
    try {
      if (row.method === 'pix') {
        if (!this.provider.resumePix) return this.fail(ws, 'Não foi possível recuperar este PIX agora. Tente de novo em instantes.', 'server_error');
        const r = await this.provider.resumePix(ref);
        if (!r) return this.fail(ws, 'Não foi possível recuperar este PIX agora. Tente de novo em instantes ou cancele o pedido.', 'server_error');
        // R175b · só retoma o que é inequivocamente deste pedido (external_reference e id do pagamento conferidos)
        if (!this.validEvent(r.event, ref) || (r.charge && String(r.charge.provider_payment_id || '') !== String(r.event.providerPaymentId))) {
          console.error('[pagamentos] resposta do PIX não confere com o pedido — nada retomado', ref);
          return this.fail(ws, 'Não foi possível confirmar este PIX com o Mercado Pago agora. Nada foi alterado. Tente de novo em instantes.', 'provider_unverified');
        }
        if (r.charge) return sendCharge(r.charge);
        const ev = r.event;
        if (ev.status === 'paid' || ev.status === 'refunded') {
          await this.apply(ev);
          const now = await this.store.getPayment(prov, ref);
          return this.send(ws, { type: 'payment_update', charge: { id: ref, status: now ? now.status : ev.status, product_id: row.product_id } });
        }
        if (ev.status === 'cancelled' || r.event.expired) {
          if (ev.status === 'cancelled') await this.apply({ ...ev, detail: ev.detail || 'expired' });
          else await this.expireOrder(row);
          return closed('order_expired', 'Este PIX expirou. Nada foi cobrado. Comece um novo pedido.');
        }
        return this.fail(ws, 'Não foi possível recuperar este PIX agora. Tente de novo em instantes ou cancele o pedido.', 'server_error');
      }
      // cartão: antes de abrir o formulário de novo, confere se este pedido já foi aprovado (R175b · em dúvida, NÃO segue)
      const chk = await this.providerCheck(ref);
      if (chk.state === 'paid') {
        await this.apply(chk.ev);
        const now = await this.store.getPayment(prov, ref);
        return this.send(ws, { type: 'payment_update', charge: { id: ref, status: now ? now.status : 'paid', product_id: row.product_id } });
      }
      const block = this.cardBlock(ref, chk);
      if (block) return this.fail(ws, block.message, block.code);
      const res = await this.resolveAttempt(row);   // R175c · tentativa incerta gravada no pedido
      if (res.paid) {
        await this.apply(res.paid);
        const now = await this.store.getPayment(prov, ref);
        return this.send(ws, { type: 'payment_update', charge: { id: ref, status: now ? now.status : 'paid', product_id: row.product_id } });
      }
      if (res.block) return this.fail(ws, res.message, res.code);
      const charge = await this.provider.createCharge({ ref, userId: ws.user.id, productId: row.product_id, method: 'card', amountCents: amount,
        title: product.title, email: ws.user.email, idemSuffix: ':continuar:' + this.now() });
      return sendCharge(charge);
    } catch (e) {
      console.error('payment_resume', ref, e && e.message);
      return this.fail(ws, 'O Mercado Pago não respondeu agora. Nada foi cobrado. Tente de novo em instantes.', 'server_error');
    }
  }

  // CANCELAR: idempotente. Confere no provedor antes; se já foi pago, entrega em vez de cancelar.
  async cancelOrder(ws, ref) {
    const prov = this.provider.name;
    const reply = (status, extra = {}) => this.send(ws, { type: 'payment_cancel_result', charge_id: ref, status, ...extra });
    const row = this.store.getPayment ? await this.store.getPayment(prov, ref) : null;
    if (!row || row.user_id !== ws.user.id) return reply('not_found', { message: 'Pedido não encontrado.' });
    if (row.status === 'cancelled') return reply('cancelled', { already: true, product_id: row.product_id });
    if (row.status !== 'pending') return reply(row.status, { product_id: row.product_id,
      message: row.status === 'paid' ? 'Este pedido já foi pago e a vantagem já está na sua conta.' : 'Este pedido não está mais aberto.' });
    const r = await this.closeOrder(row, 'user', ws.user.id);
    if (r.result === 'closed') {
      reply('cancelled', { product_id: row.product_id });
      this.notify(row.user_id, ref, 'cancelled', row.product_id, { reason: 'user' });
      return;
    }
    if (r.result === 'paid' || r.result === 'changed') {
      const now = await this.store.getPayment(prov, ref);
      const st = now ? now.status : 'pending';
      return reply(st, { product_id: row.product_id, message: st === 'paid' ? 'Este pedido já tinha sido pago: a vantagem foi entregue na sua conta.' :
        st === 'sold_out' ? 'Este pedido já tinha sido pago, mas as vagas do Fundador acabaram: o valor será devolvido integralmente.' : 'Este pedido mudou enquanto cancelava. Confira em MINHAS COMPRAS.' });
    }
    if (r.result === 'mismatch') return reply('error', { code: 'provider_mismatch', message: 'A resposta do Mercado Pago não confere com este pedido. Nada foi alterado. Tente de novo em instantes ou fale com o suporte.' });
    if (r.result === 'in_review') return reply('error', { code: 'in_review', message: 'O pagamento com cartão deste pedido está em análise no Mercado Pago e não pode ser cancelado agora. Aguarde a resposta.' });
    return reply('error', { code: 'unverified', message: 'Não foi possível confirmar com o Mercado Pago agora. Nada foi alterado. Tente cancelar de novo em instantes.' });
  }

  // R175b · pode cobrar de novo neste pedido? Só com confirmação: nenhum pagamento ('none') ou só tentativas recusadas/
  // canceladas. Em análise, estornado ou inconclusivo → bloqueia. (R175c: tentativa incerta → ver resolveAttempt.)
  cardBlock(ref, chk) {
    if (chk.state === 'unknown') return { code: 'provider_unverified', message: 'Não foi possível confirmar com o Mercado Pago se este pedido já foi pago. Nada foi cobrado agora. Tente de novo em alguns instantes.' };
    if (chk.state === 'pending') return { code: 'payment_in_review', message: 'Já existe um pagamento deste pedido em análise no Mercado Pago. Nada novo foi cobrado. Aguarde a resposta.' };
    if (chk.state === 'refunded') return { code: 'provider_unverified', message: 'Este pedido tem um pagamento estornado no Mercado Pago. Nada foi cobrado agora. Comece um novo pedido ou fale com o suporte.' };
    if (!['none', 'failed', 'cancelled'].includes(chk.state)) return { code: 'provider_unverified', message: 'Não foi possível confirmar o estado deste pedido. Nada foi cobrado agora. Tente de novo em alguns instantes.' };
    return null;
  }

  // ---------------------------------------------------------------- R175c · tentativa de cartão PERSISTENTE
  // Antes de mandar QUALQUER cobrança de cartão, o servidor grava no pedido (payments.raw.card_attempt) a tentativa
  // { id, state: 'inflight' } com compare-and-set (status pending + versão do raw). Só depois envia ao Mercado Pago,
  // com metadata.fraiha_attempt = id. Enquanto existir card_attempt, NENHUMA nova cobrança sai — em qualquer instância,
  // aba ou aparelho, e depois de qualquer reinício. Ela só é liberada quando o provedor CONFIRMA o resultado DESSA
  // tentativa (recusada/cancelada → libera; aprovada → entrega; em análise, vazio, erro ou dúvida → continua bloqueado).
  attemptOf(row) { const a = row && row.raw && row.raw.card_attempt; return a && typeof a === 'object' && a.id ? a : null; }
  rawWith(row, change, histEvent) {
    const cur = (row.raw && typeof row.raw === 'object' && !Array.isArray(row.raw)) ? row.raw : {};
    const rev = Number.isInteger(Number(cur.rev)) && Number(cur.rev) > 0 ? Number(cur.rev) : 0;
    const next = { ...cur, ...change, rev: rev + 1 };
    if (histEvent) next.history = [...(Array.isArray(cur.history) ? cur.history : []), { at: new Date(this.now()).toISOString(), ...histEvent }].slice(-20);
    return { rev, next };
  }
  async casRaw(row, change, histEvent) {
    if (!this.store.casPaymentRaw) return null;
    const { rev, next } = this.rawWith(row, change, histEvent);
    return this.store.casPaymentRaw(this.provider.name, row.provider_ref, row.status, rev, next);
  }
  // muda a tentativa gravada SÓ se ela ainda for a mesma (relê e tenta de novo se outra escrita mudou a versão)
  async updateAttempt(ref, attemptId, change, histEvent) {
    for (let i = 0; i < 4; i++) {
      const row = await this.store.getPayment(this.provider.name, ref);
      const a = this.attemptOf(row);
      if (!row || !a || a.id !== attemptId) return null;
      const done = await this.casRaw(row, { card_attempt: change === null ? null : { ...a, ...change } }, histEvent);
      if (done) return done;
    }
    return null;
  }
  attemptBlock(code) {
    const M = {
      payment_unconfirmed: 'A tentativa anterior com cartão ainda não foi confirmada pelo Mercado Pago. Nada novo foi cobrado. Aguarde e confira em MINHAS COMPRAS: assim que o Mercado Pago confirmar, o pedido é atualizado.',
      payment_in_review: 'Já existe um pagamento deste pedido em análise no Mercado Pago. Nada novo foi cobrado. Aguarde a resposta.',
      attempt_busy: 'Outra tentativa de pagamento deste pedido está em andamento (outra aba ou aparelho). Nada novo foi cobrado. Aguarde alguns segundos.',
      provider_unverified: 'Não foi possível confirmar com o Mercado Pago o resultado da tentativa anterior. Nada novo foi cobrado. Tente de novo em alguns instantes.',
    };
    return { block: true, code, message: M[code] || M.provider_unverified };
  }
  // → { free: true, row } | { paid: ev } | { block, code, message }
  async resolveAttempt(row) {
    const a = this.attemptOf(row);
    if (!a) return { free: true, row };
    const ref = row.provider_ref;
    if (!this.provider.findAttempt) return this.attemptBlock('provider_unverified');
    let ev;
    try { ev = await this.provider.findAttempt(ref, a.id); }
    catch (e) { console.warn('[pagamentos] tentativa de cartão sem confirmação (consulta falhou)', ref, a.id, e && e.message); return this.attemptBlock('provider_unverified'); }
    if (ev === null || ev === undefined) return this.attemptBlock('payment_unconfirmed');   // busca vazia/defasada: NUNCA libera
    if (!this.validEvent(ev, ref)) return this.attemptBlock('provider_unverified');
    if (ev.status === 'paid') return { paid: ev };
    if (ev.status === 'pending') return this.attemptBlock('payment_in_review');
    if (ev.status !== 'failed' && ev.status !== 'cancelled') return this.attemptBlock('provider_unverified');
    // provedor CONFIRMOU que esta tentativa foi recusada/cancelada → libera (compare-and-set)
    const done = await this.updateAttempt(ref, a.id, null, { event: 'card_attempt_resolved', attempt: a.id, provider_status: ev.status, provider_payment_id: String(ev.providerPaymentId) });
    if (!done) return this.attemptBlock('attempt_busy');
    return { free: true, row: done };
  }

  // R175d · INCERTEZA DA CONTA: uma tentativa de cartão incerta/em andamento em QUALQUER pedido da conta (mesmo vencido,
  // expirado ou cancelado) bloqueia nova cobrança e novo pedido até o provedor confirmar o resultado dela.
  //   aprovada → entrega o pedido antigo e NÃO deixa cobrar de novo · recusada/cancelada confirmada → libera
  //   em análise, vazio, erro, timeout, resposta inválida → continua bloqueado. Tempo sozinho nunca libera.
  async accountGate(userId, exceptRef) {
    if (!this.store.listPaymentsWithAttempt) return null;
    let rows;
    try { rows = await this.store.listPaymentsWithAttempt(userId); }
    catch (e) { console.error('[pagamentos] não deu para conferir tentativas de cartão da conta', userId, e && e.message); return this.accountBlock('previous_attempt_unconfirmed'); }
    for (const row of rows || []) {
      if (!row || row.provider_ref === exceptRef || !this.attemptOf(row)) continue;
      const res = await this.resolveAttempt(row);
      if (res.free) continue;
      if (res.paid) {
        try { await this.apply(res.paid); } catch (e) { console.error('[pagamentos] entrega do pedido anterior', row.provider_ref, e && e.message); }
        return this.accountBlock('previous_payment_confirmed', row);
      }
      console.warn('[pagamentos] conta com tentativa de cartão NÃO reconciliada — nova cobrança bloqueada', userId, row.provider_ref, res.code);
      return this.accountBlock('previous_attempt_unconfirmed', row);
    }
    return null;
  }
  accountBlock(code, row) {
    const M = {
      previous_payment_confirmed: 'Um pagamento anterior com cartão foi confirmado agora pelo Mercado Pago e entregue na sua conta. Nada novo foi cobrado. Confira em MINHAS COMPRAS antes de comprar de novo.',
      previous_attempt_unconfirmed: 'Um pagamento anterior com cartão ainda não foi confirmado pelo Mercado Pago. Para não cobrar duas vezes, novas compras ficam bloqueadas até essa confirmação. Nada novo foi cobrado. Confira em MINHAS COMPRAS em alguns minutos.',
    };
    return { block: true, code, message: M[code], charge_id: row ? row.provider_ref : '' };
  }

  // R40 · Cartão no jogo: o navegador manda o TOKEN do formulário seguro do Mercado Pago; o servidor
  // cria o pagamento com o preço do servidor, no pedido (ref) que pertence a este jogador.
  async cardPay(ws, m, seenGeneration, receivedAt) {
    const ref = String(m.charge_id || '');
    const reply = (status, extra = {}) => this.send(ws, { type: 'payment_card_result', charge_id: ref, status, ...extra });
    const row = this.store.getPayment ? await this.store.getPayment(this.provider.name, ref) : null;
    if (!row || row.user_id !== ws.user.id || (row.method && row.method !== 'card')) return reply('error', { message: 'Pedido de pagamento não encontrado. Feche e comece de novo.' });
    if (row.status === 'paid') return reply('approved');
    if (row.status === 'cancelled') return reply('error', { code: 'order_closed', message: 'Este pedido foi cancelado. Nada foi cobrado. Feche e comece um novo pedido.' });
    if (row.status !== 'pending') return reply('error', { message: 'Este pedido não está mais aberto. Feche e comece de novo.' });
    if (this.expired(row)) return reply('error', { code: 'order_expired', message: 'Este pedido expirou. Nada foi cobrado. Feche e comece um novo pedido.' });
    if (!this.provider.payCard) return reply('error', { message: 'Pagamento com cartão no jogo indisponível. Use a página do Mercado Pago.' });
    const token = String(m.token || ''), pm = String(m.payment_method_id || '');
    if (!/^[A-Za-z0-9_-]{8,128}$/.test(token) || !/^[a-z0-9_]{2,40}$/.test(pm)) return reply('rejected', { message: 'Dados do cartão incompletos. Confira e tente de novo.' });
    // R175 · pedido retomado / segunda tentativa: se ESTE pedido já foi aprovado no Mercado Pago (confirmação que não
    // chegou), entrega o que já foi pago e NÃO cobra de novo com o token novo. A idempotência é do pedido, não do token.
    // R175b · FAIL CLOSED: só cobra se o provedor CONFIRMAR que não há aprovação anterior. Consulta com erro, timeout,
    // resposta inválida/incompleta ou de outro pedido → não cobra, não usa o token, pede para tentar depois.
    const deliver = async (prior) => {
      try { await this.apply(prior); } catch (e) { console.error('payment_card_pay apply prévio', e && e.message); }
      const after = await this.store.getPayment(this.provider.name, ref);
      if (after && after.status === 'paid') return reply('approved');
      if (after && after.status === 'sold_out') return reply('sold_out', { message: 'As vagas do Pacote Fundador acabaram no exato momento do seu pagamento. Você NÃO recebeu o pacote e o valor será devolvido integralmente.' });
      return reply('error', { message: 'Este pedido já foi pago no Mercado Pago e a confirmação está chegando. Nada novo foi cobrado. Aguarde alguns segundos.' });
    };
    const chk = await this.providerCheck(ref);
    if (chk.state === 'paid') return deliver(chk.ev);
    {   // R175d · tentativa incerta em OUTRO pedido da conta (mesmo vencido) → não cobra este
      const g = await this.accountGate(ws.user.id, ref);
      if (g) return reply('error', { code: g.code, message: g.message });
    }
    const block = this.cardBlock(ref, chk);
    if (block) { console.warn('payment_card_pay: nova cobrança BLOQUEADA', ref, block.code, chk.why || ''); return reply('error', { code: block.code, message: block.message }); }
    // R175c · tentativa anterior gravada no pedido (incerta / em andamento): só segue com confirmação DELA no provedor
    const res = await this.resolveAttempt(row);
    if (res.paid) return deliver(res.paid);
    if (res.block) { console.warn('payment_card_pay: tentativa anterior não confirmada — nova cobrança BLOQUEADA', ref, res.code); return reply('error', { code: res.code, message: res.message }); }
    this.cardAttempts = this.cardAttempts || new Map();
    const n = (this.cardAttempts.get(ref) || 0) + 1;
    if (n > CARD_ATTEMPTS) return reply('rejected', { message: 'Muitas tentativas neste pedido. Feche e comece de novo, ou pague com PIX.' });
    const product = PRODUCTS[row.product_id];
    if (!product) return reply('error', { message: 'Produto inválido.' });
    // R175c/e · grava a tentativa ANTES de enviar (write-ahead), pela porta ÚNICA do banco (0028, fraiha_card_attempt_begin):
    // trava a conta, confere o pedido, nenhuma tentativa ativa na conta e que a requisição não é antiga (geração vista no
    // recebimento). Só o vencedor envia o POST; sem a 0028 o cartão FALHA FECHADO (nada é cobrado).
    const attemptId = crypto.randomUUID();
    if (typeof seenGeneration !== 'number' || !Number.isFinite(seenGeneration) || !this.store.cardAttemptBegin)
      return reply('error', { code: 'card_unavailable', message: 'O pagamento com cartão está temporariamente indisponível. Nada foi cobrado. Tente de novo em instantes ou pague com PIX.' });
    let begin;
    try { begin = await this.store.cardAttemptBegin({ userId: ws.user.id, provider: this.provider.name, ref, attemptId, seenGeneration, receivedAt: receivedAt || new Date(this.now()).toISOString() }); }
    catch (e) { console.error('[pagamentos] fraiha_card_attempt_begin falhou', ref, e && e.message); begin = { ok: false, reason: 'error' }; }
    if (!begin || begin.missing) {
      console.error('[pagamentos] migração 0028 ausente: cartão FECHADO');
      return reply('error', { code: 'card_unavailable', message: 'O pagamento com cartão está temporariamente indisponível. Nada foi cobrado. Tente de novo em instantes ou pague com PIX.' });
    }
    if (!begin.ok) {
      const why = String(begin.reason || '');
      console.warn('payment_card_pay: tentativa RECUSADA pela guarda da conta', ref, why);
      if (why === 'previous_attempt_unconfirmed') return reply('error', { code: why, message: this.accountBlock(why).message });
      if (why === 'payment_in_progress') return reply('error', { code: why, message: 'Outra tentativa de pagamento desta conta foi iniciada enquanto esta aguardava. Nada foi cobrado por esta. Se ainda quiser comprar, confira MINHAS COMPRAS e tente de novo.' });
      if (why === 'order_closed') return reply('error', { code: 'order_closed', message: 'Este pedido não está mais aberto. Nada foi cobrado. Feche e comece de novo.' });
      return reply('error', { code: 'card_unavailable', message: 'Não foi possível iniciar o pagamento com cartão agora. Nada foi cobrado. Tente de novo em instantes.' });
    }
    this.cardAttempts.set(ref, n);
    const amountCents = Number(row.amount_cents) || product.amount_cents;
    const uncertain = async (why) => {
      console.error('[pagamentos] cobrança de cartão com resultado INCERTO — pedido bloqueado até o provedor confirmar', ref, attemptId, why);
      await this.updateAttempt(ref, attemptId, { state: 'uncertain', uncertain_at: new Date(this.now()).toISOString(), why: String(why || '').slice(0, 120) },
        { event: 'card_attempt_uncertain', attempt: attemptId }).catch(() => null);   // mesmo se falhar, a marca 'inflight' continua bloqueando
      return reply('error', { code: 'payment_unconfirmed', message: 'O Mercado Pago não confirmou o resultado do pagamento. NÃO tente de novo agora: assim que o Mercado Pago confirmar, o pedido é atualizado (confira em MINHAS COMPRAS).' });
    };
    let ev;
    try {
      ev = await this.provider.payCard({ ref, token, paymentMethodId: pm, issuerId: String(m.issuer_id || '').replace(/[^0-9]/g, '').slice(0, 12),
        amountCents, title: product.title, email: ws.user.email, idType: String(m.id_type || '').replace(/[^A-Za-z]/g, '').slice(0, 8),
        idNumber: String(m.id_number || '').replace(/[^0-9]/g, '').slice(0, 20), deviceId: String(m.device_id || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 120),
        userId: ws.user.id, productId: row.product_id, attemptId });
    } catch (e) {
      // R175d · só libera quando o erro PROVA que a cobrança não foi criada (definitiveNoCharge: 401 ou 400 com causa de
      // validação conhecida). Qualquer outro erro (outros 4xx, 400 sem causa reconhecida, 5xx, timeout, rede) = INCERTO.
      if (definitiveNoCharge(e)) {
        console.warn('payment_card_pay recusado pela API antes de criar o pagamento', e.status, (e.causes || []).join(','), e.message);
        await this.updateAttempt(ref, attemptId, null, { event: 'card_attempt_refused', attempt: attemptId, http_status: e.status, causes: (e.causes || []).join(',') }).catch(() => null);
        return reply('rejected', { message: CARD_REJECT_DEFAULT });
      }
      return uncertain(e && e.message);
    }
    if (!this.validEvent(ev, ref)) return uncertain('resposta da cobrança não confere com o pedido');
    if (ev.status === 'paid') {
      await this.updateAttempt(ref, attemptId, { state: 'approved', provider_payment_id: String(ev.providerPaymentId) }, { event: 'card_attempt_approved', attempt: attemptId, provider_payment_id: String(ev.providerPaymentId) }).catch(() => null);
      try { await this.apply(ev); }
      catch (e) { console.error('payment_card_pay apply', e && e.message); return reply('error', { message: 'Pagamento aprovado, mas a confirmação ainda não chegou. Aguarde alguns segundos: a vantagem aparece sozinha.' }); }
      const after = await this.store.getPayment(this.provider.name, ref);
      if (after && after.status === 'paid') return reply('approved');
      if (after && after.status === 'sold_out') return reply('sold_out', { message: 'As vagas do Pacote Fundador acabaram no exato momento do seu pagamento. Você NÃO recebeu o pacote e o valor será devolvido integralmente.' });   // R171 · SEC-009
      return reply('error', { message: 'Pagamento aprovado, mas a confirmação ainda não chegou. Aguarde alguns segundos: a vantagem aparece sozinha.' });
    }
    if (ev.status === 'pending') {
      await this.updateAttempt(ref, attemptId, { state: 'pending', provider_payment_id: String(ev.providerPaymentId) }, { event: 'card_attempt_in_review', attempt: attemptId }).catch(() => null);
      return reply('pending', { message: 'Pagamento em análise pelo Mercado Pago. Assim que for aprovado, a vantagem aparece sozinha.' });
    }
    if (ev.status === 'failed' || ev.status === 'cancelled') {
      // recusa CONFIRMADA na própria resposta desta tentativa → libera para outro cartão
      const freed = await this.updateAttempt(ref, attemptId, null, { event: 'card_attempt_rejected', attempt: attemptId, provider_payment_id: String(ev.providerPaymentId), detail: String(ev.detail || '') }).catch(() => null);
      if (!freed) console.warn('[pagamentos] recusa confirmada mas a tentativa não foi liberada agora (será resolvida na próxima)', ref, attemptId);
      return reply('rejected', { detail: ev.detail || '', message: CARD_REJECT[ev.detail] || CARD_REJECT_DEFAULT });
    }
    return uncertain('estado inesperado: ' + ev.status);
  }

  // Aplica um evento do provedor (webhook ou consulta). Idempotente: cada transição acontece uma vez.
  //   pending → paid       : confere valor e moeda, libera o direito
  //   pending → cancelled  : PIX expirado / cobrança cancelada
  //   paid    → refunded   : reembolso ou contestação (chargeback): o direito é retirado
  //   rejected (cartão)    : continua pending (o jogador pode tentar outro cartão no mesmo checkout)
  async apply(ev) {
    const ref = String(ev.providerRef || '');
    if (!ref || !this.store.getPayment) return { ok: false, reason: 'no_ref' };
    // R175 · uma aplicação por pedido de cada vez (webhook duplicado, JÁ PAGUEI, cartão e CANCELAR na mesma hora)
    return this.lock('ref:' + ref, () => this.applyLocked(ev, ref));
  }
  async applyLocked(ev, ref) {
    let row = await this.store.getPayment(this.provider.name, ref);
    if (!row) { console.warn('[pagamentos] notificação sem pedido conhecido', ref); return { ok: false, reason: 'unknown_ref' }; }
    let changed = null;
    if (ev.status === 'paid') {
      const expected = PRODUCTS[row.product_id] ? PRODUCTS[row.product_id].amount_cents : -1;
      const amount = Number(row.amount_cents) || expected;
      if (ev.currency !== 'BRL' || Number(ev.amountCents) !== amount) {
        console.error('[pagamentos] valor/moeda não confere — direito NÃO liberado', ref, ev.amountCents, ev.currency, amount);
        return { ok: false, reason: 'amount_mismatch' };
      }
      // R175 · aprovado DEPOIS de cancelado/expirado (ou de um pedido marcado como falho): o pagamento confirmado
      // nunca se perde. O MESMO pedido volta a "aguardando" com o histórico preservado no raw (cancelamento +
      // aprovação tardia) e passa pela rotina única de entrega (fraiha_pay_and_grant, 0023): com vaga entrega 1 vez;
      // sem vaga vira sold_out + reembolso. Nunca entrega fora dela.
      if ((row.status === 'cancelled' || row.status === 'failed') && this.store.reopenPayment) {
        console.error('[pagamentos] pagamento APROVADO depois de ' + row.status + ' — pedido reaberto para a entrega normal', ref, row.user_id);
        const reopened = await this.store.reopenPayment(this.provider.name, ref, { event: 'provider_approved_after_' + row.status,
          provider_payment_id: String(ev.providerPaymentId || ''), previous_status: row.status });
        if (!reopened) row = await this.store.getPayment(this.provider.name, ref) || row;
      }
      changed = await this.payAndGrant(ref, row.product_id);
      if (changed && changed.status === 'sold_out') return this.soldOut(changed, ref, ev);   // R171 · SEC-009
      if (changed && this.backend.referrals) this.backend.referrals.onPurchase(changed.user_id);   // R105 · +30 dias para quem convidou
      if (changed && this.backend.creators) this.backend.creators.onPurchase({ ref, user_id: changed.user_id, product_id: row.product_id, amount_cents: amount });   // R121
    } else if (ev.status === 'cancelled') {
      // R175 · cancelado/expirado no Mercado Pago: registra o motivo e libera a reserva do Fundador
      changed = this.store.cancelPayment
        ? await this.store.cancelPayment(this.provider.name, ref, { reason: ev.detail === 'expired' ? 'expired' : 'provider', provider_payment_id: String(ev.providerPaymentId || '') })
        : await this.store.markPayment(this.provider.name, ref, 'cancelled');
    } else if (ev.status === 'refunded') {
      changed = this.store.markRefund ? await this.store.markRefund(this.provider.name, ref) : null;
      if (changed && this.backend.creators) this.backend.creators.onRefund(ref);   // R121 · comissão não paga é cancelada
      if (changed && changed.was === 'sold_out') console.log('[pagamentos] reembolso concluído de pagamento sem vaga (sold_out)', ref);
      else if (changed && this.store.revokeEntitlement) {
        try { await this.store.revokeEntitlement(changed.user_id, changed.product_id); }
        catch (e) { console.error('[pagamentos] REEMBOLSO SEM RETIRAR DIREITO (aplique a migração 0010)', ref, e && e.message); }
      }
    }
    // R175d · aviso/consulta do provedor sobre o pagamento de uma tentativa gravada: recusa/cancelamento CONFIRMADO
    // dessa tentativa libera a marca (a aprovação já foi tratada acima: pedido pago).
    if ((ev.status === 'failed' || ev.status === 'cancelled') && ev.attempt && this.validEvent(ev, ref)) {
      const cur = await this.store.getPayment(this.provider.name, ref);
      const a = this.attemptOf(cur);
      if (a && a.id === ev.attempt) await this.updateAttempt(ref, a.id, null, { event: 'card_attempt_resolved', attempt: a.id, provider_status: ev.status, provider_payment_id: String(ev.providerPaymentId) }).catch(() => null);
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
