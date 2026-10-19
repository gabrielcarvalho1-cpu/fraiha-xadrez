'use strict';
// R157 · TORNEIOS DE EVENTO (XADREZ, por código): o Admin cria; só quem tem o código entra; vagas e inscrições
// fechadas respeitadas; o Admin monta as chaves (eliminação simples com quem passa direto), marca vencedores até o campeão.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { AdminService } = require('../../online_v021/admin/service');
const { makeBracket, setWinner, champion } = require('../../online_v021/economy/events');

const U = ['11111111-1111-4111-a111-111111111111', '22222222-2222-4222-a222-222222222222', '33333333-3333-4333-a333-333333333333',
  '66666666-6666-4666-a666-666666666666', '77777777-7777-4777-a777-777777777777'];
const BOSS = '44444444-4444-4444-a444-444444444444', VIEW = '55555555-5555-4555-a555-555555555555';
const flush = async () => { for (let i = 0; i < 80; i++) await Promise.resolve(); await new Promise(r => setTimeout(r, 5)); };

test('chaves: 5 jogadores → 8 vagas, 3 passam direto, ninguém contra vaga vazia em dupla', () => {
  const b = makeBracket(['a', 'b', 'c', 'd', 'e']);
  assert.equal(b.rounds.length, 3);
  assert.equal(b.rounds[0].length, 4);
  assert.ok(b.rounds[0].every(x => x.a || x.b), 'nenhuma partida vazia');
  assert.equal(b.rounds[0].filter(x => x.winner).length, 3, '3 passam direto');
  const all = b.rounds[0].flatMap(x => [x.a, x.b]).filter(Boolean).sort();
  assert.deepEqual(all, ['a', 'b', 'c', 'd', 'e']);
  // joga tudo até o campeão
  for (let r = 0; r < b.rounds.length; r++) for (let m = 0; m < b.rounds[r].length; m++) {
    const x = b.rounds[r][m];
    if (x.a && x.b && !x.winner) assert.ok(setWinner(b, r, m, x.a).ok);
  }
  assert.ok(champion(b));
  assert.equal(setWinner(b, 0, 0, 'zzz').error === 'not_in_match' || setWinner(b, 0, 0, 'zzz').error === 'match_not_ready', true);
});

test('fluxo: Admin cria → código → inscrições → vagas → chaves → resultados → campeão', async t => {
  const messages = [];
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  backend.attachRanked(new Ranked({ send: backend.send }));
  backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual' }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  const sockets = U.map(() => ({ readyState: 1 }));
  for (const [i, id] of U.entries()) {
    await backend.store.createProfile(id, 'Jogador' + i, 'warrior');
    await backend.handle(sockets[i], { type: 'acct_auth', access_token: 'tok-' + id });
  }
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  const admin = new AdminService({ backend, env: { FRAIHA_ADMIN_USERS: `${BOSS}=owner,${VIEW}=viewer`, FRAIHA_ENV: 'dev' }, autostart: false });
  const server = http.createServer((req, res) => admin.owns(req) ? admin.handle(req, res) : (res.writeHead(404), res.end()));
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.close(); for (const s of sockets) backend.onClose(s); backend.party.stop(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, token, body) => {
    const res = await fetch(base + path, { method, headers: { Authorization: 'Bearer ' + token, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
    const text = await res.text(); return { status: res.status, body: text ? JSON.parse(text) : null };
  };
  const last = (i, type) => [...messages].reverse().find(m => m.socket === sockets[i] && m.type === type);
  const send = async (i, m) => { await backend.handle(sockets[i], m); await flush(); };

  // só quem pode escrever cria
  assert.equal((await call('POST', '/admin/api/events', 'tok-' + VIEW, { name: 'X', code: 'ABCD' })).status, 403);
  assert.equal((await call('POST', '/admin/api/events', 'tok-' + BOSS, { name: 'Torneio', code: 'a b' })).body.error, 'invalid_code');
  const c = await call('POST', '/admin/api/events', 'tok-' + BOSS, { name: 'Torneio da Cidade', code: 'maringa26', mode: 'casual_10min', max_players: 4, notes: 'Praça central' });
  assert.equal(c.status, 200);
  const id = c.body.item.id;
  assert.equal(c.body.item.code, 'MARINGA26');
  assert.equal((await call('POST', '/admin/api/events', 'tok-' + BOSS, { name: 'Outro', code: 'MARINGA26' })).body.error, 'code_taken');

  // jogadores: código errado / certo / lotado
  await send(0, { type: 'tev_join', code: 'ERRADO1' });
  assert.equal(last(0, 'tev_error').code, 'not_found');
  for (let i = 0; i < 4; i++) await send(i, { type: 'tev_join', code: ' maringa26 ' });
  const st = last(3, 'tev_state');
  assert.equal(st.available, true);
  assert.equal(st.events.length, 1);
  assert.equal(st.events[0].players, 4);
  assert.equal(st.events[0].joined, true);
  assert.equal(st.events[0].notes, 'Praça central');
  await send(4, { type: 'tev_join', code: 'MARINGA26' });
  assert.equal(last(4, 'tev_error').code, 'full');
  // entrar de novo não duplica
  await send(0, { type: 'tev_join', code: 'MARINGA26' });
  assert.equal(last(0, 'tev_state').events[0].players, 4);

  // chaves
  const b = await call('POST', `/admin/api/events/${id}/bracket`, 'tok-' + BOSS, { reason: 'teste' });
  assert.equal(b.status, 200);
  assert.equal(b.body.item.status, 'running');
  const list = await call('GET', '/admin/api/events', 'tok-' + BOSS);
  const ev = list.body.items[0];
  assert.equal(ev.entrants.length, 4);
  assert.equal(ev.bracket.rounds.length, 2);
  // inscrição fechada depois das chaves
  await send(1, { type: 'tev_leave', id });
  assert.equal(last(1, 'tev_error').code, 'closed');
  // resultados até o campeão
  const r0 = ev.bracket.rounds[0];
  assert.equal((await call('POST', `/admin/api/events/${id}/result`, 'tok-' + BOSS, { round: 1, match: 0, winner: r0[0].a })).body.error, 'not_in_match');
  for (let m = 0; m < 2; m++) assert.equal((await call('POST', `/admin/api/events/${id}/result`, 'tok-' + BOSS, { round: 0, match: m, winner: r0[m].a })).status, 200);
  const fin = await call('POST', `/admin/api/events/${id}/result`, 'tok-' + BOSS, { round: 1, match: 0, winner: r0[1].a });
  assert.equal(fin.status, 200);
  assert.equal(fin.body.item.status, 'finished');
  await send(2, { type: 'tev_list' });
  const v = last(2, 'tev_state').events[0];
  assert.ok(v.bracket && v.champion, 'jogador vê as chaves e o campeão');
  assert.ok(admin.audit.list({ limit: 50 }).some(a => a.action === 'event_bracket'), 'Admin Log registra');
});
