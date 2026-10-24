'use strict';
// R181 · calibração do RIVAL DE IA da fila contra o Stockfish do jogo com UCI_LimitStrength (âncora, padrão 1320 =
// o mínimo do Stockfish). Usa EXATAMENTE a lógica de lance do servidor (ranked/queue_ai.js → pickMove).
// Uso: node tools/calibrar_rival_ia.js <liga 0..10 | JSON do nível> [partidas=40] [elo_âncora=1320] [ms_âncora=100]
// Saída: pontuação e Elo estimado = âncora + 400·log10(p/(1−p)).
const { Position } = require('../chess_rules');
const { UciEngine } = require('../bots/engine');
const { LEVELS, pickMove } = require('../ranked/queue_ai');
const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const sq = ([x, y]) => 'abcdefgh'[x] + (8 - y);

async function main() {
  const arg = process.argv[2] || '0';
  const level = /^\d+$/.test(arg) ? LEVELS[Number(arg)] : JSON.parse(arg);
  const games = Number(process.argv[3] || 40), anchorElo = Number(process.argv[4] || 1320), anchorMs = Number(process.argv[5] || 100);
  const cand = new UciEngine({ timeoutMs: 20000 }), anchor = new UciEngine({ timeoutMs: 20000 });
  await cand.init(); await anchor.init({ UCI_LimitStrength: 'true', UCI_Elo: anchorElo });
  let score = 0, w = 0, d = 0, l = 0;
  for (let g = 0; g < games; g++) {
    const pos = new Position(), candColor = g % 2 === 0 ? 'w' : 'b';
    let out = null;
    while (!out && pos.ply < 220) {
      let mv;
      if (pos.turn === candColor) mv = (await pickMove(cand, pos, level)).move;
      else {
        const r = await anchor.analyse(START, { movetime: anchorMs, moves: pos.history });
        mv = pos.legalMoves().find(m => sq(m.from) + sq(m.to) === r.best.slice(0, 4) && (r.best.length < 5 || m.promotion === r.best[4].toUpperCase()));
      }
      if (!mv) break;
      pos.play(mv);
      out = pos.outcome();
    }
    // xeque-mate: quem jogou por último venceu
    if (out === 'checkmate') { const winner = pos.turn === 'w' ? 'b' : 'w'; if (winner === candColor) { score += 1; w++; } else l++; }
    else { score += 0.5; d++; }
  }
  cand.stop(); anchor.stop();
  const p = Math.min(0.99, Math.max(0.01, score / games));
  const elo = Math.round(anchorElo + 400 * Math.log10(p / (1 - p)));
  console.log(JSON.stringify({ level, games, w, d, l, score, pct: Math.round(p * 1000) / 10, anchor: anchorElo, elo }));
}
main().catch(e => { console.error(e); process.exit(1); });
