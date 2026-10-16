'use strict';
// R128 · FRAIHA Admin · LIBERAR TODAS AS LIGAS (teste visual). Servidor decide: o Admin liga/desliga com motivo +
// confirmação "ligas"; TODOS os conectados (contas e convidados) recebem na hora ('leagues_preview') e quem entra
// depois recebe no acct_state/guest_state. Só aparência: não mexe em PL, liga nem Ranked. Viewer não pode mudar.
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


const set = (h, enabled, token = h.boss, extra = {}) => h.call('POST', '/admin/api/leagues-preview', { token, body: { enabled, reason: 'teste visual das ligas', confirm: 'ligas', ...extra } });
const last = (h, sock) => { const m = h.messages.filter(x => x.socket === sock && (x.type === 'leagues_preview' || ((x.type === 'acct_state' || x.type === 'guest_state') && 'leagues_preview' in x))).at(-1); return m ? (m.type === 'leagues_preview' ? m.enabled : m.leagues_preview) : undefined; };

test('padrão: desligado; acct_state e guest_state informam; painel mostra o estado', async t => {
  const h = await fixture(t);
  assert.equal(last(h, h.sockets[0]), false, 'acct_state leva leagues_preview=false');
  const g = { readyState: 1 };
  await h.backend.handle(g, { type: 'guest_auth' }); await flush();
  assert.equal(last(h, g), false, 'guest_state também');
  const q = await h.call('GET', '/admin/api/queues', { token: h.boss });
  assert.equal(q.status, 200);
  assert.equal(q.body.leagues.enabled, false);
});

test('ligar: todos os conectados recebem na hora; quem entra depois recebe no acct_state; Admin Log registra', async t => {
  const h = await fixture(t);
  const g = { readyState: 1 };
  await h.backend.handle(g, { type: 'guest_auth' }); await flush();
  const r = await set(h, true);
  assert.equal(r.status, 200); assert.equal(r.body.changed, true); assert.equal(r.body.leagues.enabled, true);
  for (const s of h.sockets) assert.equal(last(h, s), true, 'conta conectada recebeu');
  assert.equal(last(h, g), true, 'convidado conectado recebeu');
  const late = { readyState: 1 };
  await h.backend.store.createProfile('66666666-6666-4666-a666-666666666666', 'Tarde', 'warrior');
  await h.backend.handle(late, { type: 'acct_auth', access_token: 'tok-66666666-6666-4666-a666-666666666666' }); await flush();
  assert.equal(last(h, late), true, 'quem entra depois já vem liberado');
  const log = await h.call('GET', '/admin/api/audit?action=leagues.preview_on', { token: h.boss });
  assert.ok(log.body.items.some(i => i.action === 'leagues.preview_on' && i.result === 'ok' && i.reason === 'teste visual das ligas'));
  const again = await set(h, true);
  assert.equal(again.body.changed, false, 'repetir = sem mudança (noop registrado)');
  const off = await set(h, false);
  assert.equal(off.body.leagues.enabled, false);
  for (const s of h.sockets) assert.equal(last(h, s), false, 'desligar também chega na hora');
});

test('segurança: viewer não muda; sem motivo/confirmação ou com campo extra = recusado; sem login = 401', async t => {
  const h = await fixture(t);
  assert.equal((await set(h, true, h.viewer)).status, 403);
  assert.equal((await h.call('POST', '/admin/api/leagues-preview', { token: h.boss, body: { enabled: true, reason: 'x', confirm: 'ligas' } })).body.error, 'reason_required');
  assert.equal((await h.call('POST', '/admin/api/leagues-preview', { token: h.boss, body: { enabled: true, reason: 'teste', confirm: 'ranked' } })).body.error, 'confirmation_required');
  assert.equal((await set(h, true, h.boss, { pl: 999 })).status, 400);
  assert.equal((await h.call('POST', '/admin/api/leagues-preview', { body: { enabled: true, reason: 'teste', confirm: 'ligas' } })).status, 401);
  assert.equal((await h.call('POST', '/admin/api/leagues-preview', { token: h.alice, body: { enabled: true, reason: 'teste', confirm: 'ligas' } })).status, 403, 'jogador comum não é admin');
  assert.equal(h.backend.leaguesPreview(), false, 'nada mudou');
});

test('reinício: padrão vem de FRAIHA_LEAGUES_PREVIEW', () => {
  assert.equal(new ModeControls({ env: {} }).leaguesPreview(), false);
  assert.equal(new ModeControls({ env: { FRAIHA_LEAGUES_PREVIEW: '1' } }).leaguesPreview(), true);
  assert.equal(new ModeControls({ env: { FRAIHA_LEAGUES_PREVIEW: 'nao' } }).leaguesPreview(), false);
});
