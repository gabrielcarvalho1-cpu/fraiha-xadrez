'use strict';
// R194 · compras pelo Google Play (app da Play Store): o servidor confere cada compra na Google Play Developer API
// (aqui, um Google falso) e entrega pela MESMA rotina do Mercado Pago. Nada sem o Google confirmar; nada duas vezes.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');

const U1 = '11111111-1111-4111-8111-111111111111';
const U2 = '22222222-2222-4222-8222-222222222222';
const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const SA = JSON.stringify({ client_email: 'fraiha@proj.iam.gserviceaccount.com', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }), token_uri: 'https://oauth2.googleapis.com/token' });
const TOK = n => 'tok' + String(n).padStart(30, 'x');

function fakeGoogle(purchases) {
  const calls = [];
  const impl = async (url, opts = {}) => {
    calls.push({ url, method: opts.method || 'GET', body: opts.body, auth: opts.headers && opts.headers.Authorization });
    if (url.includes('oauth2.googleapis.com/token')) return { status: 200, json: async () => ({ access_token: 'ACCESS', expires_in: 3600 }) };
    const tok = decodeURIComponent(url.split('/tokens/')[1].split(':')[0]);
    if (url.endsWith(':acknowledge')) { if (purchases[tok]) purchases[tok].acknowledgementState = 1; return { status: 204, json: async () => ({}) }; }
    const p = purchases[tok];
    if (!p) return { status: 404, json: async () => ({}) };
    if (p === 'down') return { status: 503, json: async () => ({}) };
    return { status: 200, json: async () => ({ ...p }) };
  };
  return { impl, calls };
}
function setup({ env = {}, purchases = {}, limit = 100 } = {}) {
  const store = new MemoryStore(); const sent = [];
  const backend = { store, socketsOf: () => [], state: async () => {} };
  const qe = console.error, ql = console.log; console.error = () => {}; console.log = () => {};
  const pay = new Payments({ send: (ws, o) => sent.push(o), backend, env: { FRAIHA_FOUNDER_LIMIT: String(limit), FRAIHA_GOOGLE_PLAY_SERVICE_ACCOUNT: SA, ...env } });
  const g = fakeGoogle(purchases);
  pay.google.fetch = g.impl;
  const buy = async (uid, gid, tok) => { await pay.handle({ user: { id: uid }, profile: {} }, { type: 'payment_google', product_id: gid, purchase_token: tok }); return sent.filter(o => o.type === 'payment_google_result').pop(); };
  return { store, pay, sent, g, buy, restore: () => { console.error = qe; console.log = ql; } };
}
const purchase = (owner, extra = {}) => ({ purchaseState: 0, consumptionState: 0, acknowledgementState: 0, obfuscatedExternalAccountId: owner, orderId: 'GPA.1', ...extra });

test('sem a conta de serviço do Google: nada entregue, o app não finaliza', async () => {
  const t = setup({ env: { FRAIHA_GOOGLE_PLAY_SERVICE_ACCOUNT: '' }, purchases: { [TOK(1)]: purchase(U1) } });
  try {
    const r = await t.buy(U1, 'club.mensal', TOK(1));
    assert.equal(r.ok, false); assert.equal(r.finish, false); assert.equal(r.code, 'google_not_configured');
    assert.equal(t.g.calls.length, 0);
  } finally { t.restore(); }
});

test('Club 30 dias: Google confirma → Club ativo, o app consome; repetir não soma de novo', async () => {
  const t = setup({ purchases: { [TOK(2)]: purchase(U1) } });
  try {
    const r = await t.buy(U1, 'club.mensal', TOK(2));
    assert.equal(r.ok, true); assert.equal(r.finish, true); assert.equal(r.consume, true); assert.equal(r.fraiha_id, 'club_monthly');
    const e1 = await t.store.getEntitlements(U1); assert.equal(e1.club_active, true);
    const again = await t.buy(U1, 'club.mensal', TOK(2));
    assert.equal(again.already, true); assert.equal(again.consume, true);
    assert.equal((await t.store.getEntitlements(U1)).club_expires_at, e1.club_expires_at);
    assert.ok(!t.g.calls.some(c => c.url.endsWith(':acknowledge')), 'consumível: quem confirma é o app (consumir)');
    const tokCall = t.g.calls.find(c => c.url.includes('oauth2'));
    const assertion = decodeURIComponent(tokCall.body.split('assertion=')[1]);
    const [h, b, s] = assertion.split('.');
    assert.ok(crypto.verify('sha256', Buffer.from(h + '.' + b), publicKey, Buffer.from(s, 'base64url')), 'JWT da conta de serviço assinado');
  } finally { t.restore(); }
});

test('Fundador: entregue e confirmado (acknowledge) no Google; 2º sem vaga → sold_out, sem confirmar (Google devolve)', async () => {
  const t = setup({ limit: 1, purchases: { [TOK(3)]: purchase(U1), [TOK(4)]: purchase(U2) } });
  try {
    await t.pay.capacityReady();
    const a = await t.buy(U1, 'fundador', TOK(3));
    assert.equal(a.ok, true); assert.equal(a.consume, false);
    assert.ok(t.g.calls.some(c => c.url.endsWith(':acknowledge') && c.url.includes(TOK(3))));
    const b = await t.buy(U2, 'fundador', TOK(4));
    assert.equal(b.status, 'sold_out'); assert.equal(b.finish, true);
    assert.ok(!t.g.calls.some(c => c.url.endsWith(':acknowledge') && c.url.includes(TOK(4))), 'sem vaga: não confirma');
    assert.equal(await t.store.countFounders(), 1);
  } finally { t.restore(); }
});

test('compra de outra conta, cancelada, pendente, de teste: nada entregue', async () => {
  const t = setup({ purchases: { [TOK(5)]: purchase(U2), [TOK(6)]: purchase(U1, { purchaseState: 1 }), [TOK(7)]: purchase(U1, { purchaseState: 2 }), [TOK(8)]: purchase(U1, { purchaseType: 0 }) } });
  try {
    for (const [tok, code, finish] of [[TOK(5), 'owner', false], [TOK(6), 'cancelled', true], [TOK(7), 'pending', false], [TOK(8), 'test', true]]) {
      const r = await t.buy(U1, 'club.anual', tok);
      assert.equal(r.ok, false, code); assert.equal(r.code, code); assert.equal(r.finish, finish, code);
    }
    const e = await t.store.getEntitlements(U1); assert.ok(!e || !e.club_active);
  } finally { t.restore(); }
});

test('teste interno: com FRAIHA_GOOGLE_PLAY_TEST=1 a compra de teste vale', async () => {
  const t = setup({ env: { FRAIHA_GOOGLE_PLAY_TEST: '1' }, purchases: { [TOK(9)]: purchase(U1, { purchaseType: 0 }) } });
  try { assert.equal((await t.buy(U1, 'club.mensal', TOK(9))).ok, true); } finally { t.restore(); }
});

test('Google fora do ar ou produto/token inválido: nada entregue', async () => {
  const t = setup({ purchases: { [TOK(10)]: 'down' } });
  try {
    const r = await t.buy(U1, 'club.mensal', TOK(10));
    assert.equal(r.code, 'google_unavailable'); assert.equal(r.finish, false);
    assert.equal((await t.buy(U1, 'moedas', TOK(10))).code, 'bad_request');
    assert.equal((await t.buy(U1, 'club.mensal', 'curto')).code, 'bad_request');
  } finally { t.restore(); }
});
