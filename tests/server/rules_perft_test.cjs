'use strict';
const { Position } = require('../../online_v021/chess_rules');
const { check, summary } = require('./helpers.cjs');
function fromFen(fen) {
  const [rows, turn, rights, ep] = fen.split(' ');
  const p = new Position(); p.board = {};
  rows.split('/').forEach((r, y) => { let x = 0; for (const ch of r) { if (/\d/.test(ch)) x += +ch; else { p.board[x + ',' + y] = (ch === ch.toUpperCase() ? 'w' : 'b') + ch.toUpperCase(); x++; } } });
  p.turn = turn; p.rights = rights === '-' ? '' : rights; p.ep = ep === '-' ? null : ['abcdefgh'.indexOf(ep[0]), 8 - +ep[1]];
  p.repetitions = {}; return p;
}
function perft(p, d) { if (d === 0) return 1; let n = 0; for (const m of p.legalMoves()) { const q = p.clone(); q.play(m); n += perft(q, d - 1); } return n; }
const start = new Position();
[[1,20],[2,400],[3,8902]].forEach(([d,n]) => check(perft(start,d) === n, `perft inicial ${d} = ${n}`));
const kiwi = fromFen('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -');
[[1,48],[2,2039]].forEach(([d,n]) => check(perft(kiwi,d) === n, `perft kiwipete (roque/promo) ${d} = ${n}`));
const p3 = fromFen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -');
[[1,14],[2,191],[3,2812]].forEach(([d,n]) => check(perft(p3,d) === n, `perft posição 3 (en passant) ${d} = ${n}`));
const p4 = fromFen('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq -');
[[1,6],[2,264],[3,9467]].forEach(([d,n]) => check(perft(p4,d) === n, `perft posição 4 (promoção/xeque) ${d} = ${n}`));
// canMate for flag-fall
check(!fromFen('8/8/8/4k3/8/8/8/4K3 w - -').canMate('w'), 'rei sozinho não pode vencer por tempo');
check(!fromFen('8/8/8/4k3/8/8/8/3NK3 w - -').canMate('w'), 'rei+cavalo contra rei sozinho não vence por tempo');
check(fromFen('8/8/8/4k3/8/8/8/3QK3 w - -').canMate('w'), 'rei+dama pode vencer por tempo');
check(fromFen('8/8/4p3/4k3/8/8/8/3NK3 w - -').canMate('w'), 'cavalo contra peão ainda pode dar mate (vence por tempo)');
summary('RULES_JS');
