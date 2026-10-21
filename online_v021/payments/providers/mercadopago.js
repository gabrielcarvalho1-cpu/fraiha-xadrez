'use strict';
// R39 · Provedor MERCADO PAGO (PIX + cartão). Só roda no servidor; o Godot nunca vê chave nem dado de cartão.
//
//  PIX    → POST /v1/payments (payment_method_id 'pix'): devolve QR (imagem base64) + Copia e Cola.
//  Cartão → POST /checkout/preferences (Checkout Pro, página do Mercado Pago): devolve o link (init_point).
//  Cartão no jogo (R40) → o formulário seguro do Mercado Pago (Card Payment Brick) roda no navegador e
//            devolve só um TOKEN de uso único; o servidor cria o pagamento (POST /v1/payments com o token),
//            sempre com o PREÇO DO SERVIDOR. Número/CVV nunca passam pelo FRAIHA.
//  Webhook → a notificação só diz "o pagamento X mudou"; o servidor CONSULTA o pagamento na API
//            (GET /v1/payments/X) e só confia no que a API responde (status, valor, external_reference).
//            Com segredo configurado, a assinatura x-signature é conferida (HMAC-SHA256 do manifesto
//            "id:<data.id>;request-id:<x-request-id>;ts:<ts>;") e notificação com assinatura errada é recusada.
//
// Variáveis de ambiente (Render → Environment; NUNCA no repositório nem no Godot):
//   FRAIHA_PAYMENT_PROVIDER   = mercadopago
//   FRAIHA_MP_ACCESS_TOKEN    = Access Token da aplicação (produção: APP_USR-…; teste: credencial de teste)
//   FRAIHA_MP_WEBHOOK_SECRET  = "Assinatura secreta" da tela de Webhooks da aplicação
//   FRAIHA_MP_PUBLIC_KEY      = Public Key da aplicação (pública: vai para o formulário de cartão no jogo).
//                               Sem ela, o cartão continua na página do Mercado Pago (Checkout Pro).
//   FRAIHA_PUBLIC_URL         = URL pública HTTPS deste servidor (ex.: https://fraiha-xadrez-staging.onrender.com)
//   FRAIHA_GAME_URL           = para onde o checkout do cartão volta (padrão https://jogar.fraihaxadrez.com)
//   FRAIHA_PIX_MINUTES        = validade do PIX em minutos (padrão 30)
//   FRAIHA_MP_API             = só para testes (servidor falso local)
const crypto = require('crypto');

const STATUS = {
  approved: 'paid',
  authorized: 'pending', pending: 'pending', in_process: 'pending', in_mediation: 'pending',
  rejected: 'failed',
  cancelled: 'cancelled',
  refunded: 'refunded', charged_back: 'refunded',
};

// "2026-10-04T15:30:00.000-03:00" (horário de Brasília, como nos exemplos do Mercado Pago)
function brt(ms) {
  const d = new Date(ms - 3 * 3600 * 1000).toISOString().replace('Z', '');
  return d + '-03:00';
}

// R40.1 · Detalhes do item (recomendação do Mercado Pago para a análise antifraude aprovar mais).
const DESCRIPTIONS = {
  founder: 'Pacote Fundador FRAIHA Xadrez: selo, título, avatar, moldura e 30 dias de Club (compra única, sem vantagem em partida)',
  club_monthly: 'Club FRAIHA Xadrez: 30 dias de análises e treino (sem renovação automática, sem vantagem em partida)',
};
function itemInfo(productId, title, amount) {
  return { id: productId, title, description: DESCRIPTIONS[productId] || title, category_id: 'virtual_goods', quantity: 1, unit_price: amount };
}

// Proteção: se a API recusar os detalhes extras (400 citando additional_info/category/item/descriptor),
// tenta UMA vez sem eles — a cobrança nunca deixa de sair por causa de um campo opcional.
async function withOptional(send, body, strip) {
  try { return await send(body, ''); }
  catch (e) {
    if (e.status === 400 && /additional_info|category|items?\b|statement_descriptor|descriptor/i.test(String(e.message))) {
      console.warn('[pagamentos] Mercado Pago recusou campo opcional; repetindo sem ele:', e.message);
      return send(strip(body), ':sem-extras');   // outra chave de idempotência (a 1ª ficou guardada como erro)
    }
    throw e;
  }
}
const stripExtras = (b) => { const c = { ...b }; delete c.additional_info; delete c.statement_descriptor; return c; };

class MercadoPago {
  constructor(env = process.env) {
    this.name = 'mercadopago';
    this.token = String(env.FRAIHA_MP_ACCESS_TOKEN || '').trim();
    this.secret = String(env.FRAIHA_MP_WEBHOOK_SECRET || '').trim();
    this.requireSignature = /^(1|true|sim)$/i.test(String(env.FRAIHA_MP_REQUIRE_SIGNATURE || '').trim()) && !!this.secret;   // R110
    // R170 · SEC-006: aviso SEM assinatura não pode virar consulta paga em massa: no máximo N por minuto (total),
    // 2 consultas simultâneas e o mesmo pagamento é consultado no máximo 1 vez a cada 60 s.
    this.unsignedPerMin = Math.max(1, Number(env.FRAIHA_MP_UNSIGNED_PER_MIN) || 30);
    this.unsignedWin = { start: 0, n: 0 };
    this.unsignedActive = 0;
    this.recentLookups = new Map();   // data.id -> quando foi consultado (sem assinatura)
    this.inflight = new Set();        // R171 · SEC-006: avisos sem assinatura sendo consultados/aplicados agora
    this.publicKey = String(env.FRAIHA_MP_PUBLIC_KEY || '').trim();
    this.api = String(env.FRAIHA_MP_API || 'https://api.mercadopago.com').replace(/\/+$/, '');
    this.publicUrl = String(env.FRAIHA_PUBLIC_URL || '').replace(/\/+$/, '');
    this.gameUrl = String(env.FRAIHA_GAME_URL || 'https://jogar.fraihaxadrez.com');
    this.pixMinutes = Math.max(5, Math.min(1440, Number(env.FRAIHA_PIX_MINUTES) || 30));
    this.timeoutMs = Number(env.FRAIHA_MP_TIMEOUT_MS) || 12000;
  }
  ready() { return !!this.token && !!this.publicUrl; }
  // O que falta configurar (para o log do servidor; nunca mostra valores).
  missing() { return ['FRAIHA_MP_ACCESS_TOKEN', 'FRAIHA_PUBLIC_URL'].filter(k => !(k === 'FRAIHA_MP_ACCESS_TOKEN' ? this.token : this.publicUrl)); }

  async call(method, path, body, idem, extraHeaders) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), this.timeoutMs);
    try {
      const headers = { Authorization: 'Bearer ' + this.token, 'Content-Type': 'application/json' };
      if (idem) headers['X-Idempotency-Key'] = idem;
      if (extraHeaders) Object.assign(headers, extraHeaders);
      const res = await fetch(this.api + path, { method, headers, body: body ? JSON.stringify(body) : undefined, signal: ctl.signal });
      const text = await res.text();
      let data = null; try { data = text ? JSON.parse(text) : null; } catch { data = null; }
      if (!res.ok) {
        const e = new Error('mercadopago ' + method + ' ' + path.split('?')[0] + ' → ' + res.status + ' ' + (data && (data.message || data.error) || ''));
        e.status = res.status; e.code = 'provider_error';
        // R175d · códigos de causa do Mercado Pago (cause[].code) para classificar o erro com segurança
        e.causes = (data && Array.isArray(data.cause) ? data.cause : []).map(c => String(c && c.code !== undefined ? c.code : '')).filter(Boolean);
        throw e;
      }
      return data || {};
    } finally { clearTimeout(timer); }
  }

  // ref = id interno do FRAIHA (external_reference): liga a notificação ao pedido sem confiar no cliente.
  // idemSuffix (R175): CONTINUAR um pedido de cartão gera outra preferência para o MESMO pedido (mesmo external_reference)
  async createCharge({ ref, userId, productId, method, amountCents, title, email, idemSuffix = '' }) {
    if (!this.ready()) { const e = new Error('Mercado Pago sem configuração: ' + this.missing().join(', ')); e.code = 'provider_not_configured'; throw e; }
    const notification_url = this.publicUrl + '/webhooks/payments';
    const amount = Math.round(amountCents) / 100;
    const metadata = { fraiha_ref: ref, user_id: userId, product_id: productId };
    if (method === 'pix') {
      const expires = Date.now() + this.pixMinutes * 60 * 1000;
      const p = await withOptional((b, k) => this.call('POST', '/v1/payments', b, ref + k), {
        transaction_amount: amount, description: title, payment_method_id: 'pix',
        payer: { email }, external_reference: ref, notification_url,
        date_of_expiration: brt(expires), metadata, statement_descriptor: 'FRAIHA XADREZ',
        additional_info: { items: [itemInfo(productId, title, amount)] },
      }, stripExtras);
      const td = (p.point_of_interaction && p.point_of_interaction.transaction_data) || {};
      if (!td.qr_code) { const e = new Error('mercadopago: PIX sem qr_code'); e.code = 'provider_error'; throw e; }
      return { id: ref, provider_payment_id: String(p.id || ''), method: 'pix', status: 'pending',
        copy_paste: String(td.qr_code), qr_code_base64: String(td.qr_code_base64 || ''), ticket_url: String(td.ticket_url || ''),
        expires_at: new Date(expires).toISOString() };
    }
    if (method === 'card') {
      const expires = Date.now() + 24 * 3600 * 1000;
      const pref = await withOptional((b, k) => this.call('POST', '/checkout/preferences', b, ref + idemSuffix + k), {
        items: [{ ...itemInfo(productId, title, amount), currency_id: 'BRL' }],
        payer: { email }, external_reference: ref, notification_url,
        back_urls: { success: this.gameUrl, pending: this.gameUrl, failure: this.gameUrl }, auto_return: 'approved',
        payment_methods: { excluded_payment_types: [{ id: 'ticket' }, { id: 'atm' }] },
        statement_descriptor: 'FRAIHA XADREZ',
        expires: true, expiration_date_to: brt(expires), metadata,
      }, (b) => ({ ...b, items: b.items.map(({ id, title, quantity, unit_price, currency_id }) => ({ id, title, quantity, unit_price, currency_id })), statement_descriptor: undefined }));
      if (!pref.init_point) { const e = new Error('mercadopago: preferência sem init_point'); e.code = 'provider_error'; throw e; }
      const out = { id: ref, method: 'card', status: 'pending', checkout_url: String(pref.init_point), expires_at: new Date(expires).toISOString() };
      if (this.publicKey) out.public_key = this.publicKey;   // formulário de cartão dentro do jogo (Web)
      return out;
    }
    const e = new Error('método inválido'); e.code = 'bad_request'; throw e;
  }

  // Assinatura x-signature: "ts=<ms>,v1=<hex>". Manifesto oficial: id:<data.id>;request-id:<x-request-id>;ts:<ts>;
  // (data.id vem da URL da notificação e vai em minúsculas). Partes ausentes ficam de fora.
  signatureOk(req, dataId) {
    const sig = String(req.headers['x-signature'] || '');
    const parts = {};
    for (const kv of sig.split(',')) { const i = kv.indexOf('='); if (i > 0) parts[kv.slice(0, i).trim()] = kv.slice(i + 1).trim(); }
    if (!parts.ts || !parts.v1) return false;
    const rid = String(req.headers['x-request-id'] || '');
    let manifest = '';
    if (dataId) manifest += 'id:' + String(dataId).toLowerCase() + ';';
    if (rid) manifest += 'request-id:' + rid + ';';
    manifest += 'ts:' + parts.ts + ';';
    const mine = crypto.createHmac('sha256', this.secret).update(manifest).digest('hex');
    const a = Buffer.from(mine, 'utf8'), b = Buffer.from(String(parts.v1).toLowerCase(), 'utf8');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  }

  // Devolve { ignore:true } (notificação que não é de pagamento), null (assinatura inválida) ou o evento:
  //   { providerRef, status:'paid'|'pending'|'failed'|'cancelled'|'refunded', amountCents, currency, providerPaymentId }
  async verifyWebhook(req, rawBody) {
    const url = new URL(req.url || '/', 'http://local');
    let body = {}; try { body = rawBody ? JSON.parse(rawBody) : {}; } catch { body = {}; }
    const type = String(url.searchParams.get('type') || url.searchParams.get('topic') || body.type || body.topic || '');
    const dataId = String(url.searchParams.get('data.id') || (body.data && body.data.id) || url.searchParams.get('id') || '');
    if (!dataId || (type && type !== 'payment')) return { ignore: true };
    if (!/^[A-Za-z0-9_-]{1,40}$/.test(dataId)) return null;   // R170 · formato conferido ANTES de qualquer trabalho
    if (this.secret && req.headers['x-signature'] && !this.signatureOk(req, dataId)) return null;
    // R110 · aviso SEM assinatura: com FRAIHA_MP_REQUIRE_SIGNATURE=1 é recusado. Sem a variável continua aceito
    // (a consulta abaixo na API do Mercado Pago é a fonte da verdade, então não há fraude possível), mas fica
    // registrado no log para conferir antes de ligar a exigência.
    if (!req.headers['x-signature']) {
      if (this.requireSignature) return null;
      console.warn('[pagamentos] aviso do Mercado Pago sem assinatura (x-signature) — tipo ' + (type || '?'));
      // R170 · SEC-006: limites só para o caminho SEM assinatura (o assinado segue normal)
      // R171 · SEC-006 (reteste Orca): "já processado" só é marcado DEPOIS que a consulta E a aplicação deram certo
      // (webhookSettled). Consulta que falhou não vira "ignorado": a próxima tentativa consulta de novo.
      // Repetição enquanto a 1ª ainda está em andamento recebe 503 (o provedor tenta de novo), nunca 200 calado.
      const t = Date.now();
      const last = this.recentLookups.get(dataId);
      if (last && t - last < 60e3) return { ignore: true };   // repetido: já consultado E aplicado há pouco
      if (this.inflight.has(dataId)) return { busy: true };
      if (t - this.unsignedWin.start >= 60e3) this.unsignedWin = { start: t, n: 0 };
      if (++this.unsignedWin.n > this.unsignedPerMin || this.unsignedActive >= 2) return { busy: true };   // 503: o provedor tenta de novo depois
      this.inflight.add(dataId);
      this.unsignedActive++;
      let ev;
      try { ev = await this.lookup(dataId); }
      catch (e) { this.inflight.delete(dataId); throw e; }   // falha transitória: nada marcado, retry consulta de novo
      finally { this.unsignedActive--; }
      if (!ev) { this.inflight.delete(dataId); throw new Error('consulta ao Mercado Pago sem resposta'); }   // R172: vazio = falha (retry), nunca "processado"
      if (ev.ignore) { this.webhookSettled(dataId, true); return ev; }   // consulta OK, nada a aplicar
      return { ...ev, unsignedId: dataId };
    }
    if (!/^[A-Za-z0-9_-]{1,40}$/.test(dataId)) return null;
    return this.lookup(dataId);
  }

  // R171 · SEC-006: chamado pelo serviço depois de aplicar (ok=true) ou falhar (ok=false) um aviso sem assinatura
  webhookSettled(id, ok) {
    if (!id) return;
    this.inflight.delete(id);
    if (!ok) return;
    if (this.recentLookups.size > 5000) this.recentLookups.clear();
    this.recentLookups.set(id, Date.now());
  }

  // R171 · SEC-009: estorno integral (pagamento de Fundador aprovado sem vaga). Idempotente pela chave.
  async refund(paymentId) {
    if (!/^[0-9]{1,30}$/.test(String(paymentId || ''))) throw new Error('payment id inválido para estorno');
    return this.call('POST', '/v1/payments/' + encodeURIComponent(paymentId) + '/refunds', {}, 'fraiha-refund-' + paymentId);
  }

  // Consulta oficial do pagamento (a fonte da verdade).
  async lookup(paymentId) {
    const p = await this.call('GET', '/v1/payments/' + encodeURIComponent(paymentId));
    return this.event(p);
  }

  // Busca pelo id interno (quando o jogador pergunta "já pagou?" e o webhook ainda não chegou).
  async findByRef(ref) {
    const pick = await this.findRawByRef(ref);
    return pick ? this.event(pick) : null;
  }
  // R175 · o pagamento do Mercado Pago mais importante deste pedido: aprovado > reembolsado > em análise > o mais recente.
  // R175b · resposta sem a lista "results" é INVÁLIDA (erro, nunca "nenhum pagamento"); itens de outro pedido ou sem
  // id também invalidam a consulta inteira — o serviço trata como inconclusivo e não cobra/cancela.
  async searchByRef(ref) {
    const r = await this.call('GET', '/v1/payments/search?sort=date_created&criteria=desc&external_reference=' + encodeURIComponent(ref));
    if (!r || !Array.isArray(r.results)) { const e = new Error('mercadopago: busca sem lista de resultados'); e.code = 'provider_invalid'; throw e; }
    const list = r.results;
    for (const p of list) {
      if (!p || String(p.external_reference || '') !== String(ref) || !p.id) { const e = new Error('mercadopago: busca devolveu pagamento de outro pedido ou incompleto'); e.code = 'provider_invalid'; throw e; }
    }
    return list;
  }
  // R175c · o pagamento de UMA tentativa de cartão (metadata.fraiha_attempt gravado na cobrança). null = a busca não
  // mostra essa tentativa (ainda) — para o serviço isso é inconclusivo, nunca "pode cobrar".
  async findAttempt(ref, attemptId) {
    const list = (await this.searchByRef(ref)).filter(p => p.metadata && String(p.metadata.fraiha_attempt || '') === String(attemptId));
    const pick = list.find(p => p.status === 'approved') || list.find(p => ['pending', 'in_process', 'authorized', 'in_mediation'].includes(p.status)) || list[0];
    return pick ? this.event(pick) : null;
  }
  async findRawByRef(ref) {
    const list = await this.searchByRef(ref);
    return list.find(p => p.status === 'approved') || list.find(p => p.status === 'refunded' || p.status === 'charged_back')
      || list.find(p => ['pending', 'in_process', 'authorized', 'in_mediation'].includes(p.status)) || list[0] || null;
  }

  // R175 · CONTINUAR um PIX: devolve o MESMO pagamento (mesmo QR / Copia e Cola), nunca cria outro.
  //   → { event }                         pagamento já não está aberto (pago, cancelado, expirado…)
  //   → { charge }                        ainda aberto: QR + Copia e Cola + validade reais do Mercado Pago
  //   → null                              nenhum PIX deste pedido no Mercado Pago
  async resumePix(ref) {
    const found = await this.findRawByRef(ref);
    if (!found) return null;
    const p = found.id ? await this.call('GET', '/v1/payments/' + encodeURIComponent(found.id)) : found;
    const ev = this.event(p);
    const exp = p.date_of_expiration ? Date.parse(p.date_of_expiration) : NaN;
    if (ev.status !== 'pending' || (Number.isFinite(exp) && exp <= Date.now())) return { event: { ...ev, expired: Number.isFinite(exp) && exp <= Date.now() } };
    const td = (p.point_of_interaction && p.point_of_interaction.transaction_data) || {};
    if (!td.qr_code) return { event: ev, no_qr: true };
    return { event: ev, charge: { id: ref, provider_payment_id: String(p.id || ''), method: 'pix', status: 'pending',
      copy_paste: String(td.qr_code), qr_code_base64: String(td.qr_code_base64 || ''), ticket_url: String(td.ticket_url || ''),
      expires_at: Number.isFinite(exp) ? new Date(exp).toISOString() : '' } };
  }

  // R175 · CANCELAR no Mercado Pago um pagamento ainda aberto (PIX pendente). Devolve o estado real depois do pedido.
  async cancel(paymentId) {
    if (!/^[0-9]{1,30}$/.test(String(paymentId || ''))) throw new Error('payment id inválido para cancelar');
    const p = await this.call('PUT', '/v1/payments/' + encodeURIComponent(paymentId), { status: 'cancelled' });
    // R175b · a resposta tem de ser do MESMO pagamento (o serviço confere também o external_reference do pedido)
    if (!p || String(p.id || '') !== String(paymentId)) { const e = new Error('mercadopago: resposta do cancelamento é de outro pagamento'); e.code = 'provider_mismatch'; throw e; }
    return this.event(p);
  }

  // R40 · Cartão no jogo: cria o pagamento com o token do Card Payment Brick.
  // amountCents vem do SERVIDOR (preço do produto); nada do valor enviado pelo navegador é usado.
  // binary_mode: aprova ou recusa na hora (sem "em análise"), então o jogador sabe o resultado no ato.
  async payCard({ ref, token, paymentMethodId, issuerId, amountCents, title, email, idType, idNumber, deviceId, userId, productId, attemptId = '' }) {
    if (!this.ready()) { const e = new Error('Mercado Pago sem configuração: ' + this.missing().join(', ')); e.code = 'provider_not_configured'; throw e; }
    const body = {
      transaction_amount: Math.round(amountCents) / 100, token, description: title, installments: 1,
      payment_method_id: paymentMethodId, payer: { email }, external_reference: ref,
      notification_url: this.publicUrl + '/webhooks/payments', statement_descriptor: 'FRAIHA XADREZ', binary_mode: true,
      metadata: { fraiha_ref: ref, user_id: userId, product_id: productId, fraiha_attempt: attemptId },   // R175c · liga a cobrança à tentativa gravada no pedido
      additional_info: { items: [itemInfo(productId, title, Math.round(amountCents) / 100)] },
    };
    if (issuerId) body.issuer_id = issuerId;
    if (idType && idNumber) body.payer.identification = { type: idType, number: idNumber };
    const extra = deviceId ? { 'X-meli-session-id': deviceId } : null;
    // Idempotência pelo token: o mesmo token (clique repetido) nunca vira duas cobranças.
    const idem = ref + ':card:' + crypto.createHash('sha256').update(token).digest('hex').slice(0, 24);
    const p = await withOptional((b, k) => this.call('POST', '/v1/payments', b, idem + k, extra), body, stripExtras);
    return this.event(p);
  }

  event(p) {
    return {
      providerRef: String(p.external_reference || ''),
      status: STATUS[String(p.status || '')] || 'pending',
      amountCents: Math.round(Number(p.transaction_amount || 0) * 100),
      currency: String(p.currency_id || ''),
      providerPaymentId: String(p.id || ''),
      detail: String(p.status_detail || ''),
      attempt: String((p.metadata && p.metadata.fraiha_attempt) || ''),   // R175c/d · tentativa de cartão que gerou este pagamento
    };
  }
}

module.exports = { create: (env) => new MercadoPago(env), MercadoPago, STATUS, brt };
