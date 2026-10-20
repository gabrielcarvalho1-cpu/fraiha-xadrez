'use strict';
// R168 · Admin ENVIAR/TIRAR COROAS (copiado do fixture de Clube/Fundador)
// FRAIHA Admin · CLUBE FRAIHA + FUNDADOR: escrita administrativa server-side (tabela entitlements da 0005).
// Cobre: permissões (owner/operator/viewer/comum), payload estrito, datas, motivo, confirmação, versão
// (UI desatualizada), UUID inexistente, conceder/alterar/revogar Clube (prazos, sem expiração, data
// personalizada, expirado), conceder/revogar Fundador (independente do Clube), idempotência, Admin Log,
// jogador online recebe acct_state novo, lista ONLINE (entra/sai), e o caminho Supabase (PostgREST falso).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { AdminService } = require('../../online_v021/admin/service');
const Ent = require('../../online_v021/admin/entitlements');
const { SupabaseStore } = require('../../online_v021/accounts/store');

const A = '11111111-1111-4111-a111-111111111111';     // online, tem perfil
const B = '22222222-2222-4222-a222-222222222222';     // offline, tem perfil
const NOPROF = '33333333-3333-4333-a333-333333333333'; // não existe
const BOSS = '44444444-4444-4444-a444-444444444444';
const VIEW = '55555555-5555-4555-a555-555555555555';
const OPER = '66666666-6666-4666-a666-666666666666';
const DAY = 86400e3;
const user = id => ({ id, email: 'local@dev.invalid', provider: 'dev' });

async function fixture(t) {
  const messages = [], logs = [];
  const origLog = console.log; console.log = (...a) => logs.push(a.join(' '));
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? user(m[1]) : null; } };
  backend.attachRanked(new Ranked({ send: backend.send }));
  backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual' }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  await backend.store.createProfile(A, 'AliceTest', 'warrior');
  await backend.store.createProfile(B, 'BobTest', 'warrior');
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  const sockA = { readyState: 1 };
  await backend.handle(sockA, { type: 'acct_auth', access_token: 'tok-' + A });
  const admin = new AdminService({ backend, env: { FRAIHA_ADMIN_USERS: `${BOSS}=owner,${VIEW}=viewer,${OPER}=operator`, FRAIHA_ENV: 'dev' }, autostart: false });
  const server = http.createServer((req, res) => admin.owns(req) ? admin.handle(req, res) : (res.writeHead(404), res.end()));
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.close(); backend.onClose(sockA); backend.party.stop(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, { token = 'tok-' + BOSS, body, raw } = {}) => {
    const headers = { Authorization: 'Bearer ' + token };
    if (body !== undefined || raw !== undefined) headers['Content-Type'] = 'application/json';
    const res = await fetch(base + path, { method, headers, body: raw !== undefined ? raw : body !== undefined ? JSON.stringify(body) : undefined });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  };
  const state = async uid => (await call('GET', '/admin/api/players/' + uid)).body.ent;
  const act = async (uid, kind, extra, token) => {
    const cur = await state(uid);
    return call('POST', `/admin/api/players/${uid}/${kind}`, { token, body: { reason: 'teste admin', confirm: uid, expect_version: cur.version, ...extra } });
  };
  return { backend, admin, messages, logs, call, state, act, sockA };
}


test('R168: dono envia e tira Coroas; viewer não; motivo e quantidade validados; jogador online avisado; Admin Log', async t => {
  const h = await fixture(t);
  let r = await h.call('GET', `/admin/api/players/${A}/crowns`);
  assert.equal(r.status, 200); assert.equal(r.body.available, true);
  const b0 = r.body.balance;   // entrada do dia já pagou ao logar
  r = await h.call('POST', `/admin/api/players/${A}/crowns`, { token: 'tok-' + VIEW, body: { amount: 100, reason: 'teste' } });
  assert.equal(r.status, 403);
  r = await h.call('POST', `/admin/api/players/${A}/crowns`, { body: { amount: 100, reason: '' } });
  assert.equal(r.body.error, 'reason_required');
  r = await h.call('POST', `/admin/api/players/${A}/crowns`, { body: { amount: 1.5, reason: 'teste' } });
  assert.equal(r.body.error, 'invalid_amount');
  r = await h.call('POST', `/admin/api/players/${NOPROF}/crowns`, { body: { amount: 10, reason: 'teste' } });
  assert.equal(r.status, 404);
  h.messages.length = 0;
  r = await h.call('POST', `/admin/api/players/${A}/crowns`, { body: { amount: 50000, reason: 'Teste do dono' } });
  assert.equal(r.status, 200); assert.equal(r.body.balance, b0 + 50000);
  await new Promise(res => setTimeout(res, 30));
  const got = h.messages.find(m => m.type === 'crowns_reward');
  assert.ok(got && got.gained === 50000 && got.lines[0].includes('Presente do FRAIHA'), 'jogador online recebe o aviso');
  // duas vezes a mesma quantidade: cada envio vale (referência única)
  r = await h.call('POST', `/admin/api/players/${A}/crowns`, { body: { amount: 50000, reason: 'Teste do dono' } });
  assert.equal(r.body.balance, b0 + 100000);
  r = await h.call('POST', `/admin/api/players/${A}/crowns`, { body: { amount: -(b0 + 100001), reason: 'tirar demais' } });
  assert.equal(r.body.error, 'insufficient_balance');
  r = await h.call('POST', `/admin/api/players/${A}/crowns`, { body: { amount: -1000, reason: 'correção' } });
  assert.equal(r.body.balance, b0 + 99000);
  r = await h.call('GET', `/admin/api/players/${A}/crowns`);
  assert.equal(r.body.balance, b0 + 99000);
  assert.ok(r.body.recent.some(x => x.reason === 'admin' && x.delta === -1000));
  const audit = (await h.call('GET', '/admin/api/audit?limit=20')).body.items;
  assert.ok(audit.some(x => x.action === 'crowns_give') && audit.some(x => x.action === 'crowns_take'));
});
