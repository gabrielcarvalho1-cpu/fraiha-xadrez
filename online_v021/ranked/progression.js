'use strict';
// Regras de PL/ligas: independentes de armazenamento e de rede.
const { LEAGUES } = require('./config');
const TOP = LEAGUES.length - 1;
const rating = s => s.league * 100 + s.pl; // interno, nunca exibido

// diff = PL do adversário − meu PL (pré-partida, mesma modalidade).
function points(diff, outcome) {
  if (outcome === 'draw') return 0;
  let band = [6, -6];
  if (diff >= 60) band = [10, -3];
  else if (diff >= 30) band = [8, -4];
  else if (diff <= -60) band = [3, -10];
  else if (diff <= -30) band = [4, -8];
  return outcome === 'win' ? band[0] : band[1];
}

// Aplica o resultado a uma cópia das estatísticas. Promoção carrega excedente;
// sem rebaixamento; PL nunca abaixo de 0.
function applyResult(stats, opponent, outcome) {
  const change = points(rating(opponent) - rating(stats), outcome);
  const s = { ...stats };
  let pl = s.pl + change, league = s.league;
  if (pl < 0) pl = 0;
  while (pl >= 100 && league < TOP) { pl -= 100; league++; }
  if (league === TOP) pl = Math.min(pl, 100);
  // Variação exibida: nominal, exceto quando o piso de 0 PL limita a perda.
  const applied = change < 0 ? Math.max(change, -s.pl) : change;
  s.league = league; s.pl = pl;
  s.matches += 1;
  if (outcome === 'win') s.wins += 1; else if (outcome === 'loss') s.losses += 1; else s.draws += 1;
  s.highest_league = Math.max(s.highest_league, league);
  return { stats: s, change, applied, promoted: league > stats.league };
}
module.exports = { points, applyResult, rating, TOP };
