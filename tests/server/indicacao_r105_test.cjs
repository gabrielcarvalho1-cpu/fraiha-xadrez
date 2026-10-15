'use strict';
// R105 · convite por link e indicação: código único, conta NOVA ligada a quem convidou, 5 partidas = 7 dias de
// Club para os dois, primeira compra = +30 dias para quem convidou, limite de 10 premiadas por mês, sem repetir.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { cleanCode, CODE_RE } = require('../../online_v021/social/referrals');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const C = '33333333-3333-4333-a333-333333333333';
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
  return { backend, messages, login, of, st: backend.store };
}

test('código do convite, conta nova ligada, 5 partidas premiam os dois, compra premia quem convidou', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaConvida', 'warrior');
  const a = await h.login(A);
  await h.backend.handle(a, { type: 'ref_get' }); await flush();
  const info = h.of(a, 'ref_info').pop();
  assert.equal(info.available, true); assert.match(info.code, CODE_RE);
  await h.backend.handle(a, { type: 'ref_get' }); await flush();
  assert.equal(h.of(a, 'ref_info').pop().code, info.code, 'o código não muda');
  // conta nova pelo link (código em minúsculas também vale)
  const b = await h.login(B);
  await h.backend.handle(b, { type: 'acct_create_profile', nickname: 'BiaNova', ref: info.code.toLowerCase() }); await flush();
  assert.ok(await h.st.getReferral(B), 'indicação registrada');
  // a própria pessoa não se indica; conta que já existia não entra
  assert.equal(await h.backend.referrals.onProfileCreated(A, info.code), null);
  // 4 partidas: nada; 5ª: os dois ganham 7 dias
  for (let i = 0; i < 4; i++) await h.backend.referrals.onGame(B);
  assert.equal((await h.st.getEntitlements(B)).club_active, false);
  await h.backend.referrals.onGame(B); await flush();
  const eb = await h.st.getEntitlements(B), ea = await h.st.getEntitlements(A);
  assert.ok(eb.club_active && ea.club_active, 'os dois ganharam Club');
  const days = d => Math.round((Date.parse(d) - Date.now()) / 86400e3);
  assert.equal(days(eb.club_expires_at), 7); assert.equal(days(ea.club_expires_at), 7);
  assert.equal(h.of(b, 'ref_reward').length, 1); assert.equal(h.of(a, 'ref_reward').length, 1);
  // mais partidas não premiam de novo
  for (let i = 0; i < 3; i++) await h.backend.referrals.onGame(B);
  assert.equal(days((await h.st.getEntitlements(A)).club_expires_at), 7);
  // primeira compra da conta convidada: +30 para quem convidou, só uma vez
  await h.backend.referrals.onPurchase(B); await h.backend.referrals.onPurchase(B);
  assert.equal(days((await h.st.getEntitlements(A)).club_expires_at), 37);
  await h.backend.handle(a, { type: 'ref_get' }); await flush();
  const after = h.of(a, 'ref_info').pop();
  assert.equal(after.invited, 1); assert.equal(after.qualified, 1); assert.equal(after.rewarded_month, 1); assert.equal(after.purchases, 1);
});

test('limite de 10 indicações premiadas por mês e código inválido ignorado', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaConvida', 'warrior');
  const a = await h.login(A);
  await h.backend.handle(a, { type: 'ref_get' }); await flush();
  const code = h.of(a, 'ref_info').pop().code;
  for (let i = 0; i < 11; i++) {
    const id = `4444444${i.toString(16)}-4444-4444-a444-444444444444`;
    await h.st.createProfile(id, 'Amigo' + i, 'warrior');
    await h.backend.referrals.onProfileCreated(id, code);
    for (let g = 0; g < 5; g++) await h.backend.referrals.onGame(id);
  }
  const ea = await h.st.getEntitlements(A);
  assert.equal(Math.round((Date.parse(ea.club_expires_at) - Date.now()) / 86400e3), 70, '10 x 7 dias, a 11ª não premia');
  assert.equal(cleanCode('abc'), ''); assert.equal(cleanCode('ABCDEF0'), '', 'sem 0/O/1/I');
  await h.st.createProfile(C, 'CaioSemLink', 'warrior');
  assert.equal(await h.backend.referrals.onProfileCreated(C, 'ZZZZZZZ'), null, 'código que não existe');
});

test('partida casual terminada com lances suficientes conta; desistência na hora não conta', async t => {
  const h = await fixture(t);
  const calls = [];
  h.backend.referrals.onGame = uid => { calls.push(uid); };
  const { Ranked } = require('../../online_v021/ranked/service');
  const casual = new Ranked({ send: h.backend.send, kind: 'casual' });
  h.backend.attachCasual(casual); casual.stop();
  const e = id => ({ userId: id, nickname: id.slice(0, 4), avatar: 'warrior', stats: { league: 0, pl: 0 } });
  const fake = (w, b, ply) => ({ id: 'm' + ply, mode: 'casual_5min', status: 'finished', result: { winner: 'w', reason: 'resign' }, pos: { ply },
    players: { w: { userId: w, connected: false }, b: { userId: b, connected: false } } });
  const end = async m => { await casual.persist(m); await flush(); };
  await end(fake(A, B, 2));
  assert.equal(calls.length, 0, 'desistência com 2 lances não conta');
  const D = '55555555-5555-4555-a555-555555555555';
  await end(fake(C, D, 24));
  assert.deepEqual(calls.slice().sort(), [C, D].sort());
});
