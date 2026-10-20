'use strict';
// R120 · PASSE DA TEMPORADA: temporada = mês de Brasília, 30 níveis × 150 XP, XP por vitória/partida/missão/entrada,
// limite diário de XP de partidas, faixa grátis para todos, faixa Club (com retroativo ao assinar), itens da Loja
// entregues uma vez (ou +300 se já tinha), nada pago duas vezes.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const P = require('../../online_v021/economy/season_pass');

const A = '11111111-1111-4111-a111-111111111111';
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); await new Promise(r => setImmediate(r)); };

async function fixture(t) {
  const messages = [];
  const origLog = console.log; console.log = () => {};
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop(); backend.tournaments.stop();
  t.after(() => backend.party.stop());
  let now = Date.parse('2026-10-15T15:00:00Z');
  for (const x of [backend.seasonPass, backend.crowns]) x.now = () => now;
  const login = async id => { const ws = { readyState: 1 }; await backend.handle(ws, { type: 'acct_auth', access_token: 'tok-' + id }); await flush(); return ws; };
  const of = (ws, type) => messages.filter(m => m.socket === ws && m.type === type);
  await backend.store.createProfile(A, 'AnaPasse', 'warrior');
  return { backend, SP: backend.seasonPass, st: backend.store, login, of, setNow: v => { now = v; } };
}

test('temporada e níveis', () => {
  assert.equal(P.seasonOf(Date.parse('2026-10-15T15:00:00Z')), '2026-10');
  assert.equal(P.seasonOf(Date.parse('2026-11-01T02:59:00Z')), '2026-10', '31/10 23:59 de Brasília');
  assert.equal(P.seasonOf(Date.parse('2026-11-01T03:00:00Z')), '2026-11');
  assert.equal(P.seasonName('2026-10'), 'Temporada de Outubro');
  assert.equal(P.levelOf(0), 0); assert.equal(P.levelOf(149), 0); assert.equal(P.levelOf(150), 1); assert.equal(P.levelOf(1e9), 30);
  const r = P.rewards('2026-10');
  assert.equal(r.length, 30);
  assert.ok(r[9].club.item && r[19].club.item && r[29].club.crowns === 500, 'itens nos níveis 10 e 20 e 500 Coroas no 30 da faixa Club (R167)');
  assert.notDeepEqual(P.seasonItems('2026-10'), P.seasonItems('2026-11'), 'itens mudam com a temporada');
});

test('faixa grátis: sobe de nível e recebe uma vez; limite de XP de partidas por dia', async t => {
  const h = await fixture(t);
  for (let i = 0; i < 9; i++) await h.SP.add(A, 'win');   // 270 XP
  await h.SP.add(A, 'win'); await h.SP.add(A, 'win');        // passa do limite de 300
  let c = await h.st.crownDaily(A, '2026-10-01');
  assert.equal(c.pass_xp, 300, 'partidas: até 300 XP por dia');
  await h.SP.add(A, 'mission', 3); await h.SP.add(A, 'daily');   // +170
  c = await h.st.crownDaily(A, '2026-10-01');
  assert.equal(c.pass_xp, 470); assert.equal(P.levelOf(470), 3);
  const w = await h.st.crownWallet(A);
  assert.equal(w.balance, 30, 'nível 3 da faixa grátis: +30 (sem Club, nada da faixa Club)');
  await h.SP.grant(A, '2026-10', 1, 3, false);
  assert.equal((await h.st.crownWallet(A)).balance, 30, 'não paga duas vezes');
});

test('faixa Club: retroativo ao assinar, item da loja no nível 10 (ou +300 se já tinha)', async t => {
  const h = await fixture(t);
  await h.st.crownBump(A, '2026-10-01', { pass_xp: 1500 });   // nível 10 sem Club
  const a = await h.login(A);
  await h.backend.handle(a, { type: 'pass_get' }); await flush();
  let s = h.of(a, 'pass_state').pop();
  assert.equal(s.available, true); assert.equal(s.level, 10); assert.equal(s.club, false);
  await h.st.grantClubDays(A, 30, 'test');
  const item = P.seasonItems('2026-10')[10];
  await h.backend.handle(a, { type: 'pass_get' }); await flush();
  s = h.of(a, 'pass_state').pop();
  assert.equal(s.club, true);
  assert.ok((await h.st.crownItems(A)).includes(item), 'emote da temporada entregue');
  const bal = (await h.st.crownWallet(A)).balance;
  await h.backend.handle(a, { type: 'pass_get' }); await flush();
  assert.equal((await h.st.crownWallet(A)).balance, bal, 'retroativo não paga de novo');
  // já tinha o item: +300 no lugar
  const B = '22222222-2222-4222-a222-222222222222';
  await h.st.createProfile(B, 'BiaPasse', 'warrior');
  await h.st.crownAward(B, 5000, 'game', 'x'); await h.st.crownBuy(B, item, 100);
  const before = (await h.st.crownWallet(B)).balance;
  await h.SP.grant(B, '2026-10', 10, 10, true);
  assert.equal((await h.st.crownWallet(B)).balance, before + 300 + 0 + 0 + 0, 'já tinha: +300');
});

test('partida online dá XP do passe (via Coroas)', async t => {
  const h = await fixture(t);
  await h.backend.crowns.onGame(A, { kind: 'casual', ref: 'm1', result: 'win' }); await flush();
  const xp = (await h.st.crownDaily(A, '2026-10-01')).pass_xp;
  assert.ok(xp >= 30 && (xp - 30) % 50 === 0, 'vitória 30 (+50 por missão que completou): ' + xp);
});
