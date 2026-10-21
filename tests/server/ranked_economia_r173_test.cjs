'use strict';
// R173 · integridade Ranked/Economia (auditoria Orca em 40df312):
//  1) Ranked: desistência/abandono antes de 10 meios-lances = sem PL, sem placar, sem Coroas, sem indicação;
//     depois do mínimo, xeque-mate, tempo e empates seguem iguais;
//  2) Coroas: teto diário de 150 por partidas atômico com finalizações simultâneas; dedupe por partida; teto exato.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { RankedMatch, MIN_RATED_PLY } = require('../../online_v021/ranked/match');
const { CONFIG } = require('../../online_v021/ranked/config');
const { applyResult } = require('../../online_v021/ranked/progression');
const { MATCH_CAP, dayOf } = require('../../online_v021/economy/crowns');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const gameCrowns = async (st, id) => ((await st.crownLedger(id, 200)) || []).filter(r => r.reason === 'game').reduce((a, r) => a + r.delta, 0);
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); await new Promise(r => setImmediate(r)); };
const sq = s => ['abcdefgh'.indexOf(s[0]), 8 - Number(s[1])];
const stats0 = () => ({ league: 0, pl: 0, highest_league: 0, wins: 0, losses: 0, draws: 0, matches: 0, forca: 1200, forca_rd: 350 });
const cfg = { ...CONFIG, startDelayMs: 0, reconnectGraceMs: 1000 };
const seat = (id, stats) => ({ userId: id, nickname: id.slice(0, 4), avatar: 'warrior', stats, connected: true, leftAt: 0 });
// lances de peão que nunca repetem posição nem capturam (até 16 meios-lances)
const SEQ = 'abcdefgh'.split('').flatMap(c => [[c + '2', c + '3'], [c + '7', c + '6']]);
function play(m, plies) {
  for (let i = 0; i < plies; i++) {
    const [f, t] = SEQ[i];
    const r = m.move(m.pos.turn, { from: sq(f), to: sq(t) }, 1 + i);
    assert.ok(r.ok, 'lance ' + (i + 1) + ' ' + JSON.stringify(r));
  }
}
function match() {
  const m = new RankedMatch({ mode: 'ranked_5min', white: seat(A, stats0()), black: seat(B, stats0()), now: 0, cfg, rated: true });
  m.tick(0);
  return m;
}

test('regra: mínimo de 10 meios-lances (5 de cada lado)', () => { assert.equal(MIN_RATED_PLY, 10); });

// st(liga, PL, Força?) — com Força conhecida (RD 60) o PL normal fica previsível
const st = (league, pl, forca, rd = 60) => ({ league, pl, highest_league: league, wins: 0, losses: 0, draws: 0, matches: forca ? 30 : 0, forca: forca || 1200, forca_rd: forca ? rd : 350 });
function matchOf(ws, bs, prefixPlies = 0) {
  const m = new RankedMatch({ mode: 'ranked_5min', white: seat(A, ws), black: seat(B, bs), now: 0, cfg, rated: true });
  m.tick(0); play(m, prefixPlies); return m;
}
const normal = (W, L) => ({ win: applyResult(W, L, 'win'), loss: applyResult(L, W, 'loss') });
const R = s => s.league * 100 + s.pl;

// Exemplos do dono: perdedor perde o normal; vencedor recebe exatamente o que saiu (até o ganho normal)
const CASES = [
  ['+36/−4 → +4/−4', st(0, 50), st(0, 50), 4, -4],
  ['+19/−9 → +9/−9', st(1, 50, 750 + 175 * 1.15), st(1, 50, 922.5), 9, -9],
  ['piso: perdedor com 3 PL perde só 3 → vencedor +3', st(0, 50), st(0, 3), 3, -3],
  ['perda efetiva 0 (Madeira 0 PL) → vencedor +0', st(0, 50), st(0, 0), 0, 0],
  ['rebaixamento: perdedor cai de liga (−10 nominal) → vencedor +10 (o ganho normal é 17)', st(2, 40, 1026), st(2, 0, 980), 10, -10],
  ['Grão-Mestre travado em 100 → vencedor +0 (o perdedor perde normal)', st(9, 100, 1900), st(9, 50, 1900), 0, -5],
];
for (const plies of [0, 1, 5, 9]) {
  for (const [name, W, L, gain, lossShown] of CASES) {
    test(`precoce · ${plies} meio(s)-lance(s) · ${name}`, () => {
      // as Brancas desistem (perdedor = Brancas); com ply ímpar quem desiste é quem está na vez ou não, tanto faz
      const m = matchOf(L, W, plies);
      m.resign('w', 100);
      assert.equal(m.result.early, true);
      const n = normal(W, L), rw = m.result.b, rl = m.result.w;
      assert.equal(rl.applied + 0, lossShown, 'perdedor: perda normal exibida');
      assert.equal(rl.stats.league, n.loss.stats.league); assert.equal(rl.stats.pl, n.loss.stats.pl, 'perdedor: mesma posição da derrota normal');
      assert.equal(rw.applied, gain, 'vencedor: só o que saiu do outro');
      assert.ok(rw.applied <= Math.max(0, n.win.change), 'nunca acima do ganho normal');
      assert.ok(R(rw.stats) - R(W) <= R(L) - R(rl.stats), 'nunca cria PL líquido');
      for (const [r, o] of [[rw, W], [rl, L]]) { assert.equal(r.stats.forca, o.forca); assert.equal(r.stats.forca_rd, o.forca_rd, 'Força intacta'); }
      const rec = m.record();
      assert.equal(rec.white_forca_after, null); assert.equal(rec.black_forca_after, null, 'banco mantém a Força (coalesce)');
      const out = m.resultFor('b', true);
      assert.equal(out.pl_change, gain); assert.equal(out.early, true); assert.equal(out.outcome, 'win');
    });
  }
}

test('rebaixamento precoce: perdedor cai de liga como numa derrota normal', () => {
  const W = st(2, 40, 1026), L = st(2, 0, 980);
  const m = matchOf(L, W, 3); m.resign('w', 50);
  assert.equal(m.result.w.demoted, true); assert.equal(m.result.w.stats.league, 1); assert.equal(m.result.w.stats.pl, 75);
});

test('promoção precoce: vencedor pode subir de liga com o PL transferido (sem passar do ganho normal)', () => {
  const W = st(8, 95, 750 + 895 * 1.15), L = st(8, 50, 750 + 850 * 1.15);
  const m = matchOf(L, W, 2); m.resign('w', 50);
  assert.equal(m.result.b.applied, 8); assert.equal(m.result.b.stats.league, 9); assert.equal(m.result.b.stats.pl, 3); assert.equal(m.result.b.promoted, true);
});

test('placar no precoce: NÃO soma partida/vitória/derrota/empate; Força não muda; gravação manda count_stats=false', () => {
  const W = st(0, 50, 1100), L = st(0, 50, 1100);
  W.matches = 7; W.wins = 4; W.losses = 3; L.matches = 9; L.wins = 2; L.losses = 6; L.draws = 1;
  const m = matchOf(L, W, 0); m.resign('w', 10);
  for (const [r, o] of [[m.result.b.stats, W], [m.result.w.stats, L]]) for (const k of ['matches', 'wins', 'losses', 'draws', 'forca', 'forca_rd']) assert.equal(r[k], o[k], k);
  assert.equal(m.record().count_stats, false);
  const n = matchOf(L, W, 10); n.resign('w', 10);
  assert.equal(n.record().count_stats, true, '10+ meios-lances conta normalmente');
  assert.equal(n.result.b.stats.matches, 8); assert.equal(n.result.b.stats.wins, 5); assert.equal(n.result.w.stats.losses, 7);
});

test('duas contas alternando desistências precoces NÃO criam PL líquido (200 partidas, várias posições)', () => {
  for (const [a0, b0] of [[st(0, 50), st(0, 50)], [st(0, 0), st(0, 0)], [st(3, 10, 1150), st(3, 90, 1180)], [st(9, 100, 1900), st(9, 100, 1900)]]) {
    let a = a0, b = b0;
    const start = R(a) + R(b);
    for (let i = 0; i < 200; i++) {
      const aLoses = i % 2 === 0;
      const m = matchOf(aLoses ? a : b, aLoses ? b : a, i % 10);
      m.resign('w', 10);
      const lw = m.result.w.stats, lb = m.result.b.stats;
      if (aLoses) { a = lw; b = lb; } else { b = lw; a = lb; }
      assert.ok(R(a) + R(b) <= start, `partida ${i + 1}: soma ${R(a) + R(b)} > início ${start}`);
    }
  }
});

test('10 meios-lances → cálculo NORMAL (+36/−4, Força muda)', () => {
  const W = st(0, 50), L = st(0, 50);
  const m = matchOf(L, W, 10); m.resign('w', 200);
  assert.ok(!m.result.early);
  assert.equal(m.result.b.applied, 36); assert.equal(m.result.w.applied, -4);
  assert.notEqual(m.result.b.stats.forca, W.forca, 'Força atualizada');
  assert.notEqual(m.record().white_forca_after, null);
});

test('abandono (sem reconectar) antes do mínimo → precoce', () => {
  const m = matchOf(st(0, 50), st(0, 50), 4);
  m.players.w.connected = false; m.players.w.leftAt = 10;
  m.tick(10 + cfg.reconnectGraceMs + 1);
  assert.equal(m.result.reason, 'abandon'); assert.equal(m.result.early, true);
  assert.equal(m.result.b.applied, 4); assert.equal(m.result.w.applied, -4);
});

test('xeque-mate legítimo em 4 meios-lances → PL normal (não é precoce)', () => {
  const m = matchOf(st(0, 50), st(0, 50), 0);
  for (const [i, [f, t]] of [['f2', 'f3'], ['e7', 'e5'], ['g2', 'g4'], ['d8', 'h4']].entries()) assert.ok(m.move(m.pos.turn, { from: sq(f), to: sq(t) }, 1 + i).ok);
  assert.equal(m.result.reason, 'checkmate'); assert.ok(!m.result.early);
  assert.equal(m.result.b.applied, 36);
});

test('tempo esgotado continua normal (fora da regra)', () => {
  const m = new RankedMatch({ mode: 'ranked_5min', white: seat(A, stats0()), black: seat(B, stats0()), now: 0, cfg: { ...cfg, baseMs: () => 1000 }, rated: true });
  m.tick(0); m.tick(5000);
  assert.equal(m.result.reason, 'timeout'); assert.ok(!m.result.early);
});

test('Casual: regra não muda nada', () => {
  const m = new RankedMatch({ mode: 'casual_5min', white: seat(A, null), black: seat(B, null), now: 0, cfg, rated: false, prefix: 'casual' });
  m.tick(0); m.resign('w', 10);
  assert.equal(m.result.winner, 'b'); assert.ok(!m.result.early);
});

// ---------- serviço: nada gravado no Ranked, nada de Coroas/indicação para a partida curta
async function fixture(t, nowMs) {
  const messages = [];
  const origLog = console.log; console.log = () => {};
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  t.after(() => backend.party.stop());
  let now = nowMs || Date.parse('2026-10-21T15:00:00Z');
  backend.crowns.now = () => now;
  const ranked = new Ranked({ send: (ws, o) => messages.push({ socket: ws, ...o }), cfg, now: () => 1000 });
  clearInterval(ranked.timer);
  ranked.canStartMatch = () => true;   // sem sockets/fila neste teste: o que importa é o fim da partida
  backend.attachRanked(ranked);
  t.after(() => clearInterval(ranked.timer));
  for (const [id, n] of [[A, 'AnaR173'], [B, 'BiaR173']]) await backend.store.createProfile(id, n, 'warrior');
  return { backend, ranked, st: backend.store, C: backend.crowns, messages };
}

test('serviço: precoce grava a transferência de PL (sem Força, sem Coroas); com 10 lances → normal e paga', async t => {
  const h = await fixture(t);
  const full = id => h.st.getRankedStats(id, { forca: true });
  const s = async id => (await full(id)).ranked_5min;
  for (const id of [A, B]) { const x = h.st.stats.get(id).ranked_5min; x.pl = 50; x.forca = 1200; x.forca_rd = 350; }
  const entry = async id => ({ userId: id, nickname: id.slice(0, 4), avatar: 'warrior', stats: await s(id), since: 0 });
  let m = h.ranked.startMatch('ranked_5min', await entry(A), await entry(B), 0, true);
  m.tick(0);
  const loser = m.players.w.userId, winner = m.players.b.userId;
  m.resign('w', 50);
  await h.ranked.persist(m); await flush();
  assert.equal(h.st.matches.length, 1, 'partida gravada (histórico)');
  assert.equal((await s(loser)).pl, 46); assert.equal((await s(winner)).pl, 54, '+4/−4');
  for (const id of [loser, winner]) { const x = await s(id); assert.equal(x.matches, 0); assert.equal(x.wins + x.losses + x.draws, 0, 'precoce fora do placar'); }
  assert.equal((await s(loser)).forca, 1200); assert.equal((await s(winner)).forca_rd, 350, 'Força intacta no banco');
  for (const id of [A, B]) assert.equal(((await h.st.crownWallet(id)) || { balance: 0 }).balance, 0, 'sem Coroas no precoce');
  // depois do mínimo
  m = h.ranked.startMatch('ranked_5min', await entry(A), await entry(B), 0, true);
  m.tick(0); play(m, 10);
  const w2 = m.players.b.userId, wBefore = (await s(w2)).pl;
  m.resign('w', 500);
  await h.ranked.persist(m); await flush();
  assert.equal(h.st.matches.length, 2);
  assert.equal((await s(w2)).matches, 1); assert.equal((await s(w2)).wins, 1, 'normal conta no placar');
  assert.ok((await s(w2)).pl - wBefore > 4, 'ganho normal');
  assert.notEqual((await s(w2)).forca, 1200, 'Força atualizada');
  assert.ok((await h.st.crownWallet(w2)).balance > 0, 'Coroas pagas');
});

// ---------- Coroas: teto diário atômico
test('Coroas: duas partidas terminando JUNTAS com 145 no dia → paga só 5 (teto 150)', async t => {
  const h = await fixture(t);
  const day = dayOf(Date.parse('2026-10-21T15:00:00Z'));
  await h.st.crownBump(A, day, { match_crowns: 145 });
  const [r1, r2] = await Promise.all([
    h.C.onGame(A, { kind: 'ranked', ref: 'm-1', result: 'win' }),
    h.C.onGame(A, { kind: 'xeque', ref: 'm-2', result: 'win' })]);
  const paid = (r1 ? r1.lines : []).concat(r2 ? r2.lines : []);
  assert.equal((await h.st.crownDaily(A, day)).match_crowns, MATCH_CAP, 'contador termina em 150');
  assert.equal(await gameCrowns(h.st, A), 5, 'só 5 Coroas de partida pagas');
  assert.ok(paid.some(l => /limite de 150/.test(l)), 'a segunda avisa o limite');
});

test('Coroas: 10 partidas simultâneas a partir de 0 → nunca passa de 150', async t => {
  const h = await fixture(t);
  const day = dayOf(Date.parse('2026-10-21T15:00:00Z'));
  await h.st.crownBump(A, day, { match_crowns: 100 });
  await Promise.all(Array.from({ length: 10 }, (_, i) => h.C.onGame(A, { kind: 'casual', ref: 'c-' + i, result: 'win' })));
  assert.equal((await h.st.crownDaily(A, day)).match_crowns, 150);
  assert.equal(await gameCrowns(h.st, A), 50);
});

test('Coroas: teto EXATO — 140 + vitória (10) = 150; a próxima paga 0', async t => {
  const h = await fixture(t);
  const day = dayOf(Date.parse('2026-10-21T15:00:00Z'));
  await h.st.crownBump(A, day, { match_crowns: 140 });
  await h.C.onGame(A, { kind: 'ranked', ref: 'x-1', result: 'win' });
  assert.equal((await h.st.crownDaily(A, day)).match_crowns, 150);
  assert.equal(await gameCrowns(h.st, A), 10);
  await h.C.onGame(A, { kind: 'ranked', ref: 'x-2', result: 'win' });
  assert.equal(await gameCrowns(h.st, A), 10, 'no teto: 0');
  assert.equal((await h.st.crownDaily(A, day)).match_crowns, 150);
});

test('Coroas: a MESMA partida repetida (replay) nunca paga duas vezes, nem em paralelo', async t => {
  const h = await fixture(t);
  const day = dayOf(Date.parse('2026-10-21T15:00:00Z'));
  const r = await Promise.all([1, 2, 3].map(() => h.C.onGame(A, { kind: 'ranked', ref: 'same', result: 'win' })));
  assert.equal(r.filter(Boolean).length, 1);
  assert.equal(await gameCrowns(h.st, A), 10);
  assert.equal((await h.st.crownDaily(A, day)).match_crowns, 10);
  assert.equal((await h.st.crownDaily(A, day)).games, 1);
});

test('Coroas: contas diferentes não esperam uma pela outra (fila é por conta)', async t => {
  const h = await fixture(t);
  await Promise.all([h.C.onGame(A, { kind: 'ranked', ref: 'a1', result: 'win' }), h.C.onGame(B, { kind: 'ranked', ref: 'b1', result: 'loss' })]);
  assert.equal(await gameCrowns(h.st, A), 10);
  assert.equal(await gameCrowns(h.st, B), 3);
});
