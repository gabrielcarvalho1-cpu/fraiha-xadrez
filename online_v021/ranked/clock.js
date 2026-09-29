'use strict';
// Relógio de xadrez autoritativo: sem incremento; só troca em jogada aceita.
class ChessClock {
  constructor(baseMs) { this.remaining = { w: baseMs, b: baseMs }; this.active = null; this.since = 0; }
  start(color, now) { this.active = color; this.since = now; }
  left(color, now) { return Math.max(0, this.remaining[color] - (this.active === color ? now - this.since : 0)); }
  // Chamado somente depois que o servidor aceitou uma jogada legal de `color`.
  press(color, now) {
    if (this.active !== color) return false;
    this.remaining[color] = this.left(color, now);
    this.active = color === 'w' ? 'b' : 'w'; this.since = now;
    return true;
  }
  flagged(now) { return this.active && this.left(this.active, now) <= 0 ? this.active : null; }
  stop(now) { if (this.active) { this.remaining[this.active] = this.left(this.active, now); this.active = null; } }
  snapshot(now) { return { w_ms: Math.round(this.left('w', now)), b_ms: Math.round(this.left('b', now)), active: this.active || '' }; }
}
module.exports = { ChessClock };
