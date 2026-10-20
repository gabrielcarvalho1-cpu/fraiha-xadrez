'use strict';
// R171 · Invariantes de sessão COM as Coroas ligadas (pedido do dono após o reteste do Orca).
// Os 13 testes históricos contam mensagens; aqui a checagem é por DONO: depois que A sai (ou B entra no mesmo
// aparelho), nenhuma mensagem com dado de A chega ao socket — saldo/aviso de Coroas, perfil, vantagens, id.
// A conta A tem marcas inconfundíveis: apelido "AliceMarcada", saldo de Coroas >= 7000, Fundador nº 77.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const user = id => ({ id, email: id.slice(0, 4) + '@dev.local', provider: 'dev' });
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const flush = async () => { for (let i = 0; i < 200; i++) await Promise.resolve(); await new Promise(r => setImmediate(r)); };

async function fixture(t) {
  let now = 1_800_000_000_000;
  const messages = [], ws = { readyState: 1 };
  const origLog = console.log; console.log = () => {}; t.after(() => { console.log = origLog; });
  const be = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, now: () => now, send: (socket, m) => messages.push({ socket, at_user: socket.user ? socket.user.id : null, ...m }) });
  clearInterval(be.sweeper); be.presence.stop(); be.invites.stop();
  t.after(() => { be.onClose(ws); be.party.stop(); });
  be.auth = { verify: async tok => tok === 'A' ? user(A) : tok === 'B' ? user(B) : null };
  await be.store.createProfile(A, 'AliceMarcada', 'warrior');
  await be.store.createProfile(B, 'BobLimpo', 'mage');
  await be.store.crownAward(A, 7000, 'admin', 'marca');
  await be.store.setEntitlements(A, { is_founder: true, founder_number: 77, founder_tier: 'founder' });
  const login = tok => be.handle(ws, { type: 'acct_auth', access_token: tok });
  return { be, ws, messages, login, advance: ms => { now += ms; } };
}
// Mensagem com dado da conta A?
function hasA(m) {
  const s = JSON.stringify({ ...m, socket: undefined });
  return s.includes(A) || s.includes('AliceMarcada') || (typeof m.balance === 'number' && m.balance >= 7000) || s.includes('"founder_number":77');
}
function assertNoAAfter(messages, cut, label) {
  const bad = messages.slice(cut).filter(m => m.socket && hasA(m) && m.type !== 'acct_logged_out');
  assert.equal(bad.length, 0, label + ': ' + JSON.stringify(bad.map(m => [m.type, m.balance, m.nickname])));
}

for (const slowAt of ['crownCheckin', 'crownWallet']) test(`A → logout → B (mesmo aparelho) com o banco das Coroas de A lento em ${slowAt}: B nunca recebe nada de A`, async t => {
  // crownCheckin = antes de decidir o prêmio; crownWallet = DEPOIS de o aviso já ter escolhido os aparelhos (a janela
  // do vazamento real da R112–R170)
  const h = await fixture(t);
  const gate = deferred(), orig = h.be.store[slowAt].bind(h.be.store);
  let armed = true;
  h.be.store[slowAt] = async (uid, ...r) => { if (uid === A && armed) { armed = false; await gate.promise; } return orig(uid, ...r); };
  const loginA = h.login('A'); await flush();
  await h.be.handle(h.ws, { type: 'acct_logout' });
  const cut = h.messages.length;
  await h.login('B');
  gate.resolve(); await loginA; await flush();
  assert.equal(h.ws.user.id, B);
  assertNoAAfter(h.messages, cut, 'nada de A depois do logout');
  const mineB = h.messages.slice(cut).filter(m => m.type && m.type.startsWith('crowns_'));
  assert.ok(mineB.length >= 1 && mineB.every(m => m.at_user === B), 'B recebe as SUAS Coroas (entrada do dia), não some nada de B');
});

test('login lento de A seguido de B: só B fica, nenhum dado de A chega (Coroas incluídas)', async t => {
  const h = await fixture(t);
  const slow = deferred(), verify = h.be.auth.verify;
  h.be.auth.verify = tok => tok === 'A' ? slow.promise : verify(tok);
  const a = h.login('A'); await flush();
  await h.login('B');
  slow.resolve(user(A)); await a; await flush();
  assert.equal(h.ws.user.id, B); assert.equal(h.ws.identity.id, B);
  assertNoAAfter(h.messages, 0, 'em nenhum momento');
  assert.equal(h.be.online.has(A), false);
});

test('revalidação antiga de A (que até volta VÁLIDA) depois de B entrar não afeta B nem entrega nada de A', async t => {
  const h = await fixture(t);
  await h.login('A');
  const slow = deferred(), verify = h.be.auth.verify;
  h.be.auth.verify = (tok, o) => tok === 'A' ? slow.promise : verify(tok, o);
  h.advance(61_000);
  const ens = h.be.ensureSession(h.ws);   // revalidação de rotina de A em andamento
  await flush();
  await h.be.handle(h.ws, { type: 'acct_logout' });
  const cut = h.messages.length;
  await h.login('B');
  slow.resolve(user(A)); await ens; await flush();
  assert.equal(h.ws.user.id, B); assert.equal(h.ws.identity.id, B);
  assertNoAAfter(h.messages, cut, 'revalidação velha de A');
});

test('mensagens adiadas (Coroas de A produzidas durante a revalidação) só saem para A; trocou para B → descartadas', async t => {
  for (const outcome of ['confirma A', 'troca para B']) {
    const h = await fixture(t);
    await h.login('A');
    const typ = 'crowns_get';
    // operação de A começa ANTES da revalidação e só responde DEPOIS que ela começou (banco lento)
    const gate = deferred(), origW = h.be.store.crownWallet.bind(h.be.store);
    h.be.store.crownWallet = async uid => { await gate.promise; return origW(uid); };
    const op = h.be.handle(h.ws, { type: typ }); await flush();
    const slow = deferred(), verify = h.be.auth.verify;
    h.be.auth.verify = (tok, o) => (tok === 'A' && o && o.force) ? slow.promise : verify(tok, o);
    h.advance(61_000);
    const ens = h.be.ensureSession(h.ws); await flush();
    const cut = h.messages.length;
    gate.resolve(); await flush();
    assert.equal(h.messages.length, cut, outcome + ': resposta de A segura enquanto a sessão não é confirmada');
    if (outcome === 'confirma A') {
      slow.resolve(user(A)); await ens; await op; await flush();
      const got = h.messages.slice(cut);
      assert.ok(got.some(m => m.type === 'crowns_state' && m.balance >= 7000) && got.every(m => m.at_user === A), 'confirmada: entregue para A');
    } else {
      await h.be.handle(h.ws, { type: 'acct_logout' });
      const cut2 = h.messages.length;
      await h.login('B');
      slow.resolve(user(A)); await ens; await op; await flush();
      assert.equal(h.ws.user.id, B);
      assertNoAAfter(h.messages, cut2, 'resposta adiada de A não chega a B');
      assert.ok(!h.messages.slice(cut).some(m => m.type === 'crowns_state' && m.balance >= 7000), 'a resposta de A foi descartada');
    }
  }
});

test('A e B em aparelhos diferentes: cada um recebe só as suas Coroas', async t => {
  const h = await fixture(t);
  const wsB = { readyState: 1 };
  await h.login('A');
  await h.be.handle(wsB, { type: 'acct_auth', access_token: 'B' });
  const cut = h.messages.length;
  await h.be.crowns.notify(A, 10, ['x']); await h.be.crowns.notify(B, 10, ['y']); await flush();
  const out = h.messages.slice(cut);
  assert.ok(out.filter(m => m.socket === wsB).every(m => !hasA(m)), 'aparelho de B sem dado de A');
  assert.ok(out.filter(m => m.socket === h.ws && m.type === 'crowns_state').every(m => m.balance >= 7000), 'aparelho de A recebe o saldo de A');
  h.be.onClose(wsB);
});
