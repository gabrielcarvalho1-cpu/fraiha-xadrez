'use strict';
// R172 · Fundador FAIL-CLOSED pela configuração: não existe "Fundador ilimitado".
// FRAIHA_FOUNDER_LIMIT ausente, vazio, 0, negativo ou texto → founder_ready=false (venda e entrega fechadas, nem consulta
// o banco). Só um inteiro positivo explícito abre — e só depois de o banco confirmar EXATAMENTE esse valor.
// O Club e o resto do jogo funcionam igual em todos os casos.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');

const quiet = () => { const o = [console.log, console.error, console.warn]; console.log = console.error = console.warn = () => {}; return () => { [console.log, console.error, console.warn] = o; }; };
const founders = s => [...(s.entitlements || new Map()).values()].filter(e => e.is_founder).length;

function make(envLimit, { slowDb = false, answer } = {}) {
  const store = new MemoryStore(), sent = [];
  store.payments = [{ payment_id: 'old', user_id: 'U0', product_id: 'founder', method: 'pix', provider: 'fake', provider_ref: 'old', amount_cents: 4490, status: 'pending', created_at: new Date().toISOString() },
    { payment_id: 'club', user_id: 'U9', product_id: 'club_monthly', method: 'pix', provider: 'fake', provider_ref: 'club', amount_cents: 1690, status: 'pending', created_at: new Date().toISOString() }];
  const calls = []; let release = () => {};
  const gate = slowDb ? new Promise(r => { release = r; }) : null;
  const orig = store.founderSetLimit.bind(store);
  store.founderSetLimit = async l => { calls.push(l); if (gate) await gate; return answer !== undefined ? answer : orig(l); };
  const env = { FRAIHA_FOUNDER_CAPACITY_WAIT_MS: '60' };
  if (envLimit !== undefined) env.FRAIHA_FOUNDER_LIMIT = envLimit;
  const pay = new Payments({ send: (ws, o) => sent.push(o), backend: { store, socketsOf: () => [], state: async () => {} }, env });
  pay.provider = { name: 'fake', ready: () => true, createCharge: async ({ ref, amountCents }) => ({ id: ref, method: 'pix', status: 'pending', amount: amountCents }) };
  const user = id => ({ user: { id, email: id + '@x.dev' }, profile: { nickname: id } });
  return { store, pay, sent, calls, release: () => release(), user };
}

for (const [label, v] of [['ausente', undefined], ['vazia', ''], ['0', '0'], ['negativa', '-5'], ['texto inválido', 'dez'], ['decimal', '1.5'], ['espaços', '   '], ['null (texto)', 'null']]) {
  test(`FRAIHA_FOUNDER_LIMIT ${label} → founder_ready=false: nada de venda, entrega ou reconciliação de Fundador; Club normal`, async () => {
    const restore = quiet();
    try {
      const t = make(v);
      assert.equal(await t.pay.capacityReady(), false);
      assert.equal(t.pay.founderReady, false);
      assert.deepEqual(t.calls, [], 'nem grava limite no banco (não existe "sem limite")');
      // vitrine e criação de pedido
      const offer = await t.pay.offer(t.user('A'));
      assert.equal(offer.founder_open, false, 'loja mostra Fundador indisponível');
      await t.pay.handle(t.user('A'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
      assert.equal(t.sent.at(-1).code, 'founder_unavailable');
      await t.pay.handle(t.user('A'), { type: 'payment_create', product_id: 'founder_legend', method: 'card' });
      assert.equal(t.sent.at(-1).code, 'founder_unavailable');
      // webhook / JÁ PAGUEI (apply) e reconciliação não entregam o pedido antigo
      await assert.rejects(t.pay.apply({ providerRef: 'old', status: 'paid', amountCents: 4490, currency: 'BRL' }));
      assert.equal(await t.pay.reconcile(), null);
      assert.equal(founders(t.store), 0);
      assert.equal(t.store.payments[0].status, 'pending', 'pagamento antigo fica pendente (sem perda)');
      // banco espelho também não entrega sem limite positivo
      await t.store.founderSetLimit(0);
      await assert.rejects(t.store.payAndGrant('fake', 'old', 'fake'));
      // Club continua
      await t.pay.handle(t.user('B'), { type: 'payment_create', product_id: 'club_monthly', method: 'pix' });
      assert.equal(t.sent.at(-1).type, 'payment_charge');
      await t.pay.apply({ providerRef: 'club', status: 'paid', amountCents: 1690, currency: 'BRL' });
      assert.equal((await t.store.getEntitlements('U9')).club_active, true, 'Club entregue normalmente');
    } finally { restore(); }
  });
}

for (const n of [1, 100]) {
  test(`FRAIHA_FOUNDER_LIMIT=${n} → fechado até o banco confirmar ${n}; depois abre e respeita o limite`, async () => {
    const restore = quiet();
    try {
      const t = make(String(n), { slowDb: true });
      assert.equal(t.pay.founderReady, false, 'começa fechado');
      assert.equal(await t.pay.capacityReady(), false, 'banco ainda não confirmou');
      await assert.rejects(t.pay.apply({ providerRef: 'old', status: 'paid', amountCents: 4490, currency: 'BRL' }));
      assert.equal(founders(t.store), 0);
      t.release(); await new Promise(r => setTimeout(r, 10));
      assert.equal(await t.pay.capacityReady(), true);
      assert.equal(t.pay.founderReady, true);
      assert.deepEqual(t.calls, [n], 'gravou exatamente o valor configurado');
      assert.equal(t.store.founderLimit, n);
      await t.pay.apply({ providerRef: 'old', status: 'paid', amountCents: 4490, currency: 'BRL' });
      assert.equal(founders(t.store), 1);
      await t.pay.handle(t.user('C'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
      assert.equal(t.sent.at(-1).type, n > 1 ? 'payment_charge' : 'payment_error', n > 1 ? 'há vaga: abre' : 'limite 1 já usado: esgotado');
      if (n === 1) assert.equal(t.sent.at(-1).code, 'founder_sold_out');
      assert.ok(founders(t.store) <= n);
    } finally { restore(); }
  });
}

test('banco confirma valor DIFERENTE do configurado (ou 0) → continua fechado', async () => {
  const restore = quiet();
  try {
    for (const answer of [0, 99, null]) {
      const t = make('100', { answer });
      assert.equal(await t.pay.capacityReady(), false, 'banco devolveu ' + answer);
      assert.equal(t.pay.founderReady, false);
    }
  } finally { restore(); }
});
