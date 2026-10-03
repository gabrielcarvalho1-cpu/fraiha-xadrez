'use strict';
// R35 · Partidas ONLINE dos modos de cartas (MARCHA REAL e XEQUE) entre amigos, com bots completando
// a mesa de 4. O SERVIDOR é a autoridade: guarda o estado, valida cada jogada com o motor de regras
// (porta 1:1 do Godot, conferida por tests/server/modes_parity_test.cjs), sorteia, roda os bots e
// decide o tempo. O cliente só pede ações e anima o que o servidor manda.
//
// Lugares: quem convidou = lugar 0; o amigo = lugar 2 (na MARCHA é a DUPLA de quem convidou: 0+2
// contra os bots 1+3; no XEQUE é cada um por si). Cada jogador recebe a mesa GIRADA para ele ficar
// sempre no lugar 0 (embaixo), como no jogo contra bots — o cliente usa a mesma tela.
// Partida com amigo não consome a partida grátis do dia (fase de testes).
// Em memória: se o servidor reiniciar, a partida acaba (o cliente avisa e volta ao lobby).
const crypto = require('crypto');
const { rngFrom } = require('./rng');
const M = require('./marcha_rules');
const X = require('./xeque_rules');

const env = process.env;
const num = (v, d) => (v !== undefined && v !== '' && Number.isFinite(Number(v)) ? Number(v) : d);
const T = {
  turnMs: num(env.FRAIHA_PARTY_TURN_MS, 30000),          // vez do jogador (igual ao jogo local)
  marchaBotMs: num(env.FRAIHA_PARTY_MARCHA_BOT_MS, 950),
  xequeBotMin: num(env.FRAIHA_PARTY_XEQUE_BOT_MIN_MS, 1600), xequeBotMax: num(env.FRAIHA_PARTY_XEQUE_BOT_MAX_MS, 3000),   // R36: ritmo mais calmo
  awayMs: num(env.FRAIHA_PARTY_AWAY_MS, 1500),           // jogador desconectado: o bot joga por ele depois disso
  stepMs: num(env.FRAIHA_PARTY_STEP_MS, 260),            // R37: 0,26 s por casa, em pulinho (marcha_ui.gd STEP_TIME)
  exitMs: num(env.FRAIHA_PARTY_EXIT_MS, 550), captureMs: num(env.FRAIHA_PARTY_CAPTURE_MS, 500), crownMs: num(env.FRAIHA_PARTY_CROWN_MS, 1200),             // R37: saída em arco, abatido some, chegada da DAMA (EXIT_TIME/CAPTURE_TIME/CROWN_WAIT)
  swapMs: num(env.FRAIHA_PARTY_SWAP_MS, 3200),           // troca do J (marcha_ui.gd: 0,35 + até 2,4 + 0,35 s)
  mesaMs: num(env.FRAIHA_PARTY_MESA_MS, 4400),           // distribuição (DEAL_T 2,4 s) + carta da MESA (MESA_T 1,9 s) no xeque_ui.gd
  introMs: num(env.FRAIHA_PARTY_INTRO_MS, 3200),         // apresentação do baralho antes da 1ª rodada (INTRO_T)
  revealMs: num(env.FRAIHA_PARTY_REVEAL_MS, 3200), clockMs: num(env.FRAIHA_PARTY_CLOCK_MS, 2400),
  safeMs: num(env.FRAIHA_PARTY_SAFE_MS, 2000), mateMs: num(env.FRAIHA_PARTY_MATE_MS, 3800),
  keepEndedMs: 120000,
};
const GAMES = { marcha: { name: 'MARCHA REAL' }, xeque: { name: 'XEQUE' } };
const MARCHA_BOTS = { 1: 'ReiDoBlitz', 3: 'Cavalo_Louco' };
const XEQUE_BOTS = { 1: ['Dama de Ferro', 'cauteloso'], 3: ['Torre Velha', 'blefador'] };
const rot = (s, v) => (s < 0 ? s : (s - v + 4) % 4);            // absoluto → visto pelo jogador v
const unrot = (s, v) => (s + v) % 4;                             // visto pelo jogador v → absoluto
const rotArr = (a, v) => [0, 1, 2, 3].map(rs => a[unrot(rs, v)]);

class Party {
  constructor({ send, backend, now = () => Date.now() }) {
    this.send = send; this.backend = backend; this.now = now;
    this.rooms = new Map(); this.byUser = new Map();
    this.sweep = setInterval(() => this.cleanup(), 30000); this.sweep.unref && this.sweep.unref();
  }
  sockets(uid) { return this.backend && this.backend.socketsOf ? this.backend.socketsOf(uid) : []; }
  toUser(uid, msg) { for (const ws of this.sockets(uid)) this.send(ws, msg); }
  roomOf(uid) { const r = this.rooms.get(this.byUser.get(uid)); return r && !r.ended ? r : null; }
  activeMatchOf(uid) { return this.roomOf(uid); }
  seatOf(room, uid) { return room.seats.findIndex(s => s.kind === 'human' && s.uid === uid); }

  // ---------- início (chamado pelo convite aceito) ----------
  start(game, humans, opts = {}) {
    if (!GAMES[game]) throw new Error('bad game');
    const id = crypto.randomUUID();
    const rng = rngFrom(opts.seed || 0);
    const seats = [];
    for (let s = 0; s < 4; s++) seats.push(null);
    const humanSeats = [0, 2];
    humans.forEach((h, i) => { seats[humanSeats[i]] = { kind: 'human', uid: h.user_id, nickname: h.nickname, avatar: h.avatar_id || '', badge: h.badge || '', connected: true, away_since: 0, left: false }; });
    for (let s = 0; s < 4; s++) if (!seats[s]) {
      seats[s] = game === 'marcha' ? { kind: 'bot', nickname: MARCHA_BOTS[s] || `Bot ${s}` } : { kind: 'bot', nickname: (XEQUE_BOTS[s] || [`Bot ${s}`])[0], profile: (XEQUE_BOTS[s] || [0, 'equilibrado'])[1] };
    }
    const room = { id, game, seats, rng, ver: 0, ended: false, busy: false, timer: null, deadline: 0, turn_seat: -1, started_at: this.now(), result: null, last: null };
    if (game === 'marcha') {
      room.g = new M.Marcha(rng);
      room.g.setup();
      room.g.names = seats.map(s => s.nickname);
    } else {
      room.g = new X.Xeque(rng);
      room.g.setup(seats.map(s => s.nickname));
    }
    this.rooms.set(id, room);
    for (const s of seats) if (s.kind === 'human') this.byUser.set(s.uid, id);
    for (const s of seats) if (s.kind === 'human') this.toUser(s.uid, this.startMsg(room, this.seatOf(room, s.uid)));
    if (game === 'marcha') this.marchaBegin(room);
    else this.later(room, T.introMs + T.mesaMs, () => this.xequeBegin(room));     // baralho, distribuição e carta da MESA primeiro
    return room;
  }
  startMsg(room, v) {
    return { type: 'party_start', room_id: room.id, game: room.game, game_name: GAMES[room.game].name, seat: 0,
      players: rotArr(room.seats, v).map(s => ({ user_id: s.kind === 'human' ? s.uid : '', name: s.nickname, avatar: s.avatar || '', badge: s.badge || '', bot: s.kind !== 'human', connected: s.kind !== 'human' || s.connected, left: !!s.left })),
      ruleset: room.game === 'marcha' ? M.RULESET_VERSION : X.RULESET_VERSION, turn_ms: T.turnMs, snapshot: this.snapshot(room, v) };
  }
  later(room, ms, fn) { clearTimeout(room.timer); room.timer = setTimeout(() => { room.timer = null; if (!room.ended) fn(); }, Math.max(0, ms)); room.timer.unref && room.timer.unref(); }

  // ---------- visão de cada jogador (girada; mãos alheias e relógio escondidos) ----------
  snapshot(room, v) {
    const now = this.now();
    const base = { ver: room.ver, turn_left_ms: room.deadline ? Math.max(0, room.deadline - now) : 0, my_turn: room.turn_seat === unrot(0, v) && room.deadline > 0,
      players_connected: rotArr(room.seats, v).map(s => s.kind !== 'human' || (s.connected && !s.left)) };
    if (room.game === 'marcha') {
      const g = room.g;
      const winner = g.winner < 0 ? -1 : (g.winner === v % 2 ? 0 : 1);
      return { ...base, pawns: rotArr(g.pawns, v).map(row => row.map(p => this.rotPawn(p, v))), my_hand: g.hands[v].slice(),
        hand_counts: rotArr(g.hands, v).map(h => h.length), turn: rot(g.turn, v), round_no: g.round_no, winner, log: g.log.slice(), names: rotArr(g.names, v) };
    }
    const g = room.g, pub = g.publicState(v);
    const r = g.last_result ? this.rotResult(g.last_result, v) : null;
    return { ...base, state: pub.state, round: pub.round, target: pub.target, turn: rot(pub.turn, v), lives: rotArr(pub.lives, v), hand_counts: rotArr(pub.hand_counts, v),
      clock_left: rotArr(pub.clock_left, v), last_play: pub.last_play.seat !== undefined ? { seat: rot(pub.last_play.seat, v), count: pub.last_play.count } : {},
      plays_this_round: pub.plays_this_round.map(p => ({ seat: rot(p.seat, v), count: p.count })),
      reveals: pub.reveals.map(x => ({ ...x, seat: rot(x.seat, v) })), names: rotArr(pub.names, v), winner: rot(pub.winner, v),
      eliminated_round: rotArr(pub.eliminated_round, v), finish_order: g.finish_order.map(s => rot(s, v)), next_starter: rot(g.next_starter === undefined ? -1 : g.next_starter, v),
      public_log: g.public_log.slice(-30), my_hand: g.hands[v].slice(), last_result: r, can_challenge: pub.can_challenge };
  }
  rotPawn(p, v) { return p.zone === 'track' ? { zone: 'track', pos: M.posmod(p.pos - v * M.ARM, M.TRACK) } : { zone: p.zone, pos: p.pos }; }
  rotEvents(ev, v) {
    return ev.map(e => {
      const o = { ...e };
      if (o.pawn) o.pawn = [rot(o.pawn[0], v), o.pawn[1]];
      if (o.target) o.target = [rot(o.target[0], v), o.target[1]];
      if (o.seat !== undefined) o.seat = rot(o.seat, v);
      if (o.path) o.path = o.path.map(p => this.rotPawn(p, v));
      return o;
    });
  }
  rotMove(mv, v) {
    const o = { ...mv };
    if (o.pawn) o.pawn = [rot(o.pawn[0], v), o.pawn[1]];
    if (o.target) o.target = [rot(o.target[0], v), o.target[1]];
    if (o.target_seat !== undefined) o.target_seat = rot(o.target_seat, v);
    if (o.parts) o.parts = o.parts.map(p => ({ pawn: [rot(p.pawn[0], v), p.pawn[1]], steps: p.steps }));
    return o;
  }
  unrotMove(mv, v) {
    const o = {};
    for (const k of ['card', 'steps', 'target_seat']) if (mv[k] !== undefined) o[k] = Math.trunc(Number(mv[k]));
    o.kind = String(mv.kind || '');
    const w = a => (Array.isArray(a) && a.length === 2 ? [unrot(Math.trunc(Number(a[0])) & 3, v), Math.trunc(Number(a[1]))] : undefined);
    if (mv.pawn) o.pawn = w(mv.pawn);
    if (mv.target) o.target = w(mv.target);
    if (o.target_seat !== undefined) o.target_seat = unrot(o.target_seat & 3, v);
    if (Array.isArray(mv.parts)) o.parts = mv.parts.slice(0, 2).map(p => ({ pawn: w(p && p.pawn), steps: Math.trunc(Number(p && p.steps)) }));
    return o;
  }
  rotResult(r, v) { const o = { ...r, cards: (r.cards || []).slice(), false_cards: (r.false_cards || []).slice() }; for (const k of ['caller', 'accused', 'loser', 'winner', 'next_starter']) if (o[k] !== undefined) o[k] = rot(o[k], v); return o; }
  broadcast(room, ev) {
    room.ver++;
    room.seats.forEach((s, abs) => {
      if (s.kind !== 'human' || s.left) return;
      const msg = { type: 'party_event', room_id: room.id, ev: ev.ev, snapshot: this.snapshot(room, abs) };
      if (ev.seat !== undefined) msg.seat = rot(ev.seat, abs);
      if (ev.move) msg.move = this.rotMove(ev.move, abs);
      if (ev.events) msg.events = this.rotEvents(ev.events, abs);
      if (ev.play) msg.play = { ...ev.play, seat: rot(ev.play.seat, abs), forced: ev.play.forced ? this.rotResult(ev.play.forced, abs) : undefined };
      if (ev.result) msg.result = this.rotResult(ev.result, abs);
      if (ev.reason) msg.reason = ev.reason;
      if (ev.who !== undefined) msg.who = rot(ev.who, abs);
      this.toUser(s.uid, msg);
    });
  }
  humanActive(room, seat) { const s = room.seats[seat]; return s.kind === 'human' && !s.left && s.connected; }

  // ---------- MARCHA REAL ----------
  marchaBegin(room) {
    const g = room.g;
    room.busy = false; room.deadline = 0; room.turn_seat = -1;
    if (g.winner >= 0) return this.finish(room);
    let guard = 0;
    while (!g.hands[g.turn].length && guard++ < 8) g.nextTurn();
    room.turn_seat = g.turn;
    const seat = g.turn;
    if (this.humanActive(room, seat)) {
      room.deadline = this.now() + T.turnMs;
      this.broadcast(room, { ev: 'turn' });
      this.later(room, T.turnMs, () => this.marchaAuto(room, seat, 'timeout'));
    } else {
      this.broadcast(room, { ev: 'turn' });
      this.later(room, room.seats[seat].kind === 'bot' ? T.marchaBotMs : T.awayMs, () => this.marchaAuto(room, seat, room.seats[seat].kind === 'bot' ? 'bot' : 'away'));
    }
  }
  marchaAuto(room, seat, reason) {
    if (room.turn_seat !== seat || room.busy) return;
    this.marchaApply(room, seat, M.chooseAI(room.g, seat, null), reason);
  }
  marchaApply(room, seat, mv, reason) {
    const g = room.g;
    const canon = g.canonical(seat, mv);
    if (!canon || !g.isLegal(seat, canon)) return false;
    room.busy = true; room.deadline = 0; clearTimeout(room.timer);
    const events = g.apply(seat, canon);
    if (!events.length) { room.busy = false; return false; }
    this.broadcast(room, { ev: 'move', seat, move: canon, events, reason });
    this.later(room, this.marchaAnimMs(events) + 250, () => {
      if (g.winner >= 0) return this.finish(room);
      g.nextTurn();
      this.marchaBegin(room);
    });
    return true;
  }
  marchaAnimMs(events) {
    let ms = 0;
    for (const e of events) {
      if (e.type === 'move') ms += e.path.length * T.stepMs;
      else if (e.type === 'exit') ms += T.exitMs;
      else if (e.type === 'capture') ms += T.captureMs;
      else if (e.type === 'burn') ms += 400;
      else if (e.type === 'crown') ms += T.crownMs;
      else if (e.type === 'swap') ms += T.swapMs;        // J: brilho + travessia em arco (até 2,4 s) + brilho
      else ms += 180;
    }
    return ms;
  }

  // ---------- XEQUE ----------
  xequeBegin(room) {
    const g = room.g;
    room.busy = false; room.deadline = 0; room.turn_seat = -1;
    if (g.state === X.S.MATCH_END) return this.finish(room);
    if (g.state !== X.S.TURN_WAITING) return;
    const seat = g.turn;
    room.turn_seat = seat;
    if (this.humanActive(room, seat)) {
      room.deadline = this.now() + T.turnMs;
      this.broadcast(room, { ev: 'turn' });
      this.later(room, T.turnMs, () => this.xequeTimeout(room, seat));
    } else {
      this.broadcast(room, { ev: 'turn' });
      const bot = room.seats[seat].kind === 'bot';
      this.later(room, bot ? room.rng.int(T.xequeBotMin, T.xequeBotMax) : T.awayMs, () => this.xequeBot(room, seat));
    }
  }
  xequeBot(room, seat) {
    const g = room.g;
    if (room.turn_seat !== seat || room.busy) return;
    const prof = room.seats[seat].profile || 'equilibrado';
    const d = X.decide(g.publicState(seat), g.hands[seat].slice(), prof, room.rng);
    if (d.action === 'challenge' && g.canChallenge(seat)) return this.xequeChallenge(room, seat);
    if (!this.xequePlay(room, seat, d.idx || [0])) this.xequeTimeout(room, seat);
  }
  xequeTimeout(room, seat) {
    const g = room.g;
    if (room.turn_seat !== seat || room.busy) return;
    const i = g.hands[seat].length ? room.rng.int(0, g.hands[seat].length - 1) : -1;
    if (i >= 0) this.xequePlay(room, seat, [i], 'timeout');
    else if (g.canChallenge(seat)) this.xequeChallenge(room, seat);
  }
  xequePlay(room, seat, idx, reason) {
    const g = room.g;
    if (!g.canPlay(seat, idx)) return false;
    room.busy = true; room.deadline = 0; clearTimeout(room.timer);
    const pub = g.play(seat, idx);
    if (!pub) { room.busy = false; return false; }
    this.broadcast(room, { ev: 'play', play: pub, reason });
    if (pub.forced) this.xequeAfterChallenge(room, pub.forced);
    else this.later(room, 350, () => this.xequeBegin(room));
    return true;
  }
  xequeChallenge(room, seat) {
    const g = room.g;
    if (!g.canChallenge(seat)) return false;
    room.busy = true; room.deadline = 0; clearTimeout(room.timer);
    const r = g.challenge(seat);
    this.broadcast(room, { ev: 'challenge', result: r });
    this.xequeAfterChallenge(room, r);
    return true;
  }
  // a apresentação (revelar → relógio → seguro/xeque-mate) roda no cliente; o servidor espera o mesmo tempo
  xequeAfterChallenge(room, r) {
    const present = T.revealMs + T.clockMs + (r.mate ? T.mateMs : T.safeMs) + 300;
    this.later(room, present, () => {
      const g = room.g;
      if (g.state === X.S.MATCH_END) return this.finish(room);
      g.nextRound();
      this.broadcast(room, { ev: 'round' });
      this.later(room, T.mesaMs, () => this.xequeBegin(room));
    });
  }

  // ---------- fim / saída / conexão ----------
  finish(room, reason = '') {
    if (room.ended) return;
    room.ended = true; room.deadline = 0; room.turn_seat = -1; clearTimeout(room.timer);
    room.ended_at = this.now();
    this.broadcast(room, { ev: 'end', reason });
    this.recordStats(room);
    for (const s of room.seats) if (s.kind === 'human' && this.byUser.get(s.uid) === room.id) this.byUser.delete(s.uid);
    for (const s of room.seats) if (s.kind === 'human' && this.backend && this.backend.presenceChanged) this.backend.presenceChanged(s.uid);
  }
  // R37 · placar do modo (cartão de perfil): vitória/derrota de cada pessoa da mesa. Quem saiu perde.
  recordStats(room) {
    const st = this.backend && this.backend.store;
    if (!st || !st.recordModeResult) return;
    const w = room.g ? room.g.winner : -1;
    room.seats.forEach((s, seat) => {
      if (s.kind !== 'human' || !/^[0-9a-f-]{36}$/i.test(String(s.uid || ''))) return;
      let res = '';
      if (s.left) res = 'loss';
      else if (w >= 0) res = (room.game === 'marcha' ? seat % 2 === w : seat === w) ? 'win' : 'loss';
      if (res) st.recordModeResult(s.uid, room.game, res).catch(e => console.error('mode stats failed', e && e.message));
    });
  }
  leave(room, uid) {
    const seat = this.seatOf(room, uid);
    if (seat < 0) return;
    const s = room.seats[seat];
    s.left = true;
    if (this.byUser.get(uid) === room.id) this.byUser.delete(uid);
    // o lugar continua na mesa, jogado pelo bot (a partida dos outros segue)
    s.nickname = s.nickname;
    this.broadcast(room, { ev: 'left', who: seat });
    if (!room.seats.some(x => x.kind === 'human' && !x.left)) return this.finish(room, 'all_left');
    if (room.turn_seat === seat && !room.busy) {
      clearTimeout(room.timer); room.deadline = 0;
      this.later(room, T.awayMs, () => (room.game === 'marcha' ? this.marchaAuto(room, seat, 'away') : this.xequeBot(room, seat)));
    }
    if (this.backend && this.backend.presenceChanged) this.backend.presenceChanged(uid);
  }
  onClose(ws) {
    const uid = ws.identity && ws.identity.id;
    if (!uid) return;
    const room = this.roomOf(uid);
    if (!room) return;
    if (this.sockets(uid).some(x => x !== ws)) return;           // outra aba/aparelho ainda conectado
    const seat = this.seatOf(room, uid);
    const s = room.seats[seat];
    s.connected = false; s.away_since = this.now();
    this.broadcast(room, { ev: 'presence' });
    if (room.turn_seat === seat && !room.busy) {
      clearTimeout(room.timer); room.deadline = 0;
      this.later(room, T.awayMs, () => (room.game === 'marcha' ? this.marchaAuto(room, seat, 'away') : this.xequeBot(room, seat)));
    }
  }
  onAuthenticated(ws) {
    const uid = ws.user && ws.user.id;
    const room = uid ? this.roomOf(uid) : null;
    if (!room) return;
    const seat = this.seatOf(room, uid);
    const s = room.seats[seat];
    const was = s.connected;
    s.connected = true; s.away_since = 0;
    this.send(ws, { ...this.startMsg(room, seat), resumed: true });
    if (!was) this.broadcast(room, { ev: 'presence' });
  }
  handle(ws, m) {
    const a = String(m.type || ''), uid = ws.user.id;
    const room = this.rooms.get(String(m.room_id || '')) || this.roomOf(uid);
    if (a === 'party_sync') {
      if (!room || this.seatOf(room, uid) < 0) return this.send(ws, { type: 'party_none' });
      const seat = this.seatOf(room, uid);
      return this.send(ws, { ...this.startMsg(room, seat), resumed: true, ended: room.ended });
    }
    if (!room || room.ended) return this.send(ws, { type: 'party_error', code: 'no_room', message: 'Esta partida já terminou.' });
    const seat = this.seatOf(room, uid);
    if (seat < 0 || room.seats[seat].left) return this.send(ws, { type: 'party_error', code: 'not_player', message: 'Você não está nesta partida.' });
    if (a === 'party_leave') { this.leave(room, uid); return this.send(ws, { type: 'party_left', room_id: room.id }); }
    if (a !== 'party_action') return this.send(ws, { type: 'party_error', code: 'invalid', message: 'Ação desconhecida.' });
    const reject = (code, message) => this.send(ws, { type: 'party_error', code, message, room_id: room.id, snapshot: this.snapshot(room, seat) });
    if (room.busy || room.turn_seat !== seat) return reject('not_your_turn', 'Aguarde a sua vez.');
    const act = m.action && typeof m.action === 'object' ? m.action : {};
    if (room.game === 'marcha') {
      if (!this.marchaApply(room, seat, this.unrotMove(act, seat), 'player')) return reject('illegal', 'Jogada inválida.');
      return;
    }
    if (act.kind === 'challenge') { if (!this.xequeChallenge(room, seat)) return reject('illegal', 'Não dá para dar XEQUE agora.'); return; }
    const idx = Array.isArray(act.idx) ? act.idx.slice(0, X.MAX_PLAY).map(x => Math.trunc(Number(x))) : [];
    if (!this.xequePlay(room, seat, idx, 'player')) return reject('illegal', 'Jogada inválida.');
  }
  cleanup() {
    const now = this.now();
    for (const [id, r] of this.rooms) {
      if (r.ended && now - (r.ended_at || 0) > T.keepEndedMs) { clearTimeout(r.timer); this.rooms.delete(id); }
      // ninguém conectado há 10 min: encerra
      else if (!r.ended && r.seats.every(s => s.kind !== 'human' || s.left || (!s.connected && now - s.away_since > 600000))) this.finish(r, 'abandoned');
    }
  }
  stop() { clearInterval(this.sweep); for (const r of this.rooms.values()) clearTimeout(r.timer); }
}
module.exports = { Party, GAMES, T };
