'use strict';
// R175d · a incerteza financeira atravessa o VENCIMENTO do pedido: uma tentativa de cartão incerta/em andamento em
// qualquer pedido da conta (mesmo vencido) bloqueia NOVO pedido e nova cobrança até o Mercado Pago confirmar o resultado
// dela. E só erros que PROVAM que a cobrança não foi criada liberam a tentativa (classificação dos 4xx).
// Classe REAL do provedor contra um Mercado Pago FALSO por HTTP; "reinício" = instância nova sobre o mesmo banco.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');
const { MercadoPago } = require('../../online_v021/payments/providers/mercadopago');

const tick = (ms = 0) => new Promise(r => setTimeout(r, ms));
const quiet = () => { const k = { e: console.error, l: console.log, w: console.warn }; console.error = () => {}; console.log = () => {}; console.warn = () => {}; return () => { console.error = k.e; console.log = k.l; console.warn = k.w; }; };

// Mercado Pago FALSO por HTTP (a classe REAL do provedor fala com ele). Cobranças com token: aprovadas por padrão;
// "slow" = aprova no MP mas responde depois do timeout do servidor (resposta perdida).
function fakeMP() {
  const mp = { payments: new Map(), nextId: 70000, posts: [], searchMode: 'ok', cardStatus: 'approved', slowMs: 0, attemptStatus: null };
  const json = (res, code, body) => { if (!res.writableEnded) { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); } };
  mp.srv = http.createServer((req, res) => {
    let raw = ''; req.on('data', d => raw += d);
    req.on('end', async () => {
      const body = raw ? JSON.parse(raw) : {};
      if (req.method === 'POST' && req.url === '/v1/payments' && mp.postError && body.token) {
        mp.posts.push({ token: body.token, attempt: body.metadata && body.metadata.fraiha_attempt, error: mp.postError.status });
        if (mp.postError.creates) {   // erro ambíguo: o MP criou (e aprovou) mesmo assim
          const id = mp.nextId++;
          mp.payments.set(String(id), { id, status: 'approved', transaction_amount: body.transaction_amount, currency_id: 'BRL', external_reference: body.external_reference, metadata: body.metadata || {} });
        }
        return json(res, mp.postError.status, mp.postError.body || { message: 'erro' });
      }
      if (req.method === 'POST' && req.url === '/v1/payments') {
        mp.posts.push({ token: body.token, attempt: body.metadata && body.metadata.fraiha_attempt, idem: req.headers['x-idempotency-key'] });
        const id = mp.nextId++;
        const p = { id, status: body.token ? mp.cardStatus : 'pending', status_detail: mp.cardStatus === 'rejected' ? 'cc_rejected_other_reason' : 'accredited', transaction_amount: body.transaction_amount,
          currency_id: 'BRL', external_reference: body.external_reference, metadata: body.metadata || {} };
        if (!body.token) p.point_of_interaction = { transaction_data: { qr_code: 'PIX' + id, qr_code_base64: 'B' } };
        mp.payments.set(String(id), p);          // aceito NO MERCADO PAGO antes de responder
        if (mp.slowMs) await tick(mp.slowMs);    // resposta chega tarde demais (o servidor já desistiu)
        return json(res, 201, p);
      }
      if (req.method === 'POST' && req.url === '/checkout/preferences') return json(res, 201, { id: 'pref', init_point: 'https://mp.test/c' });
      if (req.method === 'GET' && req.url.startsWith('/v1/payments/search')) {
        if (mp.searchMode === '500') return json(res, 500, { message: 'x' });
        if (mp.searchMode === 'empty') return json(res, 200, { results: [] });   // busca defasada: ainda não mostra
        const ref = new URL(req.url, 'http://x').searchParams.get('external_reference');
        return json(res, 200, { results: [...mp.payments.values()].filter(p => p.external_reference === ref).reverse() });
      }
      json(res, 404, {});
    });
  });
  mp.approvals = ref => [...mp.payments.values()].filter(p => p.external_reference === ref && p.status === 'approved').length;
  mp.cardPosts = () => mp.posts.filter(p => p.token).length;
  return mp;
}

async function world(fn, { limit = '5' } = {}) {
  const mp = fakeMP();
  await new Promise(r => mp.srv.listen(0, '127.0.0.1', r));
  const restore = quiet();
  const store = new MemoryStore();   // o "banco": sobrevive aos reinícios
  const sent = [];
  let clock = 0;
  const boot = () => {   // instância NOVA do servidor (memória zerada)
    const pay = new Payments({ send: (ws, o) => sent.push({ to: ws.uid, ...o }), backend: { store, socketsOf: uid => [{ uid }], state: async () => {} }, env: { FRAIHA_PAYMENT_PROVIDER: '', FRAIHA_FOUNDER_LIMIT: limit } });
    pay.provider = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'T', FRAIHA_PUBLIC_URL: 'https://srv.test', FRAIHA_MP_API: 'http://127.0.0.1:' + mp.srv.address().port, FRAIHA_MP_PUBLIC_KEY: 'PK', FRAIHA_MP_TIMEOUT_MS: '120' });
    pay.now = () => Date.now() + clock;
    return pay;
  };
  const ws = (id = 'ana') => ({ uid: id, user: { id, email: id + '@x.dev' }, profile: { nickname: id } });
  const last = type => [...sent].reverse().find(o => o.type === type);
  const card = (pay, ref, token, who) => pay.handle(ws(who), { type: 'payment_card_pay', charge_id: ref, token, payment_method_id: 'visa' });
  const row = () => store.payments[0];
  try { await fn({ mp, store, boot, ws, last, card, row, sent, advance: ms => { clock += ms; for (const p of store.payments || []) { p.created_at = new Date(Date.parse(p.created_at) - ms).toISOString(); if (p.seat_hold_until) p.seat_hold_until = new Date(Date.parse(p.seat_hold_until) - ms).toISOString(); } clock -= ms; } }); }
  finally { restore(); mp.srv.closeAllConnections && mp.srv.closeAllConnections(); mp.srv.close(); }
}
async function order(t, pay, product = 'founder') {
  await pay.handle(t.ws(), { type: 'payment_create', product_id: product, method: 'card' });
  return t.last('payment_charge').charge.id;
}
// cobrança aceita pelo MP, resposta perdida (timeout no servidor)
async function lostResponse(t, pay, ref, token = 'tokenUM_123456') {
  t.mp.slowMs = 400;
  await t.card(pay, ref, token);
  await tick(450);           // o MP terminou (aprovou) depois do timeout
  t.mp.slowMs = 0;
  return t.last('payment_card_result');
}


async function order(t, pay, product = 'club_monthly', method = 'card') {
  const n = t.sent.length;
  await pay.handle(t.ws(), { type: 'payment_create', product_id: product, method });
  const c = t.sent.slice(n).find(o => o.type === 'payment_charge');
  return c ? c.charge.id : null;
}
async function lostResponse(t, pay, ref, token = 'tokenUM_123456') {
  t.mp.slowMs = 400;
  await t.card(pay, ref, token);
  await tick(450);
  t.mp.slowMs = 0;
  return t.last('payment_card_result');
}
const lastErr = t => t.last('payment_error');

test('tentativa incerta → 30 min → pedido NOVO bloqueado (cartão, PIX, Fundador), sem cobrança', () => world(async t => {
  let pay = t.boot();
  const a = await order(t, pay);
  await lostResponse(t, pay, a);
  t.mp.searchMode = 'empty';
  t.advance(31 * 60e3);
  for (const [p, m] of [['club_monthly', 'card'], ['club_yearly', 'pix'], ['founder', 'card'], ['founder', 'pix']]) {
    assert.equal(await order(t, pay, p, m), null, p + '/' + m);
    assert.equal(lastErr(t).code, 'previous_attempt_unconfirmed');
    assert.equal(lastErr(t).charge_id, a, 'aponta o pedido incerto');
  }
  assert.equal(t.store.payments.length, 1, 'nenhum pedido novo, nenhuma reserva');
  assert.equal(t.mp.cardPosts(), 1); assert.equal(t.mp.approvals(a), 1);
  // o pedido A aparece como expirado no histórico, mas a incerteza continua gravada
  await pay.handle(t.ws(), { type: 'payment_history' });
  assert.equal(t.last('payment_history').items[0].state, 'expired');
  assert.equal(t.store.payments[0].raw.card_attempt.state, 'uncertain');
}));

test('reinício ANTES e DEPOIS dos 30 min → continua bloqueado', () => world(async t => {
  let pay = t.boot();
  const a = await order(t, pay);
  await lostResponse(t, pay, a);
  t.mp.searchMode = 'empty';
  pay = t.boot(); t.advance(10 * 60e3);
  assert.equal(await order(t, pay), null); assert.equal(lastErr(t).code, 'previous_attempt_unconfirmed');
  pay = t.boot(); t.advance(25 * 60e3);
  assert.equal(await order(t, pay), null); assert.equal(lastErr(t).code, 'previous_attempt_unconfirmed');
  pay = t.boot(); t.advance(6 * 3600e3);   // horas depois: tempo sozinho nunca libera
  assert.equal(await order(t, pay), null);
  assert.equal(t.mp.cardPosts(), 1); assert.equal(t.store.payments.length, 1);
}));

test('DUAS INSTÂNCIAS criando pedido novo ao mesmo tempo com A incerto → nenhuma cria', () => world(async t => {
  const pay = t.boot();
  const a = await order(t, pay);
  await lostResponse(t, pay, a);
  t.mp.searchMode = 'empty'; t.advance(31 * 60e3);
  const insts = [t.boot(), t.boot(), t.boot()];
  await Promise.all(insts.map(p => p.handle(t.ws(), { type: 'payment_create', product_id: 'club_monthly', method: 'card' })));
  assert.equal(t.sent.filter(o => o.type === 'payment_error' && o.code === 'previous_attempt_unconfirmed').length, 3);
  assert.equal(t.store.payments.length, 1); assert.equal(t.mp.cardPosts(), 1);
}));

test('aprovação ANTIGA aparece depois → pedido A entregue, pedido B não é criado nem cobrado; nunca 2 aprovações', () => world(async t => {
  let pay = t.boot();
  const a = await order(t, pay);
  await lostResponse(t, pay, a);
  t.mp.searchMode = 'empty'; t.advance(31 * 60e3);
  pay = t.boot();
  assert.equal(await order(t, pay), null);
  t.mp.searchMode = 'ok';   // a cobrança de A aparece na busca
  pay = t.boot();
  assert.equal(await order(t, pay), null, 'B não nasce na mesma ação que confirmou A');
  assert.equal(lastErr(t).code, 'previous_payment_confirmed');
  assert.equal(t.store.payments[0].status, 'paid', 'A entregue (pagamento confirmado não se perde)');
  assert.equal(t.mp.approvals(a), 1); assert.equal(t.mp.cardPosts(), 1);
  // agora a conta não tem incerteza: uma compra NOVA, consciente, é permitida e cobrada 1 vez
  const b = await order(t, pay);
  assert.ok(b && b !== a);
  await t.card(pay, b, 'tokenB_1234567');
  assert.equal(t.last('payment_card_result').status, 'approved');
  assert.equal(t.mp.approvals(a), 1); assert.equal(t.mp.approvals(b), 1);
}));

test('confirmação de REJEIÇÃO antiga (busca) libera pedido novo', () => world(async t => {
  let pay = t.boot();
  const a = await order(t, pay);
  t.mp.cardStatus = 'rejected';
  await lostResponse(t, pay, a);
  t.mp.cardStatus = 'approved';
  t.mp.searchMode = 'empty'; t.advance(31 * 60e3);
  pay = t.boot();
  assert.equal(await order(t, pay), null);
  t.mp.searchMode = 'ok';   // MP mostra: a tentativa de A foi recusada
  pay = t.boot();
  const b = await order(t, pay);
  assert.ok(b, 'liberado só depois da confirmação');
  assert.equal(t.store.payments.find(p => p.provider_ref === a).raw.card_attempt, null);
  await t.card(pay, b, 'tokenB_1234567');
  assert.equal(t.last('payment_card_result').status, 'approved');
  assert.equal(t.mp.approvals(a), 0); assert.equal(t.mp.approvals(b), 1);
}));

test('confirmação de rejeição pelo AVISO (webhook) do MP também libera', () => world(async t => {
  let pay = t.boot();
  const a = await order(t, pay);
  t.mp.cardStatus = 'rejected';
  await lostResponse(t, pay, a);
  t.mp.cardStatus = 'approved'; t.mp.searchMode = 'empty';
  const p = [...t.mp.payments.values()][0];
  pay = t.boot();
  await pay.apply(pay.provider.event(p));   // webhook da recusa
  assert.equal(t.store.payments[0].raw.card_attempt, null);
  assert.ok(await order(t, pay));
}));

test('outro pedido JÁ aberto (B) não pode ser cobrado nem retomado enquanto A está incerto', () => world(async t => {
  let pay = t.boot();
  const b = await order(t, pay, 'club_yearly', 'card');   // B criado antes
  const a = await order(t, pay);
  await lostResponse(t, pay, a);
  t.mp.searchMode = 'empty';
  pay = t.boot();
  await t.card(pay, b, 'tokenB_1234567');
  assert.equal(t.last('payment_card_result').code, 'previous_attempt_unconfirmed');
  await pay.handle(t.ws(), { type: 'payment_resume', charge_id: b });
  assert.equal(lastErr(t).code, 'previous_attempt_unconfirmed');
  assert.equal(t.mp.cardPosts(), 1); assert.equal(t.mp.approvals(b), 0);
}));

test('nunca mais de 1 aprovação externa: muitos reinícios, abas e pedidos com A incerto', () => world(async t => {
  let pay = t.boot();
  const a = await order(t, pay);
  await lostResponse(t, pay, a);
  t.mp.searchMode = 'empty';
  for (let i = 0; i < 8; i++) {
    pay = t.boot(); if (i % 3 === 0) t.advance(20 * 60e3);
    await Promise.all([order(t, pay), order(t, t.boot(), 'founder', 'pix'), t.card(pay, a, 'tokenR_' + i + '_abcdef')]);
  }
  assert.equal(t.mp.cardPosts(), 1);
  const total = [...t.mp.payments.values()].filter(p => p.status === 'approved').length;
  assert.equal(total, 1);
  assert.equal(t.store.payments.length, 1);
}));

// --------------------------------------------------- classificação dos erros HTTP (4xx)
const CASES = [
  ['400 + causa 2006 (card token não encontrado)', { status: 400, body: { message: 'bad', cause: [{ code: 2006 }] } }, 'released'],
  ['400 + causa 3003 (card_token_id inválido)', { status: 400, body: { message: 'bad', cause: [{ code: '3003' }] } }, 'released'],
  ['401 (credencial recusada)', { status: 401, body: { message: 'unauthorized' } }, 'released'],
  ['400 SEM causa', { status: 400, body: { message: 'bad request' } }, 'uncertain'],
  ['400 com causa desconhecida', { status: 400, body: { message: 'x', cause: [{ code: 9999 }] } }, 'uncertain'],
  ['400 com causa conhecida + desconhecida', { status: 400, body: { message: 'x', cause: [{ code: 2006 }, { code: 9999 }] } }, 'uncertain'],
  ['403', { status: 403, body: { message: 'forbidden' } }, 'uncertain'],
  ['404', { status: 404, body: { message: 'not found' } }, 'uncertain'],
  ['409', { status: 409, body: { message: 'conflict' } }, 'uncertain'],
  ['422', { status: 422, body: { message: 'unprocessable' } }, 'uncertain'],
  ['429', { status: 429, body: { message: 'too many' } }, 'uncertain'],
];
for (const [label, err, expect] of CASES) {
  test('4xx · ' + label + ' → ' + (expect === 'released' ? 'libera (prova de que não criou)' : 'INCERTO (bloqueia)'), () => world(async t => {
    const pay = t.boot();
    const a = await order(t, pay);
    t.mp.postError = err;
    await t.card(pay, a, 'tokenUM_1234567');
    t.mp.postError = null;
    const att = t.store.payments[0].raw.card_attempt;
    if (expect === 'released') {
      assert.equal(t.last('payment_card_result').status, 'rejected');
      assert.equal(att, null);
      await t.card(pay, a, 'tokenDOIS_7654321');
      assert.equal(t.last('payment_card_result').status, 'approved');
    } else {
      assert.equal(t.last('payment_card_result').code, 'payment_unconfirmed');
      assert.equal(att.state, 'uncertain');
      t.mp.searchMode = 'empty';
      await t.card(pay, a, 'tokenDOIS_7654321');
      assert.equal(t.last('payment_card_result').code, 'payment_unconfirmed');
      assert.equal(await order(t, pay), null);
    }
  }));
}

test('4xx AMBÍGUO em que o MP criou e aprovou mesmo assim → bloqueado; aparece na busca → entrega; 1 aprovação', () => world(async t => {
  let pay = t.boot();
  const a = await order(t, pay);
  t.mp.postError = { status: 400, body: { message: 'algo' }, creates: true };
  await t.card(pay, a, 'tokenUM_1234567');
  t.mp.postError = null; t.mp.searchMode = 'empty';
  pay = t.boot();
  await t.card(pay, a, 'tokenDOIS_7654321');
  assert.equal(t.last('payment_card_result').code, 'payment_unconfirmed');
  t.mp.searchMode = 'ok';
  await t.card(pay, a, 'tokenTRES_7654321');
  assert.equal(t.last('payment_card_result').status, 'approved');
  assert.equal(t.mp.approvals(a), 1); assert.equal(t.mp.posts.length, 1);
}));
