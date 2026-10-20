'use strict';
// R161 · NOVIDADES: o Admin publica frases do outdoor e itens das abas; o jogo lê GET /news (público, CORS),
// só o publicado (e com data já chegada); destaque primeiro; apagar/esconder somem; perfil social leva Xeque/Marcha.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { AdminService } = require('../../online_v021/admin/service');
const { News } = require('../../online_v021/economy/news');

const BOSS = '44444444-4444-4444-a444-444444444444', VIEW = '55555555-5555-4555-a555-555555555555';

test('validação', () => {
  assert.equal(News.validate({ kind: 'x', title: 'Oi' }).error, 'invalid_kind');
  assert.equal(News.validate({ kind: 'noticia', title: 'O' }).error, 'invalid_title');
  assert.equal(News.validate({ kind: 'noticia', title: 'Oi', button_label: 'Ir', button_action: 'javascript:alert(1)' }).error, 'invalid_action');
  assert.equal(News.validate({ kind: 'noticia', title: 'Oi', button_label: 'Ir' }).error, 'invalid_action');
  assert.ok(News.validate({ kind: 'noticia', title: 'Oi', button_label: 'Ir', button_action: 'https://fraihaxadrez.com/x' }).value);
  const b = News.validate({ kind: 'banner', title: 'FRASE', body: 'ignorado', button_label: 'x', button_action: 'torneios' }).value;
  assert.equal(b.body, ''); assert.equal(b.button_action, '');
});

test('Admin publica → GET /news mostra só o publicado, destaque primeiro', async t => {
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: () => {} });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  const admin = new AdminService({ backend, env: { FRAIHA_ADMIN_USERS: `${BOSS}=owner,${VIEW}=viewer`, FRAIHA_ENV: 'dev' }, autostart: false });
  const server = http.createServer((req, res) => {
    if (admin.owns(req)) return admin.handle(req, res);
    if (req.method === 'GET' && req.url === '/news') return backend.news.http(req, res);
    res.writeHead(404); res.end();
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.close(); backend.party.stop(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, token, body) => {
    const res = await fetch(base + path, { method, headers: { Authorization: 'Bearer ' + token, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
    const text = await res.text(); return { status: res.status, body: text ? JSON.parse(text) : null };
  };
  const feed = async () => { backend.news.cache = null; const r = await fetch(base + '/news'); assert.equal(r.headers.get('access-control-allow-origin'), '*'); return r.json(); };

  assert.deepEqual(await feed(), { items: [], banners: [] });
  assert.equal((await call('POST', '/admin/api/news', 'tok-' + VIEW, { kind: 'noticia', title: 'Oi' })).status, 403);
  const b1 = await call('POST', '/admin/api/news', 'tok-' + BOSS, { kind: 'banner', title: 'TORNEIO SÁBADO 20H' });
  assert.equal(b1.status, 200);
  await call('POST', '/admin/api/news', 'tok-' + BOSS, { kind: 'banner', title: 'NOVA ATUALIZAÇÃO', pinned: true });
  const n1 = await call('POST', '/admin/api/news', 'tok-' + BOSS, { kind: 'atualizacao', title: 'R161', body: '• perfil novo', published_at: '2026-10-19T10:00:00Z' });
  const n2 = await call('POST', '/admin/api/news', 'tok-' + BOSS, { kind: 'campeonato', title: 'Torneio', button_label: 'Ver torneios', button_action: 'torneios', published_at: '2026-10-18T10:00:00Z', pinned: true });
  await call('POST', '/admin/api/news', 'tok-' + BOSS, { kind: 'evento', title: 'Futuro', published_at: '2099-01-01T00:00:00Z' });
  let f = await feed();
  assert.deepEqual(f.banners, ['NOVA ATUALIZAÇÃO', 'TORNEIO SÁBADO 20H'], 'destaque primeiro');
  assert.deepEqual(f.items.map(x => x.title), ['Torneio', 'R161'], 'destaque primeiro; data futura não aparece');
  assert.equal(f.items[0].button_action, 'torneios');
  // esconder e apagar
  assert.equal((await call('POST', '/admin/api/news/' + n1.body.item.id, 'tok-' + BOSS, { published: false })).status, 200);
  assert.equal((await call('POST', '/admin/api/news/' + n2.body.item.id + '/delete', 'tok-' + BOSS, { reason: 'teste' })).status, 200);
  f = await feed();
  assert.deepEqual(f.items, []);
  const list = await call('GET', '/admin/api/news', 'tok-' + BOSS);
  assert.equal(list.body.available, true);
  assert.equal(list.body.items.length, 4, 'escondida continua no Admin; apagada sai');
  assert.ok(admin.audit.list({ limit: 50 }).some(a => a.action === 'news_delete'), 'Admin Log registra');
});
