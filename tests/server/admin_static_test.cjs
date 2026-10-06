'use strict';
// FRAIHA Admin · frontend servido em /admin/ pelo PRÓPRIO servidor do jogo (online_v021/server.js).
// Sobe o servidor real (processo filho, porta livre, contas DEV em memória) e confere: frontend e assets,
// API intacta (não capturada pelo estático), 404 sem vazar conteúdo, path traversal recusado, sem listagem,
// GET / igual, WebSocket do jogo funcionando, e Admin desligado (sem FRAIHA_ADMIN_USERS) → nem a tela.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('child_process');
const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const ROOT = path.resolve(__dirname, '..', '..');
const BOSS = '1ea3aa2e-1217-4d41-a665-c1a26b626cde';   // UUID determinístico de dev:boss (DevAuth)

const freePort = () => new Promise(res => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); }); });

async function startServer(t, extraEnv) {
  const port = await freePort();
  const env = { ...process.env, PORT: String(port), FRAIHA_DEV_AUTH: '1', FRAIHA_ENV: 'local', ...extraEnv };
  for (const k of ['SUPABASE_URL', 'SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY']) delete env[k];
  if (!extraEnv.FRAIHA_ADMIN_USERS) delete env.FRAIHA_ADMIN_USERS;
  const child = spawn(process.execPath, ['online_v021/server.js'], { cwd: ROOT, env, stdio: ['ignore', 'pipe', 'pipe'] });
  let out = ''; child.stdout.on('data', d => { out += d; }); child.stderr.on('data', d => { out += d; });
  t.after(() => child.kill());
  for (let i = 0; i < 100; i++) {   // espera o servidor aceitar conexões
    try { const r = await get(port, '/'); if (r.status === 200) return port; } catch { /* ainda subindo */ }
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('servidor não subiu: ' + out);
}

// Requisição crua (o caminho vai EXATAMENTE como escrito, sem normalização do cliente).
function get(port, rawPath, { method = 'GET', headers = {} } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method, path: rawPath, headers }, res => {
      const chunks = []; res.on('data', c => chunks.push(c)); res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString('utf8') }));
    });
    req.on('error', reject); req.end();
  });
}

const read = rel => fs.readFileSync(path.join(ROOT, rel), 'utf8');

test('Admin LIGADO: /admin/ serve o frontend, assets corretos, API intacta, nada além do Admin exposto, jogo funcionando', async t => {
  const port = await startServer(t, { FRAIHA_ADMIN_USERS: `${BOSS}=owner` });

  // --- frontend
  const idx = await get(port, '/admin/');
  assert.equal(idx.status, 200);
  assert.match(idx.headers['content-type'], /^text\/html/);
  assert.equal(idx.body, read('admin/index.html'), '/admin/ = admin/index.html');
  assert.match(idx.headers['content-security-policy'], /script-src 'self'/);
  assert.match(idx.headers['content-security-policy'], /frame-ancestors 'none'/);
  assert.equal(idx.headers['x-frame-options'], 'DENY');
  assert.equal(idx.headers['x-content-type-options'], 'nosniff');
  assert.equal((await get(port, '/admin/index.html')).body, idx.body);
  assert.equal((await get(port, '/admin/?v=1')).status, 200, 'query string não quebra');
  // acesso direto sem barra → redireciona para /admin/ (os caminhos relativos do index dependem da barra)
  const bare = await get(port, '/admin');
  assert.equal(bare.status, 301); assert.equal(bare.headers.location, '/admin/');
  // HEAD
  const head = await get(port, '/admin/', { method: 'HEAD' });
  assert.equal(head.status, 200); assert.equal(head.body, '');

  // --- assets que o index e os módulos realmente pedem
  const assets = { '/admin/assets/admin.css': /^text\/css/, '/admin/src/app.js': /^text\/javascript/, '/admin/src/api.js': /^text\/javascript/,
    '/admin/src/config.js': /^text\/javascript/, '/admin/src/oauth.js': /^text\/javascript/, '/admin/src/ui.js': /^text\/javascript/, '/admin/src/views/index.js': /^text\/javascript/ };
  for (const [p, type] of Object.entries(assets)) {
    const r = await get(port, p);
    assert.equal(r.status, 200, p); assert.match(r.headers['content-type'], type, p);
    assert.equal(r.body, read(p.replace(/^\//, '')), p + ' = arquivo do repositório');
  }
  for (const ref of idx.body.match(/(?:href|src)="([^"]+)"/g).map(s => s.replace(/^(?:href|src)="|"$/g, ''))) {
    assert.equal((await get(port, '/admin/' + ref)).status, 200, 'referência do index: ' + ref);
  }

  // --- /admin/api/* continua sendo a API (JSON, auth), não o estático
  const s0 = await get(port, '/admin/api/session');
  assert.equal(s0.status, 401); assert.match(s0.headers['content-type'], /application\/json/); assert.deepEqual(JSON.parse(s0.body), { error: 'auth_required' });
  const s1 = await get(port, '/admin/api/session', { headers: { Authorization: 'Bearer dev:boss' } });
  assert.equal(s1.status, 200); const sess = JSON.parse(s1.body);
  assert.equal(sess.admin.role, 'owner'); assert.equal(sess.env, 'local');
  assert.equal((await get(port, '/admin/api/session', { headers: { Authorization: 'Bearer dev:jogador1' } })).status, 403, 'não-admin continua 403');
  const bad = await get(port, '/admin/api/session', { headers: { Authorization: 'Bearer dev:boss', Origin: 'https://evil.example' } });
  assert.equal(bad.status, 403); assert.deepEqual(JSON.parse(bad.body), { error: 'origin_not_allowed' });
  const ovw = await get(port, '/admin/api/overview', { headers: { Authorization: 'Bearer dev:boss' } });
  assert.equal(ovw.status, 200); assert.ok(JSON.parse(ovw.body).cards);

  // --- inexistente: 404 curto, sem conteúdo de arquivo, sem listagem
  for (const p of ['/admin/nao-existe.js', '/admin/src/', '/admin/src', '/admin/assets/', '/admin/src/views/', '/admin/package.json', '/admin/.gdignore',
    '/admin/index.htm', '/admin/apix', '/admin/API/session']) {
    const r = await get(port, p);
    assert.equal(r.status, 404, p); assert.equal(r.body, 'Not found\n', p + ' sem conteúdo/listagem');
  }

  // --- path traversal (cru e codificado): nunca devolve arquivo de fora de admin/
  const secrets = [read('online.cfg'), read('package.json'), read('online_v021/server.js')];
  for (const p of ['/admin/../online.cfg', '/admin/..%2fonline.cfg', '/admin/%2e%2e/online.cfg', '/admin/%2e%2e%2fpackage.json', '/admin/..%5conline.cfg',
    '/admin/src/../../online_v021/server.js', '/admin//etc/passwd', '/admin/%2fetc%2fpasswd', '/admin/src/%2e%2e/%2e%2e/package.json',
    '/admin/..;/online.cfg', '/admin/src/app.js%00.png', '/admin/....//online.cfg']) {
    const r = await get(port, p);
    assert.ok([400, 404].includes(r.status), `${p} → ${r.status}`);
    for (const s of secrets) assert.ok(!r.body.includes(s.slice(0, 40)), p + ' não vaza arquivo interno');
  }

  // --- métodos que não sejam GET/HEAD
  assert.equal((await get(port, '/admin/', { method: 'POST' })).status, 405);
  assert.equal((await get(port, '/admin/src/app.js', { method: 'PUT' })).status, 405);

  // --- GET / continua igual
  const root = await get(port, '/');
  assert.equal(root.status, 200); assert.equal(root.body, 'FRAIHA multiplayer server\n');

  // --- WebSocket do jogo: ping/pong, sala casual criada, segundo jogador entra, lance aceito
  const ws1 = new WebSocket(`ws://127.0.0.1:${port}`), ws2 = new WebSocket(`ws://127.0.0.1:${port}`);
  t.after(() => { ws1.close(); ws2.close(); });
  const next = (ws, pred) => new Promise((res, rej) => { const to = setTimeout(() => rej(new Error('ws timeout')), 5000); const f = d => { const m = JSON.parse(d); if (pred(m)) { clearTimeout(to); ws.off('message', f); res(m); } }; ws.on('message', f); });
  await Promise.all([ws1, ws2].map(w => new Promise(r => w.once('open', r))));
  const pong = next(ws1, m => m.type === 'pong'); ws1.send(JSON.stringify({ type: 'ping' })); await pong;
  const w1 = next(ws1, m => m.type === 'welcome'); ws1.send(JSON.stringify({ type: 'create' })); const welcome = await w1;
  const w2 = next(ws2, m => m.type === 'welcome'); ws2.send(JSON.stringify({ type: 'join', room: welcome.room })); assert.equal((await w2).color, 'b');
  const moved = next(ws2, m => m.type === 'state' && m.move_count === 1 && m.turn === 'b');
  ws1.send(JSON.stringify({ type: 'move', from: [4, 6], to: [4, 4], revision: 0 }));
  await moved;
  // contas (backend) também respondem pelo WebSocket
  const acct = next(ws1, m => typeof m.type === 'string' && m.type.startsWith('acct_'));
  ws1.send(JSON.stringify({ type: 'acct_auth', access_token: 'dev:jogador1' }));
  await acct;
});

test('Admin DESLIGADO (sem FRAIHA_ADMIN_USERS): nem a tela é servida; API 503; jogo igual', async t => {
  const port = await startServer(t, {});
  for (const p of ['/admin/', '/admin/index.html', '/admin/src/app.js', '/admin/assets/admin.css', '/admin']) {
    const r = await get(port, p);
    assert.equal(r.status, 404, p); assert.equal(r.body, 'Not found\n');
  }
  const api = await get(port, '/admin/api/session', { headers: { Authorization: 'Bearer dev:boss' } });
  assert.equal(api.status, 503); assert.deepEqual(JSON.parse(api.body), { error: 'admin_disabled' });
  assert.equal((await get(port, '/')).body, 'FRAIHA multiplayer server\n');
});

test('loadFiles: só .html/.css/.js de admin/, sem ocultos, sem package.json, sem symlink', () => {
  const { loadFiles } = require('../../online_v021/admin/static');
  const keys = [...loadFiles().keys()].sort();
  assert.deepEqual(keys, ['/admin/', '/admin/assets/admin.css', '/admin/index.html', '/admin/src/api.js', '/admin/src/app.js',
    '/admin/src/config.js', '/admin/src/oauth.js', '/admin/src/ui.js', '/admin/src/views/index.js']);
  const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'fx-static-'));
  try {
    fs.writeFileSync(path.join(tmp, 'index.html'), 'ok'); fs.writeFileSync(path.join(tmp, '.env.js'), 'x'); fs.writeFileSync(path.join(tmp, 'a.json'), '{}');
    fs.symlinkSync(path.join(ROOT, 'online.cfg'), path.join(tmp, 'link.js'));
    assert.deepEqual([...loadFiles(tmp).keys()].sort(), ['/admin/', '/admin/index.html']);
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
});
