'use strict';
// R171 · SEC-008: o servidor confere, com o MESMO Stockfish do jogo, se os lances do LADO DO BOT numa vitória
// declarada parecem lances do bot daquele nível — e não lances inventados/ruins enviados pelo cliente.
//
// Medida: perda média do bot (centipeões, teto 1000 por lance) nas posições ainda DISPUTADAS (bot com 8–92% de
// chance antes do lance). Com menos de 3 posições disputadas, usa a média de todos os lances do bot.
// Lances em que o bot já estava levando mate não contam (qualquer lance perde).
// Calibração (relatório R171): partidas REAIS que os bots fortes perdem ficam em ~15–80; lances ao acaso ou de um
// motor fraco no lugar do bot ficam acima de ~115. Limite padrão 100 (FRAIHA_BOT_ACPL_MAX).
//
// Só os níveis fortes são conferidos (platina em diante + challenger): os níveis baixos ERRAM DE PROPÓSITO
// (lances ao acaso / perdas sorteadas), então não dá para distinguir "bot de verdade" de "lance inventado" neles.
const os = require('os');
const { UciEngine, winPct } = require('./engine');
const LADDER = require('../../bot/bot_ladder.json');

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const STRONG = new Set(LADDER.bots.filter(b => (b.engine.elo && b.engine.elo >= 1700) || (!b.engine.elo && (b.engine.skill ?? 0) >= 20)).map(b => b.id));
const MAX_BOT_MOVES = 80;          // conferimos no máximo os últimos 80 lances do bot (partidas muito longas)
const cpOf = e => e.mate ? (e.mate > 0 ? 1000 : -1000) : Math.max(-1000, Math.min(1000, e.cp));

// moves: lances UCI desde a posição inicial (já validados por chess_rules); botColor: 'w' | 'b'
async function measure(engine, moves, botColor) {
  const idx = [];
  for (let i = 0; i < moves.length; i++) if ((i % 2 === 0 ? 'w' : 'b') === botColor) idx.push(i);
  const losses = [], cont = [];
  for (const i of idx.slice(-MAX_BOT_MOVES)) {
    const before = await engine.analyse(START, { depth: 10, moves: moves.slice(0, i) });
    if (before.mate < 0) continue;   // bot já levando mate: não conta
    const after = await engine.analyse(START, { depth: 9, moves: moves.slice(0, i + 1) });
    const loss = Math.max(0, Math.min(1000, cpOf(before) + cpOf(after)));   // after é do ponto de vista do adversário
    losses.push(loss);
    const w = winPct(before);
    if (w > 8 && w < 92) cont.push(loss);
  }
  const avg = a => a.reduce((s, x) => s + x, 0) / Math.max(1, a.length);
  const mean = avg(losses), meanC = avg(cont);
  return { n: losses.length, nC: cont.length, mean: +mean.toFixed(1), meanC: +meanC.toFixed(1), score: +(cont.length >= 3 ? meanC : mean).toFixed(1) };
}

class BotVerifier {
  constructor({ env = process.env, engine = null, log = (...a) => console.log(...a) } = {}) {
    this.enabled = env.FRAIHA_BOT_VERIFY !== '0';
    this.max = Number(env.FRAIHA_BOT_ACPL_MAX || 100);
    this.maxQueue = Number(env.FRAIHA_BOT_VERIFY_QUEUE || 8);
    this.idleMs = Number(env.FRAIHA_BOT_ENGINE_IDLE_MS || 60000);
    this.engine = engine; this.injected = !!engine; this.ready = null; this.waiting = 0; this.idle = null; this.log = log;
  }
  needs(botId) { return this.enabled && STRONG.has(botId); }
  async _engine() {
    if (this.idle) { clearTimeout(this.idle); this.idle = null; }
    if (this.injected) return this.engine;
    if (!this.engine || !this.engine.proc) {
      this.engine = new UciEngine({ timeoutMs: 20000 });
      if (!this.engine.available()) throw new Error('engine_missing');
      this.ready = this.engine.init({ Threads: 1, Hash: 16 }).then(() => {
        try { os.setPriority(this.engine.proc.pid, 19); } catch { /* sem permissão: segue */ }   // nunca atrasa as partidas
      });
    }
    await this.ready;
    return this.engine;
  }
  _release() {
    if (this.injected || this.waiting > 0) return;
    this.idle = setTimeout(() => { if (this.engine) this.engine.stop(); this.engine = null; }, this.idleMs);
    if (this.idle.unref) this.idle.unref();
  }
  // { ok:true, stats } | { ok:false, code:'bot_game_rejected', stats } | { ok:false, code:'verify_busy'|'verify_unavailable' }
  async check(botId, moves, botColor) {
    if (!this.needs(botId)) return { ok: true, skipped: true };
    if (this.waiting >= this.maxQueue) return { ok: false, code: 'verify_busy' };
    this.waiting++;
    try {
      const engine = await this._engine();
      const stats = await measure(engine, moves, botColor);
      const ok = stats.score <= this.max;
      this.log('[bot-verify]', JSON.stringify({ bot: botId, ok, ...stats, limit: this.max }));
      return ok ? { ok: true, stats } : { ok: false, code: 'bot_game_rejected', stats };
    } catch (e) {
      console.error('[bot-verify] motor indisponível', e && e.message);
      if (this.engine && !this.injected) { this.engine.stop(); this.engine = null; }
      return { ok: false, code: 'verify_unavailable' };
    } finally { this.waiting--; this._release(); }
  }
  stop() { if (this.idle) clearTimeout(this.idle); if (this.engine && !this.injected) this.engine.stop(); this.engine = null; }
}

module.exports = { BotVerifier, measure, STRONG, START };
