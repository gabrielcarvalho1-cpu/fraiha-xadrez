'use strict';
// FRAIHA Admin · CASUAL com o mesmo controle do Ranked. Inspeção do código: o Casual tem 4 filas REAIS por ritmo
// (ranked/config.js CASUAL_MODES = casual_3/5/10/20min; matchmaker com uma fila por ritmo; o jogador escolhe o
// ritmo na tela JOGAR ONLINE). Ritmo/família OFF = entrada recusada no servidor, quem esperava sai da fila com
// aviso, partidas iniciadas continuam, TODOS os conectados (contas e convidados) recebem a lista de ritmos
// abertos (acct_state / guest_state / 'casual_modes') e a ação + motivo vão para o Admin Log.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { AdminService } = require('../../online_v021/admin/service');
const { ModeControls } = require('../../online_v021/admin/controls');
const { CASUAL_MODES } = require('../../online_v021/ranked/config');

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


const ALL = ['casual_3min', 'casual_5min', 'casual_10min', 'casual_20min'];
const setMode = (h, mode, enabled, token = h.boss, extra = {}) => h.call('POST', '/admin/api/queues/casual/' + mode, { token, body: { enabled, reason: 'liquidez casual', confirm: mode, ...extra } });
const setFamily = (h, enabled) => h.call('POST', '/admin/api/queues/casual', { token: h.boss, body: { enabled, reason: 'manutenção casual', confirm: 'casual' } });
const lastModes = (h, sock) => { const m = h.messages.filter(x => x.socket === sock && (x.type === 'casual_modes' || ((x.type === 'acct_state' || x.type === 'guest_state') && x.casual_modes))).at(-1); return m && (m.type === 'casual_modes' ? m.modes : m.casual_modes); };
async function guest(h) {
  const g = { readyState: 1 };
  await h.backend.handle(g, { type: 'guest_auth' }); await flush();
  return g;
}
const casualQ = h => h.call('GET', '/admin/api/queues', { token: h.boss }).then(r => r.body.queues.find(x => x.family === 'casual'));

test('inspeção: o Casual tem exatamente as 4 filas reais do servidor; Admin, acct_state e guest_state mostram as 4', async t => {
  const h = await fixture(t);
  assert.deepEqual(Object.keys(CASUAL_MODES), ALL, 'config do servidor');
  assert.deepEqual([...h.backend.casual.mm.queues.keys()].sort(), [...ALL].sort(), 'uma fila por ritmo no matchmaker');
  assert.deepEqual(ModeControls.modeIds('casual'), ALL);
  assert.deepEqual(lastModes(h, h.sockets[0]), ALL, 'acct_state informa ao jogo');
  const g = await guest(h);
  assert.deepEqual(lastModes(h, g), ALL, 'guest_state também (o Casual aceita convidado)');
  const cq = await casualQ(h);
  assert.deepEqual(cq.modes.map(m => [m.mode, m.label, m.enabled, m.open]), ALL.map((m, i) => [m, ['RELÂMPAGO', 'RÁPIDA', 'NORMAL', 'CONVENCIONAL'][i], true, true]));
  for (const k of ['waiting', 'longest_wait_ms', 'avg_wait_ms', 'active_matches', 'active_players']) assert.ok(k in cq.modes[0], 'métrica por ritmo: ' + k);
  h.backend.onClose(g);
});

test('métricas por ritmo: na fila, maior espera, tempo médio, partidas e jogadores ativos', async t => {
  const h = await fixture(t);
  h.backend.casual.startMatch('casual_10min', h.entry(A), h.entry(B), Date.now() - 30000);
  h.admin.metrics.onPaired('casual', 'casual_10min', [4000, 6000]);
  await h.backend.handle(h.sockets[2], { type: 'casual_queue', mode: 'casual_5min' }); await flush();
  assert.ok(h.backend.casual.mm.has(C));
  const cq = await casualQ(h);
  const by = Object.fromEntries(cq.modes.map(m => [m.mode, m]));
  assert.equal(by.casual_5min.waiting, 1); assert.ok(by.casual_5min.longest_wait_ms >= 0);
  assert.equal(by.casual_10min.active_matches, 1); assert.equal(by.casual_10min.active_players, 2);
  assert.equal(by.casual_10min.avg_wait_ms, 5000); assert.equal(by.casual_10min.avg_samples, 2);
  assert.equal(by.casual_3min.waiting, 0); assert.equal(by.casual_3min.longest_wait_ms, null); assert.equal(by.casual_3min.avg_wait_ms, null);
  assert.equal(cq.waiting.value, 1); assert.equal(cq.active_matches.value, 1); assert.equal(cq.active_players.value, 2);
});

test('desligar RELÂMPAGO do Casual: entrada recusada, quem esperava sai com aviso, partida continua, todos (inclusive convidado) recebem a lista; religar volta', async t => {
  const h = await fixture(t);
  const g = await guest(h);
  const m = h.backend.casual.startMatch('casual_3min', h.entry(A), h.entry(B), Date.now() - 30000);
  h.backend.casual.tick(); await flush();
  await h.backend.handle(h.sockets[2], { type: 'casual_queue', mode: 'casual_3min' }); await flush();
  assert.ok(h.backend.casual.mm.has(C));
  h.messages.length = 0;
  const r = await setMode(h, 'casual_3min', false);
  assert.equal(r.status, 200); assert.equal(r.body.changed, true); assert.deepEqual(r.body.open_modes, ['casual_5min', 'casual_10min', 'casual_20min']);
  for (const s of [...h.sockets, g]) assert.deepEqual(lastModes(h, s), ['casual_5min', 'casual_10min', 'casual_20min'], 'aviso imediato a contas e convidados');
  assert.ok(!h.backend.casual.mm.has(C), 'quem esperava saiu da fila');
  assert.equal(h.messages.find(x => x.socket === h.sockets[2] && x.type === 'casual_error').code, 'mode_disabled');
  h.messages.length = 0;
  await h.backend.handle(g, { type: 'casual_queue', mode: 'casual_3min' }); await flush();
  assert.equal(h.messages.find(x => x.socket === g && x.type === 'casual_error').code, 'mode_disabled', 'convidado também é recusado no servidor');
  await h.backend.handle(h.sockets[2], { type: 'casual_queue', mode: 'casual_5min' }); await flush();
  assert.ok(h.backend.casual.mm.has(C), 'outro ritmo continua aberto');
  const white = m.players.w.userId === A ? 0 : 1, rev = m.revision;
  await h.backend.handle(h.sockets[white], { type: 'casual_move', match_id: m.id, from: [4, 6], to: [4, 4] }); await flush();
  assert.ok(m.revision > rev); assert.equal(m.status, 'playing', 'partida Casual em andamento continua');
  h.backend.casual.mm.cancel(C);
  const on = await setMode(h, 'casual_3min', true);
  assert.equal(on.body.changed, true); assert.deepEqual(lastModes(h, g), ALL);
  await h.backend.handle(h.sockets[2], { type: 'casual_queue', mode: 'casual_3min' }); await flush();
  assert.ok(h.backend.casual.mm.has(C), 'reaberto: aceita entrada');
  const log = (await h.call('GET', '/admin/api/audit', { token: h.boss })).body.items;
  assert.equal(log[1].action, 'queue.mode_disable'); assert.deepEqual(log[1].target, { family: 'casual', mode: 'casual_3min' }); assert.equal(log[1].meta.removed_from_queue, 1); assert.equal(log[1].reason, 'liquidez casual');
  assert.equal(log[0].action, 'queue.mode_enable');
  h.backend.onClose(g);
});

test('Casual inteiro OFF: lista vazia para todos (jogo mostra indisponível), entrada recusada, fila esvaziada, partida continua; ON volta', async t => {
  const h = await fixture(t);
  const g = await guest(h);
  const m = h.backend.casual.startMatch('casual_5min', h.entry(A), h.entry(B), Date.now() - 30000);
  h.backend.casual.tick(); await flush();
  await h.backend.handle(h.sockets[2], { type: 'casual_queue', mode: 'casual_10min' }); await flush();
  const r = await setFamily(h, false);
  assert.equal(r.status, 200); assert.equal(r.body.changed, true);
  for (const s of [...h.sockets, g]) assert.deepEqual(lastModes(h, s), [], 'nenhum ritmo aberto');
  assert.ok(!h.backend.casual.mm.has(C));
  await h.backend.handle(g, { type: 'casual_queue', mode: 'casual_5min' }); await flush();
  assert.ok(!h.backend.casual.mm.has(g.identity && g.identity.id), 'convidado recusado');
  assert.equal(m.status, 'playing');
  const log = (await h.call('GET', '/admin/api/audit', { token: h.boss })).body.items;
  assert.equal(log[0].action, 'queue.disable'); assert.equal(log[0].meta.removed_from_queue, 1); assert.equal(log[0].reason, 'manutenção casual');
  assert.deepEqual((await setFamily(h, true)).body.changed, true);
  assert.deepEqual(lastModes(h, h.sockets[0]), ALL);
  h.backend.onClose(g);
});

test('sem pareamento em ritmo fechado; Ranked não é afetado pelo Casual', async t => {
  const h = await fixture(t);
  await setMode(h, 'casual_20min', false);
  h.backend.casual.mm.enqueue('casual_20min', { ...h.entry(A), since: Date.now() - 60e3 });
  h.backend.casual.mm.enqueue('casual_20min', { ...h.entry(B), since: Date.now() - 60e3 });
  h.backend.casual.tick(); await flush();
  assert.equal([...h.backend.casual.matches.values()].length, 0);
  assert.deepEqual(h.backend.rankedModesOpen(), ['ranked_3min', 'ranked_5min', 'ranked_10min', 'ranked_20min']);
});

test('segurança: viewer/comum não mudam; confirmação, motivo, ritmo e campos validados; noop registrado', async t => {
  const h = await fixture(t);
  assert.equal((await setMode(h, 'casual_3min', false, h.viewer)).status, 403);
  assert.equal((await setMode(h, 'casual_3min', false, h.alice)).status, 403);
  assert.equal((await setMode(h, 'casual_3min', false, h.boss, { confirm: 'casual_5min' })).status, 400);
  assert.equal((await setMode(h, 'casual_3min', false, h.boss, { reason: '' })).status, 400);
  assert.equal((await setMode(h, 'casual_3min', false, h.boss, { extra: 1 })).status, 400);
  assert.equal((await setMode(h, 'ranked_3min', false, h.boss, { confirm: 'ranked_3min' })).status, 404, 'ritmo do Ranked não vale na rota do Casual');
  assert.equal((await setMode(h, 'casual_1min', false, h.boss, { confirm: 'casual_1min' })).status, 404);
  assert.deepEqual(lastModes(h, h.sockets[0]), ALL);
  const n = await setMode(h, 'casual_5min', true);
  assert.equal(n.body.changed, false);
  assert.equal((await h.call('GET', '/admin/api/audit', { token: h.boss })).body.items[0].result, 'noop');
});

test('padrão ao subir: FRAIHA_CASUAL_MODES_OPEN', () => {
  assert.deepEqual(new ModeControls({ env: { FRAIHA_CASUAL_MODES_OPEN: 'casual_5min,x' } }).openModes('casual'), ['casual_5min']);
  assert.deepEqual(new ModeControls({ env: {} }).openModes('casual'), ALL);
});
