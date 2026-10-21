'use strict';
// R171 · SEC-009 — limite de vagas do Fundador atômico (serviço de pagamentos + MemoryStore com as regras da 0023).
// A corrida REAL no banco está em founder_seats_pg_test.cjs (Postgres 16, várias conexões).
// Invariante em todos os cenários: Fundadores entregues <= FRAIHA_FOUNDER_LIMIT.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');

function setup(limit, env = {}) {
  const store = new MemoryStore(); const sent = [];
  const backend = { store, socketsOf: uid => [{ uid }], state: async () => {} };
  const quietE = console.error, quietL = console.log; console.error = () => {}; console.log = () => {};
  const pay = new Payments({ send: (ws, o) => sent.push({ to: ws.uid, ...o }), backend, env: { FRAIHA_PAYMENT_PROVIDER: '', FRAIHA_FOUNDER_LIMIT: String(limit), ...env } });
  pay.provider = { name: 'fake', ready: () => true, refunds: [],
    createCharge: async ({ ref, amountCents }) => { await new Promise(r => setTimeout(r, Math.random() * 5)); return { id: ref, method: 'pix', status: 'pending', amount: amountCents }; },
    refund: async id => { pay.provider.refunds.push(id); } };
  const ws = id => ({ uid: id, user: { id, email: id + '@x.dev' }, profile: { nickname: id } });
  const restore = () => { console.error = quietE; console.log = quietL; };
  return { store, pay, sent, ws, restore };
}
const founders = async s => s.countFounders();
const paid = (t, ref, amount = 4490) => t.pay.apply({ providerRef: ref, status: 'paid', amountCents: amount, currency: 'BRL', providerPaymentId: '9' + Math.floor(Math.random() * 1e8) });
// pedidos já abertos com reserva vencida (pior caso: pedido antigo/limite reduzido) — criados direto no banco
const oldOrder = (t, uid) => { const ref = 'old-' + uid; t.store.payments = t.store.payments || []; t.store.payments.push({ payment_id: ref, user_id: uid, product_id: 'founder', method: 'pix', provider: 'fake', provider_ref: ref, amount_cents: 4490, status: 'pending', created_at: new Date().toISOString(), seat_hold_until: new Date(Date.now() - 60e3).toISOString() }); return ref; };

for (const [limit, buyers] of [[1, 2], [1, 10], [2, 10]]) {
  test(`SEC-009: ${limit} vaga(s) / ${buyers} compradores criando pedido ao mesmo tempo → só ${limit} pedido(s)`, async () => {
    const t = setup(limit);
    try {
      await Promise.all(Array.from({ length: buyers }, (_, i) => t.pay.handle(t.ws('u' + i), { type: 'payment_create', product_id: 'founder', method: 'pix' })));
      const charges = t.sent.filter(o => o.type === 'payment_charge');
      const soldOut = t.sent.filter(o => o.type === 'payment_error' && o.code === 'founder_sold_out');
      assert.equal(charges.length, limit, 'cobranças criadas = vagas');
      assert.equal(soldOut.length, buyers - limit, 'os outros veem "vagas esgotadas" antes de pagar');
      await Promise.all(charges.map(c => paid(t, c.charge.id)));
      assert.equal(await founders(t.store), limit);
    } finally { t.restore(); }
  });
  test(`SEC-009: ${limit} vaga(s) / ${buyers} pedidos antigos pagos ao mesmo tempo → ${limit} Fundador(es), resto sold_out com aviso`, async () => {
    const t = setup(limit);
    try {
      await t.store.founderSetLimit(limit);
      const refs = Array.from({ length: buyers }, (_, i) => oldOrder(t, 'v' + i));
      await Promise.all(refs.map(r => paid(t, r)));
      assert.ok(await founders(t.store) <= limit);
      assert.equal(await founders(t.store), limit);
      const so = t.store.payments.filter(p => p.status === 'sold_out');
      assert.equal(so.length, buyers - limit);
      for (const p of so) {
        const notes = t.sent.filter(o => o.to === p.user_id && o.type === 'payment_error' && o.code === 'founder_sold_out_paid');
        assert.equal(notes.length, 1, 'quem pagou sem vaga é avisado (nada silencioso)');
        assert.match(notes[0].message, /devolvido integralmente/);
      }
      assert.equal(t.store.payments.filter(p => p.status === 'pending').length, 0, 'nenhum pagamento fica pendurado');
    } finally { t.restore(); }
  });
}

test('SEC-009: webhook duplicado, retry simultâneo, JÁ PAGUEI e reconciliação na mesma compra → entrega 1 vez', async () => {
  const t = setup(1);
  try {
    await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder', method: 'card' });
    const ref = t.sent.find(o => o.type === 'payment_charge').charge.id;
    t.pay.provider.findByRef = async r => ({ providerRef: r, status: 'paid', amountCents: 4990, currency: 'BRL' });
    await Promise.all([...Array.from({ length: 8 }, () => paid(t, ref, 4990)), t.pay.handle(t.ws('ana'), { type: 'payment_status', charge_id: ref }), t.pay.reconcile()]);
    assert.equal(await founders(t.store), 1);
    assert.equal(t.store.payments.filter(p => p.status === 'paid').length, 1);
    const e = await t.store.getEntitlements('ana');
    assert.equal(e.founder_number, 1);
    assert.ok((new Date(e.club_expires_at) - Date.now()) / 86400e3 < 91, 'Club de bônus entregue 1 vez só');
  } finally { t.restore(); }
});

test('SEC-009: quem reservou a última vaga recebe mesmo que outro pedido antigo pague antes', async () => {
  const t = setup(1);
  try {
    await t.pay.handle(t.ws('dono'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    const mine = t.sent.find(o => o.type === 'payment_charge').charge.id;
    const intruso = oldOrder(t, 'intruso');
    await paid(t, intruso);
    await paid(t, mine);
    assert.equal(t.store.payments.find(p => p.provider_ref === mine).status, 'paid');
    assert.equal(t.store.payments.find(p => p.provider_ref === intruso).status, 'sold_out');
    assert.equal(await founders(t.store), 1);
  } finally { t.restore(); }
});

test('SEC-009: estorno automático só com FRAIHA_FOUNDER_AUTO_REFUND=1; reembolso fecha o sold_out sem retirar nada', async () => {
  const t = setup(1, { FRAIHA_FOUNDER_AUTO_REFUND: '1' });
  try {
    await t.store.founderSetLimit(1);
    const [a, b] = [oldOrder(t, 'a'), oldOrder(t, 'b')];
    await paid(t, a); await paid(t, b);
    assert.equal(t.pay.provider.refunds.length, 1, 'estorno pedido ao provedor para quem ficou sem vaga');
    await t.pay.apply({ providerRef: b, status: 'refunded' });
    assert.equal(t.store.payments.find(p => p.provider_ref === b).status, 'refunded');
    assert.equal((await t.store.getEntitlements('a')).is_founder, true, 'o Fundador legítimo não perde nada');
    const t2 = setup(1);
    await t2.store.founderSetLimit(1);
    await paid(t2, oldOrder(t2, 'c')); await paid(t2, oldOrder(t2, 'd'));
    assert.equal(t2.pay.provider.refunds.length, 0, 'sem a variável: reembolso manual (avisado), nada automático');
    t2.restore();
  } finally { t.restore(); }
});

test('SEC-009: upgrade Fundador → Lendário com vagas esgotadas não ocupa vaga; R172: sem limite = fechado', async () => {
  const t = setup(1);
  try {
    await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    await paid(t, t.sent.find(o => o.type === 'payment_charge').charge.id);
    t.sent.length = 0;
    await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder_legend', method: 'card' });
    const ref = t.sent.find(o => o.type === 'payment_charge').charge.id;
    await paid(t, ref, 9990);
    assert.equal((await t.store.getEntitlements('ana')).founder_tier, 'legend');
    await t.pay.handle(t.ws('bia'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    assert.ok(t.sent.some(o => o.type === 'payment_error' && o.code === 'founder_sold_out'));
    assert.equal(await founders(t.store), 1);
    // R172: limite 0/vazio não é "sem limite" — o Fundador fica fechado (nenhum pedido, nenhum Fundador)
    const free = setup(0);
    await Promise.all(Array.from({ length: 6 }, (_, i) => free.pay.handle(free.ws('f' + i), { type: 'payment_create', product_id: 'founder', method: 'pix' })));
    assert.equal(free.sent.filter(o => o.type === 'payment_charge').length, 0);
    assert.equal(free.sent.filter(o => o.code === 'founder_unavailable').length, 6);
    assert.equal(await founders(free.store), 0);
    free.restore();
  } finally { t.restore(); }
});

test('SEC-009: cartão aprovado no instante em que a última vaga acabou → resposta "sold_out" (nunca "aprovado"/"aguarde")', async () => {
  const t = setup(1);
  try {
    await t.store.founderSetLimit(1);
    const ref = oldOrder(t, 'caio'); t.store.payments.find(p => p.provider_ref === ref).method = 'card';
    await paid(t, oldOrder(t, 'dono'));   // outro pedido levou a última vaga
    t.pay.provider.findByRef = async () => null;   // R175b · o provedor confirma: nenhuma aprovação anterior → pode cobrar
    t.pay.provider.payCard = async () => ({ providerRef: ref, status: 'paid', amountCents: 4490, currency: 'BRL', providerPaymentId: '77' });
    await t.pay.handle(t.ws('caio'), { type: 'payment_card_pay', charge_id: ref, token: 'tok-approve-123', payment_method_id: 'master' });
    const r = t.sent.filter(o => o.type === 'payment_card_result').at(-1);
    assert.equal(r.status, 'sold_out'); assert.match(r.message, /devolvido integralmente/);
    assert.equal((await t.store.getEntitlements('caio')).is_founder || false, false);
    assert.equal(await founders(t.store), 1);
  } finally { t.restore(); }
});
