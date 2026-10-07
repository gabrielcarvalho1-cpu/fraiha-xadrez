'use strict';
const { check, summary } = require('./helpers.cjs');
const { points, applyResult } = require('../../online_v021/ranked/progression');
const { ChessClock } = require('../../online_v021/ranked/clock');
const { Matchmaker } = require('../../online_v021/ranked/matchmaker');
const S = (league, pl) => ({ league, pl, matches: 0, wins: 0, losses: 0, draws: 0, highest_league: league });
// Tabela de PL (R51: base +15/−10)
const table = [[60,20,-6],[100,20,-6],[30,18,-8],[59,18,-8],[0,15,-10],[29,15,-10],[-29,15,-10],[-30,12,-12],[-59,12,-12],[-60,10,-14],[-100,10,-14],[250,20,-6],[-250,10,-14]];
for (const [d, w, l] of table) check(points(d,'win') === w && points(d,'loss') === l, `diferença ${d}: vitória ${w}, derrota ${l}`);
check(points(40,'draw') === 0 && points(-80,'draw') === 0, 'empate = 0 PL');
let r = applyResult(S(0,96), S(0,96), 'win'); check(r.stats.league === 1 && r.stats.pl === 11 && r.promoted, 'Madeira 96 +15 → Ferro 11 (excedente)');
r = applyResult(S(0,96), S(1,60), 'win'); check(r.change === 20 && r.stats.league === 1 && r.stats.pl === 16, 'Madeira 96 +20 → Ferro 16');
r = applyResult(S(2,3), S(2,3), 'loss'); check(r.stats.pl === 0 && r.stats.league === 2 && r.applied === -3 && !r.demoted, 'derrota com PL > 0 para em 0 e a liga fica');
r = applyResult(S(2,0), S(2,0), 'loss'); check(r.stats.league === 1 && r.stats.pl === 75 && r.demoted && !r.promoted, 'R51: derrota com 0 PL rebaixa (Bronze 0 → Ferro 75)');
r = applyResult(S(1,0), S(0,50), 'loss'); check(r.stats.league === 0 && r.stats.pl === 75 && r.demoted && r.stats.highest_league === 1, 'R51: Ferro 0 perde → Madeira 75 (maior liga continua Ferro)');
r = applyResult(S(0,0), S(0,0), 'loss'); check(r.stats.league === 0 && r.stats.pl === 0 && !r.demoted, 'Madeira nunca rebaixa');
r = applyResult(S(2,0), S(2,0), 'draw'); check(r.stats.league === 2 && r.stats.pl === 0 && !r.demoted, 'empate com 0 PL não rebaixa');
r = applyResult(S(10,97), S(10,97), 'win'); check(r.stats.league === 10 && r.stats.pl === 100, 'Challenger fica limitado a 100 PL');
r = applyResult(S(4,50), S(4,50), 'draw'); check(r.stats.pl === 50 && r.stats.draws === 1 && r.stats.matches === 1, 'empate conta partida, 0 PL');
r = applyResult(S(1,10), S(1,10), 'win'); check(r.stats.wins === 1 && r.stats.highest_league === 1, 'vitória registrada');
// Relógio
const c = new ChessClock(300000); c.start('w', 1000);
check(c.snapshot(3000).w_ms === 298000 && c.snapshot(3000).b_ms === 300000 && c.active === 'w', 'Brancas começam com relógio ativo; Pretas paradas');
check(!c.press('b', 4000), 'jogada fora de turno não troca o relógio');
c.press('w', 5000); check(c.active === 'b' && c.snapshot(5000).w_ms === 296000, 'jogada legal das Brancas para o relógio delas e inicia o das Pretas');
check(c.snapshot(15000).b_ms === 290000 && c.snapshot(15000).w_ms === 296000, 'relógio das Pretas corre, Brancas paradas');
c.press('b', 15000); check(c.active === 'w', 'jogada das Pretas devolve o relógio às Brancas');
check(c.flagged(15000 + 296000) === 'w', 'queda de bandeira detectada em 00:00');
// Matchmaking
const mm = new Matchmaker({ initialPlWindow: 20, expandEveryMs: 10000, expandStep: 40, maxWindow: 1100 });
const E = (id, l, p, since = 0) => ({ userId: id, stats: S(l, p), since });
mm.enqueue('ranked_3min', E('a', 2, 50)); mm.enqueue('ranked_5min', E('b', 2, 50));
check(mm.tick(1000).length === 0, 'modalidades diferentes não se encontram');
mm.enqueue('ranked_3min', E('c', 2, 65)); let p = mm.tick(1000); check(p.length === 1 && p[0].mode === 'ranked_3min', 'mesma modalidade, mesma liga, ±20 PL se encontram');
mm.enqueue('ranked_5min', E('d', 3, 10)); check(mm.tick(1000).length === 0, 'liga diferente não pareia no início');
check(mm.tick(10500).length === 1, 'após espera, faixa ampliada pareia');
// R51 · faixa de ligas
{ const L = Matchmaker.leaguesOk;
  check(L(3,2) && L(3,4) && L(3,3) && !L(3,1) && !L(3,5), 'Prata joga com Bronze, Prata e Ouro (não com Ferro/Platina)');
  check(L(1,0) && L(1,2) && !L(1,3), 'Ferro joga com Madeira e Bronze');
  check(L(0,1) && L(0,2) && !L(0,3), 'Madeira joga com Ferro e Bronze (exceção), não com Prata');
  check(L(10,9) && !L(10,8), 'Challenger joga com Grande Mestre');
  const mm2 = new Matchmaker({ initialPlWindow: 20, expandEveryMs: 10000, expandStep: 40, maxWindow: 300 });
  mm2.enqueue('ranked_3min', E('p', 3, 50)); mm2.enqueue('ranked_3min', E('f', 1, 50));
  check(mm2.tick(600000).length === 0, 'mesmo esperando muito, Prata nunca pega Ferro');
  mm2.enqueue('ranked_3min', E('o', 4, 0)); check(mm2.tick(600000).length === 1, 'Prata pega Ouro depois de esperar');
  const mm3 = new Matchmaker({ initialPlWindow: 20, expandEveryMs: 10000, expandStep: 40, maxWindow: 300 });
  mm3.enqueue('ranked_3min', E('m', 0, 90)); mm3.enqueue('ranked_3min', E('b', 2, 10));
  check(mm3.tick(600000).length === 1, 'Madeira pega Bronze depois de esperar'); }
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
summary('RANKED_UNIT');
