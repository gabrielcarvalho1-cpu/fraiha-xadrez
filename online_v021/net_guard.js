'use strict';
// R170 · HARDENING (auditoria Orca R168): utilitários de proteção de rede, sem dependências.
//   clientIp     — IP do cliente atrás do proxy do Render: o ÚLTIMO valor do X-Forwarded-For é o que o proxy
//                  confiável acrescentou (o primeiro pode ser escrito pelo próprio remetente).
//   Window       — limite por chave numa janela fixa, com teto de chaves (memória limitada).
//   Gate         — no máximo N operações simultâneas (ex.: consultas ao Supabase Auth).

function clientIp(req) {
  const xff = String((req && req.headers && req.headers['x-forwarded-for']) || '');
  const parts = xff.split(',').map(s => s.trim()).filter(Boolean);
  const ip = parts.length ? parts[parts.length - 1] : String((req && req.socket && req.socket.remoteAddress) || '');
  return ip.replace(/^::ffff:/, '').slice(0, 64) || 'unknown';
}

class Window {
  constructor({ windowMs, max, maxKeys = 20000, now = () => Date.now() }) {
    this.windowMs = windowMs; this.max = max; this.maxKeys = maxKeys; this.now = now;
    this.map = new Map();
  }
  // true = pode; false = passou do limite nesta janela
  hit(key, n = 1) {
    const t = this.now();
    let e = this.map.get(key);
    if (!e || t - e.start >= this.windowMs) {
      if (!e && this.map.size >= this.maxKeys) this.prune(t);
      e = { start: t, n: 0 };
      this.map.set(key, e);
    }
    e.n += n;
    return e.n <= this.max;
  }
  prune(t = this.now()) {
    for (const [k, e] of this.map) if (t - e.start >= this.windowMs) this.map.delete(k);
    if (this.map.size >= this.maxKeys) {   // ainda cheio (ataque espalhado): descarta as mais antigas
      let drop = this.map.size - Math.floor(this.maxKeys * 0.8);
      for (const k of this.map.keys()) { if (drop-- <= 0) break; this.map.delete(k); }
    }
  }
}

class Gate {
  constructor(max) { this.max = max; this.active = 0; }
  busy() { return this.active >= this.max; }
  async run(fn) {
    this.active++;
    try { return await fn(); } finally { this.active--; }
  }
}

module.exports = { clientIp, Window, Gate };
