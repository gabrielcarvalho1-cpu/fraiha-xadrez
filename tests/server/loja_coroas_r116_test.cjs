'use strict';
// R116 · LOJA DE COROAS: catálogo e preços do servidor, compra atômica (saldo, posse única), título comprado pode ser
// usado (acct_set_cosmetics) e quem não comprou não pode; outros jogadores veem o título; catálogo igual no cliente.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs'), path = require('path');
const { Backend } = require('../../online_v021/backend');
const { ITEMS, BY_ID } = require('../../online_v021/economy/store_catalog');
const Cosmetics = require('../../online_v021/accounts/cosmetics');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); await new Promise(r => setImmediate(r)); };

async function fixture(t) {
  const messages = [];
  const origLog = console.log; console.log = () => {};
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  t.after(() => backend.party.stop());
  const login = async id => { const ws = { readyState: 1 }; await backend.handle(ws, { type: 'acct_auth', access_token: 'tok-' + id }); await flush(); return ws; };
  const of = (ws, type) => messages.filter(m => m.socket === ws && m.type === type);
  return { backend, login, of, st: backend.store };
}

test('catálogo: 10 títulos com preço, ids únicos, igual ao do cliente', () => {
  assert.equal(ITEMS.filter(i => i.kind === 'title').length, 10);
  assert.equal(new Set(ITEMS.map(i => i.id)).size, ITEMS.length);
  for (const i of ITEMS) { assert.ok(i.price > 0 && i.price <= 100000); assert.match(i.id, /^[a-z0-9_]{1,40}$/); }
  const gd = fs.readFileSync(path.join(__dirname, '../../economy/crown_store_catalog.gd'), 'utf8');
  for (const i of ITEMS) {
    assert.ok(gd.includes(`"id": "${i.id}"`), 'cliente sem ' + i.id);
    assert.ok(gd.includes(`"name": "${i.name}"`), 'nome diferente no cliente: ' + i.id);
    assert.ok(new RegExp(`"id": "${i.id}"[^}]*"price": ${i.price}\\b`).test(gd), 'preço diferente no cliente: ' + i.id);
  }
});

test('compra: sem saldo recusa; com saldo desconta e registra; segunda compra recusa; preço vem do servidor', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaLoja', 'warrior');
  const a = await h.login(A);   // entrada do dia: +10
  await h.backend.handle(a, { type: 'store_get' }); await flush();
  const s0 = h.of(a, 'store_state').pop();
  assert.equal(s0.available, true); assert.deepEqual(s0.owned, []); assert.equal(s0.items.length, ITEMS.length);
  await h.backend.handle(a, { type: 'store_buy', item: 'estrategista', price: 1 }); await flush();
  assert.equal(h.of(a, 'store_error').pop().code, 'saldo_insuficiente', 'o preço do cliente é ignorado');
  await h.st.crownAward(A, 1000, 'game', 'teste');
  await h.backend.handle(a, { type: 'store_buy', item: 'estrategista' }); await flush();
  const ok = h.of(a, 'store_bought').pop();
  assert.equal(ok.item, 'estrategista'); assert.equal(ok.balance, 10 + 1000 - 300);
  assert.deepEqual(h.of(a, 'store_state').pop().owned, ['estrategista']);
  await h.backend.handle(a, { type: 'store_buy', item: 'estrategista' }); await flush();
  assert.equal(h.of(a, 'store_error').pop().code, 'ja_tem');
  await h.backend.handle(a, { type: 'store_buy', item: 'nao_existe' }); await flush();
  assert.equal(h.of(a, 'store_error').pop().code, 'item_desconhecido');
  assert.equal((await h.st.crownWallet(A)).balance, 710);
  const led = await h.st.crownLedger(A, 5);
  assert.equal(led[0].delta, -300); assert.equal(led[0].reason, 'buy');
});

test('título comprado pode ser usado; sem comprar, não; outros veem; Lendário segue exigindo o pacote', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaLoja', 'warrior');
  await h.st.createProfile(B, 'BiaSemLoja', 'warrior');
  const a = await h.login(A), b = await h.login(B);
  await h.st.crownAward(A, 2000, 'game', 'teste');
  await h.backend.handle(a, { type: 'store_buy', item: 'imperador' }); await flush();
  await h.backend.handle(a, { type: 'acct_set_cosmetics', title: 'imperador' }); await flush();
  assert.equal(h.of(a, 'acct_cosmetics_saved').pop().title, 'imperador');
  await h.backend.handle(b, { type: 'acct_set_cosmetics', title: 'imperador' }); await flush();
  const err = h.of(b, 'acct_cosmetics_error').pop();
  assert.equal(err.code, 'cosmetic_locked'); assert.match(err.message, /Loja de Coroas/);
  assert.equal(Cosmetics.look({ title: 'imperador' }).title, 'imperador', 'outros jogadores veem o título');
  assert.equal(Cosmetics.validate({ title: 'lendario' }, { is_founder: true, founder_tier: 'founder' }, null, []).code, 'cosmetic_locked');
});

test('sem a 0017: loja indisponível, sem derrubar nada', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaLoja', 'warrior');
  const err = () => { const e = new Error('Could not find the function public.fraiha_crown_buy'); e.code = 'PGRST202'; throw e; };
  h.st.crownBuy = err; h.st.crownItems = err;
  const a = await h.login(A);
  await h.backend.handle(a, { type: 'store_get' }); await flush();
  assert.equal(h.of(a, 'store_state').pop().available, false);
  await h.backend.handle(a, { type: 'store_buy', item: 'estrategista' }); await flush();
  assert.equal(h.of(a, 'store_error').pop().code, 'indisponivel');
  await h.backend.handle(a, { type: 'acct_set_cosmetics', title: 'club' }); await flush();
  assert.equal(h.of(a, 'acct_cosmetics_error').pop().code, 'cosmetic_locked', 'cosméticos continuam funcionando');
});
