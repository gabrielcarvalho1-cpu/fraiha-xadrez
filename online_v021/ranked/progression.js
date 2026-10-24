'use strict';
// Regras de PL/ligas: independentes de armazenamento e de rede.
//
// R143 · SISTEMA NOVO (aprovado pelo dono, simulação em docs/ranked/R143_LIGAS.md):
//   · FORÇA oculta (Glicko, a mesma matemática do chess.com): escolhe o adversário e corrige o PL.
//     Começa em 1200 com incerteza alta (350): as primeiras partidas mexem muito, depois estabiliza.
//   · PL visível que DIMINUI conforme a liga sobe (Madeira +20/−8 … Grão-Mestre +6/−6). Quem é mais forte
//     que a própria liga ganha mais e perde menos (sai rápido de onde não é o lugar dele); quem está acima
//     do próprio nível ganha menos e perde mais. Da Esmeralda para cima esse bônus é pequeno.
//   · Empate = meio ponto: rende PL contra alguém mais forte, custa contra alguém mais fraco.
//   · Grão-Mestre trava em 100 PL: o Challenger é só por VAGA (os melhores de cada ritmo, ranked/challenger.js).
const { LEAGUES } = require('./config');
const TOP = LEAGUES.length - 1;          // Challenger
const GM = TOP - 1;                      // Grão-Mestre
const rating = s => s.league * 100 + s.pl; // posição visível (liga*100+PL), nunca exibida assim

// PL base por liga [vitória, derrota]: contra alguém do seu nível, com a Força batendo com a liga.
const BASE = [[20, 8], [18, 9], [17, 10], [16, 11], [15, 12], [14, 12], [13, 13], [11, 11], [8, 8], [6, 6], [6, 6]];
const BONUS_UNTIL = 5;                   // até a Platina o bônus "melhor que a liga" vai até 1,8x; depois, 1,25x

// ---------------------------------------------------------------- FORÇA (Glicko-1)
const FORCA_START = 1200, RD_START = 350, RD_MIN = 50, RD_KNOWN = 200;
// Força que se espera de quem está numa posição (Madeira 0 PL = 750 … Grão-Mestre 100 PL = 1900)
const expectedForca = R => 750 + R * 1.15;
// Força guardada; sem ela (banco sem a 0020 ou conta antiga) estima pela liga atual.
function forcaOf(s) {
  const f = Number(s && s.forca), rd = Number(s && s.forca_rd);
  if (Number.isFinite(f) && f > 0) return { f, rd: Number.isFinite(rd) && rd > 0 ? rd : RD_KNOWN };
  if (s && s.matches > 0) return { f: Math.round(expectedForca(rating(s))), rd: RD_KNOWN };
  return { f: FORCA_START, rd: RD_START };
}
const Q = Math.log(10) / 400;
const gRd = rd => 1 / Math.sqrt(1 + 3 * Q * Q * rd * rd / (Math.PI * Math.PI));
const expected = (f, fo, rdo) => 1 / (1 + Math.pow(10, -gRd(rdo) * (f - fo) / 400));
// Uma partida: devolve a nova {f, rd}. score: 1 vitória, 0,5 empate, 0 derrota.
function glicko(me, opp, score) {
  const g = gRd(opp.rd), e = expected(me.f, opp.f, opp.rd);
  const d2 = 1 / (Q * Q * g * g * e * (1 - e));
  const inv = 1 / (me.rd * me.rd) + 1 / d2;
  return { f: me.f + (Q / inv) * g * (score - e), rd: Math.max(RD_MIN, Math.sqrt(1 / inv)) };
}

// ---------------------------------------------------------------- PL da partida
// me/opp: estatísticas (liga, PL, Força). Devolve a variação nominal de PL.
function points(me, opp, outcome) {
  const lg = Math.max(0, Math.min(TOP, me.league | 0));
  const [bw, bl] = BASE[lg];
  const mf = forcaOf(me), of = forcaOf(opp);
  const d = mf.f - expectedForca(rating(me));
  const cap = lg <= BONUS_UNTIL ? 1.8 : 1.25;
  const w = bw * Math.min(cap, Math.max(0.5, 1 + d / 350));
  const l = bl * Math.min(1.8, Math.max(0.5, 1 - d / 350));
  if (outcome === 'win') return Math.round(w);
  if (outcome === 'loss') return -Math.round(l);
  const e = 1 / (1 + Math.pow(10, (of.f - mf.f) / 400));   // empate: meio ponto contra a expectativa
  return Math.round((0.5 - e) * (w + l));
}

// R51 · rebaixamento: quem PERDE já estando com 0 PL volta para a liga de baixo com DEMOTE_PL.
// A derrota com PL > 0 só leva até 0 (a liga fica). Madeira nunca rebaixa. Challenger com 0 PL que perde
// volta ao Grão-Mestre (a vaga abre para o próximo).
const DEMOTE_PL = 75;

// Aplica o resultado a uma cópia das estatísticas (PL, liga e Força).
// R181 · { vsAI: true } (rival de IA da fila): METADE do PL; Força oculta e placar (partidas/V/D/E) intactos.
function applyResult(stats, opponent, outcome, { vsAI = false } = {}) {
  const raw = points(stats, opponent, outcome);
  const change = vsAI ? Math.sign(raw) * Math.round(Math.abs(raw) / 2) : raw;
  const s = { ...stats };
  let pl = s.pl + change, league = s.league;
  let demoted = false;
  if (outcome === 'loss' && s.pl === 0 && league > 0) { league -= 1; pl = DEMOTE_PL; demoted = true; }
  if (pl < 0) pl = 0;
  while (pl >= 100 && league < GM) { pl -= 100; league++; }
  if (league >= GM) pl = Math.min(pl, 100);      // Grão-Mestre e Challenger: até 100 PL (Challenger só por vaga)
  // Variação exibida: nominal, exceto quando o piso de 0 PL / o teto de 100 limitam (no rebaixamento: a nominal).
  let applied = demoted ? change : (change < 0 ? Math.max(change, -s.pl) : change);
  if (!demoted && league === stats.league && league >= GM) applied = pl - s.pl;
  const nf = glicko(forcaOf(stats), forcaOf(opponent), outcome === 'win' ? 1 : outcome === 'loss' ? 0 : 0.5);
  s.league = league; s.pl = pl;
  if (!vsAI) {
    s.forca = Math.round(nf.f * 10) / 10; s.forca_rd = Math.round(nf.rd * 10) / 10;
    s.matches += 1;
    if (outcome === 'win') s.wins += 1; else if (outcome === 'loss') s.losses += 1; else s.draws += 1;
  }
  s.highest_league = Math.max(s.highest_league, league);
  return { stats: s, change, applied, promoted: league > stats.league, demoted, challenger_candidate: league === GM && pl >= 100 };
}
module.exports = { points, applyResult, rating, forcaOf, glicko, expectedForca, BASE, TOP, GM, DEMOTE_PL, FORCA_START, RD_START };
