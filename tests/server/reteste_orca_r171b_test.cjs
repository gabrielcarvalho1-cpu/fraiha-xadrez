'use strict';
// R171b · achados do reteste Orca da R171 (security-r171-retest-20261020):
//   SEC-010  denúncia: 1ª gravação falha → jogador recebia "denunciado" → retry tratado como repetido → denúncia perdida;
//   SEC-008  bot: a mesma partida liberava outra conta depois de reiniciar o servidor (proteção só em memória).
// (O bloqueador do Fundador no boot está em founder_boot_r171_test.cjs e founder_seats_pg_test.cjs.)
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { GlobalChat } = require('../../online_v021/social/global_chat');
const { Reports } = require('../../online_v021/moderation/reports');
const { ChatHub } = require('../../online_v021/chat');
const { MemoryStore, SupabaseStore } = require('../../online_v021/accounts/store');
const { BotService, IDS, gameHash } = require('../../online_v021/bots/service');
const G = require('./fixtures/bot_games_r171.json');

const quiet = () => { const o = [console.log, console.error]; console.log = console.error = () => {}; return () => { [console.log, console.error] = o; }; };
// banco de denúncias que falha nas N primeiras gravações
function flakyStore(failures) {
  const rows = []; let calls = 0;
  return { rows, calls: () => calls, createReport: async r => { calls++; if (calls <= failures) throw new Error('timeout do banco'); rows.push(r); } };
}

// ---------------------------------------------------------------- SEC-010
test('SEC-010 (passos do Orca): gravação falha → erro; retry grava; depois a repetida é bloqueada', async () => {
  const restore = quiet();
  try {
    const db = flakyStore(1);
    const reports = new Reports({ backend: { store: db }, log: () => {} });
    const replies = []; let now = 1e6;
    const gc = new GlobalChat({ send: (ws, m) => replies.push({ to: ws.user.id, ...m }), backend: { reports }, now: () => now, log: () => {} });
    const ws = (id, ip) => ({ readyState: 1, ip, user: { id }, profile: { nickname: id } });
    const author = ws('11111111-1111-4111-a111-111111111111', '1.1.1.1'), A = ws('22222222-2222-4222-a222-222222222222', '2.2.2.2');
    gc.handle(author, { type: 'gchat_send', text: 'mensagem de teste' });
    const id = gc.messages.at(-1).id;
    const report = async w => { now += 3000; const n = replies.length; await gc.handle(w, { type: 'gchat_report', id }); return replies.slice(n).at(-1); };
    const first = await report(A);
    assert.equal(first.type, 'gchat_error'); assert.equal(first.code, 'report_failed', '1ª: falhou → o jogador VÊ o erro (não "denunciado")');
    const retry = await report(A);
    assert.equal(retry.type, 'gchat_reported'); assert.notEqual(retry.duplicate, true, 'retry grava de verdade');
    assert.equal(db.rows.length, 1);
    const again = await report(A);
    assert.equal(again.duplicate, true, 'depois do sucesso, repetida é bloqueada');
    assert.equal(db.rows.length, 1);
  } finally { restore(); }
});

test('SEC-010: repetições AO MESMO TEMPO de uma gravação que falha recebem erro também (nenhuma vira "repetida")', async () => {
  const restore = quiet();
  try {
    const db = flakyStore(1);
    const reports = new Reports({ backend: { store: db }, log: () => {} });
    const replies = [];
    const gc = new GlobalChat({ send: (ws, m) => replies.push(m), backend: { reports }, log: () => {} });
    const author = { readyState: 1, user: { id: '11111111-1111-4111-a111-111111111111' }, profile: { nickname: 'a' } };
    const A = { readyState: 1, ip: '9.9.9.9', user: { id: '22222222-2222-4222-a222-222222222222' }, profile: { nickname: 'b' } };
    gc.handle(author, { type: 'gchat_send', text: 'outra mensagem' });
    const id = gc.messages.at(-1).id;
    await Promise.all([1, 2, 3].map(() => gc.handle(A, { type: 'gchat_report', id })));
    assert.equal(replies.filter(m => m.type === 'gchat_error' && m.code === 'report_failed').length, 3);
    assert.equal(replies.filter(m => m.type === 'gchat_reported').length, 0);
    await gc.handle(A, { type: 'gchat_report', id });
    assert.equal(db.rows.length, 1, 'retry depois: gravada');
  } finally { restore(); }
});

test('SEC-010: o limite por pessoa não é gasto por tentativas que falharam', async () => {
  const restore = quiet();
  try {
    const db = flakyStore(15);
    const reports = new Reports({ backend: { store: db }, log: () => {} });
    const replies = [];
    const gc = new GlobalChat({ send: (ws, m) => replies.push(m), backend: { reports }, log: () => {} });
    const author = { readyState: 1, user: { id: '11111111-1111-4111-a111-111111111111' }, profile: { nickname: 'a' } };
    const A = { readyState: 1, ip: '8.8.8.8', user: { id: '22222222-2222-4222-a222-222222222222' }, profile: { nickname: 'b' } };
    gc.handle(author, { type: 'gchat_send', text: 'alvo' });
    const id = gc.messages.at(-1).id;
    for (let i = 0; i < 15; i++) await gc.handle(A, { type: 'gchat_report', id });
    assert.ok(!replies.some(m => m.code === 'rate_limited'), 'falhas não contam no teto');
    await gc.handle(A, { type: 'gchat_report', id });
    assert.equal(replies.at(-1).type, 'gchat_reported'); assert.equal(db.rows.length, 1);
  } finally { restore(); }
});

test('SEC-010: denúncia do chat da PARTIDA com o mesmo problema — falha → erro e retry grava', async () => {
  const restore = quiet();
  try {
    const db = flakyStore(1);
    const out = [];
    const hub = new ChatHub({ send: (ws, m) => out.push(m), log: () => {} });
    hub.reports = new Reports({ backend: { store: db }, log: () => {} });
    const W = '11111111-1111-4111-a111-111111111111', B = '22222222-2222-4222-a222-222222222222';
    const match = { id: 'm1', chat: [], players: { w: { userId: W, nickname: 'W' }, b: { userId: B, nickname: 'B' } }, colorOf: u => u === W ? 'w' : u === B ? 'b' : null };
    const service = { kind: 'casual', sockets: new Map() };
    await hub.handle({}, { type: 'chat_report', match_id: 'm1' }, W, match, service);
    assert.equal(out.at(-1).type, 'chat_error'); assert.equal(out.at(-1).code, 'report_failed');
    await hub.handle({}, { type: 'chat_report', match_id: 'm1' }, W, match, service);
    assert.equal(out.at(-1).type, 'chat_report_ok'); assert.notEqual(out.at(-1).duplicate, true);
    await hub.handle({}, { type: 'chat_report', match_id: 'm1' }, W, match, service);
    assert.equal(out.at(-1).duplicate, true);
    assert.equal(db.rows.length, 1);
  } finally { restore(); }
});

test('SEC-010: Reports.file com banco fora devolve erro e não marca repetida nem gasta o limite (perfil/DM usam o mesmo caminho)', async () => {
  const restore = quiet();
  try {
    const db = flakyStore(1);
    const R = new Reports({ backend: { store: db }, log: () => {} });
    const row = { reporter: 'a', reported: 'b', kind: 'profile' };
    assert.equal((await R.file(row)).code, 'report_failed');
    const ok = await R.file(row);
    assert.ok(ok.ok && !ok.duplicate && ok.persisted);
    assert.equal((await R.file(row)).duplicate, true);
    assert.equal((R.rate.get('a') || []).length, 1, 'só a gravada conta no limite');
  } finally { restore(); }
});

// ---------------------------------------------------------------- SEC-008
const ws = id => ({ user: { id }, profile: { nickname: id } });
async function unlock(store, uid) { for (const b of IDS.slice(0, IDS.indexOf('platina'))) await store.recordBotVictory(uid, b, {}); }
function svc(store, sent) { return new BotService({ store, send: (w, m) => sent.push({ to: w.user.id, ...m }), env: { FRAIHA_BOT_CLAIM_GAP_MS: '0', FRAIHA_BOT_ENGINE_IDLE_MS: '50' } }); }
const claim = async (s, sent, uid, g) => { await s.handle(ws(uid), { type: 'bot_victory', bot_id: g.level, human_color: g.human_color, moves: g.moves }); return sent.filter(m => m.to === uid).at(-1); };

test('SEC-008 (passos do Orca): mesma partida em OUTRA conta depois de reiniciar o servidor → recusada (banco, não memória)', async () => {
  const restore = quiet();
  const store = new MemoryStore(), sent = [];
  await unlock(store, 'A'); await unlock(store, 'B');
  const s1 = svc(store, sent);
  try {
    assert.equal((await claim(s1, sent, 'A', G.real_platina)).new_bot, 'platina');
    assert.equal((await claim(s1, sent, 'B', G.real_platina)).code, 'bot_game_reused', 'mesma instância');
  } finally { s1.verifier.stop(); }
  const s2 = svc(store, sent);   // "reinício": serviço novo, memória vazia, mesmo banco
  try {
    assert.equal(s2.games.size, 0, 'memória vazia depois do reinício');
    assert.equal((await claim(s2, sent, 'B', G.real_platina)).code, 'bot_game_reused', 'depois do reinício: recusada pelo banco');
    assert.ok(!(await store.getBotProgress('B')).some(x => x.bot_id === 'platina'), 'B não ganhou o nível');
    assert.equal((await claim(s2, sent, 'B', G.real_platina_b)).new_bot, 'platina', 'outra partida real de B vale');
    assert.equal(await store.botGameOwner(gameHash('platina', G.real_platina.moves)), 'A', 'a partida fica gravada com o dono');
  } finally { s2.verifier.stop(); restore(); }
});

test('SEC-008: duas contas enviando a mesma partida AO MESMO TEMPO (duas instâncias) → só uma ganha', async () => {
  const restore = quiet();
  const store = new MemoryStore(), sent = [];
  await unlock(store, 'C'); await unlock(store, 'D');
  const s1 = svc(store, sent), s2 = svc(store, sent);
  try {
    const [c, d] = await Promise.all([claim(s1, sent, 'C', G.real_platina), claim(s2, sent, 'D', G.real_platina)]);
    const won = [c, d].filter(r => r.new_bot === 'platina'), lost = [c, d].filter(r => r.code === 'bot_game_reused');
    assert.equal(won.length, 1); assert.equal(lost.length, 1);
  } finally { s1.verifier.stop(); s2.verifier.stop(); restore(); }
});

test('SEC-008: nível baixo também — o mesmo replay não libera outra conta (nem depois de reiniciar)', async () => {
  const restore = quiet();
  const store = new MemoryStore(), sent = [];
  const SCHOLAR = { level: 'madeira', human_color: 'w', moves: ['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4', 'g8f6', 'h5f7'] };
  const s1 = svc(store, sent);
  try { assert.equal((await claim(s1, sent, 'E', SCHOLAR)).new_bot, 'madeira'); } finally { s1.verifier.stop(); }
  const s2 = svc(store, sent);
  try {
    assert.equal((await claim(s2, sent, 'F', SCHOLAR)).code, 'bot_game_reused');
    assert.equal((await claim(s2, sent, 'E', SCHOLAR)).new_bot, null, 'o próprio dono repetindo: revanche, sem recompensa nova');
  } finally { s2.verifier.stop(); restore(); }
});

// SupabaseStore com PostgREST simulado: as respostas reais do banco (409/23505 e coluna ausente sem a 0024)
function fakeSupabase(mode) {
  const st = new SupabaseStore({ url: 'http://x', serviceKey: 'k' });
  const calls = [];
  st.fetch = async (url, opts) => {
    calls.push({ url, body: opts && opts.body });
    const json = (status, body) => ({ ok: status < 300, status, text: async () => JSON.stringify(body) });
    if (url.includes('game_hash=eq.')) return mode === 'no0024' ? json(400, { code: '42703', message: 'column bot_progress.game_hash does not exist' }) : json(200, mode === 'owned' ? [{ user_id: 'A' }] : []);
    if (opts && opts.method === 'POST') {
      const b = JSON.parse(opts.body);
      if (mode === 'no0024' && b.game_hash) return json(400, { code: 'PGRST204', message: "Could not find the 'game_hash' column of 'bot_progress' in the schema cache" });
      if (mode === 'conflict') return json(409, { code: '23505', message: 'duplicate key value violates unique constraint "bot_progress_game_hash_uq"' });
      return json(201, [b]);
    }
    return json(200, []);
  };
  return { st, calls };
}
test('SEC-008 (SupabaseStore): índice único → bot_game_reused; dono encontrado no banco; sem a 0024 grava sem a partida e avisa', async () => {
  const restore = quiet();
  try {
    const h = 'cd'.repeat(32);
    let f = fakeSupabase('conflict');
    await assert.rejects(f.st.recordBotVictory('B', 'platina', { plies: 40, human_color: 'w', game_hash: h }), e => e.code === 'bot_game_reused');
    assert.ok(JSON.parse(f.calls[0].body).game_hash === h, 'a partida vai para o banco');
    f = fakeSupabase('owned');
    assert.equal(await f.st.botGameOwner(h), 'A');
    f = fakeSupabase('no0024');
    assert.equal(await f.st.recordBotVictory('B', 'platina', { plies: 40, human_color: 'w', game_hash: h }), true, 'sem a 0024 o progresso continua (proteção só em memória, com erro no log)');
    assert.equal(f.st.botHashMissing, true);
    assert.equal(await f.st.botGameOwner(h), null);
  } finally { restore(); }
});

test('R172 · SEC-010: falha → retry grava → 3ª repetida; OUTRO jogador denuncia a mesma mensagem; reinício não perde nem duplica', async () => {
  const restore = quiet();
  try {
    const db = flakyStore(1);
    const mk = () => { const replies = []; const reports = new Reports({ backend: { store: db }, log: () => {} });
      const gc = new GlobalChat({ send: (ws, m) => replies.push({ to: ws.user.id, ...m }), backend: { reports }, log: () => {} }); return { gc, replies }; };
    const W = id => ({ readyState: 1, ip: '3.3.3.3', user: { id }, profile: { nickname: id.slice(0, 4) } });
    const author = W('11111111-1111-4111-a111-111111111111'), A = W('22222222-2222-4222-a222-222222222222'), B = W('33333333-3333-4333-a333-333333333333');
    let s = mk();
    s.gc.handle(author, { type: 'gchat_send', text: 'mensagem denunciada' });
    const id = s.gc.messages.at(-1).id;
    const rep = async (w, msgId = id) => { const n = s.replies.length; await s.gc.handle(w, { type: 'gchat_report', id: msgId }); return s.replies.slice(n).at(-1); };
    assert.equal((await rep(A)).code, 'report_failed', '1) falha');
    assert.equal((await rep(A)).type, 'gchat_reported', '2) funciona');
    assert.equal((await rep(A)).duplicate, true, '3) repetida');
    assert.equal((await rep(B)).duplicate, undefined, '4) outro jogador registra');
    assert.deepEqual(db.rows.map(r => r.reporter_id), [A.user.id, B.user.id]);
    // 5) reinício: memória zera; a mensagem antiga deixa de existir (chat efêmero) → nada é gravado de novo por engano
    s = mk();
    assert.equal((await rep(A)).code, 'not_found', 'depois do reinício a mensagem antiga não existe mais');
    s.gc.handle(author, { type: 'gchat_send', text: 'nova mensagem' });
    const id2 = s.gc.messages.at(-1).id;
    assert.equal((await rep(A, id2)).type, 'gchat_reported', 'mensagem nova denunciável normalmente');
    assert.equal((await rep(A, id2)).duplicate, true);
    assert.equal(db.rows.length, 3, 'nenhuma denúncia perdida, nenhuma duplicada');
  } finally { restore(); }
});

test('R172 · SEC-008: identificador da partida = bot + lances — timestamp, ordem dos campos e campos extras não criam partida "nova"', async () => {
  const restore = quiet();
  const store = new MemoryStore(), sent = [];
  await unlock(store, 'P'); await unlock(store, 'Q');
  const g = G.real_platina;
  const s1 = svc(store, sent);
  try {
    assert.equal((await claim(s1, sent, 'P', g)).new_bot, 'platina');
    // mesma conta, mesmo replay: revanche (sem recompensa nova)
    await s1.handle(ws('P'), { type: 'bot_victory', bot_id: g.level, human_color: g.human_color, moves: g.moves });
    assert.equal(sent.filter(m => m.to === 'P').at(-1).new_bot, null);
  } finally { s1.verifier.stop(); }
  const s2 = svc(store, sent);   // reinício entre as tentativas
  try {
    const variants = [
      { type: 'bot_victory', bot_id: g.level, human_color: g.human_color, moves: g.moves },                                   // payload idêntico
      { moves: g.moves, human_color: g.human_color, type: 'bot_victory', bot_id: g.level },                                   // ordem dos campos
      { type: 'bot_victory', bot_id: g.level, human_color: g.human_color, moves: g.moves, played_at: Date.now(), ts: 123, nonce: 'x' },   // timestamp/extras
    ];
    for (const v of variants) {
      await s2.handle(ws('Q'), v);
      assert.equal(sent.filter(m => m.to === 'Q').at(-1).code, 'bot_game_reused', JSON.stringify(Object.keys(v)));
    }
    // cor declarada diferente não engana (a cor vem da partida) → partida inválida, não "nova"
    await s2.handle(ws('Q'), { type: 'bot_victory', bot_id: g.level, human_color: g.human_color === 'w' ? 'b' : 'w', moves: g.moves });
    assert.equal(sent.filter(m => m.to === 'Q').at(-1).code, 'bot_game_invalid');
    assert.ok(!(await store.getBotProgress('Q')).some(x => x.bot_id === 'platina'));
    assert.equal((await claim(s2, sent, 'Q', G.real_platina_b)).new_bot, 'platina', 'partida realmente diferente continua aceita');
  } finally { s2.verifier.stop(); restore(); }
});

test('R172 · webhook (ressalva do Orca): consulta que volta VAZIA não é marcada como processada; retry consulta de novo', async () => {
  const restore = quiet(); const w = console.warn; console.warn = () => {};
  try {
    const { MercadoPago } = require('../../online_v021/payments/providers/mercadopago');
    const mp = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'LOCAL_TEST', FRAIHA_PUBLIC_URL: 'https://invalid.local' });
    let calls = 0; mp.lookup = async () => { calls++; return calls === 1 ? null : { ignore: true }; };
    const req = { url: '/webhooks/payments?type=payment&data.id=nulo1', headers: {} };
    await assert.rejects(mp.verifyWebhook(req, ''));
    assert.deepEqual(await mp.verifyWebhook(req, ''), { ignore: true });
    assert.equal(calls, 2);
  } finally { console.warn = w; restore(); }
});
