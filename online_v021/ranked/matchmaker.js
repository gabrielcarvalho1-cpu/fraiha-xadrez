'use strict';
// Uma fila por modalidade; nunca mistura ritmos.
const { MODES, CONFIG } = require('./config');
const { rating } = require('./progression');
// open=true (Casual): qualquer par da mesma modalidade, por ordem de chegada.
class Matchmaker {
  constructor(cfg = CONFIG.matchmaking, modes = MODES, { open = false } = {}) {
    this.cfg = cfg; this.open = open; this.queues = new Map(Object.keys(modes).map(m => [m, []]));
  }
  has(userId) { for (const q of this.queues.values()) if (q.some(e => e.userId === userId)) return true; return false; }
  enqueue(mode, entry) {
    if (!this.queues.has(mode) || this.has(entry.userId)) return false;
    this.queues.get(mode).push(entry); return true;
  }
  cancel(userId) { let found = null; for (const q of this.queues.values()) { const i = q.findIndex(e => e.userId === userId); if (i >= 0) found = q.splice(i, 1)[0]; } return found; }
  window(waited) {
    const steps = Math.floor(waited / this.cfg.expandEveryMs);
    return steps === 0 ? null : Math.min(this.cfg.maxWindow, this.cfg.initialPlWindow + steps * this.cfg.expandStep);
  }
  compatible(a, b, now) {
    if (this.open) return true;
    const waited = Math.max(now - a.since, now - b.since);
    const w = this.window(waited);
    if (w === null) return a.stats.league === b.stats.league && Math.abs(a.stats.pl - b.stats.pl) <= this.cfg.initialPlWindow;
    return Math.abs(rating(a.stats) - rating(b.stats)) <= w;
  }
  tick(now) {
    const pairs = [];
    for (const [mode, q] of this.queues) {
      q.sort((x, y) => x.since - y.since);
      for (let i = 0; i < q.length; i++) {
        let best = -1, bestGap = Infinity;
        for (let j = i + 1; j < q.length; j++) {
          if (q[j].userId === q[i].userId || !this.compatible(q[i], q[j], now)) continue;
          const gap = this.open ? 0 : Math.abs(rating(q[i].stats) - rating(q[j].stats));
          if (gap < bestGap) { best = j; bestGap = gap; }
          if (this.open) break;
        }
        if (best >= 0) { const b = q.splice(best, 1)[0], a = q.splice(i, 1)[0]; pairs.push({ mode, a, b }); i--; }
      }
    }
    return pairs;
  }
}
module.exports = { Matchmaker };
