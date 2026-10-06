'use strict';
// FRAIHA Admin · RITMOS DO RANKED (Relâmpago 3 / Rápida 5 / Normal 10 / Convencional 20) controlados pelo Admin.
// O servidor é a fonte de verdade: ritmo fechado = entrada recusada, quem esperava sai da fila, partidas
// continuam, e TODAS as contas conectadas recebem a lista de ritmos abertos (acct_state + 'ranked_modes').
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { AdminService } = require('../../online_v021/admin/service');
const { ModeControls } = require('../../online_v021/admin/controls');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const C = '33333333-3333-4333-a333-333333333333';
const BOSS = '44444444-4444-4444-a444-444444444444';
const VIEW = '55555555-5555-4555-a555-555555555555';
const user = id => ({ id, email: 'local@dev.invalid', provider: 'dev' });
const flush = async () => { for (let i = 0; i < 50; i++) await Promise.resolve(); };

async function fixture(t, adminEnv = { FRAIHA_ADMIN_USERS: `${BOSS}=owner,${VIEW}=viewer`, FRAIHA_ENV: 'dev' }) {
  const messages = [], logs = [];
  const sockets = [A, B, C].map(() => ({ readyState: 1 }));
  const origLog = console.log; console.log = (...a) => logs.push(a.join(' '));
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  // Tokens de teste: "tok-<uuid>" → usuário; qualquer outra coisa → inválido.
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? user(m[1]) : null; } };
  backend.attachRanked(new Ranked({ send: backend.send }));
  backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual' }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  for (const [i, id] of [A, B, C].entries()) {
    await backend.store.createProfile(id, ['AliceTest', 'BobTest', 'CarolTest'][i], 'warrior');
    await backend.handle(sockets[i], { type: 'acct_auth', access_token: 'tok-' + id });
  }
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  const admin = new AdminService({ backend, env: adminEnv, autostart: false });
  const server = http.createServer((req, res) => admin.owns(req) ? admin.handle(req, res) : (res.writeHead(404), res.end()));
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.close(); for (const s of sockets) backend.onClose(s); backend.party.stop(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, { token, body, origin, raw } = {}) => {
    const headers = {};
    if (token) headers.Authorization = 'Bearer ' + token;
    if (origin) headers.Origin = origin;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const res = await fetch(base + path, { method, headers, body: raw !== undefined ? raw : body !== undefined ? JSON.stringify(body) : undefined });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
  };
  const entry = id => ({ userId: id, nickname: id === A ? 'AliceTest' : id === B ? 'BobTest' : 'CarolTest', avatar: 'warrior', stats: { league: 0, pl: 0 } });
  return { backend, admin, sockets, messages, logs, call, entry, boss: 'tok-' + BOSS, viewer: 'tok-' + VIEW, alice: 'tok-' + A };
}


const ALL = ['ranked_3min', 'ranked_5min', 'ranked_10min', 'ranked_20min'];
const setMode = (h, mode, enabled, token = h.boss, extra = {}) => h.call('POST', '/admin/api/queues/ranked/' + mode, { token, body: { enabled, reason: 'liquidez de teste', confirm: mode, ...extra } });
const lastModes = (h, sock) => { const m = h.messages.filter(x => x.socket === sock && (x.type === 'ranked_modes' || x.type === 'acct_state')).at(-1); return m && (m.type === 'ranked_modes' ? m.modes : m.ranked_modes); };

test('padrão: 4 ritmos abertos; acct_state informa a lista ao jogo', async t => {
  const h = await fixture(t);
  assert.deepEqual(lastModes(h, h.sockets[0]), ALL);
  const q = await h.call('GET', '/admin/api/queues', { token: h.boss });
  const rk = q.body.queues.find(x => x.family === 'ranked');
  assert.deepEqual(rk.modes.map(m => [m.mode, m.enabled, m.open]), ALL.map(m => [m, true, true]));
  assert.deepEqual(rk.modes.map(m => m.label), ['RELÂMPAGO', 'RÁPIDA', 'NORMAL', 'CONVENCIONAL']);
});

test('desligar RELÂMPAGO: some para todos na hora, entrada recusada, quem esperava sai, outro ritmo segue, partida continua; religar volta', async t => {
  const h = await fixture(t);
  const m = h.backend.ranked.startMatch('ranked_3min', h.entry(A), h.entry(B), Date.now() - 30000);
  h.backend.ranked.tick(); await flush();
  await h.backend.handle(h.sockets[2], { type: 'ranked_queue', mode: 'ranked_3min' }); await flush();
  assert.ok(h.backend.ranked.mm.has(C));
  h.messages.length = 0;
  const r = await setMode(h, 'ranked_3min', false);
  assert.equal(r.status, 200); assert.equal(r.body.changed, true); assert.deepEqual(r.body.open_modes, ['ranked_5min', 'ranked_10min', 'ranked_20min']);
  for (const s of h.sockets) assert.deepEqual(lastModes(h, s), ['ranked_5min', 'ranked_10min', 'ranked_20min'], 'todas as contas conectadas recebem a lista nova');
  assert.ok(!h.backend.ranked.mm.has(C), 'quem esperava no Relâmpago saiu da fila');
  assert.equal(h.messages.find(x => x.socket === h.sockets[2] && x.type === 'ranked_error').code, 'mode_disabled');
  h.messages.length = 0;
  await h.backend.handle(h.sockets[2], { type: 'ranked_queue', mode: 'ranked_3min' }); await flush();
  assert.ok(!h.backend.ranked.mm.has(C)); assert.equal(h.messages.find(x => x.socket === h.sockets[2]).code, 'mode_disabled', 'entrada no ritmo fechado recusada pelo servidor');
  await h.backend.handle(h.sockets[2], { type: 'ranked_queue', mode: 'ranked_5min' }); await flush();
  assert.ok(h.backend.ranked.mm.has(C), 'outro ritmo continua aberto');
  // partida de Relâmpago já iniciada continua
  const white = m.players.w.userId === A ? 0 : 1, rev = m.revision;
  await h.backend.handle(h.sockets[white], { type: 'ranked_move', match_id: m.id, from: [4, 6], to: [4, 4] }); await flush();
  assert.ok(m.revision > rev); assert.equal(m.status, 'playing', 'partida em andamento continua');
  // novo acct_state (próxima leitura normal) também já vem sem o ritmo
  await h.backend.handle(h.sockets[0], { type: 'acct_refresh' }); await flush();
  assert.deepEqual(h.messages.filter(x => x.socket === h.sockets[0] && x.type === 'acct_state').at(-1).ranked_modes, ['ranked_5min', 'ranked_10min', 'ranked_20min']);
  // religar
  h.backend.ranked.mm.cancel(C);
  const on = await setMode(h, 'ranked_3min', true);
  assert.equal(on.body.changed, true); assert.deepEqual(lastModes(h, h.sockets[1]), ALL, 'reaparece para todos sem nova build');
  await h.backend.handle(h.sockets[2], { type: 'ranked_queue', mode: 'ranked_3min' }); await flush();
  assert.ok(h.backend.ranked.mm.has(C), 'reaberto: volta a aceitar entrada');
  const log = (await h.call('GET', '/admin/api/audit', { token: h.boss })).body.items;
  assert.equal(log[1].action, 'queue.mode_disable'); assert.deepEqual(log[1].target, { family: 'ranked', mode: 'ranked_3min' }); assert.equal(log[1].meta.removed_from_queue, 1);
  assert.equal(log[0].action, 'queue.mode_enable'); assert.equal(log[0].reason, 'liquidez de teste');
});

test('liquidez: Relâmpago OFF, Rápida ON, Normal ON, Convencional OFF → o jogo recebe só RÁPIDA e NORMAL; sem pareamento em ritmo fechado', async t => {
  const h = await fixture(t);
  await setMode(h, 'ranked_3min', false); await setMode(h, 'ranked_20min', false);
  assert.deepEqual(lastModes(h, h.sockets[0]), ['ranked_5min', 'ranked_10min']);
  // tentativa de forçar pareamento num ritmo fechado (entrada já na fila por fora) não inicia partida
  h.backend.ranked.mm.enqueue('ranked_20min', { ...h.entry(A), since: Date.now() - 60e3 });
  h.backend.ranked.mm.enqueue('ranked_20min', { ...h.entry(B), since: Date.now() - 60e3 });
  h.backend.ranked.tick(); await flush();
  assert.equal([...h.backend.ranked.matches.values()].length, 0, 'nenhuma partida em ritmo fechado');
});

test('todos os ritmos OFF → lista vazia (jogo mostra "temporariamente indisponível"); família Ranked OFF também esvazia', async t => {
  const h = await fixture(t);
  for (const m of ALL) await setMode(h, m, false);
  assert.deepEqual(lastModes(h, h.sockets[0]), []);
  await h.backend.handle(h.sockets[2], { type: 'ranked_queue', mode: 'ranked_10min' }); await flush();
  assert.ok(!h.backend.ranked.mm.has(C));
  for (const m of ALL) await setMode(h, m, true);
  assert.deepEqual(lastModes(h, h.sockets[0]), ALL);
  await h.call('POST', '/admin/api/queues/ranked', { token: h.boss, body: { enabled: false, reason: 'manutenção', confirm: 'ranked' } });
  assert.deepEqual(lastModes(h, h.sockets[0]), [], 'Ranked inteiro desligado = nenhum ritmo');
  await h.call('POST', '/admin/api/queues/ranked', { token: h.boss, body: { enabled: true, reason: 'volta', confirm: 'ranked' } });
  assert.deepEqual(lastModes(h, h.sockets[0]), ALL);
});

test('segurança: viewer/comum não mudam; confirmação, motivo, ritmo e campos validados; noop registrado', async t => {
  const h = await fixture(t);
  assert.equal((await setMode(h, 'ranked_3min', false, h.viewer)).status, 403);
  assert.equal((await setMode(h, 'ranked_3min', false, h.alice)).status, 403);
  assert.equal((await setMode(h, 'ranked_3min', false, h.boss, { confirm: 'ranked_5min' })).status, 400);
  assert.equal((await setMode(h, 'ranked_3min', false, h.boss, { reason: ' ' })).status, 400);
  assert.equal((await setMode(h, 'ranked_3min', 'false')).status, 400);
  assert.equal((await setMode(h, 'ranked_3min', false, h.boss, { open_modes: [] })).status, 400, 'campo extra recusado');
  assert.equal((await setMode(h, 'ranked_1min', false, h.boss, { confirm: 'ranked_1min' })).status, 404);
  assert.equal((await setMode(h, 'casual_3min', false, h.boss, { confirm: 'casual_3min' })).status, 404);
  assert.deepEqual(lastModes(h, h.sockets[0]), ALL, 'nada mudou');
  const n = await setMode(h, 'ranked_5min', true);
  assert.equal(n.status, 200); assert.equal(n.body.changed, false);
  assert.equal((await h.call('GET', '/admin/api/audit', { token: h.boss })).body.items[0].result, 'noop');
});

test('padrão ao subir: FRAIHA_RANKED_MODES_OPEN define os ritmos abertos (reinício volta a ele)', () => {
  const c = new ModeControls({ env: { FRAIHA_RANKED_MODES_OPEN: 'ranked_5min, ranked_10min,lixo' } });
  assert.deepEqual(c.openRankedModes(), ['ranked_5min', 'ranked_10min']);
  assert.deepEqual(new ModeControls({ env: {} }).openRankedModes(), ALL);
  assert.deepEqual(new ModeControls({ env: { FRAIHA_RANKED_MODES_OPEN: '' } }).openRankedModes(), ALL);
  assert.deepEqual(new ModeControls({ env: { FRAIHA_RANKED_MODES_OPEN: 'nenhum' } }).openRankedModes(), [], 'valor só com ritmos inválidos = nenhum aberto (fail-closed)');
});
