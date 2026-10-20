'use strict';
// R171 · SEC-011 — CSP do site do jogo (report-only) e o receptor /csp-report do servidor.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { pathToFileURL } = require('url');
const { CspReports } = require('../../online_v021/csp_report');

const worker = () => import(pathToFileURL(path.join(__dirname, '../../web/cdn/fraiha-web-worker.mjs')).href);
const dir = p => Object.fromEntries(p.split(';').map(s => s.trim().split(/\s+/)).map(([k, ...v]) => [k, v]));

test('SEC-011: política sem curinga solto e com o que o jogo usa (Godot/WASM, workers, Agora, WebSocket, Supabase, Mercado Pago, Cloudflare)', async () => {
  const m = await worker();
  const d = dir(m.CSP_POLICY);
  for (const [k, v] of Object.entries(d)) for (const s of v) assert.ok(s !== '*' && !/^(https?|wss?):?$/.test(s) && s !== 'https:' && s !== 'wss:', `${k} sem curinga: ${s}`);
  assert.ok(d['script-src'].includes("'wasm-unsafe-eval'"), 'Godot/Stockfish (WebAssembly)');
  assert.ok(d['script-src'].includes("'unsafe-eval'"), 'JavaScriptBridge.eval do Godot');
  assert.ok(d['worker-src'].includes("'self'"), 'motor de análise (Worker)');
  for (const h of ['wss://fraiha-xadrez.onrender.com', 'https://xbdkrrbppbhpufplnsbw.supabase.co', 'wss://*.agora.io', 'https://*.sd-rtn.com', 'https://*.mercadopago.com'])
    assert.ok(d['connect-src'].includes(h), 'connect-src ' + h);
  assert.ok(d['script-src'].includes('https://sdk.mercadopago.com'));
  assert.ok(d['frame-src'].includes('https://*.mercadopago.com'), 'campos do cartão (iframes do Mercado Pago)');
  assert.ok(d['media-src'].includes('mediastream:'), 'voz (Agora)');
  assert.deepEqual(d['object-src'], ["'none'"]);
  assert.deepEqual(d['frame-ancestors'], ["'self'"]);
  assert.equal(m.CSP_HEADER, 'content-security-policy-report-only', 'começa em modo relatório (não bloqueia)');
});

test('SEC-011: o Worker põe o CSP só no index.html', async () => {
  const m = await worker();
  const objs = { 'index.html': '<html></html>', 'index-e0123456789abcdef.js': 'x' };
  const env = { BUCKET: { get: async k => objs[k] === undefined ? null : { body: objs[k], size: objs[k].length, httpEtag: '"e"', writeHttpMetadata() {} }, head: async () => null } };
  const go = p => m.default.fetch(new Request('https://jogar.fraihaxadrez.com' + p), env);
  assert.ok((await go('/')).headers.get('content-security-policy-report-only').includes("object-src 'none'"));
  assert.equal((await go('/index-e0123456789abcdef.js')).headers.get('content-security-policy-report-only'), null);
});

function fakeReq(body, { method = 'POST', ip = '1.2.3.4' } = {}) {
  const h = {};
  const req = { method, url: '/csp-report', headers: { 'x-forwarded-for': ip }, socket: { remoteAddress: ip },
    on(ev, fn) { h[ev] = fn; if (ev === 'end') setImmediate(() => { if (h.data) h.data(Buffer.from(body)); h.end(); }); return req; }, resume() {} };
  const res = { status: 0, headersSent: false, writeHead(s) { this.status = s; this.headersSent = true; }, end() { this.ended = true; } };
  return { req, res };
}
const send = (c, body, o) => new Promise(r => { const { req, res } = fakeReq(typeof body === 'string' ? body : JSON.stringify(body), o); c.handle(req, res); setImmediate(() => setImmediate(() => r(res))); });
const rep = (blocked, directive = 'connect-src') => ({ 'csp-report': { 'document-uri': 'https://jogar.fraihaxadrez.com/index.html?token=segredo', 'effective-directive': directive, 'blocked-uri': blocked } });

test('SEC-011: /csp-report registra só diretiva + host (sem caminho/consulta), agrupa repetidos e aceita os 2 formatos', async () => {
  const logs = [];
  const c = new CspReports({ log: (...a) => logs.push(a.join(' ')) });
  assert.equal((await send(c, rep('https://evil.example/roubar?cookie=abc'))).status, 204);
  await send(c, rep('https://evil.example/outra'));
  await send(c, [{ type: 'csp-violation', body: { effectiveDirective: 'script-src-elem', blockedURL: 'https://x.example/a.js', documentURL: 'https://jogar.fraihaxadrez.com/' } }]);
  assert.equal(logs.length, 2, 'mesmo host + diretiva entra 1 vez');
  assert.ok(logs[0].includes('https://evil.example') && !logs[0].includes('cookie') && !logs[0].includes('segredo'));
  assert.ok(logs[1].includes('script-src-elem'));
});

test('SEC-011: /csp-report com limites (corpo grande, lixo, método errado, muitas por IP)', async () => {
  const logs = [];
  const c = new CspReports({ log: (...a) => logs.push(a.join(' ')) });
  assert.equal((await send(c, 'x'.repeat(20000))).status, 204);
  assert.equal((await send(c, '{não é json')).status, 204);
  assert.equal((await send(c, '', { method: 'GET' })).status, 405);
  assert.equal(logs.length, 0);
  let limited = 0;
  for (let i = 0; i < 30; i++) if ((await send(c, rep('https://h' + i + '.example/'), { ip: '5.5.5.5' })).status === 429) limited++;
  assert.equal(limited, 10, '20 por minuto por IP');
  assert.equal((await send(c, rep('https://outro.example/'), { ip: '6.6.6.6' })).status, 204, 'outro IP segue');
});
