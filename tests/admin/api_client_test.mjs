// FRAIHA Admin · cliente da API (admin/src/api.js) — auditoria Orca: timeout cobre a operação INTEIRA
// (cabeçalhos + corpo), revogação no logout e nada de sucesso falso. Rodar: node --test tests/admin/api_client_test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { Api, ApiError } from '../../admin/src/api.js';

function server(handler) {
  return new Promise(res => { const s = http.createServer(handler); s.listen(0, '127.0.0.1', () => res(s)); });
}
const apiFor = (s, token = 'tok') => { const a = new Api('local', token); a.env = { api: `http://127.0.0.1:${s.address().port}` }; return a; };

test('timeout ANTES dos cabeçalhos → ApiError timeout', async t => {
  const s = await server(() => {}); t.after(() => s.close(() => {}));
  s.closeAllConnections && t.after(() => s.closeAllConnections());
  const t0 = Date.now();
  await assert.rejects(apiFor(s).request('/x', { timeout: 300 }), e => e instanceof ApiError && e.kind === 'timeout');
  assert.ok(Date.now() - t0 < 2000);
});

test('timeout DEPOIS dos cabeçalhos com corpo JSON incompleto/travado → termina com timeout (não fica pendurado)', async t => {
  const s = await server((req, res) => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.write('{"cards":{"online_now":'); /* trava */ });
  t.after(() => { s.closeAllConnections && s.closeAllConnections(); s.close(() => {}); });
  const t0 = Date.now();
  await assert.rejects(apiFor(s).request('/x', { timeout: 400 }), e => e instanceof ApiError && e.kind === 'timeout');
  const dt = Date.now() - t0;
  assert.ok(dt >= 350 && dt < 2500, 'terminou no prazo: ' + dt);
});

test('corpo inválido ou vazio com 200 NÃO é sucesso', async t => {
  let mode = 'bad';
  const s = await server((req, res) => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(mode === 'bad' ? '{quebrado' : ''); });
  t.after(() => { s.closeAllConnections && s.closeAllConnections(); s.close(() => {}); });
  await assert.rejects(apiFor(s).get('/x'), e => e instanceof ApiError && e.code === 'bad_response');
  mode = 'empty';
  await assert.rejects(apiFor(s).get('/x'), e => e instanceof ApiError && e.code === 'bad_response');
});

test('recuperação: depois de um timeout, a próxima chamada funciona', async t => {
  let stall = true;
  const s = await server((req, res) => { if (stall) { res.writeHead(200); res.write('{'); return; } res.writeHead(200, { 'Content-Type': 'application/json' }); res.end('{"ok":true}'); });
  t.after(() => { s.closeAllConnections && s.closeAllConnections(); s.close(() => {}); });
  const api = apiFor(s);
  await assert.rejects(api.request('/x', { timeout: 300 }), e => e.kind === 'timeout');
  stall = false;
  assert.deepEqual(await api.get('/x'), { ok: true });
});

test('revoke (logout): requisição em voo é abortada e nenhuma nova sai', async t => {
  let hits = 0;
  const s = await server((req, res) => { hits++; setTimeout(() => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end('{"ok":true}'); }, 500); });
  t.after(() => { s.closeAllConnections && s.closeAllConnections(); s.close(() => {}); });
  const api = apiFor(s);
  const p = api.get('/x');
  await new Promise(r => setTimeout(r, 100));
  api.revoke();
  await assert.rejects(p, e => e instanceof ApiError && e.kind === 'revoked', 'resposta tardia não vira sucesso');
  const before = hits;
  await assert.rejects(api.post('/admin/api/queues/ranked', { enabled: false }), e => e.kind === 'revoked');
  await new Promise(r => setTimeout(r, 100));
  assert.equal(hits, before, 'nenhuma requisição nova depois do logout');
  assert.equal(api.token, '', 'token apagado da memória');
});
