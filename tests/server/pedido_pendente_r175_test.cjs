'use strict';
// R175 · PEDIDO PENDENTE: histórico com estados, CONTINUAR (o mesmo pedido), CANCELAR (conferindo no provedor antes),
// expiração, pagamento tardio depois de cancelado, webhook durante o cancelamento, webhook duplicado, duas abas,
// cartão retomado com token novo sem cobrar duas vezes e reserva de vaga do Fundador preservada (regras da 0023).
// Serviço de pagamentos real + MemoryStore (mesmas regras da 0023) + Mercado Pago falso em memória.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Payments } = require('../../online_v021/payments/service');

const MAP = { approved: 'paid', pending: 'pending', in_process: 'pending', rejected: 'failed', cancelled: 'cancelled', refunded: 'refunded' };
const tick = (ms = 0) => new Promise(r => setTimeout(r, ms));

// Mercado Pago falso: um registro por pagamento (id numérico), ligado ao pedido pelo external_reference (ref)
function fakeMP() {
  const mp = { pays: new Map(), calls: [], nextId: 5000, down: false, delay: 0, cardStatus: 'approved' };
  const ev = p => ({ providerRef: p.ref, status: MAP[p.status] || 'pending', amountCents: p.amount, currency: 'BRL', providerPaymentId: String(p.id), detail: p.detail || '' });
  const latest = ref => {
    const list = [...mp.pays.values()].filter(p => p.ref === ref).reverse();
    return list.find(p => p.status === 'approved') || list.find(p => p.status === 'refunded') || list[0] || null;
  };
  const wait = async () => { if (mp.delay) await tick(mp.delay); if (mp.down) { const e = new Error('mercado pago fora'); e.status = 503; throw e; } };
  mp.provider = {
    name: 'mercadopago', ready: () => true,
    async createCharge({ ref, method, amountCents, idemSuffix = '' }) {
      mp.calls.push({ op: 'create', ref, method, idemSuffix }); await wait();
      if (method === 'pix') {
        const id = mp.nextId++;
        mp.pays.set(id, { id, ref, status: 'pending', amount: amountCents, method: 'pix', qr: 'PIXQR-' + id, exp: Date.now() + 30 * 60e3 });
        return { id: ref, method: 'pix', status: 'pending', copy_paste: 'PIXQR-' + id, qr_code_base64: 'B64-' + id, provider_payment_id: String(id), expires_at: new Date(Date.now() + 30 * 60e3).toISOString() };
      }
      return { id: ref, method: 'card', status: 'pending', checkout_url: 'https://mp.test/pref/' + ref + idemSuffix, public_key: 'PK-TEST' };
    },
    async findByRef(ref) { mp.calls.push({ op: 'find', ref }); await wait(); const p = latest(ref); return p ? ev(p) : null; },
    async resumePix(ref) {
      mp.calls.push({ op: 'resume', ref }); await wait();
      const p = latest(ref); if (!p) return null;
      const expired = p.exp <= Date.now();
      if (p.status !== 'pending' || expired) return { event: { ...ev(p), expired } };
      return { event: ev(p), charge: { id: ref, provider_payment_id: String(p.id), method: 'pix', status: 'pending', copy_paste: p.qr, qr_code_base64: 'B64-' + p.id, expires_at: new Date(p.exp).toISOString() } };
    },
    async cancel(id) {
      mp.calls.push({ op: 'cancel', id }); await wait();
      const p = mp.pays.get(Number(id));
      if (!p) { const e = new Error('404'); e.status = 404; throw e; }
      if (p.status === 'approved') { const e = new Error('400 pagamento aprovado não pode ser cancelado'); e.status = 400; throw e; }
      p.status = 'cancelled'; p.detail = 'by_collector'; return ev(p);
    },
    async payCard({ ref, token, amountCents }) {
      mp.calls.push({ op: 'payCard', ref, token }); await wait();
      const id = mp.nextId++;
      const p = { id, ref, status: mp.cardStatus, amount: amountCents, method: 'card', detail: mp.cardStatus === 'rejected' ? 'cc_rejected_other_reason' : 'accredited' };
      mp.pays.set(id, p); return ev(p);
    },
    async refund(id) { mp.calls.push({ op: 'refund', id }); const p = mp.pays.get(Number(id)); if (p) p.status = 'refunded'; return {}; },
  };
  // o pagador paga o PIX no app do banco (vira aprovado no Mercado Pago) → evento do webhook
  mp.payPix = ref => { const p = [...mp.pays.values()].reverse().find(x => x.ref === ref && x.method === 'pix'); p.status = 'approved'; return ev(p); };
  mp.expirePix = ref => { const p = [...mp.pays.values()].reverse().find(x => x.ref === ref && x.method === 'pix'); p.status = 'cancelled'; p.detail = 'expired'; return ev(p); };
  mp.count = op => mp.calls.filter(c => c.op === op).length;
  return mp;
}

function setup({ limit = 5, env = {} } = {}) {
  const store = new MemoryStore(); const sent = [];
  const backend = { store, socketsOf: uid => [{ uid }], state: async () => {} };
  const keep = { e: console.error, l: console.log, w: console.warn }; console.error = () => {}; console.log = () => {}; console.warn = () => {};
  const pay = new Payments({ send: (ws, o) => sent.push({ to: ws.uid, ...o }), backend, env: { FRAIHA_PAYMENT_PROVIDER: '', FRAIHA_FOUNDER_LIMIT: String(limit), ...env } });
  const mp = fakeMP(); pay.provider = mp.provider;
  let offset = 0; pay.now = () => Date.now() + offset;
  const ws = id => ({ uid: id, user: { id, email: id + '@x.dev' }, profile: { nickname: id } });
  const restore = () => { console.error = keep.e; console.log = keep.l; console.warn = keep.w; };
  const last = (to, type) => [...sent].reverse().find(o => o.to === to && o.type === type);
  const all = (to, type) => sent.filter(o => o.to === to && o.type === type);
  const rows = uid => (store.payments || []).filter(p => p.user_id === uid);
  const create = async (uid, product = 'founder', method = 'pix') => {
    await pay.handle(ws(uid), { type: 'payment_create', product_id: product, method });
    const c = last(uid, 'payment_charge'); return c ? c.charge : null;
  };
  const history = async uid => { await pay.handle(ws(uid), { type: 'payment_history' }); return last(uid, 'payment_history').items; };
  const travel = ms => { offset += ms; for (const p of store.payments || []) { p.created_at = new Date(Date.parse(p.created_at) - ms).toISOString(); if (p.seat_hold_until) p.seat_hold_until = new Date(Date.parse(p.seat_hold_until) - ms).toISOString(); } offset -= ms; };
  return { store, pay, sent, mp, ws, restore, last, all, rows, create, history, travel };
}
const founders = s => s.countFounders();

test('histórico: pedido aguardando aparece com estado, validade e os botões CONTINUAR / CANCELAR', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'card');
    const items = await t.history('ana');
    assert.equal(items.length, 1);
    const it = items[0];
    assert.equal(it.id, c.id); assert.equal(it.state, 'pending'); assert.equal(it.status, 'pending');
    assert.ok(it.can_continue && it.can_cancel, 'pode continuar e cancelar');
    assert.ok(Date.parse(it.expires_at) - Date.now() > 29 * 60e3, 'vale 30 min');
    assert.equal(it.method, 'card'); assert.equal(it.amount_cents, 4990);
  } finally { t.restore(); }
});

test('CONTINUAR PIX: o MESMO pagamento (mesmo QR / Copia e Cola), sem novo pedido, sem nova reserva', async () => {
  const t = setup({ limit: 1 });
  try {
    const c = await t.create('ana', 'founder', 'pix');
    const hold = t.rows('ana')[0].seat_hold_until;
    const creates = t.mp.count('create');
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: c.id });
    const r = t.last('ana', 'payment_charge').charge;
    assert.equal(r.id, c.id); assert.equal(r.copy_paste, c.copy_paste, 'mesmo Copia e Cola'); assert.equal(r.resumed, true);
    assert.equal(t.mp.count('create'), creates, 'nenhuma cobrança nova no Mercado Pago');
    assert.equal(t.rows('ana').length, 1, 'nenhum pedido novo');
    assert.equal(t.rows('ana')[0].seat_hold_until, hold, 'reserva da vaga intacta');
    assert.equal(await t.store.founderTaken(), 1, 'continua ocupando 1 vaga (a mesma)');
    // outro comprador continua sem vaga (a reserva é da ana)
    await t.pay.handle(t.ws('bia'), { type: 'payment_create', product_id: 'founder', method: 'pix' });
    assert.equal(t.last('bia', 'payment_error').code, 'founder_sold_out');
    // pagar o PIX retomado entrega 1 vez
    await t.pay.apply(t.mp.payPix(c.id));
    assert.equal(t.rows('ana')[0].status, 'paid'); assert.equal(await founders(t.store), 1);
  } finally { t.restore(); }
});

test('CONTINUAR cartão: mesmo pedido, formulário de novo, token NOVO no novo envio; nunca reusa token nem cobra 2x', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'card');
    t.mp.cardStatus = 'rejected';
    await t.pay.handle(t.ws('ana'), { type: 'payment_card_pay', charge_id: c.id, token: 'tokenUM_123456', payment_method_id: 'visa' });
    assert.equal(t.last('ana', 'payment_card_result').status, 'rejected');
    // fechou o formulário; depois CONTINUAR pelo histórico
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: c.id });
    const r = t.last('ana', 'payment_charge').charge;
    assert.equal(r.id, c.id, 'mesmo pedido interno'); assert.equal(r.method, 'card'); assert.equal(r.public_key, 'PK-TEST');
    assert.equal(t.rows('ana').length, 1, 'sem pedido novo');
    const pref = t.mp.calls.filter(x => x.op === 'create' && x.method === 'card');
    assert.equal(pref.length, 2); assert.notEqual(pref[1].idemSuffix, '', 'preferência nova do MESMO pedido com outra chave');
    t.mp.cardStatus = 'approved';
    await t.pay.handle(t.ws('ana'), { type: 'payment_card_pay', charge_id: c.id, token: 'tokenDOIS_654321', payment_method_id: 'visa' });
    assert.equal(t.last('ana', 'payment_card_result').status, 'approved');
    const cards = t.mp.calls.filter(x => x.op === 'payCard');
    assert.deepEqual(cards.map(x => x.token), ['tokenUM_123456', 'tokenDOIS_654321'], 'cada envio com o seu token');
    // clique repetido / outra aba depois de aprovado: nada é cobrado de novo
    await t.pay.handle(t.ws('ana'), { type: 'payment_card_pay', charge_id: c.id, token: 'tokenTRES_999999', payment_method_id: 'visa' });
    assert.equal(t.last('ana', 'payment_card_result').status, 'approved');
    assert.equal(t.mp.count('payCard'), 2, 'nenhuma cobrança nova');
    assert.equal(await founders(t.store), 1);
  } finally { t.restore(); }
});

test('cartão: aprovado no Mercado Pago mas a confirmação se perdeu → novo envio entrega sem cobrar de novo', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'club_monthly', 'card');
    // aprovado direto no Mercado Pago (ex.: página do MP) sem webhook ainda
    t.mp.provider.payCard.call(null, { ref: c.id, token: 'x', amountCents: 1990 });
    await tick(5);
    const before = t.mp.count('payCard');
    await t.pay.handle(t.ws('ana'), { type: 'payment_card_pay', charge_id: c.id, token: 'tokenNOVO_12345', payment_method_id: 'visa' });
    assert.equal(t.last('ana', 'payment_card_result').status, 'approved');
    assert.equal(t.mp.count('payCard'), before, 'o token novo não foi cobrado');
    assert.equal(t.rows('ana')[0].status, 'paid');
  } finally { t.restore(); }
});

test('CANCELAR PIX: confere no Mercado Pago, cancela lá, compare-and-set aqui, libera a vaga; idempotente', async () => {
  const t = setup({ limit: 1 });
  try {
    const c = await t.create('ana', 'founder', 'pix');
    assert.equal(await t.store.founderTaken(), 1);
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
    assert.equal(t.last('ana', 'payment_cancel_result').status, 'cancelled');
    const row = t.rows('ana')[0];
    assert.equal(row.status, 'cancelled'); assert.equal(row.seat_hold_until, null);
    assert.equal(row.raw.cancel.reason, 'user'); assert.equal(row.raw.cancel.by, 'ana');
    assert.ok(t.mp.calls.findIndex(x => x.op === 'find') < t.mp.calls.findIndex(x => x.op === 'cancel'), 'conferiu antes de cancelar');
    assert.equal(t.mp.count('cancel'), 1, 'PIX cancelado no Mercado Pago');
    assert.equal(await t.store.founderTaken(), 0, 'vaga liberada');
    assert.ok(t.all('ana', 'payment_update').some(u => u.charge.id === c.id && u.charge.status === 'cancelled'), 'outras abas avisadas');
    // de novo (outra aba): sem efeito
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
    const again = t.last('ana', 'payment_cancel_result');
    assert.equal(again.status, 'cancelled'); assert.equal(again.already, true);
    assert.equal(t.mp.count('cancel'), 1);
    // agora pode começar outro pedido (sem "pedido em aberto")
    const c2 = await t.create('ana', 'founder', 'card');
    assert.ok(c2 && c2.id !== c.id);
    const items = await t.history('ana');
    assert.equal(items.find(i => i.id === c.id).state, 'cancelled');
    assert.equal(items.find(i => i.id === c.id).can_continue, false);
  } finally { t.restore(); }
});

test('CANCELAR: 2 abas / 2 aparelhos cancelando ao mesmo tempo → uma transição, um cancelamento no Mercado Pago', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'pix');
    t.mp.delay = 3;
    await Promise.all(Array.from({ length: 6 }, () => t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id })));
    const res = t.all('ana', 'payment_cancel_result');
    assert.equal(res.length, 6); assert.ok(res.every(r => r.status === 'cancelled'));
    assert.equal(res.filter(r => !r.already).length, 1, 'só uma cancelou de fato');
    assert.equal(t.mp.count('cancel'), 1);
    assert.equal(t.rows('ana')[0].raw.history.length, 1, 'um registro de cancelamento');
  } finally { t.restore(); }
});

test('CANCELAR quando o PIX JÁ foi pago (webhook atrasado) → entrega em vez de cancelar', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'pix');
    t.mp.payPix(c.id);   // pago no banco; o aviso ainda não chegou
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
    const r = t.last('ana', 'payment_cancel_result');
    assert.equal(r.status, 'paid'); assert.match(r.message, /já tinha sido pago/);
    assert.equal(t.rows('ana')[0].status, 'paid'); assert.equal(t.mp.count('cancel'), 0);
    assert.equal(await founders(t.store), 1);
  } finally { t.restore(); }
});

test('CANCELAR com o Mercado Pago fora do ar → nada muda (pedido segue aberto), aviso para tentar de novo', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'pix');
    t.mp.down = true;
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
    const r = t.last('ana', 'payment_cancel_result');
    assert.equal(r.status, 'error'); assert.equal(r.code, 'unverified');
    assert.equal(t.rows('ana')[0].status, 'pending');
  } finally { t.restore(); }
});

test('CANCELAR de outra conta / pedido inexistente: recusado', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'pix');
    await t.pay.handle(t.ws('bia'), { type: 'payment_cancel', charge_id: c.id });
    assert.equal(t.last('bia', 'payment_cancel_result').status, 'not_found');
    await t.pay.handle(t.ws('bia'), { type: 'payment_resume', charge_id: c.id });
    assert.equal(t.last('bia', 'payment_error').code, 'order_not_found');
    assert.equal(t.rows('ana')[0].status, 'pending');
  } finally { t.restore(); }
});

test('expirou (30 min): histórico confere no provedor e fecha como EXPIRADO; CONTINUAR recusa; vaga liberada', async () => {
  const t = setup({ limit: 1 });
  try {
    const c = await t.create('ana', 'founder', 'pix');
    t.travel(31 * 60e3);
    const items = await t.history('ana');
    assert.equal(items[0].state, 'expired'); assert.equal(items[0].can_continue, false);
    const row = t.rows('ana')[0];
    assert.equal(row.status, 'cancelled'); assert.equal(row.raw.cancel.reason, 'expired');
    assert.equal(t.mp.count('cancel'), 1, 'PIX fechado também no Mercado Pago');
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: c.id });
    assert.equal(t.last('ana', 'payment_error').code, 'order_closed');
    assert.equal(await t.store.founderTaken(), 0);
  } finally { t.restore(); }
});

test('CONTINUAR depois de 30 min (ainda pendente no banco) → confere, fecha como expirado e avisa', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'club_monthly', 'pix');
    t.travel(40 * 60e3);
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: c.id });
    assert.equal(t.last('ana', 'payment_error').code, 'order_expired');
    assert.equal(t.rows('ana')[0].status, 'cancelled');
  } finally { t.restore(); }
});

test('PIX expirado no Mercado Pago (webhook cancelled/expired) → EXPIRADO com o motivo registrado', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'pix');
    await t.pay.apply(t.mp.expirePix(c.id));
    const row = t.rows('ana')[0];
    assert.equal(row.status, 'cancelled'); assert.equal(row.raw.cancel.reason, 'expired');
    assert.equal((await t.history('ana'))[0].state, 'expired');
  } finally { t.restore(); }
});

test('pago DEPOIS de cancelado, COM vaga: o mesmo pedido é reaberto, histórico preservado, entrega exatamente 1 vez', async () => {
  const t = setup({ limit: 2 });
  try {
    const c = await t.create('ana', 'founder', 'card');
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
    assert.equal(t.rows('ana')[0].status, 'cancelled');
    // o cartão tinha sido aprovado na página do Mercado Pago (aviso chega depois do cancelamento), 5 avisos repetidos
    t.mp.provider.payCard({ ref: c.id, token: 'pg', amountCents: 4990 });
    await tick(2);
    const ev = await t.mp.provider.findByRef(c.id);
    await Promise.all(Array.from({ length: 5 }, () => t.pay.apply(ev)));
    const row = t.rows('ana')[0];
    assert.equal(row.status, 'paid'); assert.equal(row.payment_id, t.rows('ana')[0].payment_id);
    assert.equal(t.rows('ana').length, 1, 'mesmo pedido, nenhum novo');
    assert.equal(row.raw.cancel.reason, 'user', 'o cancelamento continua registrado');
    assert.equal(row.raw.reopened.length, 1, 'uma reabertura');
    assert.equal(row.raw.reopened[0].event, 'provider_approved_after_cancelled');
    assert.deepEqual(row.raw.history.map(h => h.event), ['cancelled', 'provider_approved_after_cancelled']);
    assert.equal(await founders(t.store), 1, 'entregue 1 vez');
    const e = await t.store.getEntitlements('ana');
    assert.ok((Date.parse(e.club_expires_at) - Date.now()) / 86400e3 < 91, 'Club de bônus 1 vez só');
    const it = (await t.history('ana'))[0];
    assert.equal(it.state, 'paid'); assert.equal(it.paid_after_cancel, true);
  } finally { t.restore(); }
});

test('pago DEPOIS de cancelado, SEM vaga: sem vaga (sold_out) + reembolso, nada entregue, nada pendurado', async () => {
  const t = setup({ limit: 1, env: { FRAIHA_FOUNDER_AUTO_REFUND: '1' } });
  try {
    const c = await t.create('ana', 'founder', 'pix');
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
    // a vaga liberada foi para a bia, que pagou
    const cb = await t.create('bia', 'founder', 'pix');
    await t.pay.apply(t.mp.payPix(cb.id));
    assert.equal(await founders(t.store), 1);
    // PIX da ana aprovado depois (cenário extremo: o cancelamento no MP falhou e ela pagou)
    const p = [...t.mp.pays.values()].find(x => x.ref === c.id); p.status = 'approved';
    await t.pay.apply({ providerRef: c.id, status: 'paid', amountCents: 4490, currency: 'BRL', providerPaymentId: String(p.id) });
    const row = t.rows('ana')[0];
    assert.equal(row.status, 'sold_out'); assert.equal(await founders(t.store), 1, 'limite respeitado');
    assert.equal(t.mp.count('refund'), 1, 'estorno pedido ao Mercado Pago');
    assert.ok(t.all('ana', 'payment_error').some(m => m.code === 'founder_sold_out_paid'), 'ana avisada: sem vaga, valor devolvido');
    assert.equal(row.raw.cancel.reason, 'user');
    assert.equal((store => store.payments.filter(x => x.status === 'pending').length)(t.store), 0);
    assert.equal((await t.history('ana'))[0].state, 'sold_out');
  } finally { t.restore(); }
});

test('webhook de pagamento DURANTE o cancelamento (todas as ordens) → pago e entregue 1 vez, nunca cancelado', async () => {
  for (let i = 0; i < 25; i++) {
    const t = setup();
    try {
      const c = await t.create('ana', 'founder', 'pix');
      t.mp.delay = (i % 4);
      const ev = t.mp.payPix(c.id);
      const jobs = [() => t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id }), () => t.pay.apply(ev), () => t.pay.apply(ev)];
      if (i % 2) jobs.reverse();
      await Promise.all(jobs.map(j => j()));
      const row = t.rows('ana')[0];
      assert.equal(row.status, 'paid', 'rodada ' + i);
      assert.equal(await founders(t.store), 1);
      assert.equal(t.mp.count('cancel'), 0);
    } finally { t.restore(); }
  }
});

test('webhook de pagamento chegando ENTRE o cancelamento no MP e o compare-and-set local → entregue 1 vez', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'pix');
    // o MP "cancela" mas o pagamento já tinha sido aprovado → o cancel falha; o serviço reconfere e entrega
    const orig = t.mp.provider.cancel;
    t.mp.provider.cancel = async id => { t.mp.payPix(c.id); return orig(id); };
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
    assert.equal(t.last('ana', 'payment_cancel_result').status, 'paid');
    assert.equal(t.rows('ana')[0].status, 'paid');
    assert.equal(await founders(t.store), 1);
  } finally { t.restore(); }
});

test('webhook duplicado e simultâneo + JÁ PAGUEI no pedido retomado → entrega 1 vez', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'pix');
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: c.id });
    const ev = t.mp.payPix(c.id);
    await Promise.all([...Array.from({ length: 8 }, () => t.pay.apply(ev)), t.pay.handle(t.ws('ana'), { type: 'payment_status', charge_id: c.id })]);
    assert.equal(t.rows('ana')[0].status, 'paid');
    assert.equal(await founders(t.store), 1);
  } finally { t.restore(); }
});

test('duas abas criando Fundador ao mesmo tempo → 1 pedido; a outra recebe "pedido em aberto" com o id para CONTINUAR', async () => {
  const t = setup();
  try {
    await Promise.all([t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder', method: 'pix' }),
      t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'founder', method: 'card' })]);
    assert.equal(t.rows('ana').length, 1);
    const err = t.last('ana', 'payment_error');
    assert.equal(err.code, 'order_open'); assert.equal(err.charge_id, t.rows('ana')[0].provider_ref);
    assert.equal(err.product_id, 'founder'); assert.ok(['pix', 'card'].includes(err.method));
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: err.charge_id });
    assert.equal(t.last('ana', 'payment_charge').charge.id, err.charge_id);
  } finally { t.restore(); }
});

test('cartão em pedido cancelado é recusado sem chamar o Mercado Pago', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'card');
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
    await t.pay.handle(t.ws('ana'), { type: 'payment_card_pay', charge_id: c.id, token: 'tokenXYZ_12345', payment_method_id: 'visa' });
    const r = t.last('ana', 'payment_card_result');
    assert.equal(r.status, 'error'); assert.equal(r.code, 'order_closed');
    assert.equal(t.mp.count('payCard'), 0);
  } finally { t.restore(); }
});

test('cartão disputando com CANCELAR (2 abas) → nunca fica "cancelado e cobrado"', async () => {
  for (let i = 0; i < 10; i++) {
    const t = setup();
    try {
      const c = await t.create('ana', 'founder', 'card');
      t.mp.delay = i % 3;
      const jobs = [() => t.pay.handle(t.ws('ana'), { type: 'payment_card_pay', charge_id: c.id, token: 'tokenABC_' + i + '_xyz', payment_method_id: 'visa' }),
        () => t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id })];
      if (i % 2) jobs.reverse();
      await Promise.all(jobs.map(j => j()));
      const row = t.rows('ana')[0];
      const charged = [...t.mp.pays.values()].some(p => p.ref === c.id && p.status === 'approved');
      if (charged) { assert.equal(row.status, 'paid', 'cobrado → entregue (rodada ' + i + ')'); assert.equal(await founders(t.store), 1); }
      else assert.equal(row.status, 'cancelled');
    } finally { t.restore(); }
  }
});

test('pedido marcado como falho (cobrança não respondeu) e pago depois → reaberto e entregue 1 vez', async () => {
  const t = setup();
  try {
    const orig = t.mp.provider.createCharge;
    t.mp.provider.createCharge = async args => { await orig(args); const e = new Error('timeout'); throw e; };   // o MP criou, mas a resposta se perdeu
    await t.pay.handle(t.ws('ana'), { type: 'payment_create', product_id: 'club_monthly', method: 'pix' });
    const row0 = t.rows('ana')[0];
    assert.equal(row0.status, 'failed');
    await t.pay.apply(t.mp.payPix(row0.provider_ref));
    const row = t.rows('ana')[0];
    assert.equal(row.status, 'paid'); assert.equal(row.raw.reopened[0].previous_status, 'failed');
    const e = await t.store.getEntitlements('ana');
    assert.ok(e.club_active || e.club_expires_at);
  } finally { t.restore(); }
});

test('Club: pendente aparece, CONTINUAR e CANCELAR funcionam (sem reserva de vaga)', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'club_yearly', 'pix');
    assert.equal(t.rows('ana')[0].seat_hold_until, undefined);
    assert.equal((await t.history('ana'))[0].state, 'pending');
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: c.id });
    assert.equal(t.last('ana', 'payment_charge').charge.copy_paste, c.copy_paste);
    await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
    assert.equal(t.rows('ana')[0].status, 'cancelled');
  } finally { t.restore(); }
});

test('CONTINUAR um pedido já pago → avisa "pago" (o jogo mostra a vantagem), nada de cobrança', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'pix');
    await t.pay.apply(t.mp.payPix(c.id));
    const creates = t.mp.count('create');
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: c.id });
    assert.equal(t.last('ana', 'payment_update').charge.status, 'paid');
    assert.equal(t.mp.count('create'), creates);
  } finally { t.restore(); }
});

test('CONTINUAR PIX que foi pago mas o aviso não chegou → entrega na hora', async () => {
  const t = setup();
  try {
    const c = await t.create('ana', 'founder', 'pix');
    t.mp.payPix(c.id);
    await t.pay.handle(t.ws('ana'), { type: 'payment_resume', charge_id: c.id });
    assert.equal(t.last('ana', 'payment_update').charge.status, 'paid');
    assert.equal(t.rows('ana')[0].status, 'paid'); assert.equal(await founders(t.store), 1);
  } finally { t.restore(); }
});

test('histórico antigo: cancelado sem motivo gravado aparece como EXPIRADO; falho não aparece', async () => {
  const t = setup();
  try {
    t.store.payments = [
      { payment_id: 'a', user_id: 'ana', product_id: 'club_monthly', method: 'pix', provider: 'mercadopago', provider_ref: 'r1', amount_cents: 1790, status: 'cancelled', created_at: new Date(Date.now() - 864e5).toISOString() },
      { payment_id: 'b', user_id: 'ana', product_id: 'club_monthly', method: 'pix', provider: 'mercadopago', provider_ref: 'r2', amount_cents: 1790, status: 'failed', created_at: new Date().toISOString() }];
    const items = await t.history('ana');
    assert.equal(items.length, 1); assert.equal(items[0].state, 'expired');
  } finally { t.restore(); }
});

test('banco lento: aviso "cancelado" de outra tentativa chegando junto com o "pago" tardio → o pago nunca se perde', async () => {
  for (let i = 0; i < 10; i++) {
    const t = setup();
    try {
      const c = await t.create('ana', 'founder', 'card');
      await t.pay.handle(t.ws('ana'), { type: 'payment_cancel', charge_id: c.id });
      // banco com latência (como o Supabase): cada operação espera um pouco
      for (const k of ['getPayment', 'reopenPayment', 'cancelPayment', 'payAndGrant']) {
        const f = t.store[k].bind(t.store); t.store[k] = async (...a) => { await tick(1 + (i % 3)); return f(...a); };
      }
      t.mp.provider.payCard({ ref: c.id, token: 'pg', amountCents: 4990 }); await tick(2);
      const paidEv = await t.mp.provider.findByRef(c.id);
      const cancelledEv = { providerRef: c.id, status: 'cancelled', amountCents: 4990, currency: 'BRL', providerPaymentId: '1', detail: 'by_collector' };
      const jobs = [() => t.pay.apply(paidEv), async () => { await tick(i % 4); return t.pay.apply(cancelledEv); }];
      if (i % 2) jobs.reverse();
      await Promise.all(jobs.map(j => j()));
      const row = t.rows('ana')[0];
      assert.equal(t.rows('ana')[0].status, 'paid', 'rodada ' + i);
      assert.equal(await founders(t.store), 1);
    } finally { t.restore(); }
  }
});
