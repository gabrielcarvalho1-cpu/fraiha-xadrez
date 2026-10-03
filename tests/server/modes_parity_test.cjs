'use strict';
// R35 · O motor do SERVIDOR (online) tem de dar exatamente o mesmo resultado do motor do Godot.
// Fixture gerado pelo Godot: tools/marcha_parity_fixture.gd → tests/fixtures/marcha_parity.json.gz
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const { check, summary } = require('./helpers.cjs');
const { Marcha, chooseAI, RULESET_VERSION } = require('../../online_v021/modes/marcha_rules');
const fx = JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(__dirname, '../fixtures/marcha_parity.json.gz'))).toString());
const int = x => Math.trunc(Number(x));
const normPawns = ps => ps.map(r => r.map(p => ({ zone: p.zone, pos: int(p.pos) })));
const normMove = m => { const o = JSON.parse(JSON.stringify(m)); for (const k of ['card', 'steps', 'target_seat']) if (o[k] !== undefined) o[k] = int(o[k]); for (const k of ['pawn', 'target']) if (o[k]) o[k] = o[k].map(int); if (o.parts) o.parts = o.parts.map(p => ({ pawn: p.pawn.map(int), steps: int(p.steps) })); return o; };
const keys = list => list.map(m => Marcha.moveKey(normMove(m))).sort();
function load(st) {
  const g = new Marcha();
  g.pawns = normPawns(st.pawns); g.hands = st.hands.map(h => h.slice()); g.turn = int(st.turn); g.winner = int(st.winner); g.round_no = int(st.round_no);
  return g;
}
check(fx.ruleset === RULESET_VERSION, `mesma versão de regras (${fx.ruleset})`);
let legalBad = 0, aiBad = 0, applyBad = 0, evBad = 0, n = 0;
for (const step of fx.steps) {
  n++;
  const seat = int(step.seat);
  const g = load(step.state);
  for (let c = 0; c < step.legal.length; c++) {
    const a = keys(g.legalMoves(seat, c)), b = keys(step.legal[c]);
    if (JSON.stringify(a) !== JSON.stringify(b)) { if (legalBad++ < 3) console.log('legal diff', n, c, a.length, b.length); }
  }
  const ai = chooseAI(g, seat, null);
  if (Marcha.moveKey(ai) !== Marcha.moveKey(normMove(step.ai))) { if (aiBad++ < 3) console.log('ai diff', n, Marcha.moveKey(ai), Marcha.moveKey(normMove(step.ai))); }
  const mv = normMove(step.move);
  const ev = g.apply(seat, mv, int(step.burn_pick) >= 0 ? int(step.burn_pick) : undefined);
  const after = step.after;
  if (JSON.stringify(normPawns(after.pawns)) !== JSON.stringify(g.pawns) || JSON.stringify(after.hands) !== JSON.stringify(g.hands) || int(after.winner) !== g.winner) { if (applyBad++ < 3) console.log('apply diff', n, JSON.stringify(mv)); }
  const evN = e => JSON.stringify(e.map(x => ({ type: x.type, pawn: x.pawn ? x.pawn.map(int) : undefined, seat: x.seat !== undefined ? int(x.seat) : undefined, rank: x.rank, path: x.path ? x.path.map(p => [p.zone, int(p.pos)]) : undefined })));
  if (evN(ev) !== evN(step.events)) { if (evBad++ < 3) console.log('events diff', n, evN(ev), evN(step.events)); }
}
check(n > 3000, `${n} posições do Godot conferidas`);
check(legalBad === 0, `jogadas legais idênticas carta a carta (${legalBad} diferenças)`);
check(aiBad === 0, `bot escolhe o mesmo lance que no Godot (${aiBad} diferenças)`);
check(applyBad === 0, `aplicar a jogada dá o mesmo tabuleiro, mãos e vencedor (${applyBad} diferenças)`);
check(evBad === 0, `mesmos eventos de animação (${evBad} diferenças)`);

// ---------- XEQUE ----------
const X = require('../../online_v021/modes/xeque_rules');
const xf = JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(__dirname, '../fixtures/xeque_parity.json.gz'))).toString());
check(xf.ruleset === X.RULESET_VERSION, `XEQUE: mesma versão de regras (${xf.ruleset})`);
const ints = a => a.map(int);
function xload(b) {
  const g = new X.Xeque();
  g.names = b.names.slice(); g.state = b.state; g.round_no = int(b.round_no); g.target = b.target; g.turn = int(b.turn);
  g.lives = ints(b.lives); g.hands = b.hands.map(h => h.slice()); g.clocks = b.clocks.map(c => c.slice()); g.clock_cycles = ints(b.clock_cycles);
  g.plays = b.plays.map(p => ({ seat: int(p.seat), cards: p.cards.slice(), count: int(p.count) }));
  g.last_play = b.last_play && b.last_play.seat !== undefined ? { seat: int(b.last_play.seat), cards: b.last_play.cards.slice(), count: int(b.last_play.count) } : null;
  g.winner = int(b.winner); g.eliminated_round = ints(b.eliminated_round); g.finish_order = ints(b.finish_order);
  g.reveals = b.reveals.map(r => ({ seat: int(r.seat), cards: r.cards.slice(), target: r.target, truthful: !!r.truthful, round: int(r.round) }));
  g.public_log = b.public_log.slice(); g.next_starter = int(b.next_starter);
  return g;
}
let xn = 0, pBad = 0, rBad = 0, aBad = 0, pubBad = 0;
for (const st of xf.steps) {
  xn++;
  const seat = int(st.seat), g = xload(st.before);
  const pub = g.publicState(seat);
  const gp = st.pub;
  const pubSame = JSON.stringify([pub.state, pub.round, pub.target, pub.turn, pub.lives, pub.hand_counts, pub.clock_left, pub.last_play.seat === undefined ? -1 : pub.last_play.seat, pub.can_challenge]) ===
    JSON.stringify([gp.state, int(gp.round), gp.target, int(gp.turn), ints(gp.lives), ints(gp.hand_counts), ints(gp.clock_left), gp.last_play && gp.last_play.seat !== undefined ? int(gp.last_play.seat) : -1, !!gp.can_challenge]);
  if (!pubSame) pubBad++;
  const p = X.pLastPlayTrue(pub, g.hands[seat]);
  if (Math.abs(p - Number(st.p_true)) > 1e-9) { if (pBad++ < 3) console.log('p diff', xn, p, st.p_true); }
  const act = st.action;
  const res = act.action === 'challenge' ? g.challenge(seat) : g.play(seat, ints(act.idx));
  const r = st.result;
  const resKey = o => !o ? 'null' : JSON.stringify(o.caller !== undefined
    ? [int(o.caller), int(o.accused), o.cards, !!o.truthful, int(o.loser), o.clock, !!o.mate, !!o.eliminated, int(o.winner), int(o.next_starter)]
    : [int(o.seat), int(o.count), o.declared, o.forced ? [int(o.forced.loser), o.forced.clock, !!o.forced.mate, int(o.forced.winner)] : null]);
  if (resKey(res) !== resKey(r)) { if (rBad++ < 3) console.log('result diff', xn, resKey(res), resKey(r)); }
  const a = st.after;
  const mateNow = (res && (res.mate || (res.forced && res.forced.mate)));
  const clocksKey = c => JSON.stringify(mateNow ? c.map(x => x.length) : c);
  const afterKey = (o, cl) => JSON.stringify([o.state, int(o.turn), ints(o.lives), o.hands, int(o.winner), ints(o.eliminated_round), ints(o.finish_order), o.public_log, int(o.next_starter)]) + clocksKey(cl);
  if (afterKey(a, a.clocks) !== afterKey({ ...g, turn: g.turn, lives: g.lives }, g.clocks)) { if (aBad++ < 3) console.log('after diff', xn); }
}
check(xn > 3000, `XEQUE: ${xn} ações do Godot conferidas`);
check(pubBad === 0, `XEQUE: estado público igual (${pubBad} diferenças)`);
check(pBad === 0, `XEQUE: estimativa do bot igual (${pBad} diferenças)`);
check(rBad === 0, `XEQUE: jogar / XEQUE dão o mesmo resultado (relógio, eliminação, vencedor) (${rBad} diferenças)`);
check(aBad === 0, `XEQUE: estado depois da ação igual (${aBad} diferenças)`);
summary('MODES_PARITY');
