'use strict';
// R171b · SEC-009 BLOQUEADOR do reteste Orca: janela de INICIALIZAÇÃO. Antes o servidor gravava o limite no banco
// sem esperar; um pagamento antigo que chegasse antes (webhook, JÁ PAGUEI, cartão, reconciliação) via limite 0
// (= sem limite) e o Orca obteve 2 Fundadores com limite 1. Agora o Fundador fica FECHADO até o limite estar
// confirmado no banco. Invariante checada em todos os passos: Fundadores <= FRAIHA_FOUNDER_LIMIT.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');

const quiet = () => { const o = [console.log, console.error, console.warn]; console.log = console.error = console.warn = () => {}; return () => { [console.log, console.error, console.warn] = o; }; };
const founders = s => [...(s.entitlements || new Map()).values()].filter(e => e.is_founder).length;
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };

// boot com a gravação do limite ATRASADA (controlada pelo teste)
function boot(limit, { n = 2, hold = 'expired', env = {} } = {}) {
  const store = new MemoryStore(), sent = [];
  store.payments = [];
  for (let i = 0; i < n; i++) store.payments.push({ payment_id: 'p' + i, user_id: 'U' + i, product_id: 'founder', method: i % 2 ? 'card' : 'pix', provider: 'fake',
    provider_ref: 'ref' + i, amount_cents: 4490, status: 'pending', created_at: new Date().toISOString(),
    seat_hold_until: hold === 'expired' ? new Date(Date.now() - 60e3).toISOString() : null });
  const gate = deferred(), orig = store.founderSetLimit.bind(store);
  let began = 0;
  store.founderSetLimit = async l => { began++; await gate.promise; return orig(l); };
  const backend = { store, socketsOf: uid => [{ uid }], state: async () => {} };
  const pay = new Payments({ send: (ws, o) => sent.push({ to: ws.uid, ...o }), backend, env: { FRAIHA_FOUNDER_LIMIT: String(limit), FRAIHA_FOUNDER_CAPACITY_WAIT_MS: '60', ...env } });
  pay.provider = { name: 'fake', ready: () => true, findByRef: async ref => ({ providerRef: ref, status: 'paid', amountCents: 4490, currency: 'BRL', providerPaymentId: '9' + ref }),
    createCharge: async ({ ref, amountCents }) => ({ id: ref, method: 'pix', status: 'pending', amount: amountCents }),
    payCard: async ({ ref }) => ({ providerRef: ref, status: 'paid', amountCents: 4490, currency: 'BRL', providerPaymentId: '8' + ref }) };
  const ws = id => ({ uid: id, user: { id, email: id + '@x.dev' }, profile: { nickname: id } });
  return { store, pay, sent, gate, ws, began: () => began };
}
// todos os caminhos que entregam Fundador, ao mesmo tempo
function everyPath(t) {
  const refs = t.store.payments.map(p => p.provider_ref);
  const ev = ref => ({ providerRef: ref, status: 'paid', amountCents: 4490, currency: 'BRL', providerPaymentId: '7' + ref });
  return Promise.allSettled([
    ...refs.map(r => t.pay.apply(ev(r))),                                                           // webhook
    ...refs.map(r => t.pay.apply(ev(r))),                                                           // webhook repetido
    ...t.store.payments.map(p => t.pay.handle(t.ws(p.user_id), { type: 'payment_status', charge_id: p.provider_ref })),   // JÁ PAGUEI
    ...t.store.payments.filter(p => p.method === 'card').map(p => t.pay.handle(t.ws(p.user_id), { type: 'payment_card_pay', charge_id: p.provider_ref, token: 'tok-approve-123', payment_method_id: 'master' })),
    t.pay.reconcile(),
  ]);
}

test('Orca: limite 1, gravação do limite atrasada, 2 pagamentos simultâneos → nenhum Fundador antes; depois só 1', async () => {
  const restore = quiet();
  try {
    const t = boot(1);
    assert.equal(t.began(), 1, 'o servidor começou a gravar o limite');
    await Promise.all([t.pay.payAndGrant('ref0'), t.pay.payAndGrant('ref1')].map(p => p.catch(e => e.code)));
    assert.equal(founders(t.store), 0, 'antes do limite confirmado: nenhuma entrega');
    assert.deepEqual(t.store.payments.map(p => p.status), ['pending', 'pending'], 'pagamentos continuam pendentes (nada se perde)');
    t.gate.resolve(); await new Promise(r => setTimeout(r, 10));
    await Promise.all([t.pay.payAndGrant('ref0'), t.pay.payAndGrant('ref1')]);
    assert.equal(founders(t.store), 1, 'limite 1 → 1 Fundador');
    assert.deepEqual(t.store.payments.map(p => p.status).sort(), ['paid', 'sold_out']);
  } finally { restore(); }
});

for (const [limit, n] of [[1, 2], [1, 10], [2, 10], [3, 25]]) {
  test(`boot + capacidade atrasada + webhook/JÁ PAGUEI/cartão/reconciliação simultâneos: ${limit} vaga(s) / ${n} pagamentos → nunca passa do limite`, async () => {
    const restore = quiet();
    try {
      const t = boot(limit, { n });
      const r1 = await everyPath(t);
      assert.equal(founders(t.store), 0, 'janela de boot: 0 Fundadores');
      assert.ok(t.store.payments.every(p => p.status === 'pending'), 'janela de boot: todos pendentes');
      assert.ok(r1.filter(x => x.status === 'rejected').length >= n, 'webhooks respondem erro (o provedor repete)');
      assert.ok(t.sent.some(o => o.type === 'payment_card_result' && o.status === 'error'), 'cartão: "aguarde a confirmação", nunca "aprovado"');
      assert.ok(!t.sent.some(o => o.type === 'payment_card_result' && o.status === 'approved'));
      t.gate.resolve(); await new Promise(r => setTimeout(r, 10));
      // o provedor repete, o jogador aperta JÁ PAGUEI de novo, a reconciliação roda — tudo junto
      t.pay.lastPoll.clear();
      await everyPath(t);
      assert.ok(founders(t.store) <= limit, `Fundadores ${founders(t.store)} <= limite ${limit}`);
      assert.equal(founders(t.store), limit, 'as vagas são preenchidas');
      assert.equal(t.store.payments.filter(p => p.status === 'sold_out').length, n - limit, 'o resto: pago sem vaga (reembolso), avisado');
      assert.equal(t.store.payments.filter(p => p.status === 'pending').length, 0, 'nada pendurado');
    } finally { restore(); }
  });
}

test('venda de Fundador fechada até o limite estar confirmado; Club funciona normal', async () => {
  const restore = quiet();
  try {
    const t = boot(1, { n: 0 });
    await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    assert.equal(t.sent.at(-1).code, 'founder_unavailable');
    await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'club_monthly', method: 'pix' });
    assert.equal(t.sent.at(-1).type, 'payment_charge', 'Club não depende do limite do Fundador');
    t.gate.resolve(); await new Promise(r => setTimeout(r, 10));
    await t.pay.handle(t.ws('bia'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    assert.equal(t.sent.at(-1).type, 'payment_charge', 'depois de confirmado: abre');
  } finally { restore(); }
});

test('banco sem a 0023 com FRAIHA_FOUNDER_LIMIT>0: Fundador FECHADO (nunca o caminho antigo sem lock)', async () => {
  const restore = quiet();
  try {
    const store = new MemoryStore(), sent = [];
    store.founderSetLimit = async () => ({ missing: true });
    store.founderReserve = async () => ({ missing: true });
    store.payments = [{ payment_id: 'x', user_id: 'U1', product_id: 'founder', method: 'pix', provider: 'fake', provider_ref: 'old', amount_cents: 4490, status: 'pending', created_at: new Date().toISOString() }];
    const pay = new Payments({ send: (ws, o) => sent.push(o), backend: { store, socketsOf: () => [], state: async () => {} }, env: { FRAIHA_FOUNDER_LIMIT: '1' } });
    pay.provider = { name: 'fake', ready: () => true, createCharge: async ({ ref }) => ({ id: ref, method: 'pix', status: 'pending' }) };
    await pay.handle({ user: { id: 'U2', email: 'a@x' }, profile: {} }, { type: 'payment_create', product_id: 'founder', method: 'pix' });
    assert.equal(sent.at(-1).code, 'founder_unavailable');
    await assert.rejects(pay.apply({ providerRef: 'old', status: 'paid', amountCents: 4490, currency: 'BRL' }));
    assert.equal(founders(store), 0);
    assert.equal(store.payments[0].status, 'pending', 'pago no provedor continua pendente aqui até aplicar a 0023 (sem perda)');
  } finally { restore(); }
});

test('banco nasce fechado: MemoryStore (espelho da 0023) sem limite configurado não entrega Fundador nem na reconciliação', async () => {
  const s = new MemoryStore();
  s.payments = [{ payment_id: 'a', user_id: 'A', product_id: 'founder', method: 'pix', provider: 'p', provider_ref: 'r1', amount_cents: 4490, status: 'pending' },
    { payment_id: 'b', user_id: 'B', product_id: 'founder', method: 'pix', provider: 'p', provider_ref: 'r2', amount_cents: 4490, status: 'paid' }];
  await assert.rejects(s.payAndGrant('p', 'r1', 'p'), /founder_capacity_not_configured/);
  assert.deepEqual(await s.grantPaidMissing(), { granted: 0, sold_out: 0 });
  assert.equal(founders(s), 0);
  await s.founderSetLimit(1);
  await s.payAndGrant('p', 'r1', 'p');
  await s.grantPaidMissing();
  assert.equal(founders(s), 1, 'configurado: entrega respeitando o limite');
});

test('R172 · FRAIHA_FOUNDER_LIMIT vazio (0) = FECHADO, não "sem limite": nenhum caminho entrega Fundador', async () => {
  const restore = quiet();
  try {
    const t = boot(0, { n: 6 });
    t.gate.resolve(); await new Promise(r => setTimeout(r, 10));
    assert.equal(await t.pay.capacityReady(), false);
    await everyPath(t);
    assert.equal(founders(t.store), 0);
    assert.ok(t.store.payments.every(p => p.status === 'pending'), 'continuam pendentes (sem perda)');
  } finally { restore(); }
});

test('R172 · restart do servidor: o servidor novo começa fechado e só reabre depois de reconfirmar o limite (inclusive se ele mudou)', async () => {
  const restore = quiet();
  try {
    const t = boot(2, { n: 4 });
    t.gate.resolve(); await new Promise(r => setTimeout(r, 10));
    await t.pay.payAndGrant('ref0');
    assert.equal(founders(t.store), 1);
    // "reinício" com FRAIHA_FOUNDER_LIMIT reduzido para 1 e o banco lento para gravar
    const gate2 = deferred(), orig = Object.getPrototypeOf(t.store).founderSetLimit.bind(t.store);
    t.store.founderSetLimit = async l => { await gate2.promise; return orig(l); };
    const pay2 = new Payments({ send: () => {}, backend: { store: t.store, socketsOf: () => [], state: async () => {} }, env: { FRAIHA_FOUNDER_LIMIT: '1', FRAIHA_FOUNDER_CAPACITY_WAIT_MS: '60' } });
    pay2.provider = t.pay.provider;
    assert.equal(pay2.founderReady, false, 'founder_ready=false ao iniciar');
    const r = await Promise.allSettled(['ref1', 'ref2', 'ref3'].map(ref => pay2.payAndGrant(ref)));
    assert.ok(r.every(x => x.status === 'rejected'), 'durante o reboot nada é entregue');
    assert.equal(founders(t.store), 1);
    gate2.resolve(); await new Promise(r => setTimeout(r, 10));
    assert.equal(await pay2.capacityReady(), true); assert.equal(pay2.founderReady, true);
    await Promise.all(['ref1', 'ref2', 'ref3'].map(ref => pay2.payAndGrant(ref)));
    assert.equal(founders(t.store), 1, 'novo limite 1 respeitado (já havia 1 Fundador)');
    assert.equal(t.store.payments.filter(p => p.status === 'sold_out').length, 3);
  } finally { restore(); }
});

test('R172 · banco devolve limite errado, vazio ou erro de SQL → Fundador FECHADO (nunca "sem limite"); Club segue', async () => {
  const restore = quiet();
  try {
    for (const bad of [async () => 0, async () => null, async () => undefined, async () => 5, async () => { throw new Error('SQL timeout'); }, async () => ({ missing: true })]) {
      const store = new MemoryStore(), sent = [];
      store.payments = [{ payment_id: 'x', user_id: 'U1', product_id: 'founder', method: 'pix', provider: 'fake', provider_ref: 'old', amount_cents: 4490, status: 'pending', created_at: new Date().toISOString() }];
      store.founderSetLimit = bad;
      const pay = new Payments({ send: (ws, o) => sent.push(o), backend: { store, socketsOf: () => [], state: async () => {} }, env: { FRAIHA_FOUNDER_LIMIT: '1' } });
      pay.provider = { name: 'fake', ready: () => true, createCharge: async ({ ref }) => ({ id: ref, method: 'pix', status: 'pending' }) };
      assert.equal(await pay.capacityReady(), false, 'resposta ' + bad.toString());
      await assert.rejects(pay.apply({ providerRef: 'old', status: 'paid', amountCents: 4490, currency: 'BRL' }));
      assert.equal(await pay.reconcile(), null, 'reconciliação adiada');
      await pay.handle({ user: { id: 'U2', email: 'a@x' }, profile: {} }, { type: 'payment_create', product_id: 'founder', method: 'pix' });
      assert.equal(sent.at(-1).code, 'founder_unavailable');
      await pay.handle({ user: { id: 'U2', email: 'a@x' }, profile: {} }, { type: 'payment_create', product_id: 'club_monthly', method: 'pix' });
      assert.equal(sent.at(-1).type, 'payment_charge', 'Club continua funcionando');
      assert.equal(founders(store), 0);
    }
  } finally { restore(); }
});
