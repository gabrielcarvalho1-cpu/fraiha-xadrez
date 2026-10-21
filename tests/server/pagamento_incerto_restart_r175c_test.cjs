'use strict';
// R175c · cobrança de cartão com resultado INCERTO sobrevive a reinício: a tentativa fica gravada no pedido
// (payments.raw.card_attempt, compare-and-set por status + versão do raw) ANTES de a cobrança ser enviada, e só é
// liberada quando o provedor confirma o resultado DAQUELA tentativa (metadata.fraiha_attempt). Tempo sozinho nunca libera.
// "Reinício" = instância NOVA do serviço de pagamentos (memória zerada) sobre o MESMO banco (store) e o mesmo Mercado Pago.
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

test('SONDA ORCA: aceito no MP + resposta perdida + REINÍCIO + busca vazia + token novo → 1 POST / 1 aprovação', () => world(async t => {
  let pay = t.boot();
  const ref = await order(t, pay);
  const r1 = await lostResponse(t, pay, ref);
  assert.equal(r1.code, 'payment_unconfirmed');
  assert.equal(t.mp.cardPosts(), 1); assert.equal(t.mp.approvals(ref), 1);
  const a = t.row().raw.card_attempt;
  assert.ok(a && a.id && a.state === 'uncertain', 'tentativa incerta GRAVADA no pedido');
  assert.equal(t.mp.posts[0].attempt, a.id, 'a cobrança levou o id da tentativa (metadata.fraiha_attempt)');
  pay = t.boot();            // REINÍCIO: memória zerada
  t.mp.searchMode = 'empty'; // busca ainda defasada
  await t.card(pay, ref, 'tokenDOIS_654321');
  const r2 = t.last('payment_card_result');
  assert.equal(r2.status, 'error'); assert.equal(r2.code, 'payment_unconfirmed');
  assert.equal(t.mp.cardPosts(), 1, 'NUNCA 2 POSTs'); assert.equal(t.mp.approvals(ref), 1, 'NUNCA 2 aprovações');
  // a busca passa a mostrar → a mesma tentativa reconcilia e entrega, sem cobrar
  t.mp.searchMode = 'ok';
  pay = t.boot();
  await t.card(pay, ref, 'tokenTRES_999999');
  assert.equal(t.last('payment_card_result').status, 'approved');
  assert.equal(t.mp.cardPosts(), 1); assert.equal(t.mp.approvals(ref), 1);
  assert.equal(t.row().status, 'paid'); assert.equal(await t.store.countFounders(), 1);
}));

test('reinício imediato e depois de vários minutos, várias vezes, busca sempre vazia → nenhuma cobrança nova', () => world(async t => {
  let pay = t.boot();
  const ref = await order(t, pay);
  await lostResponse(t, pay, ref);
  t.mp.searchMode = 'empty';
  for (let i = 0; i < 6; i++) {
    pay = t.boot();                                 // reinicia
    if (i === 3) t.advance(10 * 60e3);              // "alguns minutos depois" (o pedido ainda vale)
    await t.card(pay, ref, 'tokenX_' + i + '_abcdef');
    assert.equal(t.last('payment_card_result').code, 'payment_unconfirmed', 'rodada ' + i);
    await pay.handle(t.ws(), { type: 'payment_resume', charge_id: ref });   // CONTINUAR também não abre nova cobrança
    assert.equal(t.last('payment_error').code, 'payment_unconfirmed');
  }
  assert.equal(t.mp.cardPosts(), 1); assert.equal(t.mp.approvals(ref), 1);
  assert.equal(t.row().raw.card_attempt.state, 'uncertain', 'a marca continua no pedido');
}));

test('tempo sozinho NÃO libera: depois de 3+ min com a busca vazia continua bloqueado; pedido vencido não cobra', () => world(async t => {
  let pay = t.boot();
  const ref = await order(t, pay);
  await lostResponse(t, pay, ref);
  t.mp.searchMode = 'empty';
  t.advance(20 * 60e3);
  pay = t.boot();
  await t.card(pay, ref, 'tokenNOVO_123456');
  assert.equal(t.last('payment_card_result').code, 'payment_unconfirmed');
  t.advance(15 * 60e3);   // 35 min: pedido vencido
  await t.card(pay, ref, 'tokenNOVO2_123456');
  assert.equal(t.last('payment_card_result').code, 'order_expired');
  assert.equal(t.mp.cardPosts(), 1);
}));

test('provedor depois retorna EM ANÁLISE para a tentativa → continua bloqueado', () => world(async t => {
  let pay = t.boot();
  const ref = await order(t, pay);
  t.mp.cardStatus = 'in_process';
  await lostResponse(t, pay, ref);
  t.mp.cardStatus = 'approved';
  pay = t.boot();
  await t.card(pay, ref, 'tokenDOIS_654321');
  assert.equal(t.last('payment_card_result').code, 'payment_in_review');
  assert.equal(t.mp.cardPosts(), 1);
}));

test('provedor depois CONFIRMA recusada → libera; token novo cobra 1 vez (pedido legítimo pode tentar de novo)', () => world(async t => {
  let pay = t.boot();
  const ref = await order(t, pay);
  t.mp.cardStatus = 'rejected';
  await lostResponse(t, pay, ref);
  assert.equal(t.mp.approvals(ref), 0);
  t.mp.cardStatus = 'approved';
  pay = t.boot();
  await t.card(pay, ref, 'tokenDOIS_654321');
  assert.equal(t.last('payment_card_result').status, 'approved');
  assert.equal(t.mp.cardPosts(), 2, 'a 1ª (recusada, confirmada) + a nova'); assert.equal(t.mp.approvals(ref), 1);
  const ev = t.row().raw.history.map(h => h.event);
  assert.ok(ev.includes('card_attempt_uncertain') && ev.includes('card_attempt_resolved') && ev.includes('card_attempt_approved'), ev.join(','));
}));

test('provedor confirma cancelada para a tentativa → libera', () => world(async t => {
  let pay = t.boot();
  const ref = await order(t, pay, 'club_monthly');
  await lostResponse(t, pay, ref);
  for (const p of t.mp.payments.values()) p.status = 'cancelled';
  pay = t.boot();
  await t.card(pay, ref, 'tokenDOIS_654321');
  assert.equal(t.last('payment_card_result').status, 'approved');
  assert.equal(t.mp.approvals(ref), 1);
}));

test('pagamento confirmado nunca se perde: aviso do MP chega com o pedido incerto → entregue; retry depois não cobra', () => world(async t => {
  let pay = t.boot();
  const ref = await order(t, pay);
  await lostResponse(t, pay, ref);
  pay = t.boot();
  const p = [...t.mp.payments.values()][0];
  await pay.apply(pay.provider.event(p));   // webhook
  assert.equal(t.row().status, 'paid');
  pay = t.boot();
  await t.card(pay, ref, 'tokenDOIS_654321');
  assert.equal(t.last('payment_card_result').status, 'approved');
  assert.equal(t.mp.cardPosts(), 1); assert.equal(await t.store.countFounders(), 1);
}));

test('DUAS INSTÂNCIAS ao mesmo tempo, mesmo pedido, tokens diferentes → exatamente 1 cobrança', () => world(async t => {
  const a = t.boot(), b = t.boot();
  const ref = await order(t, a);
  await Promise.all([t.card(a, ref, 'tokenA_1234567'), t.card(b, ref, 'tokenB_7654321'), t.card(a, ref, 'tokenC_1111111'), t.card(b, ref, 'tokenD_2222222')]);
  assert.equal(t.mp.cardPosts(), 1, 'só uma instância conseguiu gravar a tentativa');
  assert.equal(t.mp.approvals(ref), 1);
  const res = t.sent.filter(o => o.type === 'payment_card_result');
  assert.equal(res.filter(r => r.status === 'approved').length >= 1, true);
  assert.ok(res.filter(r => r.code === 'attempt_busy' || r.status === 'approved').length === 4, res.map(r => r.status + ':' + (r.code || '')).join(' '));
}));

test('DOIS APARELHOS (instâncias diferentes) com a 1ª incerta → o 2º não cobra', () => world(async t => {
  const a = t.boot(), b = t.boot();
  const ref = await order(t, a);
  t.mp.searchMode = 'empty';
  await lostResponse(t, a, ref);
  await t.card(b, ref, 'tokenCELULAR_12345');
  assert.equal(t.last('payment_card_result').code, 'payment_unconfirmed');
  assert.equal(t.mp.cardPosts(), 1);
}));

test('DUAS ABAS (mesma instância) com a 1ª ainda em andamento → a 2ª não cobra', () => world(async t => {
  const pay = t.boot();
  const ref = await order(t, pay);
  t.mp.searchMode = 'empty'; t.mp.slowMs = 400;
  const p1 = t.card(pay, ref, 'tokenABA1_123456');
  await tick(20);
  const p2 = t.card(pay, ref, 'tokenABA2_654321');
  await Promise.all([p1, p2]);
  t.mp.slowMs = 0; await tick(450);
  assert.equal(t.mp.cardPosts(), 1);
  const res = t.sent.filter(o => o.type === 'payment_card_result');
  assert.deepEqual(res.map(r => r.code), ['payment_unconfirmed', 'payment_unconfirmed']);
}));

test('servidor cai DEPOIS de gravar a tentativa e ANTES de enviar → bloqueado (nada no MP), sem cobrança; vencer NÃO libera (R175d)', () => world(async t => {
  let pay = t.boot();
  const ref = await order(t, pay);
  const r = t.row();
  // estado deixado por um processo que morreu entre o compare-and-set e o POST
  const ok = await t.store.casPaymentRaw('mercadopago', ref, 'pending', 0, { rev: 1, card_attempt: { id: 'att-morto', state: 'inflight', at: new Date().toISOString() } });
  assert.ok(ok && r);
  pay = t.boot();
  await t.card(pay, ref, 'tokenNOVO_123456');
  assert.equal(t.last('payment_card_result').code, 'payment_unconfirmed');
  assert.equal(t.mp.cardPosts(), 0);
  // CANCELAR também não fecha às cegas
  await pay.handle(t.ws(), { type: 'payment_cancel', charge_id: ref });
  assert.equal(t.last('payment_cancel_result').code, 'in_review');
  assert.equal(t.row().status, 'pending');
  // R175d · depois de vencer, a incerteza continua: nenhum pedido NOVO enquanto o MP não confirmar a tentativa
  t.advance(31 * 60e3);
  pay = t.boot();
  await pay.handle(t.ws(), { type: 'payment_create', product_id: 'club_monthly', method: 'card' });
  assert.equal(t.last('payment_error').code, 'previous_attempt_unconfirmed');
  assert.equal(t.store.payments.length, 1, 'nenhum pedido novo');
}));

test('compare-and-set: gravar tentativa com versão antiga do raw falha (outra instância já gravou)', () => world(async t => {
  const pay = t.boot();
  const ref = await order(t, pay);
  const first = await t.store.casPaymentRaw('mercadopago', ref, 'pending', 0, { rev: 1, card_attempt: { id: 'a1', state: 'inflight' } });
  const second = await t.store.casPaymentRaw('mercadopago', ref, 'pending', 0, { rev: 1, card_attempt: { id: 'a2', state: 'inflight' } });
  assert.ok(first); assert.equal(second, null);
  assert.equal(t.row().raw.card_attempt.id, 'a1');
  // cancelamento não apaga a tentativa gravada (preserva o raw)
  assert.equal(t.row().raw.rev, 1);
}));
