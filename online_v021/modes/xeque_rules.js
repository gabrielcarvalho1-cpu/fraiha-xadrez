'use strict';
// XEQUE — motor de regras do SERVIDOR (partidas online). Porta 1:1 de xeque/rules.gd (ruleset 1) e
// de xeque/ai.gd. A IA recebe só o estado público + a própria mão (igual ao Godot).
const { rngFrom } = require('./rng');

const MODE_ID = 'xeque', RULESET_VERSION = '2';   // R36: relógio com chance crescente por nível
const KING = 'rei', QUEEN = 'rainha', KNIGHT = 'cavalo', JOKER = 'peao';
const TARGETS = [KING, QUEEN, KNIGHT];
const DECK_COUNTS = { [KING]: 6, [QUEEN]: 6, [KNIGHT]: 6, [JOKER]: 2 };
const SEATS = 4, LIVES = 1, HAND = 5, MAX_PLAY = 3, CLOCK_SLOTS = 6;
const SAFE = 'safe', MATE = 'mate', PENDING = '?';
const CLOCK_CHANCES = [0.12, 0.20, 0.30, 0.45, 0.65, 1.0];   // chance de estourar em cada nível (1º … 6º)
const NAMES = { [KING]: 'Rei', [QUEEN]: 'Rainha', [KNIGHT]: 'Cavalo', [JOKER]: 'Peão Coroado' };
const PLURAL = { [KING]: 'Reis', [QUEEN]: 'Rainhas', [KNIGHT]: 'Cavalos', [JOKER]: 'Peões Coroados' };
const S = { SETUP: 'SETUP', ROUND_START: 'ROUND_START', TURN_WAITING: 'TURN_WAITING', CARDS_PLAYED: 'CARDS_PLAYED', CHALLENGE: 'CHALLENGE', REVEAL: 'REVEAL', CLOCK_RESOLUTION: 'CLOCK_RESOLUTION', CHECKMATE: 'CHECKMATE', ROUND_END: 'ROUND_END', MATCH_END: 'MATCH_END' };
const isTrueCard = (card, target) => card === target || card === JOKER;
const cap = s => s.split(' ').map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(' ');   // como String.capitalize() do Godot

class Xeque {
  constructor(rng) { this.rng = rng || rngFrom(0); this.state = S.SETUP; this.names = ['Você', 'Dama de Ferro', 'Sir Gambito', 'Torre Velha']; }
  setup(names) {
    if (names && names.length === SEATS) this.names = names.slice();
    this.lives = []; this.hands = []; this.clocks = []; this.clock_cycles = []; this.eliminated_round = [];
    for (let s = 0; s < SEATS; s++) { this.lives.push(LIVES); this.hands.push([]); this.clocks.push([]); this.clock_cycles.push(0); this.eliminated_round.push(-1); this.resetClock(s); }
    this.finish_order = []; this.public_log = []; this.reveals = []; this.winner = -1; this.round_no = 0;
    this.state = S.SETUP;
    this.startRound(this.rng.int(0, SEATS - 1));
  }
  resetClock(seat) {
    const c = []; for (let i = 0; i < CLOCK_SLOTS; i++) c.push(PENDING);
    this.clocks[seat] = c; this.clock_cycles[seat] += 1;
  }
  clockLeft(seat) { return this.clocks[seat].length; }
  clockLevel(seat) { return Math.min(CLOCK_SLOTS - 1, Math.max(0, CLOCK_SLOTS - this.clocks[seat].length)); }
  clockChance(seat) { return CLOCK_CHANCES[this.clockLevel(seat)]; }
  // aciona o relógio: sorteia com a chance do nível e consome o nível (nextRoll: só testes de paridade)
  pullClock(seat) {
    const chance = this.clockChance(seat);
    const slot = this.clocks[seat].shift();
    if (slot === SAFE || slot === MATE) { this.last_roll = -1; return slot; }
    const roll = this.nextRoll !== undefined ? this.nextRoll : this.rng.float();
    this.nextRoll = undefined;
    this.last_roll = roll;
    return roll < chance ? MATE : SAFE;
  }
  alive(seat) { return this.lives[seat] > 0; }
  aliveSeats() { const o = []; for (let s = 0; s < SEATS; s++) if (this.alive(s)) o.push(s); return o; }
  withCards() { const o = []; for (let s = 0; s < SEATS; s++) if (this.alive(s) && this.hands[s].length) o.push(s); return o; }
  nextSeat(seat, needCards = false) {
    for (let k = 1; k <= SEATS; k++) { const s = (seat + k) % SEATS; if (!this.alive(s)) continue; if (needCards && !this.hands[s].length) continue; return s; }
    return -1;
  }
  canChallenge(seat) { return this.state === S.TURN_WAITING && seat === this.turn && !!this.last_play && this.last_play.seat !== seat; }
  canPlay(seat, idx) {
    if (this.state !== S.TURN_WAITING || seat !== this.turn || !this.alive(seat)) return false;
    if (!Array.isArray(idx) || idx.length < 1 || idx.length > MAX_PLAY) return false;
    const seen = new Set();
    for (const i of idx) { const n = Number(i); if (!Number.isInteger(n) || n < 0 || n >= this.hands[seat].length || seen.has(n)) return false; seen.add(n); }
    return true;
  }
  declaredText(count, target) { const t = target || this.target; return `${count} ${(count === 1 ? NAMES[t] : PLURAL[t]).toUpperCase()}`; }
  startRound(starter) {
    this.state = S.ROUND_START;
    this.round_no += 1;
    const deck = [];
    for (const c of Object.keys(DECK_COUNTS)) for (let i = 0; i < DECK_COUNTS[c]; i++) deck.push(c);
    for (let i = deck.length - 1; i > 0; i--) { const j = this.rng.int(0, i); const t = deck[i]; deck[i] = deck[j]; deck[j] = t; }
    for (let s = 0; s < SEATS; s++) { this.hands[s] = []; if (!this.alive(s)) continue; for (let k = 0; k < HAND; k++) this.hands[s].push(deck.pop()); }
    this.target = TARGETS[this.rng.int(0, TARGETS.length - 1)];
    this.plays = []; this.last_play = null; this.last_result = null;
    this.turn = this.alive(starter) ? starter : this.nextSeat(starter);
    this.public_log.push(`Rodada ${this.round_no} · a mesa pede ${NAMES[this.target].toUpperCase()}`);
    this.state = S.TURN_WAITING;
  }
  nextRound() { if (this.state !== S.ROUND_END) return false; this.startRound(this.next_starter); return true; }
  play(seat, idx) {
    if (!this.canPlay(seat, idx)) return null;
    const order = idx.map(Number).sort((a, b) => a - b);
    const cards = [];
    for (let i = order.length - 1; i >= 0; i--) { cards.unshift(this.hands[seat][order[i]]); this.hands[seat].splice(order[i], 1); }
    this.last_play = { seat, cards, count: cards.length };
    this.plays.push(this.last_play);
    this.state = S.CARDS_PLAYED;
    this.public_log.push(`${this.names[seat]} disse ${cap(this.declaredText(cards.length))}`);
    const pub = { seat, count: cards.length, declared: this.declaredText(cards.length) };
    if (this.withCards().length <= 1) {
      const caller = this.nextSeat(seat);
      this.state = S.TURN_WAITING; this.turn = caller;
      pub.forced = this.resolveChallenge(caller, true);
      return pub;
    }
    this.turn = this.nextSeat(seat, true);
    this.state = S.TURN_WAITING;
    return pub;
  }
  timeoutAction(seat) {
    if (this.state !== S.TURN_WAITING || seat !== this.turn || !this.hands[seat].length) return null;
    return this.play(seat, [this.rng.int(0, this.hands[seat].length - 1)]);
  }
  challenge(seat) { if (!this.canChallenge(seat)) return null; return this.resolveChallenge(seat, false); }
  resolveChallenge(caller, forced) {
    this.state = S.CHALLENGE;
    const accused = this.last_play.seat, cards = this.last_play.cards.slice();
    this.state = S.REVEAL;
    let truthful = true; const falseCards = [];
    for (const c of cards) if (!isTrueCard(c, this.target)) { truthful = false; falseCards.push(c); }
    const loser = truthful ? caller : accused;
    this.reveals.push({ seat: accused, cards, target: this.target, truthful, round: this.round_no });
    this.public_log.push(`XEQUE de ${this.names[caller]}: ${truthful ? 'VERDADE' : 'BLEFE'}`);
    this.state = S.CLOCK_RESOLUTION;
    const leftBefore = this.clockLeft(loser);
    const chanceBefore = this.clockChance(loser);
    const pulled = this.pullClock(loser);
    const mate = pulled === MATE;
    let lostCrown = false, eliminated = false;
    if (mate) {
      this.state = S.CHECKMATE;
      this.lives[loser] -= 1; lostCrown = true; this.resetClock(loser);
      this.public_log.push(`XEQUE-MATE em ${this.names[loser]}`);
      if (this.lives[loser] <= 0) { eliminated = true; this.eliminated_round[loser] = this.round_no; this.finish_order.push(loser); this.hands[loser] = []; }
    } else this.public_log.push(`${this.names[loser]} sobreviveu ao relógio`);
    const aliveNow = this.aliveSeats();
    if (aliveNow.length === 1) { this.winner = aliveNow[0]; this.next_starter = -1; this.state = S.MATCH_END; }
    else { this.next_starter = this.alive(loser) ? loser : this.nextSeat(loser); this.state = S.ROUND_END; }
    this.last_result = { caller, accused, cards, target: this.target, truthful, false_cards: falseCards, loser, forced, clock_left_before: leftBefore, chance: chanceBefore, roll: this.last_roll, clock: pulled, mate, lost_crown: lostCrown, lives_after: this.lives[loser], eliminated, winner: this.winner, next_starter: this.next_starter, round: this.round_no };
    return this.last_result;
  }
  publicState(viewer = -1) {
    return {
      viewer, state: this.state, round: this.round_no, target: this.target, turn: this.turn,
      lives: this.lives.slice(), hand_counts: this.hands.map(h => h.length), clock_left: this.clocks.map(c => c.length),
      last_play: this.last_play ? { seat: this.last_play.seat, count: this.last_play.count } : {},
      plays_this_round: this.plays.map(p => ({ seat: p.seat, count: p.count })),
      reveals: this.reveals.map(r => ({ ...r, cards: r.cards.slice() })), names: this.names.slice(), winner: this.winner,
      eliminated_round: this.eliminated_round.slice(), deck_counts: { ...DECK_COUNTS },
      can_challenge: viewer >= 0 && this.canChallenge(viewer),
    };
  }
  placement(seat) { if (seat === this.winner) return 1; const i = this.finish_order.indexOf(seat); return i < 0 ? 0 : SEATS - i; }
}

// ---------- bots ----------
const PROFILES = {
  cauteloso: { truth: 0.92, mix: 0.04, max_false: 1, threshold: 0.68, noise: 0.08, many_true: 0.35 },
  equilibrado: { truth: 0.70, mix: 0.20, max_false: 2, threshold: 0.55, noise: 0.12, many_true: 0.55 },
  blefador: { truth: 0.42, mix: 0.30, max_false: 3, threshold: 0.42, noise: 0.16, many_true: 0.70 },
};
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
function pLastPlayTrue(pub, hand) {
  const lp = pub.last_play || {};
  if (lp.seat === undefined) return 1.0;
  const deck = pub.deck_counts, target = pub.target;
  const totalTrue = deck[target] + deck[JOKER];
  let totalCards = 0; for (const c of Object.keys(deck)) totalCards += deck[c];
  let mineTrue = 0; for (const c of hand) if (isTrueCard(c, target)) mineTrue++;
  let dealt = 0; for (const n of pub.hand_counts) dealt += n; for (const p of pub.plays_this_round) dealt += p.count;
  const unknown = Math.max(1, dealt - hand.length);
  const trueUnknown = Math.max(0, totalTrue - mineTrue);
  const pool = Math.max(unknown, totalCards - hand.length);
  const k = lp.count;
  if (trueUnknown < k) return 0.0;
  let p = 1.0;
  for (let i = 0; i < k; i++) p *= (trueUnknown - i) / (pool - i);
  let priorHonest = 0.55; const seat = lp.seat;
  let seen = 0, bluffs = 0;
  for (const r of pub.reveals) if (r.seat === seat) { seen++; if (!r.truthful) bluffs++; }
  if (seen > 0) priorHonest = clamp(0.55 + 0.25 * ((seen - bluffs) / seen - 0.5), 0.3, 0.8);
  const before = pub.hand_counts[seat] + k;
  const reach = clamp(before / 5.0, 0.4, 1.0);
  return clamp(p + (1.0 - p) * priorHonest * reach * (k >= 3 ? 0.85 : 1.0) * (k === 2 ? 0.75 : 1.0), 0, 1);
}
function decide(pub, hand, profile, rng) {
  const pr = PROFILES[profile] || PROFILES.equilibrado;
  const me = pub.viewer, lp = pub.last_play || {};
  if (pub.can_challenge && lp.seat !== undefined) {
    const suspicion = 1.0 - pLastPlayTrue(pub, hand);
    const myLeft = pub.clock_left[me], theirLeft = pub.clock_left[lp.seat];
    let need = pr.threshold;
    if (myLeft <= 2) need += myLeft === 1 ? 0.12 : 0.06;
    if (theirLeft <= 2) need -= 0.05;
    if (!hand.length) need -= 1.0;
    if (pub.hand_counts[lp.seat] === 0) need -= 0.08;
    if (suspicion + rng.range(-pr.noise, pr.noise) >= need) return { action: 'challenge' };
  }
  if (!hand.length) return { action: 'challenge' };
  return { action: 'play', idx: chooseCards(pub, hand, pr, rng) };
}
function chooseCards(pub, hand, pr, rng) {
  const target = pub.target; const trues = [], falses = [];
  for (let i = 0; i < hand.length; i++) { if (hand[i] === target) trues.unshift(i); else if (hand[i] === JOKER) trues.push(i); else falses.push(i); }
  const roll = rng.float(); let out = [];
  if (trues.length && roll < pr.truth) {
    let n = 1;
    if (trues.length >= 2 && rng.float() < pr.many_true) n = 2;
    if (trues.length >= 3 && rng.float() < pr.many_true * 0.5) n = 3;
    out = trues.slice(0, n);
  } else if (trues.length && falses.length && roll < pr.truth + pr.mix) {
    out = [trues[0], falses[rng.int(0, falses.length - 1)]];
  } else if (falses.length) {
    let n = 1; const maxf = Math.min(pr.max_false, falses.length);
    if (maxf >= 2 && rng.float() < 0.45) n = 2;
    if (maxf >= 3 && rng.float() < 0.35) n = 3;
    for (let i = falses.length - 1; i > 0; i--) { const j = rng.int(0, i); const t = falses[i]; falses[i] = falses[j]; falses[j] = t; }
    out = falses.slice(0, n);
  } else out = trues.slice(0, 1);
  out = out.slice(0, Math.min(MAX_PLAY, hand.length));
  if (!out.length) out = [0];
  return out;
}

module.exports = { Xeque, decide, pLastPlayTrue, PROFILES, S, MODE_ID, RULESET_VERSION, SEATS, MAX_PLAY, isTrueCard, CLOCK_CHANCES };
