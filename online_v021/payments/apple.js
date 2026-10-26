'use strict';
// R192 · COMPRAS PELA APPLE (app de iPhone). O Mercado Pago continua no site e no Android; no iPhone a Apple cobra.
//
// Fluxo:
//   iPhone (StoreKit) cobra  →  app manda { type:'payment_apple', transaction_id }  →  este módulo pergunta à Apple
//   (App Store Server API, com a chave do servidor)  →  confere app, produto, dono e se não foi devolvida  →
//   grava em payments (provider 'apple', ref 'apple:<transactionId>')  →  fraiha_pay_and_grant entrega a vantagem
//   (a MESMA rotina do Mercado Pago: vagas do Fundador, Club +30 dias/+1 ano)  →  responde e o app finaliza a compra.
//
// Regras:
//   • o app NUNCA confirma compra sozinho: só vale o que a Apple devolver para a chave do servidor;
//   • cada transação da Apple entrega uma vez (provider+ref únicos); repetir (restaurar, app reaberto) não entrega de novo;
//   • a compra fica presa à conta: o app manda o id da conta como appAccountToken e aqui ele precisa bater;
//   • sem configuração → fail-closed: responde "indisponível" e o app NÃO finaliza a transação (a Apple guarda e
//     ela é reenviada quando o servidor estiver pronto) — nada é perdido.
// Configuração (só no servidor, nunca no Godot nem no Git):
//   FRAIHA_APPLE_IAP_ISSUER_ID   = Issuer ID (App Store Connect → Usuários e acesso → Integrações → Compra dentro do app)
//   FRAIHA_APPLE_IAP_KEY_ID      = Key ID da chave de Compra dentro do app
//   FRAIHA_APPLE_IAP_PRIVATE_KEY = conteúdo do arquivo .p8 (pode ter \n literais)
//   FRAIHA_APPLE_BUNDLE_ID       = com.fraihaxadrez.app (padrão)
//   FRAIHA_APPLE_SANDBOX         = 1 → aceita compras de teste (TestFlight/sandbox). Em produção deixe vazio.
const crypto = require('crypto');

// produto da App Store → produto do FRAIHA (mesmos ids de PRODUCTS em service.js)
const APPLE_PRODUCTS = {
  'com.fraihaxadrez.app.club.mensal': 'club_monthly',     // Assinatura sem renovação automática (30 dias)
  'com.fraihaxadrez.app.club.anual': 'club_yearly',       // Assinatura sem renovação automática (1 ano)
  'com.fraihaxadrez.app.fundador': 'founder',             // Não consumível
  'com.fraihaxadrez.app.fundador.lendario': 'founder_legend',
};
const PROD_API = 'https://api.storekit.itunes.apple.com';
const SANDBOX_API = 'https://api.storekit-sandbox.itunes.apple.com';
const TX_RE = /^[0-9]{1,30}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const b64url = buf => Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
// payload de um JWS da Apple (a resposta veio da própria Apple por HTTPS autenticado; aqui só lemos o conteúdo)
function jwsPayload(jws) {
  const parts = String(jws || '').split('.');
  if (parts.length !== 3) return null;
  try { return JSON.parse(Buffer.from(parts[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8')); } catch { return null; }
}

class AppleIAP {
  constructor({ payments, env = process.env, fetchImpl = null, now = () => Date.now() }) {
    this.payments = payments;
    this.issuer = String(env.FRAIHA_APPLE_IAP_ISSUER_ID || '').trim();
    this.keyId = String(env.FRAIHA_APPLE_IAP_KEY_ID || '').trim();
    this.privateKey = String(env.FRAIHA_APPLE_IAP_PRIVATE_KEY || '').replace(/\\n/g, '\n').trim();
    this.bundle = String(env.FRAIHA_APPLE_BUNDLE_ID || 'com.fraihaxadrez.app').trim();
    this.sandbox = /^(1|true|sim)$/i.test(String(env.FRAIHA_APPLE_SANDBOX || '').trim());
    this.fetch = fetchImpl || ((...a) => fetch(...a));
    this.now = now;
    this._jwt = null;
  }
  ready() { return !!(this.issuer && this.keyId && this.privateKey); }
  get store() { return this.payments.store; }
  send(ws, o) { this.payments.send(ws, o); }

  // token ES256 da App Store Server API (vale 20 min; reaproveitado por 15)
  token() {
    const t = Math.floor(this.now() / 1000);
    if (this._jwt && t - this._jwt.iat < 900) return this._jwt.value;
    const head = b64url(JSON.stringify({ alg: 'ES256', kid: this.keyId, typ: 'JWT' }));
    const body = b64url(JSON.stringify({ iss: this.issuer, iat: t, exp: t + 1200, aud: 'appstoreconnect-v1', bid: this.bundle }));
    const sig = crypto.sign('sha256', Buffer.from(head + '.' + body), { key: this.privateKey, dsaEncoding: 'ieee-p1363' });
    this._jwt = { iat: t, value: head + '.' + body + '.' + b64url(sig) };
    return this._jwt.value;
  }

  // consulta a transação na Apple (produção; com FRAIHA_APPLE_SANDBOX=1 tenta também o ambiente de teste)
  async lookup(txId) {
    const hosts = this.sandbox ? [PROD_API, SANDBOX_API] : [PROD_API];
    let last = null;
    for (const host of hosts) {
      const r = await this.fetch(host + '/inApps/v1/transactions/' + txId, { headers: { Authorization: 'Bearer ' + this.token() } });
      if (r.status === 200) {
        const j = await r.json();
        const tx = jwsPayload(j && j.signedTransactionInfo);
        if (tx) return tx;
        last = 'bad_payload';
      } else if (r.status === 404) { last = 'not_found'; continue; }
      else if (r.status === 401) { last = 'auth'; break; }
      else { last = 'http_' + r.status; break; }
    }
    const e = new Error('apple_lookup_' + last); e.code = last; throw e;
  }

  // confere o que a Apple devolveu. Devolve { productId } ou { error, message }
  check(tx, ws, txId) {
    if (!tx || String(tx.transactionId) !== txId) return { error: 'mismatch', message: 'Compra não reconhecida pela Apple.' };
    if (tx.bundleId !== this.bundle) return { error: 'bundle', message: 'Compra de outro aplicativo.' };
    if (tx.environment === 'Sandbox' && !this.sandbox) return { error: 'sandbox', message: 'Compra de teste não vale no jogo publicado.' };
    const productId = APPLE_PRODUCTS[tx.productId];
    if (!productId) return { error: 'product', message: 'Produto desconhecido.' };
    if (tx.revocationDate) return { error: 'revoked', message: 'Esta compra foi devolvida pela Apple.' };
    // a compra é da conta que a fez (appAccountToken = id da conta, enviado pelo app no momento da compra)
    const owner = String(tx.appAccountToken || '').toLowerCase();
    if (!owner || owner !== String(ws.user.id).toLowerCase()) return { error: 'owner', message: 'Esta compra foi feita em outra conta FRAIHA.' };
    return { productId };
  }

  // { type:'payment_apple', transaction_id } — sempre responde payment_apple_result; finish=true → o app pode finalizar
  async handle(ws, m) {
    const txId = String(m.transaction_id || '');
    const reply = (o) => this.send(ws, { type: 'payment_apple_result', transaction_id: txId, ...o });
    if (!TX_RE.test(txId)) return reply({ ok: false, finish: false, code: 'bad_request', message: 'Compra inválida.' });
    if (!this.ready()) return reply({ ok: false, finish: false, code: 'apple_not_configured', message: 'As compras pelo iPhone ainda não estão ativas. Sua compra fica guardada e será entregue assim que estiverem.' });
    if (!UUID_RE.test(String(ws.user.id))) return reply({ ok: false, finish: false, code: 'auth_required', message: 'Entre na sua conta para receber a compra.' });
    return this.payments.lock('apple:' + txId, async () => {
      const ref = 'apple:' + txId;
      let row = await this.store.getPayment('apple', ref);
      if (row && row.user_id !== ws.user.id) return reply({ ok: false, finish: false, code: 'owner', message: 'Esta compra pertence a outra conta FRAIHA.' });
      if (row && (row.status === 'paid' || row.status === 'sold_out' || row.status === 'refunded'))
        return reply({ ok: row.status === 'paid', finish: true, status: row.status, product_id: row.product_id, already: true });
      let tx;
      try { tx = await this.lookup(txId); }
      catch (e) {
        console.error('[apple] consulta da compra falhou', txId, e && e.code);
        return reply({ ok: false, finish: false, code: 'apple_unavailable', message: 'Não conseguimos confirmar com a Apple agora. A compra fica guardada e tentamos de novo.' });
      }
      const c = this.check(tx, ws, txId);
      if (c.error) {
        console.error('[apple] compra recusada', txId, c.error);
        // recusa definitiva (outro app, produto, devolvida, outra conta): finaliza para não ficar repetindo; nada é entregue
        return reply({ ok: false, finish: c.error !== 'owner', code: c.error, message: c.message });
      }
      const productId = c.productId;
      const { PRODUCTS } = require('./service');
      const priceCents = Number.isFinite(Number(tx.price)) ? Math.round(Number(tx.price) / 10) : (PRODUCTS[productId] ? PRODUCTS[productId].amount_cents : 0);
      if (!row) {
        row = await this.store.createPayment({ user_id: ws.user.id, product_id: productId, method: 'card', provider: 'apple', provider_ref: ref, amount_cents: priceCents, status: 'pending' });
      }
      // Fundador: só com o limite de vagas confirmado no banco (mesma regra do Mercado Pago)
      if (PRODUCTS[productId] && PRODUCTS[productId].founder && !(await this.payments.capacityReady()))
        return reply({ ok: false, finish: false, code: 'founder_capacity_not_ready', message: 'Confirmando a sua vaga de Fundador. Tentamos de novo em instantes.' });
      let changed;
      try { changed = await this.store.payAndGrant('apple', ref, 'apple'); }
      catch (e) {
        console.error('[apple] entrega falhou — compra continua pendente', ref, e && e.message);
        return reply({ ok: false, finish: false, code: 'grant_failed', message: 'Recebemos a compra, mas a entrega atrasou. Tentamos de novo em instantes.' });
      }
      if (changed && changed.missing) {   // banco sem a 0012: caminho antigo
        changed = await this.store.markPayment('apple', ref, 'paid');
        if (changed && this.store.grantEntitlement) await this.store.grantEntitlement(changed.user_id, changed.product_id, 'apple');
      }
      if (changed && changed.status === 'sold_out') {
        console.error('[apple] VAGAS DO FUNDADOR ESGOTADAS no momento da compra pela Apple — reembolso pela Apple', ref, ws.user.id);
        reply({ ok: false, finish: true, status: 'sold_out', product_id: productId, code: 'founder_sold_out_paid',
          message: 'As vagas do Pacote Fundador acabaram no exato momento da sua compra. Você não recebeu o pacote: peça o reembolso em reportaproblem.apple.com (a Apple devolve o valor).' });
        return;
      }
      if (changed && this.payments.backend.referrals) this.payments.backend.referrals.onPurchase(changed.user_id);
      if (changed && this.payments.backend.creators) this.payments.backend.creators.onPurchase({ ref, user_id: changed.user_id, product_id: productId, amount_cents: priceCents });
      const now = await this.store.getPayment('apple', ref);
      reply({ ok: !!(now && now.status === 'paid'), finish: !!(now && now.status === 'paid'), status: now ? now.status : 'pending', product_id: productId });
      for (const s of this.payments.backend.socketsOf(ws.user.id)) await this.payments.backend.state(s);
    });
  }
}

module.exports = { AppleIAP, APPLE_PRODUCTS, jwsPayload };
