'use strict';
// R170 · HARDENING (auditoria Orca R168) — um teste de regressão por achado ALTO (SEC-001 a SEC-006).
// Tudo local: servidor próprio em porta aleatória, Supabase/Mercado Pago simulados. Nenhum serviço externo.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const net = require('net');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');
const WebSocket = require('ws');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { SupabaseAuth } = require('../../online_v021/accounts/auth');
const { MercadoPago } = require('../../online_v021/payments/providers/mercadopago');
const ROOT = path.join(__dirname, '..', '..');
const sleep = ms => new Promise(r => setTimeout(r, ms));

function startServer(env = {}) {
  const port = 30000 + Math.floor(Math.random() * 20000);
  const proc = spawn(process.execPath, [path.join(ROOT, 'online_v021/server.js')], {
    env: { ...process.env, PORT: String(port), FRAIHA_DEV_AUTH: '1', ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
  let out = '';
  proc.stdout.on('data', d => { out += d; }); proc.stderr.on('data', d => { out += d; });
  return { port, proc, log: () => out, ready: (async () => { for (let i = 0; i < 100 && !out.includes('listening'); i++) await sleep(50); })() };
}
const openWs = (port, headers = {}) => new Promise((resolve, reject) => {
  const ws = new WebSocket('ws://127.0.0.1:' + port, { headers });
  ws.on('open', () => resolve(ws)); ws.on('error', reject);
});
const ask = (ws, msg, type) => new Promise(resolve => {
  const on = raw => { const m = JSON.parse(raw); if (m.type === type) { ws.off('message', on); resolve(m); } };
  ws.on('message', on); ws.send(JSON.stringify(msg));
});

// ---------------------------------------------------------------- SEC-001
test('SEC-001: quadro WebSocket inválido não derruba o processo; o servidor segue aceitando conexões', async t => {
  const s = startServer(); t.after(() => s.proc.kill());
  await s.ready;
  for (const bad of [Buffer.from([0xf3, 0x80, 0, 0, 0, 0]), Buffer.from([0x81, 0x85, 0, 0, 0, 0, 0xff, 0xfe, 0xfd, 0xfc, 0xfb]), Buffer.from([0x89, 0xfe, 0xff, 0xff, 0, 0, 0, 0])]) {
    await new Promise(resolve => {
      const c = net.connect(s.port, '127.0.0.1', () => {
        const key = crypto.randomBytes(16).toString('base64');
        c.write(`GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`);
        c.once('data', () => { c.write(bad); setTimeout(() => { c.destroy(); resolve(); }, 150); });
      });
      c.on('error', () => resolve());
    });
  }
  await sleep(200);
  assert.equal(s.proc.exitCode, null, 'processo continua vivo: ' + s.log().slice(-300));
  const ws = await openWs(s.port);
  const pong = await ask(ws, { type: 'ping' }, 'pong');
  assert.equal(pong.type, 'pong');
  ws.close();
  assert.match(s.log(), /FRAIHA ws 8\.(2[1-9]|[3-9]\d)\./, 'versão do ws aparece no log de início');
});

test('SEC-001/002: conexões demais do mesmo IP são recusadas com 1013 (as outras continuam)', async t => {
  const s = startServer({ FRAIHA_MAX_CONN_PER_IP: '3' }); t.after(() => s.proc.kill());
  await s.ready;
  const keep = [];
  for (let i = 0; i < 3; i++) keep.push(await openWs(s.port));
  const extra = await openWs(s.port);
  const code = await new Promise(r => extra.on('close', c => r(c)));
  assert.equal(code, 1013);
  const pong = await ask(keep[0], { type: 'ping' }, 'pong');
  assert.equal(pong.type, 'pong');
  keep.forEach(w => w.close());
});

// ---------------------------------------------------------------- SEC-002
const jwt = (payload) => ['eyJhbGciOiJIUzI1NiJ9', Buffer.from(JSON.stringify(payload)).toString('base64url'), 'c2ln'].join('.');
test('SEC-002: tokens inventados não consultam o Supabase Auth; token recusado não é consultado de novo', async () => {
  let calls = 0;
  const auth = new SupabaseAuth({ url: 'https://x.supabase.co', apiKey: 'k', fetchImpl: async () => { calls++; return { ok: false, status: 401, json: async () => ({}) }; } });
  for (let i = 0; i < 300; i++) assert.equal(await auth.verify('x'.repeat(40 + (i % 50))), null);
  for (let i = 0; i < 300; i++) assert.equal(await auth.verify('aaaa.bbbb.cccc' + 'd'.repeat(i % 30 + 10)), null);
  assert.equal(calls, 0, 'formato inválido nunca chega ao Auth');
  const fake = jwt({ sub: 'u1', exp: Math.floor(Date.now() / 1000) + 3600 });
  for (let i = 0; i < 50; i++) await auth.verify(fake, { force: true });
  assert.equal(calls, 1, 'o mesmo token recusado só é consultado 1 vez');
  // token legítimo continua funcionando
  const good = jwt({ sub: 'u2', exp: Math.floor(Date.now() / 1000) + 3600 });
  const ok = new SupabaseAuth({ url: 'https://x.supabase.co', apiKey: 'k', fetchImpl: async () => ({ ok: true, status: 200, json: async () => ({ id: 'u2', email: 'a@b.c' }) }) });
  assert.equal((await ok.verify(good, { force: true })).id, 'u2');
});

function backendFixture(t, env = {}) {
  const out = [];
  const origLog = console.log; console.log = () => {}; t.after(() => { console.log = origLog; });
  const b = new Backend({ env: { FRAIHA_DEV_AUTH: '1', ...env }, send: (s, m) => out.push({ s, ...m }) });
  b.auth = { calls: 0, verify: async tok => { b.auth.calls++; const m = /^tok-(.+)$/.exec(tok); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  b.attachRanked(new Ranked({ send: b.send })); b.attachCasual(new Ranked({ send: b.send, kind: 'casual' }));
  b.ranked.stop(); b.casual.stop(); clearInterval(b.sweeper); b.presence.stop(); b.invites.stop();
  t.after(() => b.party.stop());
  return { b, out };
}
test('SEC-002: acct_auth limitado por conexão e por IP, sem derrubar o login que já existe; outro IP entra normal', async t => {
  const { b, out } = backendFixture(t, { FRAIHA_AUTH_PER_IP_MIN: '20' });
  await b.store.createProfile('11111111-1111-4111-a111-111111111111', 'Alice', 'warrior');
  const sa = { readyState: 1, ip: '9.9.9.9' };
  await b.handle(sa, { type: 'acct_auth', access_token: 'tok-11111111-1111-4111-a111-111111111111' });
  assert.ok(sa.user, 'login legítimo');
  for (let i = 0; i < 30; i++) await b.handle(sa, { type: 'acct_auth', access_token: 'lixo-' + i });
  const busy = out.filter(x => x.s === sa && x.code === 'auth_busy');
  assert.ok(busy.length >= 18, 'tentativas além do limite viram auth_busy (' + busy.length + ')');
  assert.ok(b.auth.calls <= 13, 'consultas ao Auth limitadas (' + b.auth.calls + ')');
  // muitas conexões do mesmo IP
  const before = b.auth.calls;
  for (let i = 0; i < 60; i++) await b.handle({ readyState: 1, ip: '7.7.7.7' }, { type: 'acct_auth', access_token: 'lixo' });
  assert.ok(b.auth.calls - before <= 20, 'por IP: no máximo 20/min (' + (b.auth.calls - before) + ')');
  const other = { readyState: 1, ip: '5.5.5.5' };
  await b.handle(other, { type: 'acct_auth', access_token: 'tok-11111111-1111-4111-a111-111111111111' });
  assert.ok(other.user, 'jogador de outro IP entra normalmente');
});

// ---------------------------------------------------------------- SEC-003
test('SEC-003: convidados têm teto e criação limitada por IP; quem está conectado não é expulso', async t => {
  const { b, out } = backendFixture(t, { FRAIHA_MAX_GUESTS: '50', FRAIHA_GUEST_PER_IP_MIN: '1000', FRAIHA_GUEST_GLOBAL_MIN: '100000' });
  const first = { readyState: 1, ip: '1.1.1.1' };
  await b.handle(first, { type: 'guest_auth' });
  const keepTok = out.find(x => x.s === first && x.type === 'guest_state').token;
  for (let i = 0; i < 400; i++) await b.handle({ readyState: 1, ip: '2.2.' + (i % 250) + '.1' }, { type: 'guest_auth' });
  assert.ok(b.guests.size <= 50, 'mapa de convidados no teto (' + b.guests.size + ')');
  assert.ok(b.guests.has(keepTok), 'convidado conectado não foi expulso');
  const { b: b2, out: out2 } = backendFixture(t, { FRAIHA_GUEST_PER_IP_MIN: '5' });
  for (let i = 0; i < 12; i++) await b2.handle({ readyState: 1, ip: '3.3.3.3' }, { type: 'guest_auth' });
  assert.equal(out2.filter(x => x.type === 'guest_state').length, 5, 'mesmo IP: 5 convidados novos por minuto');
  assert.ok(out2.some(x => x.type === 'guest_error' && x.code === 'busy'));
});

// ---------------------------------------------------------------- SEC-004
test('SEC-004: analysis_record só grava depois de análise liberada, 1 vez por partida, formato conferido', async t => {
  const { b } = backendFixture(t);
  const U = '22222222-2222-4222-a222-222222222222';
  await b.store.createProfile(U, 'Bob', 'warrior');
  const ws = { readyState: 1, ip: '4.4.4.4' };
  await b.handle(ws, { type: 'acct_auth', access_token: 'tok-' + U });
  const sum = { match_id: '', mode: 'bot', played_at: 1760900000, color: 'w', result: 'win', accuracy: 88.5, counts: { best: 3 }, critical_ply: 4, best_ply: 2,
    moves: [{ u: 'e2e4', c: 'best', l: 0, b: 'e2e4' }], engine: 'sf', depth: 12, phases: { opening: 1 }, opponent: 'BOT', plies: 1 };
  const saved = () => (b.store.analyses || []).length;
  for (let i = 0; i < 20; i++) await b.handle(ws, { type: 'analysis_record', summary: { ...sum, played_at: sum.played_at + i } });
  assert.equal(saved(), 0, 'sem analysis_request liberado nada é gravado');
  await b.handle(ws, { type: 'analysis_request' });
  await b.handle(ws, { type: 'analysis_record', summary: { ...sum, accuracy: 900 } });
  await b.handle(ws, { type: 'analysis_record', summary: { ...sum, moves: [{ u: 'x'.repeat(500) }] } });
  await b.handle(ws, { type: 'analysis_record', summary: { ...sum, mode: 'hack' } });
  assert.equal(saved(), 0, 'dados fora do formato são recusados');
  await b.handle(ws, { type: 'analysis_record', summary: sum });
  assert.equal(saved(), 1, 'análise válida e liberada é gravada');
  assert.equal(b.store.analyses[0].phases, undefined, 'campos extras não vão para o banco');
  await b.handle(ws, { type: 'analysis_request' });
  await b.handle(ws, { type: 'analysis_record', summary: sum });
  assert.equal(saved(), 1, 'a mesma partida não é gravada duas vezes');
});

// ---------------------------------------------------------------- SEC-005
test('SEC-005: ws fixado em 8.22.0 (package.json + package-lock.json + npm ci) e versão instalada fora do advisory', () => {
  const pkg = require(path.join(ROOT, 'package.json'));
  const lock = require(path.join(ROOT, 'package-lock.json'));
  assert.equal(pkg.dependencies.ws, '8.22.0');
  assert.equal(lock.packages['node_modules/ws'].version, '8.22.0');
  const fs = require('fs');
  assert.match(fs.readFileSync(path.join(ROOT, 'Dockerfile'), 'utf8'), /npm ci/);
  const [maj, min] = require('ws/package.json').version.split('.').map(Number);
  assert.ok(maj > 8 || (maj === 8 && min >= 21), 'ws instalado >= 8.21.0');
});

// ---------------------------------------------------------------- SEC-006
test('SEC-006: avisos sem assinatura não viram consultas em massa ao Mercado Pago', async () => {
  const mp = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'TEST', FRAIHA_PUBLIC_URL: 'https://x', FRAIHA_MP_UNSIGNED_PER_MIN: '30' });
  let lookups = 0;
  mp.lookup = async () => { lookups++; return { ignore: true }; };
  const origWarn = console.warn; console.warn = () => {};
  try {
    const req = id => ({ url: '/webhooks/payments?type=payment&data.id=' + id, headers: {} });
    for (let i = 0; i < 200; i++) await mp.verifyWebhook(req('pay' + i), '');
    assert.ok(lookups <= 30, 'no máximo 30 consultas por minuto sem assinatura (' + lookups + ')');
    const mp2 = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'TEST', FRAIHA_PUBLIC_URL: 'https://x' });
    let l2 = 0; mp2.lookup = async () => { l2++; return { ignore: true }; };
    for (let i = 0; i < 10; i++) await mp2.verifyWebhook(req('mesmo'), '');
    assert.equal(l2, 1, 'o mesmo aviso repetido é consultado 1 vez');
    assert.equal(await mp2.verifyWebhook(req('<script>'), ''), null, 'id fora do formato é recusado antes de qualquer trabalho');
    const strict = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'TEST', FRAIHA_PUBLIC_URL: 'https://x', FRAIHA_MP_WEBHOOK_SECRET: 's', FRAIHA_MP_REQUIRE_SIGNATURE: '1' });
    let l3 = 0; strict.lookup = async () => { l3++; return {}; };
    assert.equal(await strict.verifyWebhook(req('p1'), ''), null);
    assert.equal(await strict.verifyWebhook({ ...req('p2'), headers: { 'x-signature': 'ts=1,v1=00' } }, ''), null);
    assert.equal(l3, 0, 'assinatura ausente/errada não consulta o provedor');
  } finally { console.warn = origWarn; }
});

test('SEC-006: X-Forwarded-For variado não contorna o limite do webhook (teto global)', async t => {
  const s = startServer({ FRAIHA_WEBHOOK_MAX_PER_MIN: '40' }); t.after(() => s.proc.kill());
  await s.ready;
  const post = xff => new Promise(resolve => {
    const r = http.request({ host: '127.0.0.1', port: s.port, path: '/webhooks/payments?type=other&data.id=1', method: 'POST', headers: { 'x-forwarded-for': xff, 'content-type': 'application/json' } }, res => { res.resume(); resolve(res.statusCode); });
    r.on('error', () => resolve(0)); r.end('{}');
  });
  const codes = [];
  for (let i = 0; i < 120; i++) codes.push(await post(`10.0.${i}.1, 66.66.66.${i % 200}`));
  const passed = codes.filter(c => c !== 429).length;
  assert.ok(passed <= 40, 'passaram ' + passed + ' de 120 (teto 40/min)');
  assert.ok(codes.includes(429));
});
