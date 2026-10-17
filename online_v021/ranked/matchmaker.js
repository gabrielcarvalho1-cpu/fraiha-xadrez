'use strict';
// Uma fila por modalidade; nunca mistura ritmos.
const { MODES, CONFIG } = require('./config');
const { forcaOf } = require('./progression');
// R143 · Ranked: pareia pela FORÇA oculta (ranked/progression.js). A faixa começa estreita e amplia com a espera.
// open=true (Casual): qualquer par da mesma modalidade, por ordem de chegada.
const forca = e => forcaOf(e.stats).f;
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
    return Math.min(this.cfg.maxWindow, (this.cfg.initialWindow || 120) + steps * this.cfg.expandStep);
  }
  compatible(a, b, now) {
    if (this.open) return true;
    const waited = Math.max(now - a.since, now - b.since);
    return Math.abs(forca(a) - forca(b)) <= this.window(waited);
  }
  tick(now, eligible = () => true) {
    const pairs = [];
    for (const [mode, q] of this.queues) {
      q.sort((x, y) => x.since - y.since);
      for (let i = 0; i < q.length; i++) {
        if (!eligible(q[i])) continue;
        let best = -1, bestGap = Infinity;
        for (let j = i + 1; j < q.length; j++) {
          if (!eligible(q[j])) continue;
          if (q[j].userId === q[i].userId || !this.compatible(q[i], q[j], now)) continue;
          const gap = this.open ? 0 : Math.abs(forca(q[i]) - forca(q[j]));
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
