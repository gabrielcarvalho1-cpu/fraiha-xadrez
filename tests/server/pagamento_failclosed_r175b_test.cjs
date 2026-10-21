'use strict';
// R175b · correções da auditoria Orca da R175:
//   1. retry de cartão FAIL CLOSED — sem confirmação do provedor de que NÃO há aprovação anterior, não cobra,
//      não usa o token novo, não cria preferência nova;
//   2. cancelamento só altera o pedido local se a resposta do provedor for inequivocamente deste pagamento/pedido.
// Parte A: serviço real + MemoryStore + provedor falso em memória (controle fino de falhas).
// Parte B: classe REAL do provedor Mercado Pago contra um Mercado Pago FALSO por HTTP (500, timeout, resposta inválida).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');
const { MercadoPago } = require('../../online_v021/payments/providers/mercadopago');

const MAP = { approved: 'paid', pending: 'pending', in_process: 'pending', rejected: 'failed', cancelled: 'cancelled', refunded: 'refunded' };
const tick = (ms = 0) => new Promise(r => setTimeout(r, ms));
const quiet = () => { const k = { e: console.error, l: console.log, w: console.warn }; console.error = () => {}; console.log = () => {}; console.warn = () => {}; return () => { console.error = k.e; console.log = k.l; console.warn = k.w; }; };

// ------------------------------------------------------------------ Parte A
function fakeMP() {
  const mp = { pays: new Map(), calls: [], nextId: 8000, findMode: 'ok', cardStatus: 'approved', payCardMode: 'ok', cancelHack: null };
  const ev = p => ({ providerRef: p.ref, status: MAP[p.status] || 'pending', amountCents: p.amount, currency: 'BRL', providerPaymentId: String(p.id), detail: p.detail || '' });
  const latest = ref => { const l = [...mp.pays.values()].filter(p => p.ref === ref).reverse(); return l.find(p => p.status === 'approved') || l.find(p => p.status === 'refunded') || l.find(p => p.status === 'pending') || l[0] || null; };
  mp.approvals = ref => [...mp.pays.values()].filter(p => p.ref === ref && p.status === 'approved').length;
  mp.count = op => mp.calls.filter(c => c.op === op).length;
  mp.provider = {
    name: 'mercadopago', ready: () => true,
    async createCharge({ ref, method, amountCents, idemSuffix = '' }) {
      mp.calls.push({ op: 'create', ref, method, idemSuffix });
      if (method === 'pix') { const id = mp.nextId++; mp.pays.set(id, { id, ref, status: 'pending', amount: amountCents, method: 'pix' }); return { id: ref, method: 'pix', copy_paste: 'QR' + id, provider_payment_id: String(id) }; }
      return { id: ref, method: 'card', checkout_url: 'https://mp.test/' + ref + idemSuffix, public_key: 'PK' };
    },
    async findByRef(ref) {
      mp.calls.push({ op: 'find', ref });
      if (mp.findMode === '500') { const e = new Error('mercadopago GET /v1/payments/search → 500'); e.status = 500; throw e; }
      if (mp.findMode === 'timeout') { await tick(5); const e = new Error('The operation was aborted'); e.name = 'AbortError'; throw e; }
      if (mp.findMode === 'invalid') return { providerRef: ref, status: 'paid' };                          // sem id do pagamento
      if (mp.findMode === 'other_ref') return { providerRef: 'OUTRO-PEDIDO', status: 'failed', providerPaymentId: '1', amountCents: 1, currency: 'BRL' };
      if (mp.findMode === 'weird') return { providerRef: ref, status: 'qualquer', providerPaymentId: '1' };
      if (mp.findMode === 'lag') return null;                                                             // busca ainda não mostra
      const p = latest(ref); return p ? ev(p) : null;
    },
    async resumePix(ref) { const p = latest(ref); return p ? (p.status === 'pending' ? { event: ev(p), charge: { id: ref, provider_payment_id: String(p.id), copy_paste: 'QR' + p.id } } : { event: ev(p) }) : null; },
    async cancel(id) {
      mp.calls.push({ op: 'cancel', id });
      if (mp.cancelHack) return mp.cancelHack(id);
      const p = mp.pays.get(Number(id)); p.status = 'cancelled'; return ev(p);
    },
    async payCard({ ref, token, amountCents }) {
      mp.calls.push({ op: 'payCard', ref, token });
      const id = mp.nextId++;
      const p = { id, ref, status: mp.cardStatus, amount: amountCents, method: 'card', token };
      mp.pays.set(id, p);
      if (mp.payCardMode === 'timeout') { const e = new Error('The operation was aborted'); e.name = 'AbortError'; throw e; }   // passou no MP, resposta se perdeu
      return ev(p);
    },
    async refund() {},
  };
  // cobrança aprovada direto no Mercado Pago (primeira tentativa) sem o banco local saber
  mp.approveExternally = (ref, amount) => { const id = mp.nextId++; mp.pays.set(id, { id, ref, status: 'approved', amount, method: 'card', token: 'primeiro' }); return id; };
  return mp;
}
function setup() {
  const restore = quiet();
  const store = new MemoryStore(); const sent = [];
  const pay = new Payments({ send: (ws, o) => sent.push({ to: ws.uid, ...o }), backend: { store, socketsOf: uid => [{ uid }], state: async () => {} }, env: { FRAIHA_PAYMENT_PROVIDER: '', FRAIHA_FOUNDER_LIMIT: '5' } });
  const mp = fakeMP(); pay.provider = mp.provider;
  let offset = 0; pay.now = () => Date.now() + offset;
  const ws = id => ({ uid: id, user: { id, email: id + '@x.dev' }, profile: { nickname: id } });
  const last = (to, type) => [...sent].reverse().find(o => o.to === to && o.type === type);
  const row = () => store.payments[0];
  const create = async (product = 'founder', method = 'card') => { await pay.handle(ws('ana'), { type: 'payment_create', product_id: product, method }); return last('ana', 'payment_charge').charge.id; };
  const card = (ref, token) => pay.handle(ws('ana'), { type: 'payment_card_pay', charge_id: ref, token, payment_method_id: 'visa' });
  return { store, pay, mp, ws, last, row, create, card, restore, sent, advance: ms => { offset += ms; } };
}

test('SONDA ORCA 1: aprovação anterior + consulta falha (500) + token novo → NÃO cobra de novo', async () => {
  const t = setup();
  try {
    const ref = await t.create();
    t.mp.approveExternally(ref, 4990);            // 1ª tentativa aprovada no MP; banco local ainda "aguardando"
    t.mp.findMode = '500';
    await t.card(ref, 'tokenNOVO_123456');
    const r = t.last('ana', 'payment_card_result');
    assert.equal(r.status, 'error'); assert.equal(r.code, 'provider_unverified');
    assert.match(r.message, /Nada foi cobrado/);
    assert.equal(t.mp.count('payCard'), 0, 'nenhuma nova cobrança');
    assert.equal(t.mp.approvals(ref), 1, 'uma única aprovação externa');
    assert.equal(t.row().status, 'pending', 'pedido intacto (a conciliação entrega depois)');
    // consulta volta → a mesma tentativa reconcilia e entrega SEM cobrar
    t.mp.findMode = 'ok';
    await t.card(ref, 'tokenTERCEIRO_99999');
    assert.equal(t.last('ana', 'payment_card_result').status, 'approved');
    assert.equal(t.mp.count('payCard'), 0); assert.equal(t.mp.approvals(ref), 1);
    assert.equal(t.row().status, 'paid'); assert.equal(await t.store.countFounders(), 1);
  } finally { t.restore(); }
});

for (const [mode, label] of [['500', 'consulta 500'], ['timeout', 'timeout'], ['invalid', 'resposta incompleta (sem id)'], ['other_ref', 'resposta de outro pedido'], ['weird', 'estado desconhecido']]) {
  test(`${label} → nenhuma nova cobrança, token não usado, nada entregue por engano`, async () => {
    const t = setup();
    try {
      const ref = await t.create();
      t.mp.findMode = mode;
      await t.card(ref, 'tokenX_' + mode + '_1234');
      const r = t.last('ana', 'payment_card_result');
      assert.equal(r.status, 'error'); assert.equal(r.code, 'provider_unverified');
      assert.equal(t.mp.count('payCard'), 0);
      assert.equal(t.row().status, 'pending');
      assert.equal(await t.store.countFounders(), 0, 'resposta duvidosa não entrega nada');
    } finally { t.restore(); }
  });
}

test('provedor confirma PAGO → entrega sem cobrar', async () => {
  const t = setup();
  try {
    const ref = await t.create();
    t.mp.approveExternally(ref, 4990);
    await t.card(ref, 'tokenNOVO_123456');
    assert.equal(t.last('ana', 'payment_card_result').status, 'approved');
    assert.equal(t.mp.count('payCard'), 0); assert.equal(t.row().status, 'paid');
  } finally { t.restore(); }
});

test('provedor confirma estado seguro (nenhum pagamento / só recusados) → token novo segue e cobra 1 vez', async () => {
  const t = setup();
  try {
    const ref = await t.create();
    t.mp.cardStatus = 'rejected';
    await t.card(ref, 'tokenUM_1234567');          // provedor: nenhum pagamento → pode cobrar
    assert.equal(t.last('ana', 'payment_card_result').status, 'rejected');
    t.mp.cardStatus = 'approved';
    await t.card(ref, 'tokenDOIS_7654321');        // provedor: só um recusado → pode cobrar
    assert.equal(t.last('ana', 'payment_card_result').status, 'approved');
    assert.equal(t.mp.count('payCard'), 2); assert.equal(t.mp.approvals(ref), 1);
  } finally { t.restore(); }
});

test('pagamento anterior EM ANÁLISE no provedor → não cobra de novo', async () => {
  const t = setup();
  try {
    const ref = await t.create();
    t.mp.cardStatus = 'in_process';
    await t.card(ref, 'tokenUM_1234567');
    t.mp.cardStatus = 'approved';
    await t.card(ref, 'tokenDOIS_7654321');
    const r = t.last('ana', 'payment_card_result');
    assert.equal(r.code, 'payment_in_review'); assert.equal(t.mp.count('payCard'), 1);
  } finally { t.restore(); }
});

test('retry depois de ERRO na cobrança (timeout, mas passou no MP) → não duplica', async () => {
  const t = setup();
  try {
    const ref = await t.create();
    t.mp.payCardMode = 'timeout';
    await t.card(ref, 'tokenUM_1234567');
    assert.equal(t.last('ana', 'payment_card_result').status, 'error');
    assert.equal(t.mp.approvals(ref), 1, 'a cobrança passou no MP');
    t.mp.payCardMode = 'ok';
    // a) busca já mostra a aprovação → entrega sem cobrar
    await t.card(ref, 'tokenDOIS_7654321');
    assert.equal(t.last('ana', 'payment_card_result').status, 'approved');
    assert.equal(t.mp.count('payCard'), 1); assert.equal(t.mp.approvals(ref), 1);
  } finally { t.restore(); }
});

test('retry depois de ERRO na cobrança com a busca ATRASADA (ainda vazia) → bloqueado até confirmar', async () => {
  const t = setup();
  try {
    const ref = await t.create('club_monthly', 'card');
    t.mp.payCardMode = 'timeout';
    await t.card(ref, 'tokenUM_1234567');
    t.mp.payCardMode = 'ok'; t.mp.findMode = 'lag';
    for (let i = 0; i < 3; i++) {
      await t.card(ref, 'tokenNOVO_' + i + '_abcdef');
      assert.equal(t.last('ana', 'payment_card_result').code, 'payment_unconfirmed');
    }
    assert.equal(t.mp.count('payCard'), 1, 'só a primeira chegou ao MP');
    // a busca passa a mostrar a aprovação → entrega sem cobrar
    t.mp.findMode = 'ok';
    await t.card(ref, 'tokenFINAL_123456');
    assert.equal(t.last('ana', 'payment_card_result').status, 'approved');
    assert.equal(t.mp.count('payCard'), 1); assert.equal(t.mp.approvals(ref), 1);
  } finally { t.restore(); }
});

test('consulta falha e depois volta (sem aprovação anterior) → segue normalmente, 1 cobrança só', async () => {
  const t = setup();
  try {
    const ref = await t.create();
    t.mp.findMode = '500';
    await t.card(ref, 'tokenUM_1234567');
    await t.card(ref, 'tokenUM_1234567');
    assert.equal(t.mp.count('payCard'), 0);
    t.mp.findMode = 'ok';
    await t.card(ref, 'tokenDOIS_7654321');
    assert.equal(t.last('ana', 'payment_card_result').status, 'approved');
    assert.equal(t.mp.count('payCard'), 1); assert.equal(t.mp.approvals(ref), 1);
  } finally { t.restore(); }
});

test('CONTINUAR cartão com a consulta falhando → não cria preferência nova', async () => {
  const t = setup();
  try {
    const ref = await t.create();
    const before = t.mp.count('create');
    t.mp.findMode = '500';
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: ref });
    assert.equal(t.last('ana', 'payment_error').code, 'provider_unverified');
    assert.equal(t.mp.count('create'), before, 'nenhuma preferência/cobrança nova');
    t.mp.findMode = 'ok';
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: ref });
    assert.equal(t.last('ana', 'payment_charge').charge.id, ref);
  } finally { t.restore(); }
});

test('SONDA ORCA 2: cancelamento devolve dados de OUTRO pagamento → pedido continua aguardando', async () => {
  for (const hack of [
    (id, t) => ({ providerRef: 'OUTRO-PEDIDO', status: 'cancelled', providerPaymentId: String(id), amountCents: 4490, currency: 'BRL' }),   // outro external_reference
    (id, t) => ({ providerRef: t.ref, status: 'cancelled', providerPaymentId: '999999', amountCents: 4490, currency: 'BRL' }),             // outro id de pagamento
    (id, t) => ({ providerRef: t.ref, status: 'cancelled', amountCents: 4490, currency: 'BRL' }),                                       // sem id
  ]) {
    const t = setup();
    try {
      const ref = await t.create('founder', 'pix'); t.ref = ref;
      t.mp.cancelHack = id => hack(id, t);
      await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: ref });
      const r = t.last('ana', 'payment_cancel_result');
      assert.equal(r.status, 'error'); assert.equal(r.code, 'provider_mismatch');
      assert.equal(t.row().status, 'pending', 'pedido preservado');
      assert.equal(t.row().raw, undefined, 'nada gravado no histórico');
      assert.ok(t.row().seat_hold_until, 'reserva de vaga preservada');
    } finally { t.restore(); }
  }
});

test('cancelamento com a busca devolvendo OUTRO pedido → não cancela', async () => {
  const t = setup();
  try {
    const ref = await t.create('founder', 'pix');
    t.mp.findMode = 'other_ref';
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: ref });
    assert.equal(t.last('ana', 'payment_cancel_result').code, 'unverified');
    assert.equal(t.row().status, 'pending'); assert.equal(t.mp.count('cancel'), 0);
  } finally { t.restore(); }
});

test('resposta correta do cancelamento → cancelamento normal', async () => {
  const t = setup();
  try {
    const ref = await t.create('founder', 'pix');
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: ref });
    assert.equal(t.last('ana', 'payment_cancel_result').status, 'cancelled');
    assert.equal(t.row().status, 'cancelled'); assert.equal(t.row().raw.cancel.provider_status, 'cancelled');
    assert.equal(t.row().seat_hold_until, null);
  } finally { t.restore(); }
});

test('CONTINUAR PIX com resposta de outro pedido → não mostra QR de outro pagamento', async () => {
  const t = setup();
  try {
    const ref = await t.create('founder', 'pix');
    t.mp.provider.resumePix = async () => ({ event: { providerRef: 'OUTRO', status: 'pending', providerPaymentId: '1' }, charge: { id: ref, provider_payment_id: '1', copy_paste: 'QR-ALHEIO' } });
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: ref });
    assert.equal(t.last('ana', 'payment_error').code, 'provider_unverified');
    assert.equal(t.last('ana', 'payment_charge').charge.copy_paste, 'QR8000', 'nenhum QR novo enviado (só o da criação)');
  } finally { t.restore(); }
});

// ------------------------------------------------------------------ Parte B (classe real do provedor)
function fakeHttpMP() {
  const mp = { payments: new Map(), nextId: 9500, searchMode: 'ok', putHack: null, posts: [] };
  const json = (res, code, body) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
  const srv = http.createServer((req, res) => {
    let raw = ''; req.on('data', d => raw += d);
    req.on('end', () => {
      const body = raw ? JSON.parse(raw) : {};
      if (req.method === 'POST' && req.url === '/v1/payments') {
        mp.posts.push({ idem: req.headers['x-idempotency-key'], token: body.token });
        const id = mp.nextId++;
        const p = { id, status: body.token ? 'approved' : 'pending', transaction_amount: body.transaction_amount, currency_id: 'BRL', external_reference: body.external_reference };
        if (!body.token) p.point_of_interaction = { transaction_data: { qr_code: 'PIX' + id, qr_code_base64: 'B64' } };
        mp.payments.set(String(id), p); return json(res, 201, p);
      }
      if (req.method === 'POST' && req.url === '/checkout/preferences') return json(res, 201, { id: 'pref', init_point: 'https://mp.test/c' });
      if (req.method === 'GET' && req.url.startsWith('/v1/payments/search')) {
        if (mp.searchMode === '500') return json(res, 500, { message: 'internal' });
        if (mp.searchMode === 'timeout') return;   // nunca responde
        if (mp.searchMode === 'invalid') return json(res, 200, { paging: {} });
        if (mp.searchMode === 'other') return json(res, 200, { results: [{ id: 1, status: 'rejected', external_reference: 'OUTRO' }] });
        const ref = new URL(req.url, 'http://x').searchParams.get('external_reference');
        return json(res, 200, { results: [...mp.payments.values()].filter(p => p.external_reference === ref).reverse() });
      }
      const m = req.url.match(/^\/v1\/payments\/(\d+)$/);
      if (m && req.method === 'PUT') {
        if (mp.putHack) return json(res, 200, mp.putHack(m[1]));
        const p = mp.payments.get(m[1]); p.status = 'cancelled'; return json(res, 200, p);
      }
      if (m && req.method === 'GET') return json(res, 200, mp.payments.get(m[1]) || {});
      json(res, 404, {});
    });
  });
  mp.approvals = ref => [...mp.payments.values()].filter(p => p.external_reference === ref && p.status === 'approved').length;
  return { mp, srv };
}
async function realSetup(fn) {
  const { mp, srv } = fakeHttpMP();
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  const restore = quiet();
  try {
    const store = new MemoryStore(); const sent = [];
    const pay = new Payments({ send: (ws, o) => sent.push({ to: ws.uid, ...o }), backend: { store, socketsOf: uid => [{ uid }], state: async () => {} }, env: { FRAIHA_PAYMENT_PROVIDER: '', FRAIHA_FOUNDER_LIMIT: '5' } });
    pay.provider = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'T', FRAIHA_PUBLIC_URL: 'https://srv.test', FRAIHA_MP_API: 'http://127.0.0.1:' + srv.address().port, FRAIHA_MP_PUBLIC_KEY: 'PK', FRAIHA_MP_TIMEOUT_MS: '150' });
    const ws = { uid: 'ana', user: { id: 'ana', email: 'a@x.dev' }, profile: { nickname: 'ana' } };
    const last = type => [...sent].reverse().find(o => o.type === type);
    await fn({ mp, pay, store, ws, last });
  } finally { restore(); srv.closeAllConnections && srv.closeAllConnections(); srv.close(); }
}

test('SONDA ORCA 1 com o provedor REAL: aprovação anterior + busca 500 → só 1 aprovação no Mercado Pago', () => realSetup(async ({ mp, pay, store, ws, last }) => {
  await pay.handle(ws, { type: 'payment_create', product_id: 'founder', method: 'card' });
  const ref = last('payment_charge').charge.id;
  // 1ª tentativa aprovada no MP, mas o banco local não refletiu (simula a confirmação perdida)
  mp.payments.set('1', { id: 1, status: 'approved', transaction_amount: 49.9, currency_id: 'BRL', external_reference: ref });
  for (const mode of ['500', 'timeout', 'invalid', 'other']) {
    mp.searchMode = mode;
    await pay.handle(ws, { type: 'payment_card_pay', charge_id: ref, token: 'tokenNOVO_' + mode + '_123', payment_method_id: 'visa' });
    assert.equal(last('payment_card_result').code, 'provider_unverified', mode);
  }
  assert.equal(mp.posts.length, 0, 'nenhum POST /v1/payments com token novo');
  assert.equal(mp.approvals(ref), 1, 'uma única aprovação externa');
  assert.equal(store.payments[0].status, 'pending');
  mp.searchMode = 'ok';
  await pay.handle(ws, { type: 'payment_card_pay', charge_id: ref, token: 'tokenFINAL_123456', payment_method_id: 'visa' });
  assert.equal(last('payment_card_result').status, 'approved');
  assert.equal(mp.posts.length, 0); assert.equal(mp.approvals(ref), 1);
  assert.equal(store.payments[0].status, 'paid');
}));

test('provedor REAL: sem aprovação anterior (busca vazia válida) → cobra 1 vez', () => realSetup(async ({ mp, pay, ws, last }) => {
  await pay.handle(ws, { type: 'payment_create', product_id: 'club_monthly', method: 'card' });
  const ref = last('payment_charge').charge.id;
  await pay.handle(ws, { type: 'payment_card_pay', charge_id: ref, token: 'tokenUM_1234567', payment_method_id: 'visa' });
  assert.equal(last('payment_card_result').status, 'approved');
  assert.equal(mp.posts.length, 1); assert.equal(mp.approvals(ref), 1);
}));

test('SONDA ORCA 2 com o provedor REAL: PUT devolve outro pagamento → pedido continua aguardando', () => realSetup(async ({ mp, pay, store, ws, last }) => {
  await pay.handle(ws, { type: 'payment_create', product_id: 'founder', method: 'pix' });
  const ref = last('payment_charge').charge.id;
  mp.putHack = () => ({ id: 424242, status: 'cancelled', external_reference: 'OUTRO', transaction_amount: 44.9, currency_id: 'BRL' });
  await pay.handle(ws, { type: 'payment_cancel', charge_id: ref });
  assert.equal(last('payment_cancel_result').status, 'error');
  assert.equal(store.payments[0].status, 'pending'); assert.equal(store.payments[0].raw, undefined);
  // mesmo id mas external_reference de outro pedido
  mp.putHack = id => ({ id: Number(id), status: 'cancelled', external_reference: 'OUTRO', transaction_amount: 44.9, currency_id: 'BRL' });
  await pay.handle(ws, { type: 'payment_cancel', charge_id: ref });
  assert.equal(last('payment_cancel_result').code, 'provider_mismatch');
  assert.equal(store.payments[0].status, 'pending');
  // resposta correta → cancela
  mp.putHack = null;
  await pay.handle(ws, { type: 'payment_cancel', charge_id: ref });
  assert.equal(last('payment_cancel_result').status, 'cancelled');
  assert.equal(store.payments[0].status, 'cancelled');
}));
