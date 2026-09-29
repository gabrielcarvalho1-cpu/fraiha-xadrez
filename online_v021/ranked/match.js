'use strict';
const crypto = require('crypto');
const { Position } = require('../chess_rules');
const { ChessClock } = require('./clock');
const { ALL_MODES, CONFIG } = require('./config');
const { applyResult } = require('./progression');

const REASONS = { checkmate: 'Xeque-mate', timeout: 'Tempo esgotado', timeout_draw: 'Tempo esgotado sem material para mate',
  resign: 'Desistência', abandon: 'Abandono', stalemate: 'Afogamento', insufficient_material: 'Material insuficiente',
  fifty_moves: 'Regra dos 50 lances', repetition: 'Repetição tripla' };

// Partida autoritativa (Ranked e Casual). rated=false: sem PL, sem liga, sem gravação.
class RankedMatch {
  constructor({ mode, white, black, now, cfg = CONFIG, rated = true, prefix = 'ranked' }) {
    this.id = crypto.randomUUID(); this.mode = mode; this.cfg = cfg; this.rated = rated; this.prefix = prefix;
    this.players = { w: white, b: black };               // {userId,nickname,avatar,stats,ws,connected,leftAt}
    this.pos = new Position(); this.clock = new ChessClock(cfg.baseMs(mode));
    this.createdAt = now; this.startsAt = now + cfg.startDelayMs; this.startedAt = null;
    this.status = 'starting'; this.result = null; this.lastMove = null; this.revision = 0;
  }
  colorOf(userId) { return this.players.w.userId === userId ? 'w' : this.players.b.userId === userId ? 'b' : null; }
  // Avança estados dependentes do tempo; devolve true se algo mudou.
  tick(now) {
    if (this.status === 'starting' && now >= this.startsAt) { this.status = 'playing'; this.startedAt = now; this.clock.start('w', now); this.revision++; return true; }
    if (this.status !== 'playing') return false;
    const flag = this.clock.flagged(now);
    if (flag) {
      const winner = flag === 'w' ? 'b' : 'w';
      if (this.pos.canMate(winner)) this.finish(winner, 'timeout', now); else this.finish('draw', 'timeout_draw', now);
      return true;
    }
    for (const c of ['w', 'b']) {
      const p = this.players[c];
      if (!p.connected && p.leftAt && now - p.leftAt >= this.cfg.reconnectGraceMs) { this.finish(c === 'w' ? 'b' : 'w', 'abandon', now); return true; }
    }
    return false;
  }
  move(color, m, now) {
    if (this.tick(now) && this.status === 'finished') return { error: 'Partida encerrada.' };
    if (this.status === 'starting') return { error: 'A partida começa em instantes.' };
    if (this.status !== 'playing') return { error: 'Partida encerrada.' };
    if (this.pos.turn !== color) return { error: 'Aguarde seu turno.' };
    const applied = this.pos.play({ from: m.from, to: m.to, promotion: m.promotion || 'Q' });
    if (!applied) return { error: 'Movimento não permitido.' };        // relógio intocado
    this.clock.press(color, now);                                     // só jogada legal troca o relógio
    this.lastMove = applied; this.revision++;
    const out = this.pos.outcome();
    if (out === 'checkmate') this.finish(color, 'checkmate', now);
    else if (out) this.finish('draw', out, now);
    return { ok: true };
  }
  resign(color, now) { if (this.status === 'finished') return false; this.finish(color === 'w' ? 'b' : 'w', 'resign', now); return true; }
  // winner: 'w' | 'b' | 'draw'. Calcula PL a partir das estatísticas PRÉ-partida.
  finish(winner, reason, now) {
    if (this.status === 'finished') return;
    this.clock.stop(now); this.status = 'finished'; this.revision++;
    if (!this.rated) { this.result = { winner, reason, finishedAt: now }; return; }
    const outcome = c => (winner === 'draw' ? 'draw' : winner === c ? 'win' : 'loss');
    const w = applyResult(this.players.w.stats, this.players.b.stats, outcome('w'));
    const b = applyResult(this.players.b.stats, this.players.w.stats, outcome('b'));
    this.result = { winner, reason, finishedAt: now, w, b };
  }
  record() {
    const r = this.result, W = this.players.w, B = this.players.b;
    return { match_id: this.id, mode: this.mode, white_user_id: W.userId, black_user_id: B.userId,
      started_at: new Date(this.startedAt || this.createdAt).toISOString(), finished_at: new Date(r.finishedAt).toISOString(),
      result: r.winner === 'w' ? 'white' : r.winner === 'b' ? 'black' : 'draw', result_reason: r.reason,
      white_pl_before: W.stats.pl, black_pl_before: B.stats.pl, white_pl_change: r.w.applied, black_pl_change: r.b.applied,
      white_pl_after: r.w.stats.pl, black_pl_after: r.b.stats.pl,
      white_league_before: W.stats.league, black_league_before: B.stats.league,
      white_league_after: r.w.stats.league, black_league_after: r.b.stats.league, moves: this.pos.history.join(' ') };
  }
  publicPlayer(c) {
    const p = this.players[c], out = { nickname: p.nickname, avatar_id: p.avatar, connected: p.connected };
    if (this.rated) { out.league = p.stats.league; out.pl = p.stats.pl; }
    return out;
  }
  state(forColor, now) {
    return { type: this.prefix + '_state', match_id: this.id, mode: this.mode, mode_name: ALL_MODES[this.mode].name, you: forColor,
      status: this.status, revision: this.revision, starts_in_ms: Math.max(0, this.startsAt - now),
      white: this.publicPlayer('w'), black: this.publicPlayer('b'), position: this.pos.snapshot(),
      in_check: this.status === 'playing' && this.pos.inCheck(this.pos.turn),
      last_move: this.lastMove ? { from: this.lastMove.from, to: this.lastMove.to, captured: this.lastMove.captured } : null,
      clock: this.clock.snapshot(now) };
  }
  resultFor(c, saved) {
    const r = this.result;
    if (!this.rated) {
      return { type: this.prefix + '_result', match_id: this.id, mode: this.mode, mode_name: ALL_MODES[this.mode].name, you: c,
        outcome: r.winner === 'draw' ? 'draw' : r.winner === c ? 'win' : 'loss', reason: r.reason, reason_text: REASONS[r.reason] || r.reason,
        rated: false, pl_change: 0 };
    }
    const mine = r[c], before = this.players[c].stats;
    return { type: 'ranked_result', match_id: this.id, mode: this.mode, mode_name: ALL_MODES[this.mode].name, you: c,
      outcome: r.winner === 'draw' ? 'draw' : r.winner === c ? 'win' : 'loss', reason: r.reason, reason_text: REASONS[r.reason] || r.reason,
      pl_change: mine.applied, league_before: before.league, pl_before: before.pl, league_after: mine.stats.league, pl_after: mine.stats.pl,
      promoted: mine.promoted, stats: mine.stats, saved };
  }
}
module.exports = { RankedMatch, REASONS };
