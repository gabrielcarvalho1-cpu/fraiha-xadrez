'use strict';
// R176.8 · SUPORTE: o jogador manda o ticket pelo jogo (só conta), vê em MEUS TICKETS; o Admin lista, responde
// (a resposta chega na hora para quem está online) e fecha. Validações, limite e permissões.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { Backend } = require('../../online_v021/backend');
const { AdminService } = require('../../online_v021/admin/service');

const BOSS = '44444444-4444-4444-a444-444444444444', VIEW = '55555555-5555-4555-a555-555555555555';
const ANA = '66666666-6666-4666-a666-666666666666';

test('ticket: jogo → Admin → resposta', async t => {
  const sent = [];
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (ws, m) => sent.push({ ws, m }) });
  backend.auth = { verify: async token => { const m = /^tok-(.+)$/.exec(token); return m ? { id: m[1], email: 'x@dev.invalid', provider: 'dev' } : null; } };
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  await backend.store.createProfile(BOSS, 'Gabriel', 'warrior');
  await backend.store.createProfile(ANA, 'AnaSuporte', 'warrior');
  const admin = new AdminService({ backend, env: { FRAIHA_ADMIN_USERS: `${BOSS}=owner,${VIEW}=viewer`, FRAIHA_ENV: 'dev' }, autostart: false });
  const server = http.createServer((req, res) => { if (admin.owns(req)) return admin.handle(req, res); res.writeHead(404); res.end(); });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.close(); backend.party.stop(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, token, body) => {
    const res = await fetch(base + path, { method, headers: { Authorization: 'Bearer ' + token, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
    const text = await res.text(); return { status: res.status, body: text ? JSON.parse(text) : null };
  };
  const of = (ws, type) => sent.filter(x => x.ws === ws && x.m.type === type).map(x => x.m);

  // convidado não manda
  const guest = { identity: { id: 'guest:x', guest: true } };
  await backend.tickets.handle(guest, { type: 'ticket_send', category: 'duvida', message: 'Como jogo?' });
  assert.equal(of(guest, 'ticket_error')[0].code, 'login_required');

  const ws = { identity: { id: ANA, guest: false } };
  backend.online.set(ANA, new Set([ws]));
  await backend.tickets.handle(ws, { type: 'ticket_send', category: 'xyz', message: 'Oi oi oi' });
  assert.equal(of(ws, 'ticket_error').pop().code, 'invalid_category');
  await backend.tickets.handle(ws, { type: 'ticket_send', category: 'sugestao', message: 'oi' });
  assert.equal(of(ws, 'ticket_error').pop().code, 'invalid_message');
  await backend.tickets.handle(ws, { type: 'ticket_send', category: 'sugestao', subject: 'Modo novo', message: 'Coloquem um modo 960!', context: { platform: 'web', version: '0.37', x: 'lixo' } });
  const ok = of(ws, 'ticket_ok').pop();
  assert.ok(ok && ok.ticket.ticket_id && ok.ticket.status === 'open' && ok.ticket.category_label === 'Sugestão');
  const mine = of(ws, 'ticket_list').pop();
  assert.equal(mine.available, true); assert.equal(mine.items.length, 1);

  // limite: 5 por hora
  for (let i = 0; i < 4; i++) await backend.tickets.handle(ws, { type: 'ticket_send', category: 'duvida', message: 'Pergunta ' + i });
  await backend.tickets.handle(ws, { type: 'ticket_send', category: 'duvida', message: 'Mais uma' });
  assert.equal(of(ws, 'ticket_error').pop().code, 'rate_limited');

  // Admin: viewer não vê; owner lista, responde e fecha
  assert.equal((await call('GET', '/admin/api/tickets', 'tok-' + VIEW)).status, 403);
  const list = await call('GET', '/admin/api/tickets?status=open', 'tok-' + BOSS);
  assert.equal(list.status, 200); assert.equal(list.body.available, true); assert.equal(list.body.items.length, 5);
  const first = list.body.items.find(x => x.subject === 'Modo novo');
  assert.equal(first.nickname, 'AnaSuporte'); assert.deepEqual(first.context, { platform: 'web', version: '0.37' });
  assert.equal((await call('POST', '/admin/api/tickets/' + first.ticket_id, 'tok-' + VIEW, { reply: 'oi' })).status, 403);
  assert.equal((await call('POST', '/admin/api/tickets/' + first.ticket_id, 'tok-' + BOSS, { reply: '' })).status, 400);
  const r = await call('POST', '/admin/api/tickets/' + first.ticket_id, 'tok-' + BOSS, { reply: 'Obrigado! Vamos estudar.' });
  assert.equal(r.status, 200); assert.equal(r.body.ticket.status, 'answered');
  const up = of(ws, 'ticket_update').pop();
  assert.ok(up && up.ticket.reply === 'Obrigado! Vamos estudar.' && up.ticket.status === 'answered', 'resposta chega na hora');
  assert.equal(up.ticket.replied_by, undefined, 'jogador não vê quem respondeu');
  assert.equal((await call('POST', '/admin/api/tickets/' + first.ticket_id, 'tok-' + BOSS, { status: 'closed' })).body.ticket.status, 'closed');
  assert.equal((await call('POST', '/admin/api/tickets/' + first.ticket_id, 'tok-' + BOSS, { status: 'xyz' })).status, 400);
  assert.equal((await call('POST', '/admin/api/tickets/77777777-7777-4777-a777-777777777777', 'tok-' + BOSS, { status: 'closed' })).status, 404);
  await backend.tickets.handle(ws, { type: 'ticket_list' });
  const after = of(ws, 'ticket_list').pop();
  const mineFirst = after.items.find(x => x.ticket_id === first.ticket_id);
  assert.equal(mineFirst.status, 'closed'); assert.equal(mineFirst.reply, 'Obrigado! Vamos estudar.');
});

test('sem a tabela (0029): avisa o jogador e não quebra', async () => {
  const sent = [];
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (ws, m) => sent.push({ ws, m }) });
  clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop(); backend.party.stop();
  backend.store.createTicket = async () => { const e = new Error('relation "public.support_tickets" does not exist'); e.code = '42P01'; throw e; };
  backend.tickets.log = () => {};
  const ws = { identity: { id: ANA, guest: false } };
  await backend.tickets.handle(ws, { type: 'ticket_send', category: 'problema', message: 'Travou a partida' });
  const err = sent.filter(x => x.m.type === 'ticket_error').pop();
  assert.equal(err.m.code, 'unavailable');
});
