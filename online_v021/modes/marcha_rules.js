'use strict';
// MARCHA REAL — motor de regras do SERVIDOR (partidas online). Porta 1:1 de marcha/rules.gd
// (ruleset marcha-real-3). A paridade com o GDScript é conferida por tests/server/modes_parity_test.cjs
// com posições geradas pelo próprio Godot (tests/fixtures/marcha_parity.json).
// Mudou regra no .gd → muda aqui também e regenera o fixture (tools/marcha_parity_fixture.gd).
const { rngFrom } = require('./rng');

const RULESET_VERSION = 'marcha-real-10';  // R51: distribuição garante Ás/Rei para quem tem peão no Pátio
const TRACK = 76;
const ARM = 19;
const RANKS = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2'];
const ACE_STEPS = [11, 1];
const STEPS = { A: 11, Q: 12, '10': 10, '9': 9, '8': 8, '7': 7, '6': 6, '5': 5, '4': -4, '3': 3, '2': 2 };
const DEAL_CYCLE = [4, 4, 5], COPIES = 4;   // R38.3: 52 cartas (4 de cada), ciclos 4 → 4 → 5; fim do ciclo = baralho novo
const posmod = (a, n) => ((a % n) + n) % n;
const gateIndex = seat => seat * ARM;
const entranceIndex = seat => posmod(seat * ARM - 2, TRACK);
const teamOf = seat => seat % 2;
const partnerOf = seat => (seat + 2) % 4;
const sameW = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

class Marcha {
  constructor(rng) { this.rng = rng || rngFrom(0); this.pawns = []; this.hands = [[], [], [], []]; this.deck = []; this.discard = []; this.turn = 0; this.round_no = 1; this.winner = -1; this.log = []; this.names = ['Marfim', 'Rubi', 'Ônix', 'Esmeralda']; }

  setup() {
    this.pawns = [];
    for (let s = 0; s < 4; s++) { const row = []; for (let i = 0; i < 4; i++) row.push({ zone: 'home', pos: i }); this.pawns.push(row); }
    this.newDeck();
    this.hands = [[], [], [], []];
    this.turn = 0; this.round_no = 1; this.winner = -1; this.log = [];
    this.deal();
  }
  shuffle(a) { for (let i = a.length - 1; i > 0; i--) { const j = this.rng.int(0, i); const t = a[i]; a[i] = a[j]; a[j] = t; } }
  newDeck() {
    this.deck = []; this.discard = [];
    for (const r of RANKS) for (let c = 0; c < COPIES; c++) this.deck.push(r);
    this.shuffle(this.deck);
  }
  static handSizeFor(round) { return DEAL_CYCLE[(round - 1) % DEAL_CYCLE.length]; }
  deckCycle() { return Math.floor((this.round_no - 1) / DEAL_CYCLE.length) + 1; }
  deal() {
    if ((this.round_no - 1) % DEAL_CYCLE.length === 0 && this.round_no > 1) this.newDeck();
    const n = Marcha.handSizeFor(this.round_no);
    for (let s = 0; s < 4; s++) for (let k = 0; k < n; k++) {
      if (!this.deck.length) break;
      this.hands[s].push(this.deck.pop());
    }
    this.ensureStarters();
  }
  // R51 · quem tem peão no Pátio e nenhuma carta de saída (Ás/Rei) troca a ÚLTIMA carta da mão por uma de saída:
  // primeiro do monte, senão de um reino com 2+ cartas de saída ou que não precise. 52 cartas, 4 de cada (igual ao .gd).
  static starterCount(h) { return h.filter(r => r === 'A' || r === 'K').length; }
  inHome(seat) { return this.pawns[seat].filter(p => p.zone === 'home').length; }
  needsStarter(s) { return this.inHome(this.controlled(s)) > 0 && Marcha.starterCount(this.hands[s]) === 0 && this.hands[s].length > 0; }
  ensureStarters() {
    const isS = r => r === 'A' || r === 'K';
    for (let s = 0; s < 4; s++) {
      if (!this.needsStarter(s)) continue;
      const h = this.hands[s], give = h[h.length - 1];
      let got = false;
      for (let d = this.deck.length - 1; d >= 0; d--) if (isS(this.deck[d])) { h[h.length - 1] = this.deck[d]; this.deck[d] = give; got = true; break; }
      if (got) continue;
      for (const o of [1, 2, 3]) {
        const t = (s + o) % 4, c = Marcha.starterCount(this.hands[t]);
        if (c === 0 || (c === 1 && this.inHome(this.controlled(t)) > 0)) continue;
        const ht = this.hands[t];
        for (let k = ht.length - 1; k >= 0; k--) if (isS(ht[k])) { h[h.length - 1] = ht[k]; ht[k] = give; got = true; break; }
        if (got) break;
      }
    }
  }

  // ---------- consultas ----------
  crowned(seat) { return this.pawns[seat].filter(p => p.zone === 'lane').length; }
  teamCrowned(team) { return this.crowned(team) + this.crowned(team + 2); }
  controlled(seat) { return this.crowned(seat) === 4 ? partnerOf(seat) : seat; }
  occupant(abs) { for (let s = 0; s < 4; s++) for (let i = 0; i < 4; i++) { const p = this.pawns[s][i]; if (p.zone === 'track' && p.pos === abs) return [s, i]; } return []; }
  protectedAt(abs) { const o = this.occupant(abs); return o.length > 0 && gateIndex(o[0]) === abs; }
  enemyAt(seat, abs) { const o = this.occupant(abs); return o.length > 0 && teamOf(o[0]) !== teamOf(seat); }

  // enter=false: passa da Entrada e segue na Muralha (peça adversária andando pelo 5 da outra dupla)
  forwardPath(seat, i, steps, enter = true) {
    const p = this.pawns[seat][i];
    let zone = p.zone, pos = p.pos;
    const path = [];
    if (zone === 'home') return { ok: false };
    for (let k = 0; k < steps; k++) {
      if (zone === 'track') {
        if (pos === entranceIndex(seat) && enter) {
          if (this.enemyAt(seat, pos)) return { ok: false };   // inimigo na Entrada tranca o Salão
          zone = 'lane'; pos = 0;
        } else {
          pos = posmod(pos + 1, TRACK);
          if (this.protectedAt(pos) && !sameW(this.occupant(pos), [seat, i])) return { ok: false };
        }
      } else {
        pos += 1;
        if (pos > 3) return { ok: false };
      }
      if (zone === 'lane' && this.laneTaken(seat, pos, i)) return { ok: false };
      path.push({ zone, pos });
    }
    return this.landing(seat, i, path);
  }
  backwardPath(seat, i, steps) {
    const p = this.pawns[seat][i];
    if (p.zone !== 'track') return { ok: false };
    let pos = p.pos; const path = [];
    for (let k = 0; k < steps; k++) {
      pos = posmod(pos - 1, TRACK);
      if (this.protectedAt(pos)) return { ok: false };
      path.push({ zone: 'track', pos });
    }
    return this.landing(seat, i, path);
  }
  laneTaken(seat, k, exceptI) { for (let j = 0; j < 4; j++) if (j !== exceptI && this.pawns[seat][j].zone === 'lane' && this.pawns[seat][j].pos === k) return true; return false; }
  landing(seat, i, path) {
    if (!path.length) return { ok: false };
    const end = path[path.length - 1];
    if (end.zone === 'track') {
      const o = this.occupant(end.pos);
      if (o.length) { if (o[0] === seat) return { ok: false }; if (gateIndex(o[0]) === end.pos) return { ok: false }; }
    }
    return { ok: true, path, end };
  }

  // ---------- jogadas legais ----------
  legalMoves(seat, cardIdx) {
    const out = [];
    if (cardIdx < 0 || cardIdx >= this.hands[seat].length) return out;
    const rank = this.hands[seat][cardIdx];
    const who = this.controlled(seat);
    switch (rank) {
      case 'A': case 'K':
        for (const ex of this.exitMoves(who)) out.push({ ...ex, card: cardIdx, rank });
        if (rank === 'A') for (const n of ACE_STEPS) out.push(...this.forwardMoves(who, cardIdx, rank, n));
        break;
      case '4':
        for (let i = 0; i < 4; i++) if (this.pawns[who][i].zone === 'track' && this.backwardPath(who, i, 4).ok) out.push({ card: cardIdx, rank, kind: 'back', pawn: [who, i], steps: 4 });
        break;
      case '5':
        for (let s = 0; s < 4; s++) for (let i = 0; i < 4; i++) if (this.pawns[s][i].zone === 'track' && (s === who || this.pawns[s][i].pos !== gateIndex(s)) && this.forwardPath(s, i, 5, teamOf(s) === teamOf(seat)).ok) out.push({ card: cardIdx, rank, kind: 'move', pawn: [s, i], steps: 5 });
        break;
      case 'J':
        for (let i = 0; i < 4; i++) {
          const a = this.pawns[seat][i];      // R38.4: sempre um peão SEU (nunca do aliado), inclusive o que acabou de sair
          if (a.zone !== 'track') continue;
          for (let s = 0; s < 4; s++) for (let j = 0; j < 4; j++) {
            if (s === seat) continue;
            const b = this.pawns[s][j];
            if (b.zone !== 'track' || gateIndex(s) === b.pos) continue;
            out.push({ card: cardIdx, rank, kind: 'swap', pawn: [seat, i], target: [s, j] });
          }
        }
        break;
      case '7':
        out.push(...this.splitMoves(seat, who, cardIdx));
        break;
      case '10': {
        out.push(...this.forwardMoves(who, cardIdx, rank, STEPS[rank]));
        const nxt = this.burnTarget(seat);
        if (nxt >= 0) out.push({ card: cardIdx, rank, kind: 'burn', target_seat: nxt });
        break;
      }
      default:
        out.push(...this.forwardMoves(who, cardIdx, rank, STEPS[rank]));
    }
    return out;
  }
  exitMoves(who) {
    const out = [], o = this.occupant(gateIndex(who));
    if (o.length && o[0] === who) return out;
    for (let i = 0; i < 4; i++) if (this.pawns[who][i].zone === 'home') out.push({ kind: 'exit', pawn: [who, i] });
    return out;
  }
  forwardMoves(who, cardIdx, rank, steps) {
    const out = [];
    for (let i = 0; i < 4; i++) {
      if (this.pawns[who][i].zone === 'home') continue;
      if (this.forwardPath(who, i, steps).ok) out.push({ card: cardIdx, rank, kind: 'move', pawn: [who, i], steps });
    }
    return out;
  }
  // R37.2: se a 1ª parte coroa o ÚLTIMO peão do jogador, a 2ª parte pode ir para um peão do aliado
  splitMoves(seat, who, cardIdx) {
    const out = [];
    for (let i = 0; i < 4; i++) if (this.pawns[who][i].zone !== 'home' && this.forwardPath(who, i, 7).ok) out.push({ card: cardIdx, rank: '7', kind: 'split', parts: [{ pawn: [who, i], steps: 7 }] });
    for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) {
      if (i === j || this.pawns[who][i].zone === 'home' || this.pawns[who][j].zone === 'home') continue;
      for (let a = 1; a < 7; a++) {
        const sim = this.clone();
        if (!sim.forwardPath(who, i, a).ok) continue;
        sim.applyForward(who, i, a, []);
        if (sim.pawns[who][j].zone === 'home') continue;
        if (sim.forwardPath(who, j, 7 - a).ok) out.push({ card: cardIdx, rank: '7', kind: 'split', parts: [{ pawn: [who, i], steps: a }, { pawn: [who, j], steps: 7 - a }] });
      }
    }
    if (who === seat) {
      const ally = partnerOf(seat);
      for (let i = 0; i < 4; i++) {
        if (this.pawns[who][i].zone !== 'track') continue;
        for (let a = 1; a < 7; a++) {
          const sim = this.clone();
          if (!sim.forwardPath(who, i, a).ok) continue;
          sim.applyForward(who, i, a, []);
          if (sim.crowned(seat) !== 4) continue;
          for (let j = 0; j < 4; j++) {
            if (sim.pawns[ally][j].zone === 'home') continue;
            if (sim.forwardPath(ally, j, 7 - a).ok) out.push({ card: cardIdx, rank: '7', kind: 'split', parts: [{ pawn: [who, i], steps: a }, { pawn: [ally, j], steps: 7 - a }] });
          }
        }
      }
    }
    return out;
  }
  isLegal(seat, mv) {
    if (!(seat >= 0 && seat <= 3) || this.winner >= 0 || !mv || typeof mv !== 'object') return false;
    const c = Math.trunc(Number(mv.card));
    if (!Number.isFinite(c) || c < 0 || c >= this.hands[seat].length) return false;
    if (String(mv.kind || '') === 'discard') return !this.hasAnyMove(seat);
    if (String(mv.kind || '') === 'discard_all') return !this.hasAnyMove(seat) && this.hands[seat].length >= 2;
    const key = Marcha.moveKey(mv);
    return this.legalMoves(seat, c).some(m => Marcha.moveKey(m) === key);
  }
  // A jogada legal com a mesma chave (o servidor sempre aplica a SUA cópia, nunca o objeto do cliente).
  canonical(seat, mv) {
    if (['discard', 'discard_all'].includes(String(mv && mv.kind || ''))) { const c = Math.trunc(Number(mv.card)); return { card: c, rank: this.hands[seat][c], kind: String(mv.kind) }; }
    const key = Marcha.moveKey(mv);
    return this.legalMoves(seat, Math.trunc(Number(mv.card))).find(m => Marcha.moveKey(m) === key) || null;
  }
  static moveKey(mv) {
    const ints = a => (Array.isArray(a) ? a : []).map(x => Math.trunc(Number(x)) || 0);
    const parts = (Array.isArray(mv.parts) ? mv.parts : []).map(p => [ints(p && p.pawn), Math.trunc(Number(p && p.steps)) || 0]);
    const ts = mv.target_seat === undefined ? -1 : Math.trunc(Number(mv.target_seat));
    return JSON.stringify([String(mv.kind || ''), Math.trunc(Number(mv.card)), ints(mv.pawn), Math.trunc(Number(mv.steps || 0)), ints(mv.target), parts, ts]);
  }
  burnTarget(seat) { for (let k = 1; k < 4; k++) { const s = (seat + k) % 4; if (this.hands[s].length) return s; } return -1; }
  hasAnyMove(seat) { for (let c = 0; c < this.hands[seat].length; c++) if (this.legalMoves(seat, c).length) return true; return false; }

  // ---------- aplicar ----------
  // burnPick: só para testes de paridade (índice sorteado no Godot); no jogo, o sorteio é do servidor.
  apply(seat, mv, burnPick) {
    if (!this.isLegal(seat, mv)) return [];
    const ev = [];
    const rank = this.hands[seat][mv.card];
    this.hands[seat].splice(mv.card, 1);
    this.discard.push(rank);
    const name = String(this.names[seat]);
    switch (String(mv.kind)) {
      case 'discard': ev.push({ type: 'discard', rank }); this.logLine(`${name} descartou ${rank}`); break;
      case 'discard_all': {
        const all = [rank, ...this.hands[seat]];
        for (const r of this.hands[seat]) this.discard.push(r);
        this.hands[seat] = [];
        for (const r of all) ev.push({ type: 'discard', rank: r });
        this.logLine(`${name} descartou ${all.length} cartas sem jogada`); break;
      }
      case 'exit': {
        const w = mv.pawn, gate = gateIndex(w[0]), o = this.occupant(gate);
        if (o.length) { this.sendHome(o[0], o[1]); ev.push({ type: 'capture', pawn: o }); }
        this.pawns[w[0]][w[1]] = { zone: 'track', pos: gate };
        ev.push({ type: 'exit', pawn: w.slice() });
        this.logLine(`${name} jogou ${rank} · saiu do pátio`);
        break;
      }
      case 'move': { const w = mv.pawn; this.land(w[0], w[1], this.forwardPath(w[0], w[1], mv.steps, rank !== '5' || teamOf(w[0]) === teamOf(seat)), ev); this.logLine(`${name} jogou ${rank} · ${mv.steps} casas`); break; }
      case 'back': { const w = mv.pawn; this.land(w[0], w[1], this.backwardPath(w[0], w[1], 4), ev); this.logLine(`${name} jogou -4 · voltou 4 casas`); break; }
      case 'burn': {
        const t = mv.target_seat;
        const k = burnPick !== undefined ? burnPick : this.rng.int(0, this.hands[t].length - 1);
        const lost = this.hands[t][k];
        this.hands[t].splice(k, 1);
        this.discard.push(lost);
        ev.push({ type: 'burn', seat: t, rank: lost });
        this.logLine(`${name} jogou 10 · ${this.names[t]} descartou ${lost}`);
        break;
      }
      case 'swap': {
        const a = mv.pawn, b = mv.target, pa = this.pawns[a[0]][a[1]], pb = this.pawns[b[0]][b[1]];
        this.pawns[a[0]][a[1]] = { ...pb }; this.pawns[b[0]][b[1]] = { ...pa };
        ev.push({ type: 'swap', pawn: a.slice(), target: b.slice() });
        this.logLine(`${name} jogou J · trocou de lugar`);
        break;
      }
      case 'split':
        for (const part of mv.parts) {
          const w = part.pawn;
          if (this.pawns[w[0]][w[1]].zone === 'home') continue;
          if (this.forwardPath(w[0], w[1], part.steps).ok) this.applyForward(w[0], w[1], part.steps, ev);
        }
        this.logLine(`${name} jogou 7 · ${mv.parts.map(p => String(p.steps)).join(' + ')}`);
        break;
    }
    this.checkWinner();
    return ev;
  }
  applyForward(s, i, steps, ev) { this.land(s, i, this.forwardPath(s, i, steps), ev); }
  land(s, i, r, ev) {
    if (!r.ok) return;
    const end = r.end, wasLane = this.pawns[s][i].zone === 'lane';
    if (end.zone === 'track') {
      const o = this.occupant(end.pos);
      if (o.length && !sameW(o, [s, i])) { this.sendHome(o[0], o[1]); ev.push({ type: 'capture', pawn: o }); }
    }
    this.pawns[s][i] = { zone: end.zone, pos: end.pos };
    ev.unshift({ type: 'move', pawn: [s, i], path: r.path });
    if (end.zone === 'lane' && !wasLane) { ev.push({ type: 'crown', pawn: [s, i] }); this.logLine(`${this.names[s]} coroou um peão`); }
  }
  sendHome(s, i) {
    const used = []; for (let j = 0; j < 4; j++) if (this.pawns[s][j].zone === 'home') used.push(this.pawns[s][j].pos);
    let slot = 0; while (used.includes(slot)) slot++;
    this.pawns[s][i] = { zone: 'home', pos: slot };
  }
  checkWinner() { for (let t = 0; t < 2; t++) if (this.teamCrowned(t) === 8) this.winner = t; }
  logLine(t) { this.log.unshift(t); if (this.log.length > 8) this.log.length = 8; }
  nextTurn() {
    this.turn = (this.turn + 1) % 4;
    if (this.hands.every(h => !h.length)) { this.round_no += 1; this.deal(); }
  }
  clone() {
    const c = new Marcha(this.rng);
    c.pawns = this.pawns.map(r => r.map(p => ({ ...p })));
    c.hands = this.hands.map(h => h.slice()); c.deck = this.deck.slice(); c.discard = this.discard.slice();
    c.turn = this.turn; c.round_no = this.round_no; c.winner = this.winner; c.names = this.names;
    return c;
  }
  progress(s, i) {
    const p = this.pawns[s][i];
    if (p.zone === 'home') return -1;
    if (p.zone === 'lane') return 75 + p.pos;
    return posmod(p.pos - gateIndex(s), TRACK);
  }
}

// ---------- bots (porta de marcha/ai.gd; sem ruído = o mesmo lance do Godot) ----------
const KEEP = { A: 9, K: 9, J: 6, '7': 6, '5': 5, '4': 5, Q: 4, '10': 3, '9': 3, '8': 3, '6': 2, '3': 2, '2': 2 };
function chooseAI(g, seat, rng) {
  let best = null, bestScore = -Infinity;
  const base = evaluate(g, seat);
  for (let c = 0; c < g.hands[seat].length; c++) {
    for (const mv of g.legalMoves(seat, c)) {
      const sim = g.clone();
      sim.apply(seat, mv, mv.kind === 'burn' ? 0 : undefined);
      let sc = evaluate(sim, seat) - base;
      sc -= (KEEP[mv.rank] !== undefined ? KEEP[mv.rank] : 2) * 0.6;
      if (mv.kind === 'burn') sc += mv.target_seat % 2 !== seat % 2 ? 1.6 : -6.0;
      if (rng) sc += rng.float() * 0.5;
      if (sc > bestScore) { bestScore = sc; best = mv; }
    }
  }
  if (best) return best;
  let idx = 0, low = Infinity;
  for (let c = 0; c < g.hands[seat].length; c++) { const v = KEEP[g.hands[seat][c]] !== undefined ? KEEP[g.hands[seat][c]] : 2; if (v < low) { low = v; idx = c; } }
  return { card: idx, rank: g.hands[seat][idx], kind: 'discard' };
}
function evaluate(g, seat) {
  const team = teamOf(seat);
  let v = 0;
  for (let s = 0; s < 4; s++) {
    const sign = teamOf(s) === team ? 1 : -1;
    for (let i = 0; i < 4; i++) {
      const pr = g.progress(s, i);
      let val;
      if (pr < 0) val = -20;
      else if (pr >= 75) val = 110 + (pr - 75) * 3;
      else {
        val = pr * 1.0;
        if (g.pawns[s][i].pos === gateIndex(s)) val += 4;
        val -= danger(g, s, i) * (8 + pr * 0.25);
      }
      v += sign * val;
    }
  }
  if (g.winner === team) v += 10000; else if (g.winner >= 0) v -= 10000;
  return v;
}
function danger(g, s, i) {
  const p = g.pawns[s][i];
  if (p.zone !== 'track' || p.pos === gateIndex(s)) return 0;
  let d = 0;
  for (let o = 0; o < 4; o++) {
    if (teamOf(o) === teamOf(s)) continue;
    for (let j = 0; j < 4; j++) {
      const q = g.pawns[o][j];
      if (q.zone !== 'track') continue;
      const dist = posmod(p.pos - q.pos, TRACK);
      if (dist >= 2 && dist <= 13 && dist !== 4 && dist !== 7) d += 0.12;
    }
  }
  return Math.min(d, 0.6);
}

module.exports = { Marcha, chooseAI, evaluate, RULESET_VERSION, TRACK, ARM, STEPS, DEAL_CYCLE, COPIES, gateIndex, entranceIndex, teamOf, partnerOf, posmod };
