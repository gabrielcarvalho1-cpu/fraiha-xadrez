// FRAIHA Admin · ENTRAR COM GOOGLE (admin/src/oauth.js): início do OAuth, retorno, marcador de uso único,
// endereço limpo, sem open redirect. Rodar: node --test tests/admin/oauth_test.mjs
// (Unitário com objetos falsos de location/history/storage; o Google/Supabase REAL não é chamado.)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startGoogle, consumeGoogleReturn, adminReturnUrl, googleAuthorizeUrl } from '../../admin/src/oauth.js';
import { SUPABASE } from '../../admin/src/config.js';

function mem() { const m = new Map(); return { getItem: k => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: k => m.delete(k), m }; }
function fakeLoc(href) { const u = new URL(href); return { origin: u.origin, pathname: u.pathname, search: u.search, hash: u.hash, assigned: null, assign(x) { this.assigned = x; } }; }
function fakeHistory(loc) { return { calls: [], replaceState(_s, _t, url) { this.calls.push(url); loc.hash = ''; loc.search = ''; } }; }
const T0 = 1_700_000_000_000;

test('início: URL do Supabase /authorize com provider=google e redirect_to = página canônica do Admin', () => {
  for (const [href, expected] of [
    ['https://fraiha-xadrez-staging.onrender.com/admin/', 'https://fraiha-xadrez-staging.onrender.com/admin/'],
    ['https://fraiha-xadrez-staging.onrender.com/admin/index.html?x=1#/queues', 'https://fraiha-xadrez-staging.onrender.com/admin/'],
    ['https://fraiha-xadrez-staging.onrender.com/admin/?redirect_to=https://evil.example#/dashboard', 'https://fraiha-xadrez-staging.onrender.com/admin/'],
  ]) {
    const loc = fakeLoc(href), storage = mem();
    startGoogle('staging', { loc, storage, now: T0 });
    const u = new URL(loc.assigned);
    assert.equal(u.origin + u.pathname, SUPABASE.url + '/auth/v1/authorize');
    assert.equal(u.searchParams.get('provider'), 'google');
    assert.equal(u.searchParams.get('redirect_to'), expected, 'redirect_to nunca vem de parâmetro/hash (sem open redirect)');
    assert.deepEqual(JSON.parse(storage.getItem('fraiha_admin_oauth')), { env: 'staging', at: T0 }, 'marcador sem credencial');
  }
  assert.equal(adminReturnUrl(fakeLoc('http://127.0.0.1:8140/admin/index.html')), 'http://127.0.0.1:8140/admin/');
  assert.equal(googleAuthorizeUrl('https://a.b/admin/'), SUPABASE.url + '/auth/v1/authorize?provider=google&redirect_to=https%3A%2F%2Fa.b%2Fadmin%2F');
});

test('início: LOCAL (conta DEV) não tem Google; ambiente desconhecido recusado', () => {
  assert.throws(() => startGoogle('local', { loc: fakeLoc('http://127.0.0.1:8140/admin/'), storage: mem() }), /google_not_available/);
  assert.throws(() => startGoogle('evil', { loc: fakeLoc('http://127.0.0.1:8140/admin/'), storage: mem() }), /google_not_available/);
});

test('retorno válido: devolve token + ambiente, limpa a barra de endereço e consome o marcador (uso único)', () => {
  const storage = mem(); storage.setItem('fraiha_admin_oauth', JSON.stringify({ env: 'staging', at: T0 }));
  const loc = fakeLoc('https://s.example/admin/#access_token=eyJhbGciOi.abc.def&refresh_token=rt_secret&provider_token=goog&expires_in=3600&token_type=bearer');
  const history = fakeHistory(loc);
  const r = consumeGoogleReturn({ loc, history, storage, now: T0 + 5000 });
  assert.deepEqual(r, { envKey: 'staging', token: 'eyJhbGciOi.abc.def' }, 'refresh token e token do Google descartados');
  assert.deepEqual(history.calls, ['/admin/'], 'tokens removidos do endereço');
  assert.equal(storage.getItem('fraiha_admin_oauth'), null, 'marcador consumido');
  // repetir o MESMO retorno (ex.: voltar no histórico) não loga de novo
  const loc2 = fakeLoc('https://s.example/admin/#access_token=eyJhbGciOi.abc.def');
  assert.match(consumeGoogleReturn({ loc: loc2, history: fakeHistory(loc2), storage, now: T0 + 6000 }).error, /não iniciou um login/);
});

test('retorno SEM login iniciado nesta aba (link pronto com token de outra pessoa) é ignorado', () => {
  const loc = fakeLoc('https://s.example/admin/#access_token=eyJ.atacante.x');
  const history = fakeHistory(loc);
  const r = consumeGoogleReturn({ loc, history, storage: mem(), now: T0 });
  assert.ok(r.error && !r.token); assert.deepEqual(history.calls, ['/admin/'], 'mesmo assim o token sai da barra');
});

test('marcador vencido (> 10 min), do futuro, de ambiente DEV ou corrompido → ignorado', () => {
  for (const v of [JSON.stringify({ env: 'staging', at: T0 - 11 * 60e3 }), JSON.stringify({ env: 'staging', at: T0 + 60e3 }),
    JSON.stringify({ env: 'local', at: T0 }), '{quebrado', JSON.stringify({ env: 'staging' })]) {
    const storage = mem(); storage.setItem('fraiha_admin_oauth', v);
    const loc = fakeLoc('https://s.example/admin/#access_token=eyJ.a.b');
    assert.ok(consumeGoogleReturn({ loc, history: fakeHistory(loc), storage, now: T0 }).error, v);
  }
});

test('OAuth cancelado/falha (hash ou query) → erro legível, sem token', () => {
  for (const href of ['https://s.example/admin/#error=access_denied&error_description=The+user+denied+access',
    'https://s.example/admin/?error=server_error&error_description=Unable%20to%20exchange']) {
    const storage = mem(); storage.setItem('fraiha_admin_oauth', JSON.stringify({ env: 'production', at: T0 }));
    const loc = fakeLoc(href); const history = fakeHistory(loc);
    const r = consumeGoogleReturn({ loc, history, storage, now: T0 + 1000 });
    assert.match(r.error, /Login com Google não concluído: (The user denied access|Unable to exchange)/);
    assert.equal(r.token, undefined); assert.deepEqual(history.calls, ['/admin/']);
  }
});

test('token em formato inválido → recusado; página normal (#/dashboard) → nada a fazer', () => {
  const storage = mem(); storage.setItem('fraiha_admin_oauth', JSON.stringify({ env: 'staging', at: T0 }));
  const loc = fakeLoc('https://s.example/admin/#access_token=%3Cscript%3E');
  assert.match(consumeGoogleReturn({ loc, history: fakeHistory(loc), storage, now: T0 }).error, /resposta inválida/);
  const normal = fakeLoc('https://s.example/admin/#/dashboard'); const h = fakeHistory(normal);
  assert.equal(consumeGoogleReturn({ loc: normal, history: h, storage: mem(), now: T0 }), null);
  assert.deepEqual(h.calls, []);
});
