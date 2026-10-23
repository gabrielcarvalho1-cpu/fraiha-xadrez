'use strict';
// R177 · CHAT EXCLUSIVO (Admin ↔ jogador): abrir na tela, mensagens nos dois sentidos, presentes (Coroas e item da Loja),
// permissões, jogador offline, reabrir ao mandar mensagem e reconexão. (fixture copiado do teste de Coroas R168)
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



const of = (h, sock, type) => h.messages.filter(m => m.socket === sock && m.type === type);

test('R177: chat exclusivo — abrir, conversar, presentes, encerrar', async t => {
  const h = await fixture(t);
  // offline não abre
  let r = await h.call('POST', `/admin/api/dchat/${B}/open`, { body: {} });
  assert.equal(r.status, 409); assert.equal(r.body.error, 'offline');
  // viewer não abre
  r = await h.call('POST', `/admin/api/dchat/${A}/open`, { token: 'tok-' + VIEW, body: {} });
  assert.equal(r.status, 403);
  // dono abre: a janela chega no jogo
  r = await h.call('POST', `/admin/api/dchat/${A}/open`, { body: {} });
  assert.equal(r.status, 200); assert.equal(r.body.chat.nickname, 'AliceTest');
  assert.equal(of(h, h.sockA, 'dchat_open').length, 1);
  // mensagem do admin
  r = await h.call('POST', `/admin/api/dchat/${A}/send`, { body: { text: 'Olá! Como posso ajudar?' } });
  assert.equal(r.status, 200);
  const m1 = of(h, h.sockA, 'dchat_msg').pop();
  assert.equal(m1.msg.from, 'admin'); assert.equal(m1.msg.text, 'Olá! Como posso ajudar?');
  assert.equal(m1.msg.by, undefined, 'o jogo não vê quem do admin escreveu');
  // jogador responde pelo WebSocket
  await h.backend.handle(h.sockA, { type: 'dchat_send', text: 'Tenho uma dúvida sobre o jogo' });
  r = await h.call('GET', `/admin/api/dchat/${A}`);
  assert.equal(r.body.chat.messages.length, 2); assert.equal(r.body.chat.messages[1].from, 'player');
  r = await h.call('GET', '/admin/api/dchat');
  assert.equal(r.body.items.length, 1); assert.ok(r.body.catalog.length > 10);
  // presente de Coroas (só owner)
  r = await h.call('POST', `/admin/api/dchat/${A}/gift`, { token: 'tok-' + OPER, body: { kind: 'crowns', amount: 50 } });
  assert.equal(r.status, 403);
  const before = (await h.backend.store.crownWallet(A)).balance;
  r = await h.call('POST', `/admin/api/dchat/${A}/gift`, { body: { kind: 'crowns', amount: 500 } });
  assert.equal(r.status, 200);
  assert.equal((await h.backend.store.crownWallet(A)).balance, before + 500);
  const g1 = of(h, h.sockA, 'dchat_msg').pop();
  assert.equal(g1.msg.gift.kind, 'crowns'); assert.equal(g1.msg.gift.amount, 500);
  r = await h.call('POST', `/admin/api/dchat/${A}/gift`, { body: { kind: 'crowns', amount: 0 } });
  assert.equal(r.body.error, 'invalid_amount');
  // presente de item da loja (moldura/título): fica com o jogador sem descontar
  r = await h.call('POST', `/admin/api/dchat/${A}/gift`, { body: { kind: 'item', item: 'estrategista' } });
  assert.equal(r.status, 200); assert.equal(r.body.gift.name, 'Estrategista');
  assert.ok((await h.backend.store.crownItems(A)).includes('estrategista'));
  assert.equal((await h.backend.store.crownWallet(A)).balance, before + 500, 'item de presente não desconta Coroas');
  r = await h.call('POST', `/admin/api/dchat/${A}/gift`, { body: { kind: 'item', item: 'estrategista' } });
  assert.equal(r.body.error, 'already_owned');
  r = await h.call('POST', `/admin/api/dchat/${A}/gift`, { body: { kind: 'item', item: 'nao_existe' } });
  assert.equal(r.body.error, 'unknown_item');
  // jogador fecha a janela → mensagem nova do admin reabre
  await h.backend.handle(h.sockA, { type: 'dchat_hide' });
  const opens = of(h, h.sockA, 'dchat_open').length;
  await h.call('POST', `/admin/api/dchat/${A}/send`, { body: { text: 'Ainda está aí?' } });
  assert.equal(of(h, h.sockA, 'dchat_open').length, opens + 1);
  // encerrar
  r = await h.call('POST', `/admin/api/dchat/${A}/close`, { body: {} });
  assert.equal(r.status, 200); assert.equal(of(h, h.sockA, 'dchat_closed').length, 1);
  await h.backend.handle(h.sockA, { type: 'dchat_send', text: 'oi?' });
  assert.equal(of(h, h.sockA, 'dchat_error').pop().code, 'not_open');
  r = await h.call('POST', `/admin/api/dchat/${A}/send`, { body: { text: 'x' } });
  assert.equal(r.status, 409);
});
