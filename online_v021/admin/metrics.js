'use strict';
// FRAIHA Admin · TELEMETRIA mínima em memória (instrumentação nova da V1).
// - amostra o estado ao vivo a cada `everyMs` (padrão 15 s) e guarda 24 h (série para gráficos);
// - pico online do dia (UTC) e desde que o processo subiu;
// - tempo de espera REAL de cada pareamento (fila → partida), por modo;
// - partidas iniciadas/terminadas por modo e motivo de término (inclui abandono).
// Tudo some num reinício do servidor: a API marca esses números como PARCIAIS ("desde <started_at>").
const { liveSnapshot } = require('./live');
const DAY = 86400e3;
const utcDay = t => new Date(t).toISOString().slice(0, 10);

class Metrics {
  constructor({ backend, now = () => Date.now(), everyMs = 15e3, keepMs = DAY, autostart = true }) {
    this.backend = backend; this.now = now; this.everyMs = everyMs; this.keepMs = keepMs;
    this.startedAt = now();
    this.series = [];
    this.waits = [];                 // { at, family, mode, ms }
    this.events = [];                // { at, kind:'started'|'finished', family, mode, reason }
    this.peak = { day: utcDay(this.startedAt), today: 0, today_at: null, process: 0, process_at: null };
    if (autostart) { this.timer = setInterval(() => this.sample(), everyMs); this.timer.unref && this.timer.unref(); }
  }
  stop() { clearInterval(this.timer); }
  trim(arr, now) { const cut = now - this.keepMs; let i = 0; while (i < arr.length && arr[i].at < cut) i++; if (i) arr.splice(0, i); }
  sample() {
    const now = this.now(), s = liveSnapshot(this.backend, now);
    const byFamily = { ranked: 0, casual: 0, xeque: 0, marcha: 0 };
    for (const m of s.matches) byFamily[m.family] = (byFamily[m.family] || 0) + 1;
    const point = { at: now, online: s.online.length, accounts: s.accounts, guests: s.guests, in_match: s.inMatch.size, in_queue: s.inQueue.size, lobby: s.lobby, matches: s.matches.length, by_family: byFamily, voice: s.voice.size };
    this.series.push(point); this.trim(this.series, now);
    this.notePeak(point.online, now);
    return point;
  }
  notePeak(online, now) {
    const day = utcDay(now);
    if (day !== this.peak.day) { this.peak.day = day; this.peak.today = 0; this.peak.today_at = null; }
    if (online > this.peak.today) { this.peak.today = online; this.peak.today_at = new Date(now).toISOString(); }
    if (online > this.peak.process) { this.peak.process = online; this.peak.process_at = new Date(now).toISOString(); }
  }
  // hooks chamados pelo jogo (opcionais; nunca lançam para o chamador)
  onPaired(family, mode, waitsMs) { const at = this.now(); for (const ms of waitsMs) this.waits.push({ at, family, mode, ms: Math.max(0, ms) }); this.trim(this.waits, at); }
  onMatch(kind, family, mode, reason = '') { const at = this.now(); this.events.push({ at, kind, family, mode, reason: String(reason || '') }); this.trim(this.events, at); }
  avgWait(family, sinceMs) {
    const since = this.now() - sinceMs;
    const xs = this.waits.filter(w => w.at >= since && (!family || w.family === family));
    return xs.length ? { avg_ms: Math.round(xs.reduce((a, w) => a + w.ms, 0) / xs.length), samples: xs.length } : { avg_ms: null, samples: 0 };
  }
  today(kind) {
    const day = utcDay(this.now()), out = { total: 0, by_family: {}, by_reason: {} };
    for (const e of this.events) if (e.kind === kind && utcDay(e.at) === day) {
      out.total++; out.by_family[e.family] = (out.by_family[e.family] || 0) + 1;
      if (e.reason) out.by_reason[e.reason] = (out.by_reason[e.reason] || 0) + 1;
    }
    return out;
  }
  history(rangeMs) { const since = this.now() - rangeMs; return this.series.filter(p => p.at >= since); }
}
module.exports = { Metrics, utcDay };
