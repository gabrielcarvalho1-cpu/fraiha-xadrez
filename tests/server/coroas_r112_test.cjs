'use strict';
// R112 · COROAS: entrada do dia (+sequência), partida online (vitória/derrota, limite diário, Club +25%),
// missões do dia, sem pagar duas vezes a mesma partida, hooks da Ranqueada/Casual e de XEQUE/Marcha.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { missionsFor, dayOf, MATCH_CAP, POOL } = require('../../online_v021/economy/crowns');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); await new Promise(r => setImmediate(r)); };

async function fixture(t, nowMs) {
  const messages = [];
  const origLog = console.log; console.log = () => {};
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  t.after(() => backend.party.stop());
  let now = nowMs || Date.parse('2026-10-15T15:00:00Z');
  backend.crowns.now = () => now;
  const login = async id => { const ws = { readyState: 1 }; await backend.handle(ws, { type: 'acct_auth', access_token: 'tok-' + id }); await flush(); return ws; };
  const of = (ws, type) => messages.filter(m => m.socket === ws && m.type === type);
  return { backend, messages, login, of, st: backend.store, C: backend.crowns, setNow: v => { now = v; } };
}

test('missões do dia: 3, de grupos diferentes, iguais para todos e trocam com o dia', () => {
  const d1 = missionsFor('2026-10-15'), d2 = missionsFor('2026-10-15');
  assert.equal(d1.length, 3);
  assert.deepEqual(d1.map(m => m.id), d2.map(m => m.id));
  assert.equal(new Set(d1.map(m => m.group)).size, 3);
  const seen = new Set();
  for (let i = 0; i < 40; i++) for (const m of missionsFor(dayOf(Date.parse('2026-10-01T12:00:00Z') + i * 86400e3))) seen.add(m.id);
  assert.ok(seen.size >= POOL.length - 1, 'o sorteio passa por quase todas as missões');
  assert.equal(dayOf(Date.parse('2026-10-16T02:59:00Z')), '2026-10-15', 'dia de Brasília');
  assert.equal(dayOf(Date.parse('2026-10-16T03:00:00Z')), '2026-10-16');
});

test('entrada do dia: +10 uma vez por dia; 3º dia seguido +20; 7º +50; sequência quebra', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaCoroa', 'warrior');
  const a = await h.login(A); await flush();
  assert.equal((await h.st.crownWallet(A)).balance, 10);
  assert.equal(h.of(a, 'crowns_reward').pop().gained, 10);
  await h.C.onLogin(A); await h.C.onLogin(A);
  assert.equal((await h.st.crownWallet(A)).balance, 10, 'mesmo dia não paga de novo');
  const day = 86400e3, t0 = Date.parse('2026-10-15T15:00:00Z');
  h.setNow(t0 + day); await h.C.onLogin(A);
  h.setNow(t0 + 2 * day); const r3 = await h.C.onLogin(A);
  assert.equal(r3.streak, 3); assert.equal(r3.gained, 30);
  for (let i = 3; i < 7; i++) { h.setNow(t0 + i * day); await h.C.onLogin(A); }
  const w = await h.st.crownWallet(A);
  assert.equal(w.streak, 7); assert.equal(w.balance, 7 * 10 + 20 + 50);
  h.setNow(t0 + 9 * day); assert.equal((await h.C.onLogin(A)).streak, 1, 'pulou um dia: recomeça');
});

test('partida: vitória +10, derrota +3, sem repetir, missões pagam, limite de 150 por dia, Club +25%', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaCoroa', 'warrior');
  const day = dayOf(h.C.now());
  const ms = missionsFor(day);
  const w0 = 0;
  const r1 = await h.C.onGame(A, { kind: 'casual', ref: 'm1', result: 'win' });
  assert.ok(r1.gained >= 10);
  assert.equal(await h.C.onGame(A, { kind: 'casual', ref: 'm1', result: 'win' }), null, 'a mesma partida não paga duas vezes');
  await h.C.onGame(A, { kind: 'casual', ref: 'm2', result: 'loss' });
  const counters = await h.st.crownDaily(A, day);
  assert.equal(counters.games, 2); assert.equal(counters.wins, 1); assert.equal(counters.match_crowns, 13);
  // missões completadas até aqui (pela regra) — o saldo é partidas + recompensas
  const doneReward = ms.filter(m => (counters[m.key] || 0) >= m.target).reduce((s, m) => s + m.reward, 0);
  assert.equal((await h.st.crownWallet(A)).balance, w0 + 13 + doneReward);
  // limite diário das partidas
  for (let i = 0; i < 30; i++) await h.C.onGame(A, { kind: 'casual', ref: 'x' + i, result: 'win' });
  assert.equal((await h.st.crownDaily(A, day)).match_crowns, MATCH_CAP);
  const capped = await h.C.onGame(A, { kind: 'casual', ref: 'cap', result: 'win' });
  assert.equal(capped.gained, 0); assert.match(capped.lines[0], /limite/);
  // estado público: sem lançamentos de 0
  const st = await h.C.snapshot(A);
  assert.equal(st.match_today, MATCH_CAP);
  assert.ok(st.recent.every(r => r.delta !== 0));
  assert.equal(st.missions.length, 3);
  // Club: +25%
  await h.st.createProfile(B, 'BiaClub', 'warrior');
  await h.st.grantClubDays(B, 30, 'test');
  const rb = await h.C.onGame(B, { kind: 'ranked', ref: 'r1', result: 'win' });
  assert.match(rb.lines[0], /Vitória \+13 \(Club \+25%\)/);
});

test('hooks: Ranqueada/Casual com 10+ lances e XEQUE/Marcha dão Coroas; crowns_get responde', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaCoroa', 'warrior');
  await h.st.createProfile(B, 'BiaCoroa', 'warrior');
  const a = await h.login(A);
  const before = (await h.st.crownWallet(A)).balance;
  // partida casual curta (menos de 10 lances) não conta
  const { Ranked } = require('../../online_v021/ranked/service');
  const svc = new Ranked({ send: h.backend.send, kind: 'casual' });
  h.backend.attachCasual(svc); svc.stop();
  const fake = (ply, winner) => ({ id: 'fake-' + ply + winner, mode: 'blitz', pos: { ply }, result: { winner, reason: 'resign' },
    players: { w: { userId: A, connected: false }, b: { userId: B, connected: false } }, record: () => ({}), resultFor: () => ({}) });
  await svc.persist(fake(4, 'w')); await flush();
  assert.equal((await h.st.crownWallet(A)).balance, before);
  await svc.persist(fake(12, 'w')); await flush();
  assert.ok((await h.st.crownWallet(A)).balance >= before + 10);
  assert.ok((await h.st.crownWallet(B)).balance >= 3);
  // XEQUE: quem ficou ganha, quem saiu não
  const P = h.backend.party;
  const room = { id: 'room-1', game: 'xeque', ended: false, g: { winner: 0 }, timer: null,
    seats: [{ kind: 'human', uid: A, left: false }, { kind: 'human', uid: B, left: true }, { kind: 'bot' }, { kind: 'bot' }] };
  const bBefore = (await h.st.crownWallet(B)).balance;
  P.rewardCrowns(room); await flush();
  assert.equal((await h.st.crownDaily(A, dayOf(h.C.now()))).xeque, 1);
  assert.equal((await h.st.crownWallet(B)).balance, bBefore, 'quem saiu da mesa não ganha');
  await h.backend.handle(a, { type: 'crowns_get' }); await flush();
  const s = h.of(a, 'crowns_state').pop();
  assert.equal(s.available, true); assert.equal(s.missions.length, 3); assert.ok(s.balance > 0); assert.equal(s.daily_claimed, true);
});

test('sem a 0016 (banco sem as funções): indisponível, sem derrubar nada', async t => {
  const h = await fixture(t);
  await h.st.createProfile(A, 'AnaCoroa', 'warrior');
  const err = () => { const e = new Error('Could not find the function public.fraiha_crown_award'); e.code = 'PGRST202'; throw e; };
  h.st.crownAward = err; h.st.crownCheckin = err; h.st.crownWallet = err;
  const a = await h.login(A);
  assert.equal(await h.C.onGame(A, { kind: 'casual', ref: 'z', result: 'win' }), null);
  await h.backend.handle(a, { type: 'crowns_get' }); await flush();
  assert.equal(h.of(a, 'crowns_state').pop().available, false);
});
