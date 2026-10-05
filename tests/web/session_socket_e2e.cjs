'use strict';
// NODE_PATH apontando para deps temporárias (ws, playwright-core), sem mudar manifests.
// FRAIHA_BROWSER_EXECUTABLE: Chrome/Chromium local; FRAIHA_BROWSER_PROFILE: pasta isolada.
// Testa WebSocket nativo em navegador real contra Backend local em memória, sem Godot/export.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const { WebSocketServer } = require('ws');
const { chromium } = require('playwright-core');
const { Backend } = require('../../online_v021/backend');
const A = '11111111-1111-4111-a111-111111111111', B = '22222222-2222-4222-a222-222222222222';
const user = id => ({ id, email: 'local@dev.invalid', provider: 'dev' });
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
test('Chrome nativo: races de login/logout/close, invalidação e fluxo normal', { timeout: 30000 }, async t => {
  const server = http.createServer((req, res) => { res.writeHead(200, { 'content-type': 'text/html' }); res.end('<!doctype html><title>Session WebSocket QA</title>'); });
  const wss = new WebSocketServer({ server }), active = new Set(); let socket, delay = null, closed = deferred();
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (ws, m) => { if (ws.readyState === 1) ws.send(JSON.stringify(m)); } });
  let context;
  t.after(async () => {
    if (context) await context.close(); for (const ws of wss.clients) ws.terminate();
    clearInterval(backend.sweeper); backend.presence.stop();
    await new Promise(r => wss.close(r)); await new Promise(r => server.close(r));
  });
  backend.auth = { verify: async token => token === 'slow' ? delay.promise : token === 'A' ? user(A) : token === 'B' ? user(B) : null };
  await backend.store.createProfile(A, 'AliceWeb', 'warrior'); await backend.store.createProfile(B, 'BobWeb', 'mage');
  wss.on('connection', ws => {
    socket = ws;
    ws.on('message', raw => {
      const m = JSON.parse(raw); backend.presence.touch(ws);
      if (m.type === 'ping') return ws.send(JSON.stringify({ type: 'pong' }));
      const p = backend.handle(ws, m); active.add(p); p.finally(() => active.delete(p));
    });
    ws.on('close', () => { backend.onClose(ws); closed.resolve(); });
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  context = await chromium.launchPersistentContext(path.resolve(process.env.FRAIHA_BROWSER_PROFILE || '.session-test-deps/browser-profile'), {
    executablePath: process.env.FRAIHA_BROWSER_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
    args: ['--disable-background-networking', '--disable-component-update', '--no-first-run'],
  });
  const page = context.pages()[0]; const port = server.address().port;
  await page.goto('http://127.0.0.1:' + port);
  await page.evaluate(port => {
    window.messages = []; window.waiters = [];
    window.openSocket = () => new Promise(resolve => {
      window.socket = new WebSocket('ws://127.0.0.1:' + port);
      window.socket.onopen = resolve;
      window.socket.onmessage = ev => {
        const m = JSON.parse(ev.data); window.messages.push(m);
        for (const w of [...window.waiters]) if (w.type === m.type) { window.waiters.splice(window.waiters.indexOf(w), 1); w.resolve(m); }
      };
    });
    window.next = type => new Promise(resolve => window.waiters.push({ type, resolve }));
    window.request = async (m, type) => { const p = window.next(type); window.socket.send(JSON.stringify(m)); return p; };
    return window.openSocket();
  }, port);
  const request = (m, type) => page.evaluate(({ m, type }) => window.request(m, type), { m, type });
  const settle = async () => { await Promise.all([...active]); await request({ type: 'ping' }, 'pong'); };
  // Browser envia A lento e B na mesma sequência; o servidor cancela A quando B chega.
  delay = deferred();
  let st = await page.evaluate(async () => {
    const result = window.next('acct_state');
    window.socket.send(JSON.stringify({ type: 'acct_auth', access_token: 'slow' }));
    window.socket.send(JSON.stringify({ type: 'acct_auth', access_token: 'B' })); return result;
  });
  assert.equal(st.user_id, B); delay.resolve(user(A)); await settle();
  assert.equal(socket.user.id, B); assert.equal(socket.identity.id, B); assert.equal(backend.online.has(A), false);
  assert.equal(await page.evaluate(() => window.messages.filter(m => m.type === 'acct_state').every(m => m.user_id === m.profile.user_id && m.user_id.endsWith('222222222222'))), true);
  // Logout chega mesmo sem ws.user confirmado.
  delay = deferred();
  await page.evaluate(async () => {
    const result = window.next('acct_logged_out');
    window.socket.send(JSON.stringify({ type: 'acct_auth', access_token: 'slow' }));
    window.socket.send(JSON.stringify({ type: 'acct_logout' })); return result;
  });
  delay.resolve(user(A)); await settle(); assert.equal(socket.user, null); assert.equal(socket.identity, null);
  const before = await page.evaluate(() => window.messages.filter(m => m.type === 'acct_state').length);
  assert.equal(before, 1);
  st = await request({ type: 'acct_auth', access_token: 'A' }, 'acct_state'); assert.equal(st.user_id, A);
  const err = await request({ type: 'acct_auth', access_token: 'invalid' }, 'acct_error');
  assert.equal(err.code, 'invalid_token'); assert.equal(socket.user, null); assert.equal(socket.profile, null); assert.equal(socket.identity, null);
  assert.equal(backend.presence.raw(A), 'offline'); assert.equal(backend.online.has(A), false);
  // Novo login/refresh/logout continuam no protocolo existente.
  st = await request({ type: 'acct_auth', access_token: 'B' }, 'acct_state'); assert.equal(st.user_id, B);
  st = await request({ type: 'acct_refresh' }, 'acct_state'); assert.equal(st.profile.nickname, 'BobWeb');
  await request({ type: 'acct_logout' }, 'acct_logged_out');
  // Fechamento físico antes da resposta de Auth.
  delay = deferred(); closed = deferred();
  await page.evaluate(() => window.socket.send(JSON.stringify({ type: 'acct_auth', access_token: 'slow' })));
  await request({ type: 'ping' }, 'pong'); // confirma que o servidor já recebeu o login lento
  const old = socket; await page.evaluate(() => new Promise(r => { window.socket.onclose = r; window.socket.close(); }));
  await closed.promise; delay.resolve(user(A)); await Promise.all([...active]);
  assert.equal(old.user, null); assert.equal(old.profile, null); assert.equal(old.identity, null);
  assert.equal([...backend.online.values()].some(s => s.has(old)), false);
  console.log('BROWSER_SESSION: Chrome headless real, 6 cenários; ' + await page.evaluate(() => navigator.userAgent));
});
