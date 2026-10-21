'use strict';
// R118 · TORNEIO DA SEMANA: semana de Brasília, pontos (vitória 3 / jogada 1), só mesa com 2+ pessoas, quem saiu não
// pontua, limite de 8 por dia, placar com desempate, prêmio pago uma vez quando a semana vira, sem a 0018 = indisponível.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { weekOf, weekStart, PRIZES } = require('../../online_v021/economy/tournaments');

const U = i => `${String(i).repeat(8)}-${String(i).repeat(4)}-4${String(i).repeat(3)}-a${String(i).repeat(3)}-${String(i).repeat(12)}`;
const A = U(1), B = U(2), C = U(3);
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); await new Promise(r => setImmediate(r)); };

async function fixture(t, at) {
  const messages = [];
  const origLog = console.log; console.log = () => {};
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop(); backend.tournaments.stop();
  t.after(() => backend.party.stop());
  let now = at || Date.parse('2026-10-15T15:00:00Z');
  backend.tournaments.now = () => now; backend.crowns.now = () => now;
  const login = async id => { const ws = { readyState: 1 }; await backend.handle(ws, { type: 'acct_auth', access_token: 'tok-' + id }); await flush(); return ws; };
  const of = (ws, type) => messages.filter(m => m.socket === ws && m.type === type);
  for (const [id, n] of [[A, 'Ana'], [B, 'Bia'], [C, 'Caio']]) await backend.store.createProfile(id, n + 'Torneio', 'warrior');
  return { backend, T: backend.tournaments, st: backend.store, login, of, setNow: v => { now = v; } };
}

test('semana de Brasília (segunda 00:00 → domingo 23:59)', () => {
  assert.equal(weekOf(Date.parse('2026-10-15T15:00:00Z')), '2026-W42');
  assert.equal(weekOf(Date.parse('2026-10-19T02:59:00Z')), '2026-W42', 'domingo 23:59 de Brasília');
  assert.equal(weekOf(Date.parse('2026-10-19T03:00:00Z')), '2026-W43', 'segunda 00:00 de Brasília');
  assert.equal(new Date(weekStart(Date.parse('2026-10-15T15:00:00Z'))).toISOString(), '2026-10-12T03:00:00.000Z');
  assert.equal(weekOf(Date.parse('2027-01-01T12:00:00Z')), '2026-W53');
});

test('pontos: vitória 3, jogada 1, quem saiu 0, mesa só com bots/1 pessoa não conta, 8 por dia', async t => {
  const h = await fixture(t);
  await h.T.onTable('xeque', [{ uid: A, win: true }, { uid: B, win: false }, { uid: 'bot', win: false }]);
  await h.T.onTable('xeque', [{ uid: A, win: false }, { uid: B, win: true, left: false }, { uid: C, left: true }]);
  await h.T.onTable('xeque', [{ uid: A, win: true }]);   // sozinho com bots: não conta
  const w = weekOf(Date.parse('2026-10-15T15:00:00Z'));
  const top = await h.st.tournTop(w, 'xeque');
  const pts = Object.fromEntries(top.map(r => [r.user_id, r.points]));
  assert.deepEqual(pts, { [A]: 4, [B]: 4 });
  assert.equal(top[0].user_id, A, 'empate: chegou primeiro');
  for (let i = 0; i < 10; i++) await h.T.onTable('marcha', [{ uid: A, win: true }, { uid: B, win: false }]);
  const m = await h.st.tournTop(w, 'marcha');
  assert.equal(m.find(r => r.user_id === A).points, 8 * 3, 'só 8 partidas por dia contam');
});

test('tourn_get mostra o placar e a minha posição; prêmio pago uma vez na virada da semana', async t => {
  const h = await fixture(t);
  await h.T.onTable('xeque', [{ uid: A, win: true }, { uid: B, win: false }]);
  await h.T.onTable('xeque', [{ uid: C, win: false }, { uid: B, win: true }]);
  const b = await h.login(B);
  await h.backend.handle(b, { type: 'tourn_get', game: 'xeque' }); await flush();
  const s = h.of(b, 'tourn_state').pop();
  assert.equal(s.available, true); assert.equal(s.top.length, 3);
  assert.equal(s.top[0].nickname, 'BiaTorneio'); assert.equal(s.me.pos, 1); assert.equal(s.me.points, 4);
  assert.ok(s.ends_in_s > 0 && s.ends_in_s <= 7 * 86400);
  const before = (await h.st.crownWallet(B)) ? (await h.st.crownWallet(B)).balance : 0;
  await h.T.payDue();   // semana ainda não virou: nada
  assert.equal(((await h.st.crownWallet(B)) || { balance: 0 }).balance, before);
  h.setNow(Date.parse('2026-10-19T04:00:00Z'));   // segunda de manhã
  await h.T.payDue(); await h.T.payDue(); await flush();
  // R173 · prêmio proporcional: 3 participantes = 30% (500→150, 300→90, 200→60)
  assert.equal(s.players, 3); assert.equal(s.prize_pct, 30); assert.equal(s.me.prize, 150); assert.equal(s.top[2].prize, 60);
  assert.equal((await h.st.crownWallet(B)).balance, before + Math.floor(PRIZES[0] * 3 / 10));
  assert.equal((await h.st.crownWallet(A)).balance, Math.floor(PRIZES[1] * 3 / 10));
  assert.equal((await h.st.crownWallet(C)).balance, Math.floor(PRIZES[2] * 3 / 10));
  assert.match(h.of(b, 'crowns_reward').pop().lines[0], /1º lugar \+150/);
});

test('sem a 0018: indisponível, sem derrubar nada', async t => {
  const h = await fixture(t);
  const err = () => { const e = new Error('Could not find the function public.fraiha_tourn_add'); e.code = 'PGRST202'; throw e; };
  h.st.tournAdd = err; h.st.tournTop = err;
  await h.T.onTable('xeque', [{ uid: A, win: true }, { uid: B, win: false }]);
  const a = await h.login(A);
  await h.backend.handle(a, { type: 'tourn_get', game: 'marcha' }); await flush();
  assert.equal(h.of(a, 'tourn_state').pop().available, false);
});
