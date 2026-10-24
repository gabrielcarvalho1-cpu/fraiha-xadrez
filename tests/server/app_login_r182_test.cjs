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
