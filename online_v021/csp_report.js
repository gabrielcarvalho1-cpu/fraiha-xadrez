'use strict';
// R171 · SEC-011: recebe os avisos do CSP em modo "report-only" do site do jogo (jogar.fraihaxadrez.com).
// Serve só para ver o que o CSP BLOQUEARIA antes de ligá-lo de verdade. Nunca guarda dados do jogador:
// registra no log só a diretiva, o host bloqueado e a página. Limitado por IP e no total; avisos iguais
// (mesma diretiva + mesmo host) entram 1 vez a cada 10 min.
const { Window, clientIp } = require('./net_guard');

const MAX_BODY = 16 * 1024, DUP_MS = 10 * 60e3;
const hostOf = u => {
  const s = String(u || '');
  if (!s || /^(inline|eval|wasm-eval|self|data|blob|mediastream)$/i.test(s)) return s.toLowerCase();
  try { const x = new URL(s); return x.protocol === 'data:' || x.protocol === 'blob:' ? x.protocol.slice(0, -1) : x.protocol + '//' + x.host; } catch { return s.slice(0, 40); }
};
const pathOf = u => { try { return new URL(String(u)).pathname.slice(0, 60); } catch { return ''; } };

class CspReports {
  constructor({ env = process.env, now = () => Date.now(), log = (...a) => console.log(...a) } = {}) {
    this.perIp = new Window({ windowMs: 60000, max: 20, maxKeys: 5000 });
    this.all = new Window({ windowMs: 60000, max: Number(env.FRAIHA_CSP_REPORTS_PER_MIN || 300) });
    this.seen = new Map(); this.now = now; this.log = log; this.count = 0;
  }
  owns(req) { return req.url === '/csp-report' || String(req.url).startsWith('/csp-report?'); }
  handle(req, res) {
    const done = code => { if (!res.headersSent) { res.writeHead(code, { 'access-control-allow-origin': '*' }); res.end(); } };
    if (req.method === 'OPTIONS') { res.writeHead(204, { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'POST', 'access-control-allow-headers': 'content-type' }); return void res.end(); }
    if (req.method !== 'POST') return done(405);
    if (!this.perIp.hit(clientIp(req)) || !this.all.hit('all')) { req.resume(); return done(429); }
    let raw = '', big = false;
    req.on('data', d => { if (big) return; raw += d; if (raw.length > MAX_BODY) { big = true; raw = ''; } });
    req.on('end', () => { if (!big) this.take(raw); done(204); });
    req.on('error', () => done(400));
  }
  take(raw) {
    let body; try { body = JSON.parse(raw); } catch { return; }
    // report-uri: { "csp-report": {...} }   ·   Reporting API: [{ type: "csp-violation", body: {...} }]
    const list = Array.isArray(body) ? body.filter(r => r && r.type === 'csp-violation').map(r => r.body || {}) : [body && body['csp-report'] || {}];
    for (const r of list.slice(0, 20)) {
      const directive = String(r['effective-directive'] || r.effectiveDirective || r['violated-directive'] || '').split(' ')[0].slice(0, 40);
      const blocked = hostOf(r['blocked-uri'] || r.blockedURL);
      const page = pathOf(r['document-uri'] || r.documentURL);
      if (!directive) continue;
      const key = directive + '|' + blocked, now = this.now();
      if (this.seen.size > 2000) this.seen.clear();
      if (now - (this.seen.get(key) || 0) < DUP_MS) continue;
      this.seen.set(key, now); this.count++;
      this.log('[csp-report]', JSON.stringify({ directive, blocked, page, disposition: String(r.disposition || 'report').slice(0, 10) }));
    }
  }
}

module.exports = { CspReports, hostOf };
