'use strict';
// FRAIHA Admin · CLUBE FRAIHA + FUNDADOR: escrita administrativa server-side (tabela entitlements da 0005).
// Cobre: permissões (owner/operator/viewer/comum), payload estrito, datas, motivo, confirmação, versão
// (UI desatualizada), UUID inexistente, conceder/alterar/revogar Clube (prazos, sem expiração, data
// personalizada, expirado), conceder/revogar Fundador (independente do Clube), idempotência, Admin Log,
// jogador online recebe acct_state novo, lista ONLINE (entra/sai), e o caminho Supabase (PostgREST falso).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { AdminService } = require('../../online_v021/admin/service');
const Ent = require('../../online_v021/admin/entitlements');
const { SupabaseStore } = require('../../online_v021/accounts/store');

const A = '11111111-1111-4111-a111-111111111111';     // online, tem perfil
const B = '22222222-2222-4222-a222-222222222222';     // offline, tem perfil
const NOPROF = '33333333-3333-4333-a333-333333333333'; // não existe
const BOSS = '44444444-4444-4444-a444-444444444444';
const VIEW = '55555555-5555-4555-a555-555555555555';
const OPER = '66666666-6666-4666-a666-666666666666';
const DAY = 86400e3;
const user = id => ({ id, email: 'local@dev.invalid', provider: 'dev' });

async function fixture(t) {
  const messages = [], logs = [];
  const origLog = console.log; console.log = (...a) => logs.push(a.join(' '));
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? user(m[1]) : null; } };
  backend.attachRanked(new Ranked({ send: backend.send }));
  backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual' }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  await backend.store.createProfile(A, 'AliceTest', 'warrior');
  await backend.store.createProfile(B, 'BobTest', 'warrior');
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  const sockA = { readyState: 1 };
  await backend.handle(sockA, { type: 'acct_auth', access_token: 'tok-' + A });
  const admin = new AdminService({ backend, env: { FRAIHA_ADMIN_USERS: `${BOSS}=owner,${VIEW}=viewer,${OPER}=operator`, FRAIHA_ENV: 'dev' }, autostart: false });
  const server = http.createServer((req, res) => admin.owns(req) ? admin.handle(req, res) : (res.writeHead(404), res.end()));
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.close(); backend.onClose(sockA); backend.party.stop(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, { token = 'tok-' + BOSS, body, raw } = {}) => {
    const headers = { Authorization: 'Bearer ' + token };
    if (body !== undefined || raw !== undefined) headers['Content-Type'] = 'application/json';
    const res = await fetch(base + path, { method, headers, body: raw !== undefined ? raw : body !== undefined ? JSON.stringify(body) : undefined });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  };
  const state = async uid => (await call('GET', '/admin/api/players/' + uid)).body.ent;
  const act = async (uid, kind, extra, token) => {
    const cur = await state(uid);
    return call('POST', `/admin/api/players/${uid}/${kind}`, { token, body: { reason: 'teste admin', confirm: uid, expect_version: cur.version, ...extra } });
  };
  return { backend, admin, messages, logs, call, state, act, sockA };
}

test('permissões: só OWNER escreve; viewer/operator 403; usuário comum 403; sem token 401 — e nada muda', async t => {
  const h = await fixture(t);
  const body = { action: 'grant', duration: '30', reason: 'teste', confirm: A, expect_version: null };
  for (const [tok, st, code] of [['tok-' + VIEW, 403, 'forbidden'], ['tok-' + OPER, 403, 'forbidden'], ['tok-' + A, 403, 'not_admin']]) {
    const r = await h.call('POST', `/admin/api/players/${A}/club`, { token: tok, body });
    assert.equal(r.status, st); assert.equal(r.body.error, code);
    const f = await h.call('POST', `/admin/api/players/${A}/founder`, { token: tok, body: { action: 'grant', reason: 'teste', confirm: A, expect_version: null } });
    assert.equal(f.status, st);
  }
  assert.equal((await h.call('POST', `/admin/api/players/${A}/club`, { token: 'lixo-qualquer-coisa', body })).status, 401);
  // jogador tentando conceder para si mesmo: é usuário comum → 403
  assert.equal((await h.call('POST', `/admin/api/players/${A}/club`, { token: 'tok-' + A, body })).status, 403);
  assert.deepEqual(await h.state(A), { version: null, club: { status: 'INATIVO', active: false, expires_at: null, source: null }, founder: { value: false, since: null } });
  assert.equal(h.admin.audit.items.length, 0, 'nenhum registro: nada foi tentado com permissão');
  const s = await h.call('GET', '/admin/api/session'); assert.ok(s.body.admin.perms.includes('entitlements.write'));
  const sv = await h.call('GET', '/admin/api/session', { token: 'tok-' + VIEW }); assert.ok(!sv.body.admin.perms.includes('entitlements.write'));
  const so = await h.call('GET', '/admin/api/session', { token: 'tok-' + OPER }); assert.ok(!so.body.admin.perms.includes('entitlements.write'));
});

test('requests manipuladas / inválidas são recusadas e não mudam nada', async t => {
  const h = await fixture(t);
  const P = `/admin/api/players/${A}/club`, base = { action: 'grant', duration: '30', reason: 'teste', confirm: A, expect_version: null };
  const bad = [
    [{ ...base, reason: '' }, 400, 'reason_required'], [{ ...base, reason: '  a ' }, 400, 'reason_required'],
    [{ ...base, confirm: B }, 400, 'confirmation_required'], [{ ...base, confirm: undefined }, 400, 'confirmation_required'],
    [{ ...base, action: 'delete' }, 400, 'invalid_action'], [{ ...base, action: 'change_anything' }, 400, 'invalid_action'],
    [{ ...base, duration: '31' }, 400, 'invalid_duration'], [{ ...base, duration: 30 }, 400, 'invalid_duration'],
    [{ ...base, duration: 'custom', expires_at: 'amanhã' }, 400, 'invalid_date'], [{ ...base, duration: 'custom', expires_at: '2020-01-01T00:00:00Z' }, 400, 'invalid_date'],
    [{ ...base, duration: 'custom', expires_at: '2999-01-01T00:00:00Z' }, 400, 'invalid_date'], [{ ...base, duration: 'custom', expires_at: '2027-01-01' }, 400, 'invalid_date'],
    [{ ...base, expires_at: '2027-01-01T00:00:00Z' }, 400, 'bad_request'],
    [{ ...base, club_active: true }, 400, 'bad_request'], [{ ...base, user_id: B }, 400, 'bad_request'], [{ ...base, is_founder: true }, 400, 'bad_request'],
    [{ ...base, role: 'owner' }, 400, 'bad_request'], [{ ...base, expect_version: undefined }, 400, 'bad_request'], [{ ...base, expect_version: 5 }, 400, 'bad_request'],
  ];
  for (const [b, st, code] of bad) {
    h.admin.hits.clear();   // o limite de escrita (20/min) é testado à parte; aqui só a validação
    const r = await h.call('POST', P, { body: JSON.parse(JSON.stringify(b)) });
    assert.equal(r.status, st, JSON.stringify(b)); assert.equal(r.body.error, code, JSON.stringify(b));
  }
  h.admin.hits.clear();
  assert.equal((await h.call('POST', P, { raw: '{quebrado' })).status, 400);
  assert.equal((await h.call('POST', P, { raw: '[1,2]' })).status, 400);
  assert.equal((await h.call('POST', P, { raw: JSON.stringify({ ...base, reason: 'x'.repeat(5000) }) })).status, 413);
  assert.equal((await h.call('POST', `/admin/api/players/${A}/vip`, { body: base })).status, 404, 'tipo inexistente');
  assert.equal((await h.call('POST', `/admin/api/players/nao-e-uuid/club`, { body: base })).status, 404);
  const f = await h.call('POST', `/admin/api/players/${A}/founder`, { body: { action: 'grant', duration: '30', reason: 'teste', confirm: A, expect_version: null } });
  assert.equal(f.status, 400, 'Fundador não aceita validade (é permanente)');
  const nf = await h.call('POST', `/admin/api/players/${NOPROF}/club`, { body: { ...base, confirm: NOPROF } });
  assert.equal(nf.status, 404); assert.equal(nf.body.error, 'player_not_found');
  assert.equal((await h.state(A)).version, null, 'nada foi gravado');
  assert.equal(h.admin.audit.items.length, 0);
});

test('CLUBE: conceder 30 dias → alterar (365, sem expiração, data personalizada) → revogar; Fundador intocado; Admin Log; jogador online recebe acct_state', async t => {
  const h = await fixture(t);
  const t0 = Date.now();
  let r = await h.act(A, 'club', { action: 'grant', duration: '30' });
  assert.equal(r.status, 200); assert.equal(r.body.changed, true);
  let s = r.body.state;
  assert.equal(s.club.status, 'ATIVO'); assert.equal(s.club.source, 'manual'); assert.equal(s.founder.value, false, 'Fundador independente');
  const exp = Date.parse(s.club.expires_at); assert.ok(Math.abs(exp - (t0 + 30 * DAY)) < 60e3, 'expira em ~30 dias');
  // o JOGO lê pelo caminho normal (store.getEntitlements) e o jogador ONLINE recebe acct_state novo
  const g = await h.backend.store.getEntitlements(A); assert.equal(g.club_active, true); assert.equal(g.club_expires_at, s.club.expires_at);
  const pushed = h.messages.filter(m => m.socket === h.sockA && m.type === 'acct_state');
  assert.ok(pushed.length >= 2 && pushed.at(-1).entitlements.club_active === true, 'acct_state novo enviado ao jogador online');
  // conceder de novo com Clube ativo → 409 (usar ALTERAR)
  r = await h.act(A, 'club', { action: 'grant', duration: '7' }); assert.equal(r.status, 409); assert.equal(r.body.error, 'already_active');
  for (const [d, chk] of [['365', e => Math.abs(Date.parse(e) - (Date.now() + 365 * DAY)) < 60e3], ['none', e => e === null], ['7', e => Math.abs(Date.parse(e) - (Date.now() + 7 * DAY)) < 60e3], ['90', e => Math.abs(Date.parse(e) - (Date.now() + 90 * DAY)) < 60e3]]) {
    r = await h.act(A, 'club', { action: 'change', duration: d });
    assert.equal(r.status, 200, d); assert.equal(r.body.state.club.status, 'ATIVO'); assert.ok(chk(r.body.state.club.expires_at), d + ' → ' + r.body.state.club.expires_at);
  }
  const custom = new Date(Date.now() + 45 * DAY).toISOString();
  r = await h.act(A, 'club', { action: 'change', duration: 'custom', expires_at: custom });
  assert.equal(r.status, 200); assert.equal(r.body.state.club.expires_at, custom);
  r = await h.act(A, 'club', { action: 'revoke' });
  assert.equal(r.status, 200); assert.equal(r.body.state.club.status, 'INATIVO'); assert.equal(r.body.state.club.expires_at, null);
  assert.equal((await h.backend.store.getEntitlements(A)).club_active, false, 'jogo lê INATIVO');
  r = await h.act(A, 'club', { action: 'revoke' }); assert.equal(r.status, 200); assert.equal(r.body.changed, false, 'revogar de novo = noop (idempotente)');
  r = await h.act(A, 'club', { action: 'change', duration: '30' }); assert.equal(r.status, 409); assert.equal(r.body.error, 'not_active');
  // Admin Log
  const log = await h.call('GET', '/admin/api/audit?limit=50');
  const acts = log.body.items.map(i => i.action + ':' + i.result).reverse();
  assert.deepEqual(acts, ['clube_grant:ok', 'clube_change:ok', 'clube_change:ok', 'clube_change:ok', 'clube_change:ok', 'clube_change:ok', 'clube_revoke:ok', 'clube_revoke:noop']);
  const g1 = log.body.items.at(-1);
  assert.equal(g1.actor.id, BOSS); assert.equal(g1.actor.role, 'owner'); assert.equal(g1.target.user_id, A); assert.equal(g1.target.nickname, 'AliceTest');
  assert.equal(g1.before.club, 'INATIVO'); assert.equal(g1.after.club, 'ATIVO'); assert.equal(g1.reason, 'teste admin'); assert.ok(g1.at);
  assert.ok(h.logs.some(l => l.startsWith('[admin-audit] ') && l.includes('clube_grant')), 'linha [admin-audit] no log do servidor');
  assert.equal((await h.state(A)).founder.value, false, 'Fundador nunca foi tocado pelo Clube');
});

test('CLUBE EXPIRADO aparece como EXPIRADO e pode ser CONCEDIDO de novo; UI desatualizada (versão) não aplica', async t => {
  const h = await fixture(t);
  h.backend.store.entitlements = new Map([[B, { club_active: true, club_expires_at: new Date(Date.now() - DAY).toISOString(), club_source: 'pix', is_founder: false, updated_at: '2026-01-01T00:00:00.000Z' }]]);
  let s = await h.state(B);
  assert.equal(s.club.status, 'EXPIRADO'); assert.equal(s.version, '2026-01-01T00:00:00.000Z');
  const old = s.version;
  let r = await h.act(B, 'club', { action: 'grant', duration: '30' });
  assert.equal(r.status, 200); assert.equal(r.body.state.club.status, 'ATIVO');
  // repetir o MESMO pedido antigo (clique duplo / tela desatualizada) → 409 stale_state, nada muda
  const before = await h.state(B);
  r = await h.call('POST', `/admin/api/players/${B}/club`, { body: { action: 'change', duration: '365', reason: 'tela velha', confirm: B, expect_version: old } });
  assert.equal(r.status, 409); assert.equal(r.body.error, 'stale_state'); assert.deepEqual(r.body.state, before);
  assert.deepEqual(await h.state(B), before);
});

test('FUNDADOR: conceder (permanente, sem validade) → já ativo = noop → revogar; Clube intocado; Admin Log', async t => {
  const h = await fixture(t);
  await h.act(A, 'club', { action: 'grant', duration: 'none' });
  const clubBefore = (await h.state(A)).club;
  let r = await h.act(A, 'founder', { action: 'grant' });
  assert.equal(r.status, 200); assert.equal(r.body.changed, true); assert.equal(r.body.state.founder.value, true); assert.ok(r.body.state.founder.since);
  assert.deepEqual(r.body.state.club, clubBefore, 'Clube não muda ao conceder Fundador');
  assert.equal((await h.backend.store.getEntitlements(A)).is_founder, true, 'jogo lê Fundador');
  r = await h.act(A, 'founder', { action: 'grant' }); assert.equal(r.status, 200); assert.equal(r.body.changed, false, 'já Fundador = noop');
  r = await h.act(A, 'founder', { action: 'revoke' });
  assert.equal(r.status, 200); assert.equal(r.body.state.founder.value, false); assert.equal(r.body.state.founder.since, null);
  assert.deepEqual(r.body.state.club, clubBefore, 'Clube não muda ao revogar Fundador');
  r = await h.act(A, 'founder', { action: 'revoke' }); assert.equal(r.body.changed, false);
  r = await h.call('POST', `/admin/api/players/${A}/founder`, { body: { action: 'change', reason: 'teste', confirm: A, expect_version: (await h.state(A)).version } });
  assert.equal(r.status, 400, 'Fundador não tem ALTERAR (não há propriedade editável no modelo)');
  const acts = (await h.call('GET', '/admin/api/audit?limit=50')).body.items.map(i => i.action + ':' + i.result).reverse();
  assert.deepEqual(acts, ['clube_grant:ok', 'founder_grant:ok', 'founder_grant:noop', 'founder_revoke:ok', 'founder_revoke:noop']);
  const fg = (await h.call('GET', '/admin/api/audit?action=founder_grant')).body.items.at(-1);
  assert.equal(fg.before.founder, false); assert.equal(fg.after.founder, true); assert.equal(fg.target.user_id, A);
});

test('ONLINE AGORA: presença real; jogador entra/sai; estado real de Clube/Fundador; convidado não listado; sem e-mail', async t => {
  const h = await fixture(t);
  let r = await h.call('GET', '/admin/api/online');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.items.map(i => i.user_id), [A], 'só A está online');
  assert.equal(r.body.items[0].nickname, 'AliceTest'); assert.equal(r.body.items[0].where.place, 'lobby'); assert.equal(r.body.items[0].ent.club.status, 'INATIVO');
  assert.ok(!JSON.stringify(r.body).includes('@dev.invalid'), 'sem e-mail');
  const sockB = { readyState: 1 };
  await h.backend.handle(sockB, { type: 'acct_auth', access_token: 'tok-' + B });
  await h.act(B, 'founder', { action: 'grant' });
  r = await h.call('GET', '/admin/api/online');
  assert.deepEqual(r.body.items.map(i => i.user_id), [A, B], 'B entrou');
  assert.equal(r.body.items[1].ent.founder.value, true);
  h.backend.onClose(sockB);
  r = await h.call('GET', '/admin/api/online');
  assert.deepEqual(r.body.items.map(i => i.user_id), [A], 'B saiu');
  const sockG = { readyState: 1 };
  await h.backend.handle(sockG, { type: 'guest_auth' });
  r = await h.call('GET', '/admin/api/online');
  assert.deepEqual(r.body.items.map(i => i.user_id), [A], 'convidado não aparece como conta');
  assert.ok(r.body.online_total >= 2 && r.body.guests >= 1);
  h.backend.onClose(sockG);
  assert.equal((await h.call('GET', '/admin/api/online', { token: 'tok-' + A })).status, 403, 'usuário comum não lê');
  assert.equal((await h.call('GET', '/admin/api/online', { token: 'tok-' + VIEW })).status, 200, 'viewer lê');
});

test('erro de leitura do banco NÃO vira "sem benefício" e NÃO grava (fail-closed)', async t => {
  const h = await fixture(t);
  h.backend.store.adminEntitlementsFault = async () => { throw new Error('boom'); };
  const r = await h.call('POST', `/admin/api/players/${A}/club`, { body: { action: 'grant', duration: '30', reason: 'teste', confirm: A, expect_version: null } });
  assert.equal(r.status, 503); assert.equal(r.body.error, 'entitlements_unavailable');
  const on = await h.call('GET', '/admin/api/online');
  assert.equal(on.body.entitlements_read, 'query_error'); assert.equal(on.body.items[0].ent, null, 'estado desconhecido, não INATIVO');
  delete h.backend.store.adminEntitlementsFault;
  assert.equal((await h.state(A)).version, null);
});

// ---------------------------------------------------------------- caminho SUPABASE (PostgREST falso)
function fakePostgrest() {
  const profiles = new Map([[A, { user_id: A, nickname: 'AliceTest' }]]), ents = new Map(), calls = [];
  let clock = Date.parse('2026-10-06T12:00:00.000Z');
  const ts = () => new Date(clock += 1000).toISOString().replace('Z', '+00:00');
  const reply = (status, body) => ({ ok: status < 400, status, text: async () => body === undefined ? '' : JSON.stringify(body), headers: new Map() });
  const fetchImpl = async (url, opts = {}) => {
    const u = new URL(url), m = opts.method || 'GET', path = u.pathname.replace('/rest/v1', '');
    calls.push({ m, path, q: u.search, prefer: opts.headers && opts.headers.Prefer, body: opts.body ? JSON.parse(opts.body) : null });
    if (path === '/profiles' && m === 'GET') { const id = (u.searchParams.get('user_id') || '').replace('eq.', ''); return reply(200, profiles.has(id) ? [profiles.get(id)] : []); }
    if (path === '/entitlements' && m === 'GET') { const ids = (u.searchParams.get('user_id') || '').replace(/^in\.\(|\)$/g, '').split(','); return reply(200, ids.filter(i => ents.has(i)).map(i => ({ ...ents.get(i) }))); }
    if (path === '/entitlements' && m === 'POST') {
      const b = JSON.parse(opts.body); if (!profiles.has(b.user_id)) return reply(409, { code: '23503', message: 'fk' });
      if (ents.has(b.user_id)) return reply(201, []);   // ignore-duplicates
      const row = { is_founder: false, founder_since: null, club_active: false, club_expires_at: null, club_source: null, ...b, updated_at: ts() }; ents.set(b.user_id, row); return reply(201, [{ ...row }]);
    }
    if (path === '/entitlements' && m === 'PATCH') {
      const id = u.searchParams.get('user_id').replace('eq.', ''), ver = u.searchParams.get('updated_at').replace('eq.', '');
      const cur = ents.get(id); if (!cur || cur.updated_at !== ver) return reply(200, []);
      const row = { ...cur, ...JSON.parse(opts.body), updated_at: ts() }; ents.set(id, row); return reply(200, [{ ...row }]);
    }
    return reply(404, { message: 'no route' });
  };
  return { fetchImpl, ents, calls, profiles };
}

test('SUPABASE: grava só via servidor (service role), INSERT sem sobrescrever, PATCH condicionado à versão; conflito = 409', async t => {
  const pg = fakePostgrest();
  const store = new SupabaseStore({ url: 'https://exemplo.supabase.co', serviceKey: 'sb_secret_TESTE', fetchImpl: pg.fetchImpl });
  const backend = { store, socketsOf: () => [] };
  const audit = { items: [], record(e) { const x = { id: String(this.items.length + 1), ...e }; this.items.push(x); return x; } };
  const admin = { id: BOSS, name: 'Gabriel', role: 'owner' };
  let r = await Ent.apply({ backend, audit, admin, kind: 'club', uid: A, body: { action: 'grant', duration: '30', reason: 'teste', confirm: A, expect_version: null } });
  assert.equal(r.status, 200); assert.equal(r.body.state.club.status, 'ATIVO');
  const ins = pg.calls.find(c => c.m === 'POST');
  assert.match(ins.prefer, /resolution=ignore-duplicates/); assert.equal(ins.body.club_source, 'manual'); assert.equal(ins.body.user_id, A);
  const v1 = r.body.state.version;
  r = await Ent.apply({ backend, audit, admin, kind: 'founder', uid: A, body: { action: 'grant', reason: 'teste', confirm: A, expect_version: v1 } });
  assert.equal(r.status, 200); assert.equal(r.body.state.founder.value, true); assert.equal(r.body.state.club.status, 'ATIVO');
  const patch = pg.calls.find(c => c.m === 'PATCH');
  assert.equal(new URLSearchParams(patch.q).get('updated_at'), 'eq.' + v1, 'PATCH só se a versão for a lida');
  assert.deepEqual(Object.keys(patch.body).sort(), ['founder_since', 'is_founder', 'updated_at'], 'Fundador só muda os campos de Fundador');
  // alguém mudou a linha entre a leitura e a escrita → 409, nada sobrescrito
  const v2 = r.body.state.version;
  const real = pg.fetchImpl;
  let raced = false;
  const racing = async (url, opts = {}) => { if ((opts.method === 'PATCH') && !raced) { raced = true; const cur = pg.ents.get(A); pg.ents.set(A, { ...cur, club_source: 'pix', updated_at: '2026-10-06T13:00:00+00:00' }); } return real(url, opts); };
  store.fetch = racing;
  r = await Ent.apply({ backend, audit, admin, kind: 'club', uid: A, body: { action: 'revoke', reason: 'teste', confirm: A, expect_version: v2 } });
  assert.equal(r.status, 409); assert.equal(r.body.error, 'stale_state'); assert.equal(pg.ents.get(A).club_active, true, 'revogação não aplicada sobre estado desconhecido');
  store.fetch = real;
  // UUID sem perfil → 404 sem escrever
  const n = pg.calls.length;
  r = await Ent.apply({ backend, audit, admin, kind: 'club', uid: NOPROF, body: { action: 'grant', duration: '7', reason: 'teste', confirm: NOPROF, expect_version: null } });
  assert.equal(r.status, 404); assert.ok(!pg.calls.slice(n).some(c => c.m !== 'GET'), 'nenhuma escrita');
  // falha de escrita do banco → 502 e Admin Log 'error'
  store.fetch = async (url, opts = {}) => (opts.method === 'PATCH' ? { ok: false, status: 500, text: async () => '{"message":"down"}', headers: new Map() } : real(url, opts));
  const cur = Ent.view(pg.ents.get(A));
  r = await Ent.apply({ backend, audit, admin, kind: 'club', uid: A, body: { action: 'revoke', reason: 'teste', confirm: A, expect_version: cur.version } });
  assert.equal(r.status, 502); assert.equal(audit.items.at(-1).result, 'error');
  assert.ok(!JSON.stringify(audit.items).includes('sb_secret'), 'nenhuma chave no Admin Log');
});

test('validate(): unidades das durações e limites', () => {
  const now = Date.parse('2026-10-06T12:00:00Z');
  const ok = (d, extra = {}) => Ent.validate('club', A, { action: 'grant', duration: d, reason: 'abc', confirm: A, expect_version: null, ...extra }, now);
  assert.equal(ok('7').expires, '2026-10-13T12:00:00.000Z');
  assert.equal(ok('365').expires, '2027-10-06T12:00:00.000Z');
  assert.equal(ok('none').expires, null);
  assert.equal(ok('custom', { expires_at: '2026-12-31T23:59:59-03:00' }).expires, '2027-01-01T02:59:59.000Z');
  assert.equal(ok('custom', { expires_at: '2026-10-06T12:00:30Z' }).error, 'invalid_date', 'precisa ser futuro (> 1 min)');
});

test('limite de escrita por admin (20/min) também vale para Clube/Fundador', async t => {
  const h = await fixture(t);
  let last;
  for (let i = 0; i < 21; i++) last = await h.call('POST', `/admin/api/players/${A}/club`, { body: { action: 'revoke', reason: 'teste', confirm: A, expect_version: null } });
  assert.equal(last.status, 429);
});
