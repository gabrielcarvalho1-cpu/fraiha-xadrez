'use strict';
// R194 · COMPRAS PELO GOOGLE PLAY (app Android baixado da Play Store). O APK do site continua sem compras e o site
// continua com o Mercado Pago. Mesmo desenho das compras pela Apple (apple.js):
//   app (Play Billing) cobra  →  { type:'payment_google', product_id, purchase_token }  →  este módulo pergunta ao
//   Google (Google Play Developer API, conta de serviço do servidor)  →  confere pacote, produto, dono, estado  →
//   payments (provider 'google', ref 'google:<sha256(token)>')  →  fraiha_pay_and_grant (vagas do Fundador, Club)  →
//   Fundador: o servidor confirma (acknowledge) no Google; Club: o app consome (pode comprar de novo)  →  app finaliza.
// Regras: o app nunca confirma sozinho; cada compra entrega uma vez; a compra fica presa à conta
// (obfuscatedExternalAccountId = id da conta); sem configuração → fail-closed (o Google guarda a compra; sem
// confirmação em 3 dias o Google devolve o dinheiro sozinho — por isso o app reenvia ao abrir).
// Configuração (só no servidor, nunca no Godot nem no Git):
//   FRAIHA_GOOGLE_PLAY_SERVICE_ACCOUNT = JSON da conta de serviço com acesso à Play Console (Financeiro: ver pedidos)
//   FRAIHA_GOOGLE_PLAY_PACKAGE         = com.fraihaxadrez.app (padrão)
//   FRAIHA_GOOGLE_PLAY_TEST            = 1 → aceita compras de teste (testadores de licença). Em produção, vazio.
const crypto = require('crypto');

// produto da Play Console → produto do FRAIHA. Club = consumível (comprar de novo soma dias); Fundador = compra única.
const GOOGLE_PRODUCTS = {
  'club.mensal': { id: 'club_monthly', consumable: true },
  'club.anual': { id: 'club_yearly', consumable: true },
  'fundador': { id: 'founder', consumable: false },
  'fundador.lendario': { id: 'founder_legend', consumable: false },
};
const TOKEN_RE = /^[A-Za-z0-9._:\-]{20,600}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/';
const b64url = buf => Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

class GooglePlay {
  constructor({ payments, env = process.env, fetchImpl = null, now = () => Date.now() }) {
    this.payments = payments;
    let sa = null;
    try { const raw = String(env.FRAIHA_GOOGLE_PLAY_SERVICE_ACCOUNT || '').trim(); if (raw) sa = JSON.parse(raw); } catch { sa = null; }
    this.sa = sa && sa.client_email && sa.private_key ? { email: sa.client_email, key: String(sa.private_key).replace(/\\n/g, '\n'), tokenUri: sa.token_uri || 'https://oauth2.googleapis.com/token' } : null;
    this.pkg = String(env.FRAIHA_GOOGLE_PLAY_PACKAGE || 'com.fraihaxadrez.app').trim();
    this.allowTest = /^(1|true|sim)$/i.test(String(env.FRAIHA_GOOGLE_PLAY_TEST || '').trim());
    this.fetch = fetchImpl || ((...a) => fetch(...a));
    this.now = now;
    this._access = null;
  }
  ready() { return !!this.sa; }
  get store() { return this.payments.store; }
  send(ws, o) { this.payments.send(ws, o); }

  // token de acesso OAuth da conta de serviço (JWT RS256 → oauth2.googleapis.com), reaproveitado até 5 min antes de vencer
  async accessToken() {
    const t = Math.floor(this.now() / 1000);
    if (this._access && this._access.exp - 300 > t) return this._access.value;
    const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const body = b64url(JSON.stringify({ iss: this.sa.email, scope: 'https://www.googleapis.com/auth/androidpublisher', aud: this.sa.tokenUri, iat: t, exp: t + 3600 }));
    const sig = crypto.sign('sha256', Buffer.from(head + '.' + body), this.sa.key);
    const r = await this.fetch(this.sa.tokenUri, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: 'grant_type=' + encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer') + '&assertion=' + head + '.' + body + '.' + b64url(sig) });
    if (r.status !== 200) { const e = new Error('google_auth_' + r.status); e.code = 'auth'; throw e; }
    const j = await r.json();
    this._access = { value: j.access_token, exp: t + (Number(j.expires_in) || 3600) };
    return this._access.value;
  }
  url(productId, token, suffix = '') {
    return API + encodeURIComponent(this.pkg) + '/purchases/products/' + encodeURIComponent(productId) + '/tokens/' + encodeURIComponent(token) + suffix;
  }
  async lookup(productId, token) {
    const r = await this.fetch(this.url(productId, token), { headers: { Authorization: 'Bearer ' + await this.accessToken() } });
    if (r.status === 200) return r.json();
    const e = new Error('google_lookup_' + r.status); e.code = r.status === 404 || r.status === 400 || r.status === 410 ? 'not_found' : 'http_' + r.status; throw e;
  }
  async acknowledge(productId, token) {
    const r = await this.fetch(this.url(productId, token, ':acknowledge'), { method: 'POST', headers: { Authorization: 'Bearer ' + await this.accessToken(), 'content-type': 'application/json' }, body: '{}' });
    if (r.status !== 200 && r.status !== 204) { const e = new Error('google_ack_' + r.status); e.code = 'ack'; throw e; }
  }

  check(p, ws) {
    if (!p || typeof p !== 'object') return { error: 'mismatch', message: 'Compra não reconhecida pelo Google.' };
    if (Number(p.purchaseState) === 1) return { error: 'cancelled', message: 'Esta compra foi cancelada.' };
    if (Number(p.purchaseState) === 2) return { error: 'pending', message: 'Pagamento pendente no Google Play. A compra é entregue assim que for aprovada.' };
    if (Number(p.purchaseState) !== 0) return { error: 'mismatch', message: 'Compra não reconhecida pelo Google.' };
    if (p.purchaseType !== undefined && Number(p.purchaseType) === 0 && !this.allowTest) return { error: 'test', message: 'Compra de teste não vale no jogo publicado.' };
    const owner = String(p.obfuscatedExternalAccountId || '').toLowerCase();
    if (!owner || owner !== String(ws.user.id).toLowerCase()) return { error: 'owner', message: 'Esta compra foi feita em outra conta FRAIHA.' };
    return {};
  }

  // { type:'payment_google', product_id, purchase_token } → payment_google_result { ok, finish, consume, ... }
  async handle(ws, m) {
    const gid = String(m.product_id || ''), token = String(m.purchase_token || '');
    const reply = o => this.send(ws, { type: 'payment_google_result', purchase_token: token, product_id: gid, ...o });
    const prod = GOOGLE_PRODUCTS[gid];
    if (!prod || !TOKEN_RE.test(token)) return reply({ ok: false, finish: false, code: 'bad_request', message: 'Compra inválida.' });
    if (!this.ready()) return reply({ ok: false, finish: false, code: 'google_not_configured', message: 'As compras pelo Google Play ainda não estão ativas. Sua compra fica guardada e será entregue assim que estiverem.' });
    if (!UUID_RE.test(String(ws.user.id))) return reply({ ok: false, finish: false, code: 'auth_required', message: 'Entre na sua conta para receber a compra.' });
    const ref = 'google:' + crypto.createHash('sha256').update(token).digest('hex').slice(0, 40);
    return this.payments.lock(ref, async () => {
      let row = await this.store.getPayment('google', ref);
      if (row && row.user_id !== ws.user.id) return reply({ ok: false, finish: false, code: 'owner', message: 'Esta compra pertence a outra conta FRAIHA.' });
      if (row && (row.status === 'paid' || row.status === 'sold_out' || row.status === 'refunded')) {
        if (!prod.consumable && row.status === 'paid') await this.acknowledge(gid, token).catch(() => {});   // idempotente
        return reply({ ok: row.status === 'paid', finish: true, consume: prod.consumable && row.status === 'paid', status: row.status, already: true, fraiha_id: row.product_id });
      }
      let p;
      try { p = await this.lookup(gid, token); }
      catch (e) {
        console.error('[google] consulta da compra falhou', ref, e && e.code);
        return reply({ ok: false, finish: false, code: 'google_unavailable', message: 'Não conseguimos confirmar com o Google agora. A compra fica guardada e tentamos de novo.' });
      }
      const c = this.check(p, ws);
      if (c.error) {
        console.error('[google] compra recusada', ref, c.error);
        return reply({ ok: false, finish: c.error === 'cancelled' || c.error === 'test', code: c.error, message: c.message });
      }
      const { PRODUCTS } = require('./service');
      const priceCents = PRODUCTS[prod.id] ? PRODUCTS[prod.id].amount_cents : 0;
      if (!row) row = await this.store.createPayment({ user_id: ws.user.id, product_id: prod.id, method: 'card', provider: 'google', provider_ref: ref, amount_cents: priceCents, status: 'pending' });
      if (PRODUCTS[prod.id] && PRODUCTS[prod.id].founder && !(await this.payments.capacityReady()))
        return reply({ ok: false, finish: false, code: 'founder_capacity_not_ready', message: 'Confirmando a sua vaga de Fundador. Tentamos de novo em instantes.' });
      let changed;
      try { changed = await this.store.payAndGrant('google', ref, 'google'); }
      catch (e) {
        console.error('[google] entrega falhou — compra continua pendente', ref, e && e.message);
        return reply({ ok: false, finish: false, code: 'grant_failed', message: 'Recebemos a compra, mas a entrega atrasou. Tentamos de novo em instantes.' });
      }
      if (changed && changed.missing) {
        changed = await this.store.markPayment('google', ref, 'paid');
        if (changed && this.store.grantEntitlement) await this.store.grantEntitlement(changed.user_id, changed.product_id, 'google');
      }
      if (changed && changed.status === 'sold_out') {
        console.error('[google] VAGAS DO FUNDADOR ESGOTADAS no momento da compra pelo Google Play — sem confirmar: o Google devolve em 3 dias', ref, ws.user.id);
        // não confirma (acknowledge): sem confirmação o Google reembolsa sozinho em até 3 dias
        return reply({ ok: false, finish: true, consume: false, status: 'sold_out', fraiha_id: prod.id, code: 'founder_sold_out_paid',
          message: 'As vagas do Pacote Fundador acabaram no exato momento da sua compra. Você não recebeu o pacote e o Google Play devolve o valor automaticamente em até 3 dias.' });
      }
      const now = await this.store.getPayment('google', ref);
      const ok = !!(now && now.status === 'paid');
      if (ok && !prod.consumable) await this.acknowledge(gid, token).catch(e => console.error('[google] confirmação no Google falhou (tenta de novo quando o app reenviar)', ref, e && e.code));
      if (changed && this.payments.backend.referrals) this.payments.backend.referrals.onPurchase(changed.user_id);
      if (changed && this.payments.backend.creators) this.payments.backend.creators.onPurchase({ ref, user_id: changed.user_id, product_id: prod.id, amount_cents: priceCents });
      reply({ ok, finish: ok, consume: ok && prod.consumable, status: now ? now.status : 'pending', fraiha_id: prod.id });
      for (const s of this.payments.backend.socketsOf(ws.user.id)) await this.payments.backend.state(s);
    });
  }
}

module.exports = { GooglePlay, GOOGLE_PRODUCTS };
