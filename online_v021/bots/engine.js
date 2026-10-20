'use strict';
// R171 · SEC-008: o MESMO Stockfish 19 lite do jogo (web/engines), rodando no servidor como processo filho (UCI).
// Usado só para conferir reivindicações de vitória contra bot (raras: 1 por bot por conta). Um processo, uma
// análise por vez; se o motor não subir, quem chama decide (bots/service.js recusa a reivindicação dos bots fortes).
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const DEFAULT_PATH = path.join(__dirname, '..', '..', 'web', 'engines', 'stockfish-19-lite-single.js');

class UciEngine {
  constructor({ file = process.env.FRAIHA_ENGINE_PATH || DEFAULT_PATH, timeoutMs = 15000 } = {}) {
    this.file = file; this.timeoutMs = timeoutMs;
    this.proc = null; this.buf = ''; this.waiters = []; this.queue = Promise.resolve();
  }
  available() { return fs.existsSync(this.file); }
  start() {
    if (this.proc) return;
    this.proc = spawn(process.execPath, [this.file], { stdio: ['pipe', 'pipe', 'ignore'], cwd: path.dirname(this.file) });
    this.proc.on('exit', () => { this.proc = null; for (const w of this.waiters.splice(0)) w.reject(new Error('engine_exit')); });
    this.proc.on('error', () => { this.proc = null; });
    this.proc.stdout.setEncoding('utf8');
    this.proc.stdout.on('data', d => {
      this.buf += d;
      let i;
      while ((i = this.buf.indexOf('\n')) >= 0) {
        const line = this.buf.slice(0, i).trim(); this.buf = this.buf.slice(i + 1);
        for (const w of this.waiters.slice()) if (w.test(line)) { this.waiters.splice(this.waiters.indexOf(w), 1); w.resolve(line); } else if (w.collect) w.collect(line);
      }
    });
  }
  write(s) { if (this.proc) this.proc.stdin.write(s + '\n'); }
  waitFor(test, collect) {
    return new Promise((resolve, reject) => {
      const w = { test, collect, resolve, reject };
      const timer = setTimeout(() => { const k = this.waiters.indexOf(w); if (k >= 0) this.waiters.splice(k, 1); reject(new Error('engine_timeout')); }, this.timeoutMs);
      w.resolve = v => { clearTimeout(timer); resolve(v); };
      w.reject = e => { clearTimeout(timer); reject(e); };
      this.waiters.push(w);
    });
  }
  async init(opts = {}) {
    this.start();
    if (!this.proc) throw new Error('engine_unavailable');
    this.write('uci'); await this.waitFor(l => l === 'uciok');
    for (const [k, v] of Object.entries(opts)) this.write(`setoption name ${k} value ${v}`);
    this.write('isready'); await this.waitFor(l => l === 'readyok');
  }
  // tudo passa por uma fila: uma busca de cada vez
  run(fn) { const p = this.queue.then(fn, fn); this.queue = p.catch(() => {}); return p; }
  setOptions(opts) {
    return this.run(async () => {
      for (const [k, v] of Object.entries(opts)) this.write(`setoption name ${k} value ${v}`);
      this.write('isready'); await this.waitFor(l => l === 'readyok');
    });
  }
  // avaliação da posição para QUEM JOGA: { cp, mate, best }
  analyse(fen, { depth = 10, movetime = 0, moves = [] } = {}) {
    return this.run(async () => {
      let last = null;
      this.write('position fen ' + fen + (moves.length ? ' moves ' + moves.join(' ') : ''));
      this.write(movetime ? `go movetime ${movetime}` : `go depth ${depth}`);
      const best = await this.waitFor(l => l.startsWith('bestmove'), l => { if (l.startsWith('info') && / score /.test(l) && !/ multipv [2-9]/.test(l)) last = l; });
      const out = { best: best.split(/\s+/)[1], cp: 0, mate: 0 };
      if (last) {
        const m = / score (cp|mate) (-?\d+)/.exec(last);
        if (m) { if (m[1] === 'cp') out.cp = Number(m[2]); else out.mate = Number(m[2]); }
      }
      return out;
    });
  }
  stop() { try { this.write('quit'); } catch {} if (this.proc) this.proc.kill(); this.proc = null; }
}

// % de vitória de quem joga (mesma curva da análise do jogo / chess.com)
function winPct({ cp = 0, mate = 0 }) {
  if (mate) return mate > 0 ? 100 : 0;
  return 50 + 50 * (2 / (1 + Math.exp(-0.00368208 * cp)) - 1);
}

module.exports = { UciEngine, winPct, DEFAULT_PATH };
