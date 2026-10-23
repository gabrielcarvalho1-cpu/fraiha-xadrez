'use strict';
// R179 · Admin: aviso "entrou um jogador" (conta, conta nova, convidado novo), sem repetir em reconexão.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { AdminService } = require('../../online_v021/admin/service');
const { JoinLog } = require('../../online_v021/admin/joins');

const A = '11111111-1111-4111-a111-111111111111';
const N = '66666666-6666-4666-a666-666666666666';
const BOSS = '44444444-4444-4444-a444-444444444444';
const flush = async () => { for (let i = 0; i < 50; i++) await Promise.resolve(); };

test('JoinLog: dedupe de 10 min por jogador; conta nova e convidado novo sempre avisam', () => {
  let t = 1e6; const j = new JoinLog({ now: () => t });
  assert.ok(j.note({ id: 'a', nickname: 'Ana' }));
  assert.equal(j.note({ id: 'a', nickname: 'Ana' }), null);
  t += 11 * 60e3; assert.equal(j.note({ id: 'a', nickname: 'Ana' }).kind, 'account');
  j.markNew('b'); assert.equal(j.note({ id: 'b', nickname: 'Bia' }).kind, 'new_account');
  assert.equal(j.note({ id: 'guest:x', nickname: 'Convidado 1', guest: true, newGuest: true }).kind, 'guest_new');
  assert.equal(j.since(1).items.length, 3); assert.equal(j.since().seq, 4);
  assert.equal(j.since(4).items.length, 0);
});

test('API /admin/api/joins: login, conta nova e convidado aparecem; viewer lê; jogador comum não', async t => {
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: () => {} });
  backend.auth = { verify: async tok => { const m = /^tok-(.+)$/.exec(tok); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  backend.attachRanked(new Ranked({ send: backend.send })); backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual' }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  await backend.store.createProfile(A, 'AliceTest', 'warrior');
  const admin = new AdminService({ backend, env: { FRAIHA_ADMIN_USERS: `${BOSS}=viewer`, FRAIHA_ENV: 'dev' }, autostart: false });
  const server = http.createServer((req, res) => admin.handle(req, res));
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const socks = [];
  t.after(() => { server.close(); for (const s of socks) backend.onClose(s); backend.party.stop(); });
  const get = async (p, tok) => { const r = await fetch(`http://127.0.0.1:${server.address().port}${p}`, { headers: { Authorization: 'Bearer ' + tok } }); return { status: r.status, body: await r.json() }; };
  const base = await get('/admin/api/joins', 'tok-' + BOSS);
  assert.equal(base.status, 200);
  const s1 = { readyState: 1 }; socks.push(s1); await backend.handle(s1, { type: 'acct_auth', access_token: 'tok-' + A }); await flush();
  const s2 = { readyState: 1 }; socks.push(s2); await backend.handle(s2, { type: 'acct_auth', access_token: 'tok-' + N }); await flush();
  await backend.handle(s2, { type: 'acct_create_profile', nickname: 'NovatoTop', avatar_id: 'warrior' }); await flush();
  const s3 = { readyState: 1 }; socks.push(s3); await backend.handle(s3, { type: 'guest_auth' }); await flush();
  const s4 = { readyState: 1 }; socks.push(s4); await backend.handle(s4, { type: 'acct_auth', access_token: 'tok-' + A }); await flush();   // 2ª aba: não repete
  const r = await get('/admin/api/joins?after=' + base.body.seq, 'tok-' + BOSS);
  assert.deepEqual(r.body.items.map(i => [i.kind, i.nickname.startsWith('Convidado') ? 'Convidado' : i.nickname]),
    [['account', 'AliceTest'], ['new_account', 'NovatoTop'], ['guest_new', 'Convidado']]);
  assert.equal(r.body.online, 3); assert.equal(r.body.guests, 1);
  assert.equal((await get('/admin/api/joins', 'tok-' + A)).status, 403);
});
