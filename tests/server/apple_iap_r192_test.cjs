'use strict';
// R192 · compras pela Apple (app de iPhone): o servidor confere cada transação na App Store Server API (aqui, uma Apple
// falsa) e entrega pela MESMA rotina do Mercado Pago. Nada é entregue sem a Apple confirmar; nada é entregue duas vezes.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');

const U1 = '11111111-1111-4111-8111-111111111111';
const U2 = '22222222-2222-4222-8222-222222222222';
const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });
const b64u = o => Buffer.from(JSON.stringify(o)).toString('base64url');

function fakeApple(txs) {
  const calls = [];
  const impl = async (url, opts) => {
    calls.push({ url, auth: opts && opts.headers && opts.headers.Authorization });
    const id = url.split('/').pop();
    const tx = txs[id];
    if (!tx) return { status: 404, json: async () => ({}) };
    if (tx === 'down') return { status: 500, json: async () => ({}) };
    return { status: 200, json: async () => ({ signedTransactionInfo: b64u({ alg: 'ES256' }) + '.' + b64u(tx) + '.sig' }) };
  };
  return { impl, calls };
}

function setup({ env = {}, txs = {}, limit = 100 } = {}) {
  const store = new MemoryStore(); const sent = [];
  const backend = { store, socketsOf: () => [], state: async () => {} };
  const qe = console.error, ql = console.log; console.error = () => {}; console.log = () => {};
  const pay = new Payments({ send: (ws, o) => sent.push({ to: ws.user && ws.user.id, ...o }), backend,
    env: { FRAIHA_PAYMENT_PROVIDER: '', FRAIHA_FOUNDER_LIMIT: String(limit), FRAIHA_APPLE_IAP_ISSUER_ID: 'iss', FRAIHA_APPLE_IAP_KEY_ID: 'KEY123', FRAIHA_APPLE_IAP_PRIVATE_KEY: PEM, ...env } });
  const apple = fakeApple(txs);
  pay.apple.fetch = apple.impl;
  const ws = id => ({ user: { id }, profile: { nickname: 'x' } });
  const buy = async (uid, tx) => { await pay.handle(ws(uid), { type: 'payment_apple', transaction_id: tx }); return sent.filter(o => o.type === 'payment_apple_result').pop(); };
  return { store, pay, sent, buy, apple, restore: () => { console.error = qe; console.log = ql; } };
}
const tx = (id, product, owner, extra = {}) => ({ transactionId: id, originalTransactionId: id, bundleId: 'com.fraihaxadrez.app', productId: product,
  appAccountToken: owner, environment: 'Production', price: 19900, currency: 'BRL', ...extra });

test('sem chave da Apple no servidor: nada é entregue e o app NÃO finaliza (a Apple guarda a compra)', async () => {
  const t = setup({ env: { FRAIHA_APPLE_IAP_KEY_ID: '' }, txs: { '100': tx('100', 'com.fraihaxadrez.app.club.mensal', U1) } });
  try {
    const r = await t.buy(U1, '100');
    assert.equal(r.ok, false); assert.equal(r.finish, false); assert.equal(r.code, 'apple_not_configured');
    assert.equal(t.apple.calls.length, 0);
    const e = await t.store.getEntitlements(U1); assert.ok(!e || !e.club_active);
  } finally { t.restore(); }
});

test('Club 30 dias: a Apple confirma → Club ativo, finaliza; repetir a mesma transação não soma de novo', async () => {
  const t = setup({ txs: { '200': tx('200', 'com.fraihaxadrez.app.club.mensal', U1) } });
  try {
    const r = await t.buy(U1, '200');
    assert.equal(r.ok, true); assert.equal(r.finish, true); assert.equal(r.product_id, 'club_monthly');
    const e1 = await t.store.getEntitlements(U1); assert.equal(e1.club_active, true);
    const exp1 = e1.club_expires_at;
    const again = await t.buy(U1, '200');
    assert.equal(again.ok, true); assert.equal(again.already, true);
    assert.equal((await t.store.getEntitlements(U1)).club_expires_at, exp1, 'não somou outros 30 dias');
    assert.match(t.apple.calls[0].auth, /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/, 'pede à Apple com token assinado');
    const p = await t.store.getPayment('apple', 'apple:200'); assert.equal(p.amount_cents, 1990); assert.equal(p.status, 'paid');
  } finally { t.restore(); }
});

test('token ES256 do servidor confere com a chave', async () => {
  const t = setup();
  try {
    const [h, b, s] = t.pay.apple.token().split('.');
    assert.equal(JSON.parse(Buffer.from(h, 'base64url')).kid, 'KEY123');
    assert.equal(JSON.parse(Buffer.from(b, 'base64url')).bid, 'com.fraihaxadrez.app');
    assert.ok(crypto.verify('sha256', Buffer.from(h + '.' + b), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url')));
  } finally { t.restore(); }
});

test('compra feita em OUTRA conta não é entregue a quem mandou', async () => {
  const t = setup({ txs: { '300': tx('300', 'com.fraihaxadrez.app.club.anual', U2) } });
  try {
    const r = await t.buy(U1, '300');
    assert.equal(r.ok, false); assert.equal(r.code, 'owner'); assert.equal(r.finish, false);
    const e = await t.store.getEntitlements(U1); assert.ok(!e || !e.club_active);
  } finally { t.restore(); }
});

test('recusas definitivas: outro app, compra de teste no jogo publicado, devolvida, produto desconhecido', async () => {
  const t = setup({ txs: {
    '401': tx('401', 'com.fraihaxadrez.app.club.mensal', U1, { bundleId: 'com.outro.app' }),
    '402': tx('402', 'com.fraihaxadrez.app.club.mensal', U1, { environment: 'Sandbox' }),
    '403': tx('403', 'com.fraihaxadrez.app.club.mensal', U1, { revocationDate: 1 }),
    '404': tx('404', 'com.fraihaxadrez.app.moedas', U1) } });
  try {
    for (const [id, code] of [['401', 'bundle'], ['402', 'sandbox'], ['403', 'revoked'], ['404', 'product']]) {
      const r = await t.buy(U1, id);
      assert.equal(r.ok, false, id); assert.equal(r.code, code, id); assert.equal(r.finish, true, id);
    }
    const e = await t.store.getEntitlements(U1); assert.ok(!e || !e.club_active);
  } finally { t.restore(); }
});

test('TestFlight: com FRAIHA_APPLE_SANDBOX=1 a compra de teste vale (consulta também o ambiente de teste)', async () => {
  const t = setup({ env: { FRAIHA_APPLE_SANDBOX: '1' }, txs: { '500': tx('500', 'com.fraihaxadrez.app.club.mensal', U1, { environment: 'Sandbox' }) } });
  try {
    const r = await t.buy(U1, '500');
    assert.equal(r.ok, true);
  } finally { t.restore(); }
});

test('Apple fora do ar ou transação que não existe: nada entregue, o app guarda para tentar de novo', async () => {
  const t = setup({ txs: { '600': 'down' } });
  try {
    for (const id of ['600', '601']) {
      const r = await t.buy(U1, id);
      assert.equal(r.ok, false); assert.equal(r.finish, false); assert.equal(r.code, 'apple_unavailable');
    }
    assert.equal(await t.store.getPayment('apple', 'apple:600'), null);
  } finally { t.restore(); }
});

test('Fundador com 1 vaga: o 1º recebe; o 2º pagou na Apple sem vaga → sold_out, aviso de reembolso e finaliza', async () => {
  const t = setup({ limit: 1, txs: { '700': tx('700', 'com.fraihaxadrez.app.fundador', U1, { price: 49900 }), '701': tx('701', 'com.fraihaxadrez.app.fundador', U2, { price: 49900 }) } });
  try {
    await t.pay.capacityReady();
    const a = await t.buy(U1, '700');
    assert.equal(a.ok, true); assert.equal((await t.store.getEntitlements(U1)).is_founder, true);
    const b = await t.buy(U2, '701');
    assert.equal(b.ok, false); assert.equal(b.status, 'sold_out'); assert.equal(b.finish, true);
    assert.match(b.message, /reembolso/);
    const e2 = await t.store.getEntitlements(U2); assert.ok(!e2 || !e2.is_founder);
    assert.equal(await t.store.countFounders(), 1);
  } finally { t.restore(); }
});

test('id de transação inválido e convidado: recusados sem consultar a Apple', async () => {
  const t = setup();
  try {
    const r = await t.buy(U1, '12ab');
    assert.equal(r.code, 'bad_request');
    await t.pay.handle({ user: null }, { type: 'payment_apple', transaction_id: '1' });
    assert.equal(t.sent.pop().code, 'auth_required');
    assert.equal(t.apple.calls.length, 0);
  } finally { t.restore(); }
});

test('oferta da loja avisa se as compras pela Apple estão ativas', async () => {
  const t = setup();
  try {
    const o = await t.pay.offer({ user: { id: U1 } });
    assert.equal(o.apple_ready, true);
  } finally { t.restore(); }
});
