'use strict';
// FRAIHA Admin V1 · API administrativa: autoridade SÓ no servidor, dados sem números falsos,
// ativar/desativar modo REAL (sem encerrar partida em andamento) e audit log.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { AdminService } = require('../../online_v021/admin/service');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const C = '33333333-3333-4333-a333-333333333333';
const BOSS = '44444444-4444-4444-a444-444444444444';
const VIEW = '55555555-5555-4555-a555-555555555555';
const user = id => ({ id, email: 'local@dev.invalid', provider: 'dev' });
const flush = async () => { for (let i = 0; i < 50; i++) await Promise.resolve(); };

async function fixture(t, adminEnv = { FRAIHA_ADMIN_USERS: `${BOSS}=owner,${VIEW}=viewer`, FRAIHA_ENV: 'dev' }) {
  const messages = [], logs = [];
  const sockets = [A, B, C].map(() => ({ readyState: 1 }));
  const origLog = console.log; console.log = (...a) => logs.push(a.join(' '));
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  // Tokens de teste: "tok-<uuid>" → usuário; qualquer outra coisa → inválido.
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? user(m[1]) : null; } };
  backend.attachRanked(new Ranked({ send: backend.send }));
  backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual' }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  for (const [i, id] of [A, B, C].entries()) {
    await backend.store.createProfile(id, ['AliceTest', 'BobTest', 'CarolTest'][i], 'warrior');
    await backend.handle(sockets[i], { type: 'acct_auth', access_token: 'tok-' + id });
  }
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  const admin = new AdminService({ backend, env: adminEnv, autostart: false });
  const server = http.createServer((req, res) => admin.owns(req) ? admin.handle(req, res) : (res.writeHead(404), res.end()));
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.close(); for (const s of sockets) backend.onClose(s); backend.party.stop(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, { token, body, origin, raw } = {}) => {
    const headers = {};
    if (token) headers.Authorization = 'Bearer ' + token;
    if (origin) headers.Origin = origin;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const res = await fetch(base + path, { method, headers, body: raw !== undefined ? raw : body !== undefined ? JSON.stringify(body) : undefined });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
  };
  const entry = id => ({ userId: id, nickname: id === A ? 'AliceTest' : id === B ? 'BobTest' : 'CarolTest', avatar: 'warrior', stats: { league: 0, pl: 0 } });
  return { backend, admin, sockets, messages, logs, call, entry, boss: 'tok-' + BOSS, viewer: 'tok-' + VIEW, alice: 'tok-' + A };
}

test('sem token / token inválido / usuário comum / admin desligado: tudo recusado no servidor', async t => {
  const h = await fixture(t);
  assert.equal((await h.call('GET', '/admin/api/overview')).status, 401);
  assert.equal((await h.call('GET', '/admin/api/overview', { token: 'lixo-qualquer-coisa' })).status, 401);
  const r = await h.call('GET', '/admin/api/overview', { token: h.alice });
  assert.equal(r.status, 403); assert.equal(r.body.error, 'not_admin');
  for (const p of ['/admin/api/queues', '/admin/api/players', '/admin/api/audit', '/admin/api/matches', '/admin/api/live', '/admin/api/system'])
    assert.equal((await h.call('GET', p, { token: h.alice })).status, 403, p);
  assert.equal((await h.call('POST', '/admin/api/queues/ranked', { token: h.alice, body: { enabled: false, reason: 'teste', confirm: 'ranked' } })).status, 403);
  assert.equal(h.backend.modeControls.isOpen('ranked'), true, 'usuário comum não altera nada');
  const ok = await h.call('GET', '/admin/api/session', { token: h.boss });
  assert.equal(ok.status, 200); assert.equal(ok.body.admin.role, 'owner'); assert.equal(ok.body.admin.name, 'Gabriel'); assert.equal(ok.body.env, 'dev');
});

test('Admin sem FRAIHA_ADMIN_USERS fica DESLIGADO (fail-closed)', async t => {
  const h = await fixture(t, { FRAIHA_ENV: 'dev' });
  assert.equal((await h.call('GET', '/admin/api/session', { token: h.boss })).status, 503);
});

test('viewer lê mas não escreve; requests manipuladas são recusadas', async t => {
  const h = await fixture(t);
  assert.equal((await h.call('GET', '/admin/api/queues', { token: h.viewer })).status, 200);
  const w = await h.call('POST', '/admin/api/queues/ranked', { token: h.viewer, body: { enabled: false, reason: 'teste', confirm: 'ranked' } });
  assert.equal(w.status, 403); assert.equal(w.body.need, 'queues.write');
  const bad = [
    [{ enabled: 'false', reason: 'teste', confirm: 'ranked' }, 400],
    [{ enabled: false, reason: '', confirm: 'ranked' }, 400],
    [{ enabled: false, reason: 'teste' }, 400],
    [{ enabled: false, reason: 'teste', confirm: 'casual' }, 400],
  ];
  for (const [body, code] of bad) assert.equal((await h.call('POST', '/admin/api/queues/ranked', { token: h.boss, body })).status, code, JSON.stringify(body));
  assert.equal((await h.call('POST', '/admin/api/queues/xadrez_secreto', { token: h.boss, body: { enabled: false, reason: 'x y z', confirm: 'xadrez_secreto' } })).status, 404);
  assert.equal((await h.call('POST', '/admin/api/queues/ranked', { token: h.boss, raw: '{"enabled":false,"reason":"' + 'a'.repeat(9000) + '"}' })).status, 413, 'corpo grande');
  assert.equal((await h.call('POST', '/admin/api/queues/ranked', { token: h.boss, raw: '{quebrado' })).status, 400, 'JSON inválido');
  assert.equal((await h.call('GET', '/admin/api/players/../../etc', { token: h.boss })).status, 404);
  assert.equal((await h.call('GET', '/admin/api/players/' + '9'.repeat(8) + '-0000-4000-a000-000000000000', { token: h.boss })).status, 404);
  assert.equal((await h.call('DELETE', '/admin/api/queues/ranked', { token: h.boss })).status, 405);
  assert.equal(h.backend.modeControls.isOpen('ranked'), true, 'nenhuma request manipulada mudou o estado');
  assert.equal(h.admin.audit.list().length, 0, 'request recusada não gera ação');
});

test('CORS: origem desconhecida recusada; localhost só em DEV', async t => {
  const h = await fixture(t);
  assert.equal((await h.call('GET', '/admin/api/session', { token: h.boss, origin: 'https://evil.example' })).status, 403);
  const ok = await h.call('GET', '/admin/api/session', { token: h.boss, origin: 'http://127.0.0.1:5173' });
  assert.equal(ok.status, 200); assert.equal(ok.headers.get('access-control-allow-origin'), 'http://127.0.0.1:5173');
  assert.equal(ok.headers.get('access-control-allow-credentials'), null, 'sem cookies/credenciais');
  const prod = await fixture(t, { FRAIHA_ADMIN_USERS: `${BOSS}=owner`, FRAIHA_ENV: 'production', FRAIHA_ADMIN_ORIGINS: 'https://admin.fraihaxadrez.com' });
  assert.equal((await prod.call('GET', '/admin/api/session', { token: prod.boss, origin: 'http://127.0.0.1:5173' })).status, 403, 'produção não aceita localhost');
  assert.equal((await prod.call('GET', '/admin/api/session', { token: prod.boss, origin: 'https://admin.fraihaxadrez.com' })).status, 200);
});

test('overview: números reais do servidor; o que não existe vem null + "unavailable" (nunca inventado)', async t => {
  const h = await fixture(t);
  const m = h.backend.ranked.startMatch('ranked_3min', h.entry(A), h.entry(B));
  h.admin.metrics.sample();
  const r = await h.call('GET', '/admin/api/overview', { token: h.boss });
  assert.equal(r.status, 200);
  const c = r.body.cards;
  assert.equal(c.online_now.value, 3); assert.equal(c.online_now.status, 'real');
  assert.equal(c.in_match.value, 2); assert.equal(c.active_matches.value, 1); assert.equal(c.lobby.value, 1);
  assert.equal(c.registered_users.value, 4); assert.equal(c.registered_users.status, 'real');
  assert.equal(c.peak_online_today.status, 'partial');
  for (const k of ['unique_players_today', 'returning_players', 'platform', 'reconnects_errors']) {
    assert.equal(c[k].value, null, k); assert.equal(c[k].status, 'unavailable', k); assert.ok(c[k].note.length > 5, k);
  }
  assert.equal(c.avg_queue_time.value, null, 'sem pareamento: sem média inventada');
  const mt = await h.call('GET', '/admin/api/matches', { token: h.boss });
  assert.equal(mt.body.active.length, 1); assert.equal(mt.body.active[0].id, m.id); assert.equal(mt.body.recent_finished.status, 'unavailable');
  const pl = await h.call('GET', '/admin/api/players?q=bob', { token: h.boss });
  assert.equal(pl.body.items.length, 1); assert.equal(pl.body.items[0].where.place, 'match'); assert.equal(pl.body.items[0].platform, null);
  assert.ok(!JSON.stringify(pl.body).includes('@dev.invalid'), 'e-mail não sai na listagem');
  const det = await h.call('GET', '/admin/api/players/' + B, { token: h.boss });
  assert.equal(det.status, 200); assert.equal(det.body.profile.nickname, 'BobTest');
  assert.deepEqual(det.body.ent, { version: null, club: { status: 'INATIVO', active: false, expires_at: null, source: null }, founder: { value: false, since: null } }, 'estado real de Clube/Fundador (sem linha = sem benefício)');
});

test('DESATIVAR Ranked: fila esvaziada com aviso, nova entrada recusada, partida em andamento CONTINUA; audit log', async t => {
  const h = await fixture(t);
  const m = h.backend.ranked.startMatch('ranked_3min', h.entry(A), h.entry(B), Date.now() - 30000);
  h.backend.ranked.tick(); await flush();
  assert.equal(m.status, 'playing');
  // C na fila Ranked
  await h.backend.handle(h.sockets[2], { type: 'ranked_queue', mode: 'ranked_5min' }); await flush();
  assert.ok(h.backend.ranked.mm.has(C), 'C entrou na fila');
  h.messages.length = 0;
  const r = await h.call('POST', '/admin/api/queues/ranked', { token: h.boss, body: { enabled: false, reason: 'manutenção de teste', confirm: 'ranked' } });
  assert.equal(r.status, 200); assert.equal(r.body.changed, true); assert.equal(r.body.control.enabled, false);
  assert.ok(!h.backend.ranked.mm.has(C), 'quem esperava saiu da fila');
  const notice = h.messages.find(x => x.socket === h.sockets[2] && x.type === 'ranked_error');
  assert.ok(notice && notice.code === 'mode_disabled', 'C recebeu aviso');
  // nova entrada recusada
  h.messages.length = 0;
  await h.backend.handle(h.sockets[2], { type: 'ranked_queue', mode: 'ranked_5min' }); await flush();
  assert.ok(!h.backend.ranked.mm.has(C));
  assert.equal(h.messages.find(x => x.socket === h.sockets[2]).code, 'mode_disabled');
  // partida em andamento continua: o servidor aceita um lance válido DEPOIS de desativar
  h.backend.ranked.tick(); await flush();
  assert.equal(m.status, 'playing', 'partida não foi encerrada');
  const white = m.players.w.userId === A ? 0 : 1;
  const rev = m.revision;
  await h.backend.handle(h.sockets[white], { type: 'ranked_move', match_id: m.id, from: [4, 6], to: [4, 4] }); await flush();
  assert.ok(m.revision > rev, 'lance aceito com o modo desativado');
  assert.equal(m.status, 'playing');
  // Casual NÃO foi afetado
  await h.backend.handle(h.sockets[2], { type: 'casual_queue', mode: 'casual_5min' }); await flush();
  assert.ok(h.backend.casual.mm.has(C), 'outro modo continua aberto');
  // audit
  const log = await h.call('GET', '/admin/api/audit', { token: h.boss });
  const e = log.body.items[0];
  assert.equal(e.action, 'queue.disable'); assert.equal(e.actor.id, BOSS); assert.deepEqual(e.before, { enabled: true }); assert.deepEqual(e.after, { enabled: false });
  assert.equal(e.reason, 'manutenção de teste'); assert.equal(e.result, 'ok'); assert.equal(e.meta.removed_from_queue, 1);
  assert.ok(h.logs.some(l => l.startsWith('[admin-audit] ') && l.includes('queue.disable')), 'registro estruturado no log do servidor');
  assert.equal(log.body.persistent, false, 'API não finge persistência em banco');
  // reativar
  const on = await h.call('POST', '/admin/api/queues/ranked', { token: h.boss, body: { enabled: true, reason: 'fim do teste', confirm: 'ranked' } });
  assert.equal(on.body.control.enabled, true);
  h.backend.casual.mm.cancel(C);
  await h.backend.handle(h.sockets[2], { type: 'ranked_queue', mode: 'ranked_5min' }); await flush();
  assert.ok(h.backend.ranked.mm.has(C), 'reativado: volta a entrar');
  // repetir o mesmo estado não muda nada, mas fica registrado como noop
  const again = await h.call('POST', '/admin/api/queues/ranked', { token: h.boss, body: { enabled: true, reason: 'de novo', confirm: 'ranked' } });
  assert.equal(again.body.changed, false);
  assert.equal((await h.call('GET', '/admin/api/audit', { token: h.boss })).body.items[0].result, 'noop');
});

test('DESATIVAR XEQUE: convite novo recusado; convite já enviado não começa a mesa', async t => {
  const h = await fixture(t);
  const r = await h.call('POST', '/admin/api/queues/xeque', { token: h.boss, body: { enabled: false, reason: 'teste xeque', confirm: 'xeque' } });
  assert.equal(r.status, 200);
  h.messages.length = 0;
  h.backend.social && (h.backend.store.social.friends.add([A, B].sort().join('|')));
  await h.backend.handle(h.sockets[0], { type: 'invite_send', user_id: B, game: 'xeque' }); await flush();
  const err = h.messages.find(x => x.socket === h.sockets[0] && String(x.type).includes('error'));
  assert.ok(err && err.code === 'mode_disabled', 'convite XEQUE recusado: ' + JSON.stringify(h.messages.map(m => m.type)));
  assert.equal(h.backend.party.rooms.size, 0);
});

test('métricas: espera real de pareamento registrada (não estimada)', async t => {
  const h = await fixture(t);
  const a = h.entry(A), b = h.entry(B); a.since = Date.now() - 4000; b.since = Date.now() - 2000;
  h.backend.ranked.mm.enqueue('ranked_3min', a); h.backend.ranked.mm.enqueue('ranked_3min', b);
  h.backend.ranked.tick(); await flush();
  const r = await h.call('GET', '/admin/api/queues', { token: h.boss });
  const rk = r.body.queues.find(q => q.family === 'ranked');
  assert.equal(rk.active_matches.value, 1);
  assert.equal(rk.avg_wait_ms.status, 'partial');
  assert.ok(rk.avg_wait_ms.value >= 2500 && rk.avg_wait_ms.value <= 4500, 'média ~3 s: ' + rk.avg_wait_ms.value);
  assert.equal(r.body.queues.find(q => q.family === 'xeque').has_queue, false);
});

// ---------------------------------------------------------------- auditoria Orca (retorno)
const Q = require('../../online_v021/admin/queries');

test('Clube/Founder: true / false / sem registro (legítimo) / ERRO / TIMEOUT — erro nunca vira "não possui"', async t => {
  const h = await fixture(t);
  await h.backend.store.setEntitlements(A, { is_founder: true, club_active: true, club_expires_at: new Date(Date.now() + 86400e3).toISOString(), club_source: 'manual' });
  await h.backend.store.setEntitlements(B, { is_founder: false, club_active: false });
  // C: sem linha nenhuma (nunca teve) → legítimo INATIVO / false
  const a = (await h.call('GET', '/admin/api/players/' + A, { token: h.boss })).body;
  assert.equal(a.club.status, 'ATIVO'); assert.equal(a.founder.value, true); assert.equal(a.founder.status, 'real'); assert.equal(a.entitlements_read, 'ok');
  const b = (await h.call('GET', '/admin/api/players/' + B, { token: h.boss })).body;
  assert.equal(b.club.status, 'INATIVO'); assert.equal(b.founder.value, false); assert.equal(b.founder.status, 'real');
  const c = (await h.call('GET', '/admin/api/players/' + C, { token: h.boss })).body;
  assert.equal(c.club.status, 'INATIVO'); assert.equal(c.founder.value, false); assert.equal(c.founder.status, 'real', 'sem registro = não possui (legítimo)');
  // ERRO de consulta
  h.backend.store.adminEntitlementsFault = async () => { throw new Error('PGRST500 boom'); };
  const e = (await h.call('GET', '/admin/api/players/' + A, { token: h.boss }));
  assert.equal(e.status, 200);
  assert.equal(e.body.entitlements_read, 'query_error');
  assert.equal(e.body.club.status, 'INDISPONÍVEL', 'erro NÃO vira INATIVO');
  assert.equal(e.body.founder.value, null, 'erro NÃO vira false'); assert.equal(e.body.founder.status, 'unavailable');
  assert.equal(e.body.club.expires_at.value, null); assert.equal(e.body.club.expires_at.status, 'unavailable');
  const list = (await h.call('GET', '/admin/api/players?q=Test', { token: h.boss })).body;
  assert.equal(list.entitlements_read, 'query_error');
  assert.ok(list.items.length >= 3 && list.items.every(i => i.club === 'INDISPONÍVEL' && i.founder === null), 'lista: todos desconhecidos');
  // TIMEOUT de consulta
  const old = Q.cfg.timeoutMs; Q.cfg.timeoutMs = 150; t.after(() => { Q.cfg.timeoutMs = old; });
  h.backend.store.adminEntitlementsFault = () => new Promise(() => {});
  const t0 = Date.now();
  const to = (await h.call('GET', '/admin/api/players/' + A, { token: h.boss }));
  assert.ok(Date.now() - t0 < 3000, 'não fica pendurado');
  assert.equal(to.body.entitlements_read, 'timeout'); assert.equal(to.body.club.status, 'INDISPONÍVEL'); assert.equal(to.body.founder.value, null);
  assert.match(to.body.club.read_error, /tempo esgotado/);
  // recuperação
  delete h.backend.store.adminEntitlementsFault;
  assert.equal((await h.call('GET', '/admin/api/players/' + A, { token: h.boss })).body.club.status, 'ATIVO');
});

test('Ranked/modos: erro de leitura aparece como erro (não como "sem estatísticas")', async t => {
  const h = await fixture(t);
  const orig = h.backend.store.getRankedStats.bind(h.backend.store);
  h.backend.store.getRankedStats = async () => { throw new Error('boom'); };
  t.after(() => { h.backend.store.getRankedStats = orig; });
  const d = (await h.call('GET', '/admin/api/players/' + A, { token: h.boss })).body;
  assert.equal(d.ranked.ok, false); assert.equal(d.ranked.error, 'query_error'); assert.equal(d.modes.ok, true);
});

test('Convite: modo desativado DURANTE a consulta do perfil → convite não é criado (Casual, XEQUE, MARCHA)', async t => {
  for (const [game, mode, family] of [['chess', 'casual_5min', 'casual'], ['xeque', '', 'xeque'], ['marcha', '', 'marcha']]) {
    const h = await fixture(t);
    h.backend.store.social.friends.add([A, B].sort().join('|'));
    const orig = h.backend.store.getProfilesByIds.bind(h.backend.store);
    let release;
    h.backend.store.getProfilesByIds = ids => new Promise(res => { release = () => res(orig(ids)); });
    h.messages.length = 0;
    const sending = h.backend.handle(h.sockets[0], { type: 'invite_send', user_id: B, game, mode });
    for (let i = 0; i < 20 && !release; i++) await flush();
    assert.ok(release, `${family}: consulta do perfil pendente`);
    const r = await h.call('POST', '/admin/api/queues/' + family, { token: h.boss, body: { enabled: false, reason: 'race test', confirm: family } });
    assert.equal(r.status, 200);
    release(); await sending; await flush();
    assert.equal(h.backend.invites.invites.size, 0, `${family}: nenhum convite criado`);
    const err = h.messages.find(x => x.socket === h.sockets[0] && x.code === 'mode_disabled');
    assert.ok(err, `${family}: quem convidou recebeu mode_disabled (${JSON.stringify(h.messages.map(m => m.type + ':' + (m.code || '')))})`);
    assert.ok(!h.messages.some(x => x.socket === h.sockets[1] && x.type === 'invite_received'), `${family}: convidado não recebeu convite`);
  }
});

test('operator escreve fila; viewer não; owner tudo (papéis)', async t => {
  const OP = '66666666-6666-4666-a666-666666666666';
  const h = await fixture(t, { FRAIHA_ADMIN_USERS: `${BOSS}=owner,${VIEW}=viewer,${OP}=operator`, FRAIHA_ENV: 'dev' });
  const op = 'tok-' + OP;
  assert.equal((await h.call('POST', '/admin/api/queues/marcha', { token: op, body: { enabled: false, reason: 'operador', confirm: 'marcha' } })).status, 200);
  assert.equal((await h.call('GET', '/admin/api/audit', { token: op })).status, 200);
  assert.equal((await h.call('POST', '/admin/api/queues/marcha', { token: h.viewer, body: { enabled: true, reason: 'viewer', confirm: 'marcha' } })).status, 403);
  assert.equal((await h.call('GET', '/admin/api/audit', { token: h.viewer })).status, 403, 'viewer não lê Admin Log');
  assert.equal(h.backend.modeControls.isOpen('marcha'), false);
  assert.equal((await h.call('POST', '/admin/api/queues/marcha', { token: h.boss, body: { enabled: true, reason: 'owner', confirm: 'marcha' } })).status, 200);
  assert.equal(h.backend.modeControls.isOpen('marcha'), true);
});
