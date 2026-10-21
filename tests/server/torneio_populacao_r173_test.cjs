'use strict';
// R173 · Torneio da Semana com prêmio PROPORCIONAL (opção B do dono): fator = min(contas distintas / 10, 1).
// Roda o Tournaments REAL (MemoryStore) com 2, 4, 8, 10, 12 e 20 contas jogando a semana inteira e confere o que foi pago,
// posição por posição, e que placar/posições/pontos não mudaram.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { weekOf, PRIZES, DAILY_GAMES, prizeFor } = require('../../online_v021/economy/tournaments');

const U = i => { const h = (i + 0x1000).toString(16).padStart(4, '0'); return `${h}${h}-${h}-4${h.slice(1)}-a${h.slice(1)}-${h}${h}${h}`; };
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); await new Promise(r => setImmediate(r)); };
const sum = a => a.reduce((x, y) => x + y, 0);

const PCT = { 2: 20, 4: 40, 8: 80, 10: 100, 12: 100, 20: 100 };
const expected = n => PRIZES.slice(0, n).map(p => Math.floor(p * PCT[n] / 100));

test('prizeFor: determinístico, inteiro, nunca acima do integral', () => {
  for (let n = 0; n <= 30; n++) for (let i = 0; i < 12; i++) {
    const v = prizeFor(i, n);
    assert.ok(Number.isInteger(v) && v >= 0 && v <= (PRIZES[i] || 0));
    assert.equal(v, prizeFor(i, n));
  }
  assert.deepEqual(PRIZES.map((_, i) => prizeFor(i, 2)), [100, 60, 40, 20, 20, 20, 20, 20, 20, 20]);
  assert.deepEqual(PRIZES.map((_, i) => prizeFor(i, 10)), PRIZES);
  assert.equal(prizeFor(0, 3), 150); assert.equal(prizeFor(3, 7), 70);
});

async function week(t, n) {
  const origLog = console.log; console.log = () => {};
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: () => {} });
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop(); backend.tournaments.stop();
  t.after(() => backend.party.stop());
  let now = Date.parse('2026-10-12T12:00:00Z');   // segunda, W42
  backend.tournaments.now = () => now; backend.crowns.now = () => now;
  const ids = Array.from({ length: n }, (_, i) => U(i));
  for (const [i, id] of ids.entries()) await backend.store.createProfile(id, 'Tor' + i, 'warrior');
  // 7 dias, cada um joga o máximo que conta (8/dia) em mesas de 2, ganhando metade
  for (let d = 0; d < 7; d++) {
    now = Date.parse('2026-10-12T12:00:00Z') + d * 86400e3;
    for (let g = 0; g < DAILY_GAMES; g++)
      for (let i = 0; i + 1 < n; i += 2) {
        const w = (g + d) % 2 === 0;
        for (const game of ['xeque', 'marcha']) await backend.tournaments.onTable(game, [{ uid: ids[i], win: w }, { uid: ids[i + 1], win: !w }]);
      }
  }
  const w = weekOf(now);
  now = Date.parse('2026-10-19T12:00:00Z');   // semana virou
  await backend.tournaments.payDue(); await flush();
  let paid = 0; const byGame = {};
  for (const game of ['xeque', 'marcha']) {
    const top = await backend.store.tournTop(w, game, 50);
    byGame[game] = { order: top.map(r => r.user_id), points: top.map(r => r.points) };
    byGame[game].paid = [];
    for (const r of top) byGame[game].paid.push(sum(((await backend.store.crownLedger(r.user_id, 200)) || []).filter(x => x.reason === 'tournament' && x.ref === w + ':' + game).map(x => x.delta)));
  }
  for (const id of ids) paid += sum(((await backend.store.crownLedger(id, 200)) || []).filter(r => r.reason === 'tournament').map(r => r.delta));
  // segunda passada (servidor reinicia): nada pago de novo
  await backend.tournaments.payDue(); await flush();
  let again = 0;
  for (const id of ids) again += sum(((await backend.store.crownLedger(id, 200)) || []).filter(r => r.reason === 'tournament').map(r => r.delta));
  return { week: w, paid, again, byGame };
}

const table = [];
for (const n of [2, 4, 8, 10, 12, 20]) {
  test(`torneio · ${n} contas distintas → ${PCT[n]}% do prêmio, posição por posição, nos 2 modos`, async t => {
    const r = await week(t, n);
    for (const game of ['xeque', 'marcha']) {
      const g = r.byGame[game];
      assert.equal(g.order.length, n, 'todos no placar (posições preservadas)');
      const want = expected(n).concat(Array(Math.max(0, n - 10)).fill(0));
      assert.deepEqual(g.paid.map(x => x || 0), want.slice(0, n), game + ': pago por posição');
      for (let i = 1; i < g.points.length; i++) assert.ok(g.points[i - 1] >= g.points[i], 'ordem por pontos intacta');
    }
    assert.equal(r.paid, 2 * sum(expected(n)));
    assert.equal(r.again, r.paid, 'pagar de novo não paga duas vezes');
    table.push({ contas: n, pct: PCT[n], 'Coroas/semana (2 modos)': r.paid, antes: 2 * sum(PRIZES.slice(0, n)) });
  });
}
test('resumo', () => {
  console.error('\n' + JSON.stringify(table));
  assert.equal(table.find(x => x.contas === 2)['Coroas/semana (2 modos)'], 320, '2 contas: 1.600 → 320');
});
