'use strict';
// Regras de PL/ligas: independentes de armazenamento e de rede.
const { LEAGUES } = require('./config');
const TOP = LEAGUES.length - 1;
const rating = s => s.league * 100 + s.pl; // interno, nunca exibido

// diff = rating do adversário − meu rating (pré-partida, mesma modalidade).
// R51: base +15 / −10 (antes ±6: subir uma liga levava ~17 vitórias líquidas).
function points(diff, outcome) {
  if (outcome === 'draw') return 0;
  let band = [15, -10];
  if (diff >= 60) band = [20, -6];
  else if (diff >= 30) band = [18, -8];
  else if (diff <= -60) band = [10, -14];
  else if (diff <= -30) band = [12, -12];
  return outcome === 'win' ? band[0] : band[1];
}

// R51 · rebaixamento: quem PERDE já estando com 0 PL volta para a liga de baixo com DEMOTE_PL.
// A derrota com PL > 0 só leva até 0 (a liga fica). Madeira nunca rebaixa.
const DEMOTE_PL = 75;

// Aplica o resultado a uma cópia das estatísticas. Promoção carrega excedente.
function applyResult(stats, opponent, outcome) {
  const change = points(rating(opponent) - rating(stats), outcome);
  const s = { ...stats };
  let pl = s.pl + change, league = s.league;
  let demoted = false;
  if (outcome === 'loss' && s.pl === 0 && league > 0) { league -= 1; pl = DEMOTE_PL; demoted = true; }
  if (pl < 0) pl = 0;
  while (pl >= 100 && league < TOP) { pl -= 100; league++; }
  if (league === TOP) pl = Math.min(pl, 100);
  // Variação exibida: nominal, exceto quando o piso de 0 PL limita a perda (no rebaixamento: a nominal).
  const applied = demoted ? change : (change < 0 ? Math.max(change, -s.pl) : change);
  s.league = league; s.pl = pl;
  s.matches += 1;
  if (outcome === 'win') s.wins += 1; else if (outcome === 'loss') s.losses += 1; else s.draws += 1;
  s.highest_league = Math.max(s.highest_league, league);
  return { stats: s, change, applied, promoted: league > stats.league, demoted };
}
module.exports = { points, applyResult, rating, TOP, DEMOTE_PL };
