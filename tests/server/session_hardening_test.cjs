'use strict';
// node --test tests/server/session_hardening_test.cjs
// FRAIHA_SESSION_TEST_BASE=1 executa os mesmos casos contra HEAD, só em memória.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const Module = require('node:module');
const { execFileSync } = require('node:child_process');
function load(file) {
  const absolute = path.resolve(__dirname, '../..', file);
  if (!process.env.FRAIHA_SESSION_TEST_BASE) return require(absolute);
  const mod = new Module(absolute, module);
  mod.filename = absolute; mod.paths = Module._nodeModulePaths(path.dirname(absolute));
  mod._compile(execFileSync('git', ['show', 'HEAD:' + file], { cwd: path.resolve(__dirname, '../..'), encoding: 'utf8' }), absolute);
  return mod.exports;
}
const { Backend } = load('online_v021/backend.js');
const { SupabaseAuth } = load('online_v021/accounts/auth.js');
const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const user = id => ({ id, email: id + '@dev.local', provider: 'dev' });
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); };
class Clock {
  time = 1700000000000;
  timers = new Map();
  now = () => this.time;
  set = (fn, ms) => { const t = { fn, at: this.time + ms, unref() {} }; this.timers.set(t, t); return t; };
  clear = t => this.timers.delete(t);
  async advance(ms) {
    const end = this.time + ms;
    for (;;) {
      const next = [...this.timers.values()].filter(t => t.at <= end).sort((a, b) => a.at - b.at)[0];
      if (!next) break;
      this.time = next.at; this.timers.delete(next); next.fn(); await flush();
    }
    this.time = end; await flush();
  }
}
async function fixture(t) {
  const clock = new Clock(), messages = [], ws = { readyState: 1 }, calls = [];
  const be = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, m) => messages.push({ socket, ...m }), now: clock.now, setTimer: clock.set, clearTimer: clock.clear });
  clearInterval(be.sweeper); be.presence.stop();
  be.presence.now = clock.now;
  be.auth = { verify: async (token, opts) => { calls.push({ token, opts }); return token === 'A' ? user(A) : token === 'B' ? user(B) : null; } };
  await be.store.createProfile(A, 'AliceTest', 'warrior');
  await be.store.createProfile(B, 'BobTest', 'mage');
  t.after(() => { be.onClose(ws); clock.timers.clear(); });
  return { be, ws, clock, messages, calls, login: token => be.handle(ws, { type: 'acct_auth', access_token: token }), act: type => be.handle(ws, { type }) };
}
function empty(h) {
  assert.equal(h.ws.user, null); assert.equal(h.ws.profile, null);
  assert.equal(h.ws.identity, null); assert.equal(h.ws.guest, null);
  assert.equal([...h.be.online.values()].some(set => set.has(h.ws)), false);
}
test('login A lento → B → A termina: somente B permanece e responde', async t => {
  const h = await fixture(t), slow = deferred(), original = h.be.auth.verify;
  h.be.auth.verify = (token, opts) => token === 'A' ? slow.promise : original(token, opts);
  const a = h.login('A'); await flush(); await h.login('B');
  const count = h.messages.length; slow.resolve(user(A)); await a;
  assert.equal(h.ws.user.id, B); assert.equal(h.ws.profile.user_id, B); assert.equal(h.ws.identity.id, B);
  assert.equal(h.be.online.has(A), false); assert.equal(h.messages.length, count);
});
for (const exit of ['logout', 'close']) {
  test(`login lento → ${exit}: conclusão não restaura usuário nem presença`, async t => {
    const h = await fixture(t), slow = deferred(); h.be.auth.verify = () => slow.promise;
    const login = h.login('A'); await flush();
    if (exit === 'logout') await h.act('acct_logout'); else h.be.onClose(h.ws);
    const count = h.messages.length; slow.resolve(user(A)); await login;
    empty(h); assert.equal(h.messages.length, count);
    if (exit === 'logout') assert.equal(h.messages.at(-1).type, 'acct_logged_out');
  });
}
test('auth inválido após válido limpa identidade, presença, filas e mesa', async t => {
  const h = await fixture(t); let queueCleanup = 0, partyCleanup = 0;
  await h.login('A');
  h.be.ranked = { onClose: ws => { assert.equal(ws.identity.id, A); queueCleanup++; } };
  h.be.party.onClose = ws => { assert.equal(ws.identity.id, A); partyCleanup++; };
  await h.login('invalid'); empty(h);
  assert.equal(queueCleanup, 1); assert.equal(partyCleanup, 1);
  assert.equal(h.messages.at(-1).code, 'invalid_token');
  assert.equal(h.be.presence.raw(A), 'offline');
  h.clock.time += h.be.presence.cfg.graceMs; h.be.presence.evaluate(A);
  assert.equal(h.be.presenceOf(A), 'offline');
});
test('login sem perfil não mantém identidade de convidado', async t => {
  const h = await fixture(t); await h.act('guest_auth');
  const guest = h.ws.identity.id;
  const id = '33333333-3333-4333-a333-333333333333'; h.be.auth.verify = async () => user(id);
  await h.login('new');
  assert.equal(h.ws.user.id, id); assert.equal(h.ws.profile, null); assert.equal(h.ws.identity, null); assert.equal(h.ws.guest, null);
  assert.equal(h.be.online.has(guest), false); assert.equal(h.messages.at(-1).needs_nickname, true);
});
test('guest_auth cancela login pendente', async t => {
  const h = await fixture(t), slow = deferred(); h.be.auth.verify = () => slow.promise;
  const a = h.login('A'); await flush(); await h.act('guest_auth');
  const guest = h.ws.identity.id, count = h.messages.length; slow.resolve(user(A)); await a;
  assert.equal(h.ws.user, null); assert.equal(h.ws.identity.id, guest); assert.equal(h.messages.length, count);
});
for (const step of ['getProfile', 'getRankedStats', 'getEntitlements', 'analysisUsage', 'bots']) {
  test(`state A suspenso em ${step} → login B: não mistura perfil/identidade`, async t => {
    const h = await fixture(t); await h.login('A');
    const slow = deferred(), owner = step === 'bots' ? h.be.bots : h.be.store, method = step === 'bots' ? 'summary' : step;
    const original = owner[method].bind(owner);
    owner[method] = (...args) => args[0] === A ? slow.promise : original(...args);
    const refresh = h.act('acct_refresh'); await flush(); await h.login('B');
    const count = h.messages.length; slow.resolve(await original(A)); await refresh;
    assert.equal(h.ws.user.id, B); assert.equal(h.ws.identity.id, B); assert.equal(h.ws.profile.user_id, B); assert.equal(h.messages.length, count);
  });
}
for (const exit of ['logout', 'close', 'reauth']) {
  test(`state antigo → ${exit} cancela resposta e não revive identidade`, async t => {
    const h = await fixture(t); await h.login('A');
    const slow = deferred(), get = h.be.store.getProfile.bind(h.be.store); let first = true;
    h.be.store.getProfile = id => first ? (first = false, slow.promise) : get(id);
    const refresh = h.act('acct_refresh'); await flush();
    if (exit === 'logout') await h.act('acct_logout');
    if (exit === 'close') h.be.onClose(h.ws);
    if (exit === 'reauth') await h.login('A');
    const count = h.messages.length; slow.resolve({ ...(await get(A)), nickname: 'OldStaleName' }); await refresh;
    assert.equal(h.messages.length, count);
    if (exit === 'reauth') assert.equal(h.ws.identity.nickname, 'AliceTest'); else empty(h);
  });
}
test('dois refresh da mesma sessão: resposta antiga não sobrescreve nova', async t => {
  const h = await fixture(t); await h.login('A');
  const slow = deferred(), get = h.be.store.getProfile.bind(h.be.store); let first = true;
  h.be.store.getProfile = id => first ? (first = false, slow.promise) : get(id);
  const old = h.act('acct_refresh'); await flush(); await h.act('acct_refresh');
  const count = h.messages.length; slow.resolve({ ...(await get(A)), nickname: 'OldStaleName' }); await old;
  assert.equal(h.ws.identity.nickname, 'AliceTest'); assert.equal(h.messages.length, count);
});
test('snapshot de presença A atrasado não responde depois de login B', async t => {
  const h = await fixture(t), slow = deferred();
  h.be.presence.audience = id => id === A ? slow.promise : Promise.resolve([]);
  const a = h.login('A'); await flush(); await h.login('B');
  const count = h.messages.length; slow.resolve([A]); await a;
  assert.equal(h.messages.length, count); assert.equal(h.ws.identity.id, B);
});
test('account handler não usa B após await iniciado por A', async t => {
  const h = await fixture(t); await h.login('A'); const slow = deferred(), consumed = [];
  const original = h.be.store.getEntitlements.bind(h.be.store);
  h.be.store.getEntitlements = id => id === A ? slow.promise : original(id);
  h.be.store.analysisConsume = async id => { consumed.push(id); return { ok: true, used: 1 }; };
  const req = h.act('analysis_request'); await flush(); await h.login('B');
  const count = h.messages.length; slow.resolve({ club_active: false }); await req;
  assert.deepEqual(consumed, []); assert.equal(h.messages.length, count);
});
test('expiração remove sessão ociosa e presença sem nova mensagem', async t => {
  const h = await fixture(t); h.be.auth.verify = async () => ({ ...user(A), expires_at: h.clock.now() + 1000 });
  await h.login('A'); await h.clock.advance(1000); empty(h);
  assert.equal(h.messages.at(-1).code, 'invalid_token');
  await h.act('ranked_queue'); assert.equal(h.messages.at(-1).code, 'auth_required');
});
test('revalidação 60s detecta revogação e não consulta Auth a cada ação', async t => {
  const h = await fixture(t); await h.login('A');
  for (let i = 0; i < 5; i++) await h.act('acct_refresh');
  assert.equal(h.calls.length, 1);
  h.be.auth.verify = async (token, opts) => { h.calls.push({ token, opts }); return null; };
  await h.clock.advance(60000); empty(h);
  assert.equal(h.calls.length, 2); assert.equal(h.calls.at(-1).opts.force, true);
});
test('revalidação em voo é compartilhada e bloqueia ações até confirmação', async t => {
  const h = await fixture(t); await h.login('A'); const slow = deferred(); let verifies = 0;
  h.be.auth.verify = () => { verifies++; return slow.promise; };
  await h.clock.advance(60000); const count = h.messages.length;
  const one = h.act('acct_refresh'), two = h.act('acct_refresh'); await flush();
  assert.equal(verifies, 1); assert.equal(h.messages.length, count);
  slow.resolve(user(A)); await Promise.all([one, two]); assert.equal(h.ws.identity.id, A);
  await h.act('acct_refresh'); assert.equal(verifies, 1);
});
test('Auth travado invalida após timeout e conclusão tardia não restaura sessão', async t => {
  const h = await fixture(t); await h.login('A'); const slow = deferred(); h.be.auth.verify = () => slow.promise;
  await h.clock.advance(60000); await h.clock.advance(10000); empty(h);
  const count = h.messages.length; slow.resolve(user(A)); await flush(); empty(h); assert.equal(h.messages.length, count);
});
test('exp vence mesmo com revalidação pendente; fechamento cancela timer', async t => {
  const h = await fixture(t); h.be.auth.verify = async () => ({ ...user(A), expires_at: h.clock.now() + 65000 });
  await h.login('A'); const slow = deferred(); h.be.auth.verify = () => slow.promise;
  await h.clock.advance(60000); await h.clock.advance(5000); empty(h);
  slow.resolve(user(A)); await flush(); empty(h);
  h.be.onClose(h.ws); const count = h.messages.length; await h.clock.advance(60000); assert.equal(h.messages.length, count);
});
test('sessão sem exp tem limite de 1h mesmo após revalidações válidas', async t => {
  const h = await fixture(t); await h.login('A'); await h.clock.advance(3600000); empty(h);
  assert.equal(h.messages.at(-1).code, 'invalid_token');
});
test('normal: login, perfil, refresh, logout e novo login', async t => {
  const h = await fixture(t); await h.login('A');
  assert.equal(h.ws.identity.id, A); assert.equal(h.be.online.get(A).size, 1);
  await h.act('acct_refresh'); await h.act('acct_logout'); empty(h);
  await h.login('B'); assert.equal(h.ws.identity.id, B);
  assert.equal(h.messages.filter(m => m.type === 'acct_state').every(m => m.profile.user_id === m.user_id), true);
});
test('logout é idempotente mesmo sem usuário', async t => {
  const h = await fixture(t); await h.act('acct_logout'); await h.act('acct_logout');
  assert.deepEqual(h.messages.map(m => m.type), ['acct_logged_out', 'acct_logged_out']); empty(h);
});
test('state chamado diretamente cancela conclusão após logout sem rejeição', async t => {
  const h = await fixture(t); await h.login('A'); const slow = deferred(), get = h.be.store.getProfile.bind(h.be.store);
  h.be.store.getProfile = () => slow.promise;
  const refresh = h.be.state(h.ws); await flush(); await h.act('acct_logout');
  const count = h.messages.length; slow.resolve(await get(A));
  assert.equal(await refresh, false); empty(h); assert.equal(h.messages.length, count);
});
test('fila com sessão válida continua sendo processada sem await de Auth', async t => {
  const h = await fixture(t); await h.login('A'); let queued = false;
  h.be.ranked = { handle: () => { queued = true; }, onClose() {} };
  const action = h.act('ranked_status'); assert.equal(queued, true); await action;
  assert.equal(h.calls.length, 1);
});
test('login suspenso no perfil inicial → B: não executa callbacks de A', async t => {
  const h = await fixture(t), slow = deferred(), get = h.be.store.getProfile.bind(h.be.store), callbacks = [];
  h.be.store.getProfile = id => id === A ? slow.promise : get(id);
  h.be.party.onAuthenticated = ws => callbacks.push(ws.user.id);
  const a = h.login('A'); await flush(); await h.login('B');
  const count = h.messages.length; slow.resolve(await get(A)); await a;
  assert.deepEqual(callbacks, [B]); assert.equal(h.messages.length, count); assert.equal(h.ws.identity.id, B);
});
test('revalidação antiga após login B não invalida B', async t => {
  const h = await fixture(t); await h.login('A'); const slow = deferred(), verify = h.be.auth.verify;
  h.be.auth.verify = (token, opts) => token === 'A' ? slow.promise : verify(token, opts);
  await h.clock.advance(60000); await h.login('B');
  const count = h.messages.length; slow.resolve(null); await flush();
  assert.equal(h.ws.user.id, B); assert.equal(h.ws.identity.id, B); assert.equal(h.messages.length, count);
});
test('continuação iniciada antes do prazo aguarda revalidação e não consome após revogação', async t => {
  const h = await fixture(t); await h.login('A'); const ent = deferred(), auth = deferred(), consumed = [];
  h.be.store.getEntitlements = () => ent.promise;
  h.be.store.analysisConsume = async id => { consumed.push(id); return { ok: true }; };
  const request = h.act('analysis_request'); await flush();
  h.be.auth.verify = () => auth.promise; await h.clock.advance(60000);
  ent.resolve({ club_active: false }); await flush(); assert.deepEqual(consumed, []);
  auth.resolve(null); await request; empty(h); assert.deepEqual(consumed, []);
});
test('invalidar um socket preserva outro socket da mesma conta', async t => {
  const h = await fixture(t), other = { readyState: 1 }; t.after(() => h.be.onClose(other));
  await h.login('A'); await h.be.handle(other, { type: 'acct_auth', access_token: 'A' });
  await h.login('invalid'); empty(h); assert.equal(h.be.online.get(A).size, 1);
  assert.equal(h.be.presence.raw(A), 'online'); assert.equal(other.identity.id, A);
});
test('Supabase cache respeita exp e revalidação force ignora cache', async () => {
  const clock = new Clock(); let calls = 0, ok = true;
  const auth = new SupabaseAuth({ url: 'https://local.invalid', apiKey: 'test-public', now: clock.now, fetchImpl: async () => { calls++; return { ok, json: async () => ({ id: A }) }; } });
  const token = 'header.' + Buffer.from(JSON.stringify({ exp: (clock.now() + 1000) / 1000 })).toString('base64url') + '.signature';
  assert.equal((await auth.verify(token)).id, A); await auth.verify(token); assert.equal(calls, 1);
  ok = false; assert.equal(await auth.verify(token, { force: true }), null); assert.equal(calls, 2);
  ok = true; await auth.verify(token); clock.time += 1000;
  assert.equal(await auth.verify(token), null); assert.equal(calls, 3);
});
