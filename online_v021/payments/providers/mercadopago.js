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

class MercadoPago {
  constructor(env = process.env) {
    this.name = 'mercadopago';
    this.token = String(env.FRAIHA_MP_ACCESS_TOKEN || '').trim();
    this.secret = String(env.FRAIHA_MP_WEBHOOK_SECRET || '').trim();
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
        e.status = res.status; e.code = 'provider_error'; throw e;
      }
      return data || {};
    } finally { clearTimeout(timer); }
  }

  // ref = id interno do FRAIHA (external_reference): liga a notificação ao pedido sem confiar no cliente.
  async createCharge({ ref, userId, productId, method, amountCents, title, email }) {
    if (!this.ready()) { const e = new Error('Mercado Pago sem configuração: ' + this.missing().join(', ')); e.code = 'provider_not_configured'; throw e; }
    const notification_url = this.publicUrl + '/webhooks/payments';
    const amount = Math.round(amountCents) / 100;
    const metadata = { fraiha_ref: ref, user_id: userId, product_id: productId };
    if (method === 'pix') {
      const expires = Date.now() + this.pixMinutes * 60 * 1000;
      const p = await this.call('POST', '/v1/payments', {
        transaction_amount: amount, description: title, payment_method_id: 'pix',
        payer: { email }, external_reference: ref, notification_url,
        date_of_expiration: brt(expires), metadata,
      }, ref);
      const td = (p.point_of_interaction && p.point_of_interaction.transaction_data) || {};
      if (!td.qr_code) { const e = new Error('mercadopago: PIX sem qr_code'); e.code = 'provider_error'; throw e; }
      return { id: ref, provider_payment_id: String(p.id || ''), method: 'pix', status: 'pending',
        copy_paste: String(td.qr_code), qr_code_base64: String(td.qr_code_base64 || ''), ticket_url: String(td.ticket_url || ''),
        expires_at: new Date(expires).toISOString() };
    }
    if (method === 'card') {
      const expires = Date.now() + 24 * 3600 * 1000;
      const pref = await this.call('POST', '/checkout/preferences', {
        items: [{ id: productId, title, quantity: 1, unit_price: amount, currency_id: 'BRL' }],
        payer: { email }, external_reference: ref, notification_url,
        back_urls: { success: this.gameUrl, pending: this.gameUrl, failure: this.gameUrl }, auto_return: 'approved',
        payment_methods: { excluded_payment_types: [{ id: 'ticket' }, { id: 'atm' }] },
        statement_descriptor: 'FRAIHA XADREZ',
        expires: true, expiration_date_to: brt(expires), metadata,
      }, ref);
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
    if (this.secret && req.headers['x-signature'] && !this.signatureOk(req, dataId)) return null;
    if (!/^[A-Za-z0-9_-]{1,40}$/.test(dataId)) return null;
    return this.lookup(dataId);
  }

  // Consulta oficial do pagamento (a fonte da verdade).
  async lookup(paymentId) {
    const p = await this.call('GET', '/v1/payments/' + encodeURIComponent(paymentId));
    return this.event(p);
  }

  // Busca pelo id interno (quando o jogador pergunta "já pagou?" e o webhook ainda não chegou).
  async findByRef(ref) {
    const r = await this.call('GET', '/v1/payments/search?sort=date_created&criteria=desc&external_reference=' + encodeURIComponent(ref));
    const list = Array.isArray(r.results) ? r.results : [];
    const pick = list.find(p => p.status === 'approved') || list.find(p => p.status === 'refunded' || p.status === 'charged_back') || list[0];
    return pick ? this.event(pick) : null;
  }

  // R40 · Cartão no jogo: cria o pagamento com o token do Card Payment Brick.
  // amountCents vem do SERVIDOR (preço do produto); nada do valor enviado pelo navegador é usado.
  // binary_mode: aprova ou recusa na hora (sem "em análise"), então o jogador sabe o resultado no ato.
  async payCard({ ref, token, paymentMethodId, issuerId, amountCents, title, email, idType, idNumber, deviceId, userId, productId }) {
    if (!this.ready()) { const e = new Error('Mercado Pago sem configuração: ' + this.missing().join(', ')); e.code = 'provider_not_configured'; throw e; }
    const body = {
      transaction_amount: Math.round(amountCents) / 100, token, description: title, installments: 1,
      payment_method_id: paymentMethodId, payer: { email }, external_reference: ref,
      notification_url: this.publicUrl + '/webhooks/payments', statement_descriptor: 'FRAIHA XADREZ', binary_mode: true,
      metadata: { fraiha_ref: ref, user_id: userId, product_id: productId },
    };
    if (issuerId) body.issuer_id = issuerId;
    if (idType && idNumber) body.payer.identification = { type: idType, number: idNumber };
    const extra = deviceId ? { 'X-meli-session-id': deviceId } : null;
    // Idempotência pelo token: o mesmo token (clique repetido) nunca vira duas cobranças.
    const idem = ref + ':card:' + crypto.createHash('sha256').update(token).digest('hex').slice(0, 24);
    const p = await this.call('POST', '/v1/payments', body, idem, extra);
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
    };
  }
}

module.exports = { create: (env) => new MercadoPago(env), MercadoPago, STATUS, brt };
