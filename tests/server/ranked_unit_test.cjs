'use strict';
const { check, summary } = require('./helpers.cjs');
const { points, applyResult } = require('../../online_v021/ranked/progression');
const { ChessClock } = require('../../online_v021/ranked/clock');
const { Matchmaker } = require('../../online_v021/ranked/matchmaker');
const S = (league, pl) => ({ league, pl, matches: 0, wins: 0, losses: 0, draws: 0, highest_league: league });
// R143 · Tabela de PL por liga (contra alguém do mesmo nível, Força batendo com a liga)
const { BASE, expectedForca, forcaOf, glicko, GM, TOP } = require('../../online_v021/ranked/progression');
const SF = (league, pl, forca) => ({ ...S(league, pl), matches: 30, forca: forca ?? expectedForca(league * 100 + pl), forca_rd: 80 });
for (let lg = 0; lg <= 9; lg++) {
  const me = SF(lg, 50), opp = SF(lg, 50);
  check(points(me, opp, 'win') === BASE[lg][0] && points(me, opp, 'loss') === -BASE[lg][1], `liga ${lg}: vitória +${BASE[lg][0]}, derrota −${BASE[lg][1]}`);
}
check(BASE[0][0] === 20 && BASE[0][1] === 8 && BASE[9][0] === 6 && BASE[9][1] === 6, 'Madeira +20/−8 … Grão-Mestre +6/−6 (o ganho diminui subindo)');
// Força acima da liga: ganha mais e perde menos (limite 1,8x até a Platina, 1,25x depois)
{ const pro = SF(0, 0, 2000), opp = SF(0, 0);
  check(points(pro, opp, 'win') === 36 && points(pro, opp, 'loss') === -4, 'muito melhor que a liga (Madeira): +36 / −4');
  const proD = SF(7, 0, 2600);
  check(points(proD, SF(7, 0), 'win') === Math.round(11 * 1.25), 'Diamante pra cima: bônus pequeno (máx. 1,25x)');
  const weak = SF(4, 50, 1000);
  check(points(weak, SF(4, 50), 'win') < 15 && points(weak, SF(4, 50), 'loss') < -12, 'acima do próprio nível: ganha menos e perde mais'); }
// Empate: meio ponto contra a expectativa
{ const a = SF(4, 50), strong = SF(4, 50, expectedForca(450) + 300), weak2 = SF(4, 50, expectedForca(450) - 300);
  check(points(a, SF(4, 50), 'draw') === 0, 'empate com alguém do mesmo nível = 0');
  check(points(a, strong, 'draw') > 0, 'empate com alguém mais forte rende PL (' + points(a, strong, 'draw') + ')');
  check(points(a, weak2, 'draw') < 0, 'empate com alguém mais fraco custa PL (' + points(a, weak2, 'draw') + ')'); }
// Força: começa em 1200 / incerteza 350; sem Força guardada estima pela liga
check(forcaOf(S(0, 0)).f === 1200 && forcaOf(S(0, 0)).rd === 350, 'conta nova: Força 1200, incerteza 350');
check(forcaOf({ ...S(4, 0), matches: 10 }).f === Math.round(expectedForca(400)), 'conta antiga sem Força: estimada pela liga');
{ const a = glicko({ f: 1200, rd: 350 }, { f: 1200, rd: 80 }, 1), b = glicko({ f: 1200, rd: 60 }, { f: 1200, rd: 80 }, 1);
  check(a.f - 1200 > 100 && b.f - 1200 < 15 && a.rd < 350, 'Força: jogador novo mexe muito; jogador firme mexe pouco'); }
let r = applyResult(SF(0, 96), SF(0, 96), 'win'); check(r.stats.league === 1 && r.stats.pl === 16 && r.promoted, 'Madeira 96 +20 → Ferro 16 (excedente)');
r = applyResult(SF(2, 3), SF(2, 3), 'loss'); check(r.stats.pl === 0 && r.stats.league === 2 && r.applied === -3 && !r.demoted, 'derrota com PL > 0 para em 0 e a liga fica');
r = applyResult(SF(2, 0), SF(2, 0), 'loss'); check(r.stats.league === 1 && r.stats.pl === 75 && r.demoted && !r.promoted, 'derrota com 0 PL rebaixa (Bronze 0 → Ferro 75)');
r = applyResult({ ...SF(1, 0), highest_league: 1 }, SF(0, 50), 'loss'); check(r.stats.league === 0 && r.stats.pl === 75 && r.demoted && r.stats.highest_league === 1, 'Ferro 0 perde → Madeira 75 (maior liga continua Ferro)');
r = applyResult(SF(0, 0), SF(0, 0), 'loss'); check(r.stats.league === 0 && r.stats.pl === 0 && !r.demoted, 'Madeira nunca rebaixa');
r = applyResult(SF(2, 0), SF(2, 0), 'draw'); check(r.stats.league === 2 && r.stats.pl === 0 && !r.demoted && r.stats.draws === 1, 'empate com 0 PL não rebaixa');
r = applyResult(SF(GM, 97), SF(GM, 97), 'win'); check(r.stats.league === GM && r.stats.pl === 100 && r.applied === 3 && r.challenger_candidate, 'Grão-Mestre trava em 100 PL: Challenger só por vaga');
r = applyResult(SF(8, 96), SF(8, 96), 'win'); check(r.stats.league === GM && r.stats.pl === 4, 'Mestre 96 +8 → Grão-Mestre 4');
r = applyResult(SF(TOP, 0), SF(TOP, 0), 'loss'); check(r.stats.league === GM && r.stats.pl === 75 && r.demoted, 'Challenger com 0 PL que perde volta ao Grão-Mestre');
r = applyResult(SF(TOP, 98), SF(TOP, 98), 'win'); check(r.stats.league === TOP && r.stats.pl === 100, 'Challenger: até 100 PL');
r = applyResult(SF(1, 10), SF(1, 10), 'win'); check(r.stats.wins === 1 && r.stats.highest_league === 1 && Number.isFinite(r.stats.forca), 'vitória registrada, Força atualizada');
// R143 · vagas do Challenger
{ const { plan, slotsFor } = require('../../online_v021/ranked/challenger');
  check(slotsFor(0) === 3 && slotsFor(350) === 3 && slotsFor(1000) === 10 && slotsFor(90000) === 40, 'vagas: 1 a cada 100 ativos, mínimo 3, máximo 40');
  const now = Date.parse('2026-10-20T12:00:00Z'), fresh = '2026-10-19T12:00:00Z', old = '2026-10-01T12:00:00Z';
  const row = (id, league, pl, forca, at = fresh) => ({ user_id: id, league, pl, forca, matches: 50, updated_at: at });
  let p = plan([row('a', GM, 100, 2000), row('b', GM, 100, 2100), row('c', GM, 60, 2500), row('d', GM, 100, 1900, old)], 100, now);
  const ids = p.moves.filter(m => m.to.league === TOP).map(m => m.user_id).sort().join(',');
  check(ids === 'a,b' && p.slots === 3, 'vaga livre: entram os Grão-Mestres com 100 PL e ativos (c sem 100 PL e d inativo ficam)');
  p = plan([row('x', TOP, 40, 2000), row('y', TOP, 10, 1950), row('z', TOP, 70, 2050), row('n', GM, 100, 2300)], 100, now);
  check(p.moves.length === 2 && p.moves[0].user_id === 'y' && p.moves[0].to.league === GM && p.moves[1].user_id === 'n', 'vagas cheias: o mais forte toma a vaga do Challenger mais fraco');
  p = plan([row('x', TOP, 40, 2000), row('y', TOP, 10, 1950), row('z', TOP, 70, 2050), row('n', GM, 100, 1900)], 100, now);
  check(p.moves.length === 0, 'candidato mais fraco que todos os Challengers: espera');
  p = plan([row('x', TOP, 40, 2000, old), row('n', GM, 100, 1800)], 100, now);
  check(p.moves.some(m => m.user_id === 'x' && m.why === 'inativo') && p.moves.some(m => m.user_id === 'n' && m.to.league === TOP), '7 dias sem jogar: perde a vaga');
  p = plan([row('x', TOP, 40, 2000, old), row('n', GM, 100, 2400)], 100, now, uid => uid === 'x' || uid === 'n');
  check(p.moves.length === 0, 'quem está em fila/partida não é mexido'); }
// Relógio
const c = new ChessClock(300000); c.start('w', 1000);
check(c.snapshot(3000).w_ms === 298000 && c.snapshot(3000).b_ms === 300000 && c.active === 'w', 'Brancas começam com relógio ativo; Pretas paradas');
check(!c.press('b', 4000), 'jogada fora de turno não troca o relógio');
c.press('w', 5000); check(c.active === 'b' && c.snapshot(5000).w_ms === 296000, 'jogada legal das Brancas para o relógio delas e inicia o das Pretas');
check(c.snapshot(15000).b_ms === 290000 && c.snapshot(15000).w_ms === 296000, 'relógio das Pretas corre, Brancas paradas');
c.press('b', 15000); check(c.active === 'w', 'jogada das Pretas devolve o relógio às Brancas');
check(c.flagged(15000 + 296000) === 'w', 'queda de bandeira detectada em 00:00');
// Matchmaking (R143: pela Força oculta)
const mm = new Matchmaker({ initialWindow: 120, expandEveryMs: 10000, expandStep: 80, maxWindow: 600 });
const E = (id, l, p, since = 0, forca) => ({ userId: id, stats: { ...S(l, p), matches: 20, forca: forca ?? expectedForca(l * 100 + p) }, since });
mm.enqueue('ranked_3min', E('a', 2, 50)); mm.enqueue('ranked_5min', E('b', 2, 50));
check(mm.tick(1000).length === 0, 'modalidades diferentes não se encontram');
mm.enqueue('ranked_3min', E('c', 2, 65)); let p = mm.tick(1000); check(p.length === 1 && p[0].mode === 'ranked_3min', 'mesma modalidade, Força parecida se encontram na hora');
mm.enqueue('ranked_5min', E('d', 4, 10)); check(mm.tick(1000).length === 0, 'Força distante não pareia no início');
check(mm.tick(10500).length === 1, 'após espera, faixa ampliada pareia');
{ const mm2 = new Matchmaker({ initialWindow: 120, expandEveryMs: 10000, expandStep: 80, maxWindow: 600 });
  mm2.enqueue('ranked_3min', E('pro', 0, 0, 0, 2200)); mm2.enqueue('ranked_3min', E('novato', 0, 0, 0, 1150));
  check(mm2.tick(600000).length === 0, 'jogador forte começando na Madeira não pega iniciante (Força longe demais)');
  mm2.enqueue('ranked_3min', E('diamante', 7, 30, 0, 2050)); const pp = mm2.tick(600000);
  check(pp.length === 1 && [pp[0].a.userId, pp[0].b.userId].sort().join() === 'diamante,pro', '…e pega alguém da Força dele'); }
check(!mm.enqueue('ranked_5min', E('x', 0, 0)) || !mm.enqueue('ranked_10min', E('x', 0, 0)), 'mesmo jogador não entra em duas filas');
// Partida: empate por tempo sem material, promoção, empate = 0 PL
const { RankedMatch } = require('../../online_v021/ranked/match');
const cfg = { baseMs: () => 1000, startDelayMs: 0, reconnectGraceMs: 60000 };
const P = (id, l, pl) => ({ userId: id, nickname: id, stats: S(l, pl), connected: true, leftAt: 0 });
let m = new RankedMatch({ mode: 'ranked_3min', white: P('w', 2, 40), black: P('b', 2, 40), now: 0, cfg });
m.tick(0); m.pos.board = { '4,7': 'wK', '4,0': 'bK', '3,0': 'bN' };
m.tick(1500); check(m.result.winner === 'draw' && m.result.reason === 'timeout_draw', 'tempo esgotado contra rei+cavalo sozinho = empate');
check(m.result.w.applied === 0 && m.result.b.applied === 0 && m.result.w.stats.draws === 1, 'empate: 0 PL para ambos');
m = new RankedMatch({ mode: 'ranked_5min', white: P('w', 0, 0), black: P('b', 0, 0), now: 0, cfg: { ...cfg, baseMs: () => 60000 } });
m.tick(0); m.pos.board = { '4,7': 'wK', '0,0': 'bK', '6,1': 'wP', '0,5': 'bP' }; m.pos.rights = '';
check(m.move('w', { from: [6,1], to: [6,0], promotion: 'N' }, 10).ok && m.pos.piece(6,0) === 'wN', 'promoção escolhida (cavalo) aceita pelo servidor');
check(m.pos.history[0] === 'g7g8n' && m.clock.active === 'b', 'lance registrado e relógio trocado após promoção');
// R143 · a Força é oculta: não sai no resultado para o cliente
{ const mm4 = new RankedMatch({ mode: 'ranked_3min', white: P('w', 3, 40), black: P('b', 3, 40), now: 0, cfg: { ...cfg, baseMs: () => 60000 } });
  mm4.tick(0); mm4.resign('b', 10);
  const res = mm4.resultFor('w', true), rec = mm4.record();
  check(res.stats && !('forca' in res.stats) && !('forca_rd' in res.stats) && !JSON.stringify(mm4.state('w', 20)).includes('forca'), 'Força não vai para o cliente (resultado e estado)');
  check(Number.isFinite(rec.white_forca_after) && Number.isFinite(rec.black_forca_rd_after), 'Força vai para a gravação no banco'); }
// R143 · vagas do Challenger de ponta a ponta no MemoryStore (Grão-Mestre 100 → Challenger; o banco é atualizado)
(async () => {
  const { MemoryStore } = require('../../online_v021/accounts/store');
  const { ChallengerLadder } = require('../../online_v021/ranked/challenger');
  const st = new MemoryStore();
  const put = (id, league, pl, forca) => { const all = {}; for (const m of ['ranked_3min','ranked_5min','ranked_10min','ranked_20min']) all[m] = { ...S(0, 0) };
    all.ranked_3min = { ...S(league, pl), matches: 40, wins: 30, losses: 10, highest_league: league, forca, forca_rd: 70, updated_at: new Date().toISOString() }; st.stats.set(id, all); };
  put('g1', GM, 100, 2100); put('g2', GM, 100, 2000); put('g3', GM, 80, 2300);
  const fake = { backend: { store: st }, activeMatchOf: () => null, persistPending: () => false, mm: { has: () => false }, pendingQueues: new Map() };
  const lad = new ChallengerLadder(fake, { log: { log() {}, error() {} } }); lad.stop();
  await lad.sync('ranked_3min');
  const g = id => st.stats.get(id).ranked_3min;
  check(g('g1').league === TOP && g('g1').pl === 0 && g('g1').highest_league === TOP && g('g2').league === TOP && g('g3').league === GM, 'MemoryStore: Grão-Mestres com 100 PL viram Challenger (vaga livre); 80 PL fica');
  check(!('forca' in (await st.getRankedStats('g1')).ranked_3min) && 'forca' in (await st.getRankedStats('g1', { forca: true })).ranked_3min, 'getRankedStats público sem Força; { forca: true } com Força');
  summary('RANKED_UNIT');
})();
