'use strict';
// R180 · Admin → Sessões: tempo no jogo, telas (ui_screen) e ações, reconexão na mesma sessão, gravação e exclusão.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { AdminService } = require('../../online_v021/admin/service');
const { GRACE_MS } = require('../../online_v021/admin/sessions');

const A = '11111111-1111-4111-a111-111111111111';
const BOSS = '44444444-4444-4444-a444-444444444444';
const flush = async () => { for (let i = 0; i < 50; i++) await Promise.resolve(); };

async function fixture(t) {
  let clock = Date.parse('2026-10-23T15:00:00Z');
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: () => {}, now: () => clock, trackTimers: false });
  backend.auth = { verify: async tok => { const m = /^tok-(.+)$/.exec(tok); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  backend.attachRanked(new Ranked({ send: backend.send })); backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual' }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  await backend.store.createProfile(A, 'AliceTest', 'warrior');
  const admin = new AdminService({ backend, env: { FRAIHA_ADMIN_USERS: `${BOSS}=viewer`, FRAIHA_ENV: 'dev' }, autostart: false });
  const server = http.createServer((req, res) => admin.handle(req, res));
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const socks = [];
  t.after(() => { server.close(); for (const s of socks) backend.onClose(s); backend.party.stop(); backend.track.stop(); });
  const get = async p => { const r = await fetch(`http://127.0.0.1:${server.address().port}${p}`, { headers: { Authorization: 'Bearer tok-' + BOSS } }); return { status: r.status, body: await r.json() }; };
  const sock = () => { const s = { readyState: 1 }; socks.push(s); return s; };
  return { backend, get, sock, tick: ms => { clock += ms; } };
}

test('sessão: entrou, aparelho, telas, ações, resultado; o Admin vê tempo por tela', async t => {
  const h = await fixture(t);
  const s = h.sock();
  await h.backend.handle(s, { type: 'acct_auth', access_token: 'tok-' + A }); await flush();
  await h.backend.handle(s, { type: 'ui_hello', platform: 'Web', device: 'Android', browser: 'Chrome', mobile: true, w: 412, h: 915, version: '0.37' });
  await h.backend.handle(s, { type: 'ui_screen', name: 'Início' });
  h.tick(30e3); await h.backend.handle(s, { type: 'ui_screen', name: 'Loja de Coroas' });
  await h.backend.handle(s, { type: 'ui_screen', name: 'Loja de Coroas' });   // repetida: ignora
  h.tick(10e3); await h.backend.handle(s, { type: 'ranked_queue', mode: 'blitz' }); await flush();
  h.backend.track.outgoing(s, { type: 'ranked_result', outcome: 'win', pl_change: 18 });
  h.tick(5e3);
  const l = await h.get('/admin/api/sessions');
  assert.equal(l.status, 200);
  const it = l.body.items.find(i => i.nickname === 'AliceTest');
  assert.equal(it.state, 'online'); assert.equal(it.screen, 'Loja de Coroas'); assert.equal(it.duration_ms, 45e3);
  const d = (await h.get('/admin/api/sessions/' + it.sid)).body;
  const labels = d.events.map(e => e.l);
  assert.ok(labels[0].startsWith('Entrou'));
  assert.ok(labels.includes('Android · Chrome · celular · 412x915 · v0.37'));
  assert.ok(labels.includes('Entrou na fila do Ranqueado (blitz)'));
  assert.ok(labels.includes('Fim de partida (Ranqueado): VITÓRIA (+18 PL)'));
  assert.deepEqual(d.time_by_screen, [{ screen: 'Início', ms: 30e3 }, { screen: 'Loja de Coroas', ms: 15e3 }]);
});

test('recarregar a página = mesma sessão; sair de vez fecha e grava; excluir conta apaga', async t => {
  const h = await fixture(t);
  const s1 = h.sock();
  await h.backend.handle(s1, { type: 'acct_auth', access_token: 'tok-' + A }); await flush();
  const sid = h.backend.track.live.get(A).sid;
  h.tick(20e3); h.backend.onClose(s1); await flush();
  h.tick(10e3);
  const s2 = h.sock(); await h.backend.handle(s2, { type: 'acct_auth', access_token: 'tok-' + A }); await flush();
  assert.equal(h.backend.track.live.get(A).sid, sid, 'voltou dentro do prazo: mesma sessão');
  await h.backend.handle(s2, { type: 'ui_screen', name: 'Passe da Temporada' });
  h.tick(40e3); h.backend.onClose(s2); await flush();
  const sess = h.backend.track.live.get(A);
  h.backend.track.finish(sess);   // o prazo (GRACE) acabou
  await flush();
  assert.equal(h.backend.track.live.has(A), false);
  const row = await h.backend.store.getSession(sid);
  assert.equal(row.duration_s, 70); assert.equal(row.last_screen, 'Passe da Temporada');
  assert.ok(row.events.at(-1).l.startsWith('Saiu do jogo (estava em: Passe da Temporada)'));
  assert.ok(GRACE_MS >= 60e3);
  await h.backend.store.deleteAccount(A);
  assert.equal(await h.backend.store.getSession(sid), null);
});

test('convidado também tem sessão; flood de ui_screen é cortado', async t => {
  const h = await fixture(t);
  const g = h.sock(); await h.backend.handle(g, { type: 'guest_auth' }); await flush();
  const s = [...h.backend.track.live.values()].find(x => x.guest);
  assert.equal(s.kind, 'guest_new');
  for (let i = 0; i < 200; i++) await h.backend.handle(g, { type: 'ui_screen', name: 'Tela ' + i });
  assert.ok(s.events.filter(e => e.k === 'screen').length <= 120);
});
