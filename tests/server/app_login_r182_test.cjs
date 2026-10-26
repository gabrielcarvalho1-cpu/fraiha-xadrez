'use strict';
// R182 · login com Google no app Android: /app-login/done guarda o auth_code (PKCE) e /app-login/claim entrega UMA vez.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { AppLogin, TTL_MS } = require('../../online_v021/accounts/app_login');

async function srv(t, now) {
  const a = new AppLogin({ now });
  const s = http.createServer((req, res) => a.owns(req) ? a.handle(req, res, '10.0.0.1') : (res.writeHead(404), res.end()));
  await new Promise(r => s.listen(0, '127.0.0.1', r));
  t.after(() => s.close());
  const base = `http://127.0.0.1:${s.address().port}`;
  return { a, get: async p => { const r = await fetch(base + p); return { status: r.status, text: await r.text(), headers: r.headers }; } };
}
const C = 'ab'.repeat(16);

test('fluxo: done guarda o código, claim entrega uma vez só; depois "pending"', async t => {
  let clock = 1e12; const h = await srv(t, () => clock);
  assert.deepEqual(JSON.parse((await h.get('/app-login/claim?c=' + C)).text), { pending: true });
  const d = await h.get(`/app-login/done?c=${C}&code=3f2a1b4c-1111-4222-8333-444455556666`);
  assert.equal(d.status, 200); assert.match(d.text, /Volte para o app/); assert.equal(d.headers.get('cache-control'), 'no-store');
  assert.deepEqual(JSON.parse((await h.get('/app-login/claim?c=' + C)).text), { code: '3f2a1b4c-1111-4222-8333-444455556666' });
  assert.deepEqual(JSON.parse((await h.get('/app-login/claim?c=' + C)).text), { pending: true }, 'segunda busca não recebe de novo');
});

test('primeira gravação vale; formatos inválidos e expirado são descartados', async t => {
  let clock = 1e12; const h = await srv(t, () => clock);
  await h.get(`/app-login/done?c=${C}&code=primeiro_codigo`);
  const again = await h.get(`/app-login/done?c=${C}&code=outro_codigo`);
  assert.match(again.text, /expirou/);
  assert.equal(JSON.parse((await h.get('/app-login/claim?c=' + C)).text).code, 'primeiro_codigo');
  assert.equal((await h.get('/app-login/claim?c=xyz')).status, 400);
  assert.match((await h.get('/app-login/done?c=nao-hex&code=abcdefgh')).text, /expirou/);
  assert.match((await h.get(`/app-login/done?c=${'cd'.repeat(16)}&code=${encodeURIComponent('<script>')}`)).text, /expirou/);
  await h.get(`/app-login/done?c=${'ef'.repeat(16)}&code=codigo_velho`);
  clock += TTL_MS + 1;
  assert.deepEqual(JSON.parse((await h.get('/app-login/claim?c=' + 'ef'.repeat(16))).text), { pending: true });
});

test('erro do Google vira erro no app; limite por IP', async t => {
  let clock = 1e12; const h = await srv(t, () => clock);
  const C2 = '12'.repeat(16);
  assert.match((await h.get(`/app-login/done?c=${C2}&error=access_denied`)).text, /NÃO DEU CERTO/);
  assert.deepEqual(JSON.parse((await h.get('/app-login/claim?c=' + C2)).text), { error: 'access_denied' });
  let last = 200; for (let i = 0; i < 40; i++) last = (await h.get('/app-login/claim?c=' + C)).status;
  assert.equal(last, 429);
});

test('R184d · Android: done volta sozinho para o app (intent) com fallback /app-login/pronto; PC continua a página', async t => {
  let clock = 1e12; const a = new AppLogin({ now: () => clock });
  const s = http.createServer((req, res) => a.owns(req) ? a.handle(req, res, '10.0.0.2') : (res.writeHead(404), res.end()));
  await new Promise(r => s.listen(0, '127.0.0.1', r)); t.after(() => s.close());
  const base = `http://127.0.0.1:${s.address().port}`;
  const UA = 'Mozilla/5.0 (Linux; Android 14; SM-A145M) AppleWebKit/537.36 Chrome/129.0 Mobile Safari/537.36';
  const C3 = '34'.repeat(16);
  const r = await fetch(`${base}/app-login/done?c=${C3}&code=codigo_android`, { headers: { 'user-agent': UA }, redirect: 'manual' });
  assert.equal(r.status, 302);
  const loc = r.headers.get('location');
  assert.match(loc, /^intent:\/\/login#Intent;scheme=fraihaxadrez;package=com\.fraihaxadrez\.app;S\.browser_fallback_url=/);
  assert.ok(decodeURIComponent(loc).includes('/app-login/pronto'));
  assert.equal(JSON.parse(await (await fetch(`${base}/app-login/claim?c=${C3}`)).text()).code, 'codigo_android', 'o código foi guardado antes de voltar');
  const p = await fetch(`${base}/app-login/pronto`); const pt = await p.text();
  assert.equal(p.status, 200); assert.match(pt, /VOLTAR PARA O APP/); assert.match(pt, /intent:\/\/login/);
  const C4 = '56'.repeat(16);
  const pc = await fetch(`${base}/app-login/done?c=${C4}&code=codigo_pc`, { redirect: 'manual' });
  assert.equal(pc.status, 200); assert.match(await pc.text(), /Volte para o app/);
  const bad = await fetch(`${base}/app-login/done?c=${'78'.repeat(16)}&error=access_denied`, { headers: { 'user-agent': UA }, redirect: 'manual' });
  assert.equal(bad.status, 200, 'erro do Google não redireciona');
});

test('R193 · iPhone: done guarda o código e mostra VOLTAR PARA O APP (fraihaxadrez://login); PC sem o botão', async t => {
  const a = new AppLogin({ now: () => 1e12 });
  const s = http.createServer((req, res) => a.owns(req) ? a.handle(req, res, '10.0.0.3') : (res.writeHead(404), res.end()));
  await new Promise(r => s.listen(0, '127.0.0.1', r)); t.after(() => s.close());
  const base = `http://127.0.0.1:${s.address().port}`;
  const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 Version/18.5 Mobile/15E148 Safari/604.1';
  const C5 = '9a'.repeat(16);
  const r = await fetch(`${base}/app-login/done?c=${C5}&code=codigo_iphone`, { headers: { 'user-agent': UA }, redirect: 'manual' });
  assert.equal(r.status, 200, 'no iPhone não redireciona sozinho');
  const txt = await r.text();
  assert.match(txt, /VOLTAR PARA O APP/); assert.match(txt, /href="fraihaxadrez:\/\/login"/);
  assert.equal(JSON.parse(await (await fetch(`${base}/app-login/claim?c=${C5}`)).text()).code, 'codigo_iphone');
  const pc = await fetch(`${base}/app-login/done?c=${'9b'.repeat(16)}&code=x_pc_code`, { redirect: 'manual' });
  assert.doesNotMatch(await pc.text(), /fraihaxadrez:\/\//);
});
