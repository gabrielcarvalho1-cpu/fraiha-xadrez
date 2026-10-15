'use strict';
// R104 · Denúncias (perfil / conversa privada / partida) guardadas para o Admin; suspensão com prazo que impede
// o login, desconecta na hora e acaba sozinha; viewer não modera.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { AdminService } = require('../../online_v021/admin/service');
const { Reports, cleanContext } = require('../../online_v021/moderation/reports');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const BOSS = '44444444-4444-4444-a444-444444444444';
const VIEW = '55555555-5555-4555-a555-555555555555';
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); await new Promise(r => setImmediate(r)); };

async function fixture(t) {
  const messages = [];
  const origLog = console.log; console.log = () => {};
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  await backend.store.createProfile(A, 'AnaTest', 'warrior');
  await backend.store.createProfile(B, 'BrunoChato', 'warrior');
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  const admin = new AdminService({ backend, env: { FRAIHA_ADMIN_USERS: `${BOSS}=owner,${VIEW}=viewer`, FRAIHA_ENV: 'dev' }, autostart: false });
  const server = http.createServer((req, res) => admin.owns(req) ? admin.handle(req, res) : (res.writeHead(404), res.end()));
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.close(); backend.party.stop(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, token, body) => {
    const res = await fetch(base + path, { method, headers: { Authorization: 'Bearer ' + token, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
    const text = await res.text(); return { status: res.status, body: text ? JSON.parse(text) : null };
  };
  const login = async id => { const ws = { readyState: 1 }; await backend.handle(ws, { type: 'acct_auth', access_token: 'tok-' + id }); await flush(); return ws; };
  const of = (ws, type) => messages.filter(m => m.socket === ws && m.type === type);
  return { backend, messages, call, login, of };
}

test('denúncia pelo perfil e pela conversa privada vai para a fila do Admin com o trecho das mensagens', async t => {
  const h = await fixture(t);
  const st = h.backend.store;
  await st.addDirectMessage(B, A, 'mensagem ofensiva 1'); await st.addDirectMessage(A, B, 'para com isso'); await st.addDirectMessage(B, A, 'mensagem ofensiva 2');
  const a = await h.login(A);
  await h.backend.handle(a, { type: 'social_report', user_id: B, from: 'dm' }); await flush();
  assert.equal(h.of(a, 'social_report_ok').length, 1);
  const r = await h.call('GET', '/admin/api/reports?status=open', 'tok-' + BOSS);
  assert.equal(r.status, 200);
  assert.equal(r.body.items.length, 1);
  const it = r.body.items[0];
  assert.equal(it.kind, 'dm'); assert.equal(it.reported.nickname, 'BrunoChato'); assert.equal(it.reporter.nickname, 'AnaTest');
  assert.deepEqual(it.messages, ['mensagem ofensiva 1', 'mensagem ofensiva 2']);   // só o que o denunciado escreveu
  // a mesma denúncia de novo não duplica
  await h.backend.handle(a, { type: 'social_report', user_id: B, from: 'dm' }); await flush();
  assert.equal((await h.call('GET', '/admin/api/reports', 'tok-' + BOSS)).body.items.length, 1);
  // pelo perfil é outra denúncia
  await h.backend.handle(a, { type: 'social_report', user_id: B }); await flush();
  assert.equal((await h.call('GET', '/admin/api/reports', 'tok-' + BOSS)).body.items.length, 2);
  // viewer não vê nem modera; arquivar com owner
  assert.equal((await h.call('GET', '/admin/api/reports', 'tok-' + VIEW)).status, 403);
  assert.equal((await h.call('POST', '/admin/api/reports/' + it.report_id, 'tok-' + VIEW, { status: 'dismissed' })).status, 403);
  const d = await h.call('POST', '/admin/api/reports/' + it.report_id, 'tok-' + BOSS, { status: 'dismissed', note: 'sem ofensa real' });
  assert.equal(d.status, 200); assert.equal(d.body.report.status, 'dismissed');
  assert.equal((await h.call('GET', '/admin/api/reports?status=open', 'tok-' + BOSS)).body.items.length, 1);
});

test('suspensão: desconecta na hora, recusa o login até o prazo e acaba sozinha', async t => {
  const h = await fixture(t);
  const b = await h.login(B);
  assert.ok(h.of(b, 'acct_state').length >= 1);
  assert.equal((await h.call('POST', `/admin/api/players/${B}/suspend`, 'tok-' + BOSS, { days: 7 })).status, 400, 'motivo obrigatório');
  assert.equal((await h.call('POST', `/admin/api/players/${B}/suspend`, 'tok-' + BOSS, { days: 0, reason: 'x' })).status, 400, 'prazo inválido');
  const s = await h.call('POST', `/admin/api/players/${B}/suspend`, 'tok-' + BOSS, { days: 7, reason: 'ofensas no chat' });
  assert.equal(s.status, 200); assert.ok(s.body.until);
  assert.equal(h.of(b, 'acct_suspended').length, 1, 'quem está online é avisado e desconectado');
  assert.match(h.of(b, 'acct_suspended')[0].message, /suspensa até .*ofensas no chat/);
  const b2 = await h.login(B);
  assert.equal(h.of(b2, 'acct_suspended').length, 1, 'login recusado durante a suspensão');
  assert.equal(h.of(b2, 'acct_state').length, 0);
  // prazo vencido → entra e a conta volta a 'active'
  (await h.backend.store.getProfile(B)).suspended_until = new Date(Date.now() - 1000).toISOString();
  const b3 = await h.login(B);
  assert.equal(h.of(b3, 'acct_suspended').length, 0);
  assert.ok(h.of(b3, 'acct_state').length >= 1);
  assert.equal((await h.backend.store.getProfile(B)).account_status, 'active');
  // banir (sem prazo) e tirar a suspensão
  assert.equal((await h.call('POST', `/admin/api/players/${B}/suspend`, 'tok-' + BOSS, { days: null, reason: 'reincidente' })).status, 200);
  const b4 = await h.login(B);
  assert.match(h.of(b4, 'acct_suspended')[0].message, /tempo indeterminado/);
  assert.equal((await h.call('POST', `/admin/api/players/${B}/unsuspend`, 'tok-' + BOSS, { reason: 'perdoado' })).status, 200);
  const b5 = await h.login(B);
  assert.ok(h.of(b5, 'acct_state').length >= 1);
  const audit = await h.call('GET', '/admin/api/audit', 'tok-' + BOSS);
  assert.ok(audit.body.items.some(x => x.action === 'player_suspend') && audit.body.items.some(x => x.action === 'player_unsuspend'));
});

test('limites: 10 denúncias a cada 10 min por conta e contexto cortado', async () => {
  let now = 1e12;
  const rows = [];
  const R = new Reports({ backend: { store: { createReport: async r => { rows.push(r); return r; } } }, now: () => now, log: () => {} });
  for (let i = 0; i < 10; i++) assert.ok((await R.file({ reporter: 'a', reported: 'b' + i, kind: 'profile' })).ok);
  assert.equal((await R.file({ reporter: 'a', reported: 'z', kind: 'profile' })).code, 'rate_limited');
  now += 11 * 60 * 1000;
  assert.ok((await R.file({ reporter: 'a', reported: 'z', kind: 'profile' })).ok);
  assert.equal((await R.file({ reporter: 'a', reported: 'a', kind: 'profile' })).code, 'invalid');
  const c = cleanContext({ messages: Array.from({ length: 50 }, () => 'x'.repeat(900)), outra: 'lixo' });
  assert.equal(c.messages.length <= 20, true); assert.equal(c.messages[0].length, 500); assert.equal(c.outra, undefined);
  // sem tabela (0013 pendente): não perde a denúncia, vai para o log
  const logs = [];
  const R2 = new Reports({ backend: { store: { createReport: async () => { const e = new Error('relation "public.reports" does not exist'); e.code = '42P01'; throw e; } } }, log: l => logs.push(l) });
  const r2 = await R2.file({ reporter: 'a', reported: 'b', kind: 'match', context: { messages: ['oi'] } });
  assert.equal(r2.persisted, false); assert.ok(logs.some(l => l.startsWith('[denuncia-sem-tabela]')));
});
