'use strict';
// R121 · APOIE UM CRIADOR: código válido liga a conta por 30 dias e dá o presente uma vez; compra paga gera 10% de
// comissão (uma vez por pedido); depois de 30 dias não gera; reembolso cancela a comissão; link na conta nova;
// Admin lista, cadastra e marca como paga.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { clean } = require('../../online_v021/social/creators');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); await new Promise(r => setImmediate(r)); };

async function fixture(t) {
  const messages = [];
  const origLog = console.log; console.log = () => {};
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop(); backend.tournaments.stop();
  t.after(() => backend.party.stop());
  let now = Date.parse('2026-10-15T15:00:00Z');
  for (const x of [backend.creators, backend.crowns, backend.seasonPass]) x.now = () => now;
  const login = async id => { const ws = { readyState: 1 }; await backend.handle(ws, { type: 'acct_auth', access_token: 'tok-' + id }); await flush(); return ws; };
  const of = (ws, type) => messages.filter(m => m.socket === ws && m.type === type);
  await backend.store.upsertCreator({ code: 'XADREZDOJOAO', name: 'João Xadrez', pct: 10, gift_crowns: 200, contact: '@joao', active: true });
  return { backend, C: backend.creators, st: backend.store, login, of, setNow: v => { now = v; } };
}

test('código: limpa espaços/minúsculas; inválido ou inativo recusa', async t => {
  assert.equal(clean(' xadrez do joao '), 'XADREZDOJOAO');
  assert.equal(clean('ab'), '');
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaApoia', 'warrior');
  const a = await h.login(A);
  await h.backend.handle(a, { type: 'creator_set', code: 'NAOEXISTE' }); await flush();
  assert.equal(h.of(a, 'creator_error').pop().code, 'not_found');
  await h.st.upsertCreator({ code: 'PAUSADO', name: 'Pausado', active: false });
  await h.backend.handle(a, { type: 'creator_set', code: 'pausado' }); await flush();
  assert.equal(h.of(a, 'creator_error').pop().code, 'not_found');
});

test('apoiar: liga por 30 dias, presente uma vez só; trocar e renovar', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaApoia', 'warrior');
  const a = await h.login(A);
  const before = (await h.st.crownWallet(A)).balance;
  await h.backend.handle(a, { type: 'creator_set', code: 'xadrezdojoao' }); await flush();
  const s = h.of(a, 'creator_state').pop();
  assert.equal(s.linked.code, 'XADREZDOJOAO'); assert.equal(s.gift, 200); assert.equal(s.just_linked, 'João Xadrez');
  assert.equal((await h.st.crownWallet(A)).balance, before + 200);
  await h.st.upsertCreator({ code: 'MARIAGM', name: 'Maria GM', pct: 15, gift_crowns: 300, active: true });
  await h.backend.handle(a, { type: 'creator_set', code: 'MARIAGM' }); await flush();
  assert.equal(h.of(a, 'creator_state').pop().linked.code, 'MARIAGM', 'troca na hora');
  assert.equal((await h.st.crownWallet(A)).balance, before + 200, 'presente só na primeira vez da conta');
});

test('compra: 10% para o criador, uma vez por pedido; vencido não gera; reembolso cancela', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaApoia', 'warrior');
  await h.C.link(A, 'XADREZDOJOAO');
  const r1 = await h.C.onPurchase({ ref: 'mp-1', user_id: A, product_id: 'founder', amount_cents: 4490 });
  assert.equal(r1.commission_cents, 449);
  assert.equal(await h.C.onPurchase({ ref: 'mp-1', user_id: A, product_id: 'founder', amount_cents: 4490 }), null, 'mesmo pedido não conta duas vezes');
  await h.C.onRefund('mp-1');
  assert.equal((await h.st.listCreatorSales('XADREZDOJOAO'))[0].status, 'cancelled');
  h.setNow(Date.parse('2026-11-20T15:00:00Z'));   // passou de 30 dias
  assert.equal(await h.C.onPurchase({ ref: 'mp-2', user_id: A, product_id: 'club_monthly', amount_cents: 1790 }), null);
  assert.equal(await h.C.onPurchase({ ref: 'mp-3', user_id: B, product_id: 'club_monthly', amount_cents: 1790 }), null, 'quem não apoia ninguém');
});

test('conta nova pelo link ?criador= já apoia; Admin lista, cadastra e paga', async t => {
  const h = await fixture(t);
  const b = await h.login(B);
  await h.backend.handle(b, { type: 'acct_create_profile', nickname: 'BiaNova', creator: 'XadrezDoJoao' }); await flush();
  assert.equal((await h.st.getCreatorLink(B)).code, 'XADREZDOJOAO');
  await h.C.onPurchase({ ref: 'mp-9', user_id: B, product_id: 'club_yearly', amount_cents: 13490 });
  const admin = h.backend.admin || null;
  const AdminService = require('../../online_v021/admin/service');
  const svc = Object.create((AdminService.AdminService || AdminService).prototype);
  svc.backend = h.backend; svc.now = () => Date.parse('2026-10-15T15:00:00Z');
  const recorded = []; svc.audit = { record: x => recorded.push(x) };
  const d = await svc.creatorsList();
  const j = d.items.find(c => c.code === 'XADREZDOJOAO');
  assert.equal(j.players, 1); assert.equal(j.sales, 1); assert.equal(j.due_cents, 1349);
  let res; const out = (s, body) => { res = { s, body }; };
  await svc.creatorSave({ id: 'adm' }, { code: 'novo gm', name: 'x', pct: 10, gift_crowns: 100 }, out);
  assert.equal(res.body.error, 'invalid_code');
  await svc.creatorSave({ id: 'adm' }, { code: 'NOVOGM', name: 'Novo GM', pct: 12, gift_crowns: 100, reason: 'parceria' }, out);
  assert.equal(res.body.creator.pct, 12);
  await svc.creatorPay({ id: 'adm' }, 'XADREZDOJOAO', { reason: 'PIX feito' }, out);
  assert.equal(res.body.paid, 1); assert.equal(res.body.commission_cents, 1349);
  assert.equal((await svc.creatorsList()).items.find(c => c.code === 'XADREZDOJOAO').due_cents, 0);
  assert.deepEqual(recorded.map(r => r.action), ['creator_create', 'creator_pay']);
});
