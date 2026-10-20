'use strict';
// R171 · regressão dos 3 achados que o Orca REPRODUZIU no reteste da R170 (security-r170-retest-20261020):
//   SEC-003  sweepGuests() removia convidado AINDA CONECTADO com `seen` > 24 h;
//   SEC-004  grant legítimo de análise gravava partida INVENTADA (até Ranked) e duplicava trocando o horário;
//   SEC-006  consulta de webhook sem assinatura que FALHOU marcava o id no cache: a nova tentativa virava 200 "ignorado".
// Os cenários repetem os passos do harness do Orca (independent_backend.cjs / independent_webhook.cjs).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { MercadoPago } = require('../../online_v021/payments/providers/mercadopago');
const { Payments } = require('../../online_v021/payments/service');
const { MemoryStore } = require('../../online_v021/accounts/store');

function fixture(t, env = {}) {
  const origLog = console.log; console.log = () => {}; t.after(() => { console.log = origLog; });
  const b = new Backend({ env: { FRAIHA_DEV_AUTH: '1', ...env }, send: (w, m) => { (w.out = w.out || []).push(m); } });
  b.attachRanked(new Ranked({ send: b.send })); b.attachCasual(new Ranked({ send: b.send, kind: 'casual', cfg: { ...require('../../online_v021/ranked/config').CONFIG, startDelayMs: 0 } }));
  b.ranked.stop(); b.casual.stop(); clearInterval(b.sweeper); b.presence.stop(); b.invites.stop();
  t.after(() => b.party.stop());
  const sock = ip => ({ ip, readyState: 1, out: [] });
  const ask = async (w, m) => { const n = w.out.length; await b.handle(w, m); return w.out.slice(n); };
  return { b, sock, ask };
}

// ---------------------------------------------------------------- SEC-003
test('SEC-003: convidado CONECTADO nunca é removido pela varredura (mesmo com seen > 24 h); em partida também não', async t => {
  const { b, sock, ask } = fixture(t, { FRAIHA_MAX_GUESTS: '5', FRAIHA_GUEST_PER_IP_MIN: '50', FRAIHA_GUEST_GLOBAL_MIN: '100' });
  const gs = [];
  for (let i = 0; i < 5; i++) { const w = sock('test-ip'); const r = await ask(w, { type: 'guest_auth' }); gs.push({ w, token: r.find(x => x.type === 'guest_state').token }); }
  // passo do Orca: seen forçado para 25 h atrás com o socket ainda aberto
  b.guests.get(gs[0].token).seen = Date.now() - 25 * 3600e3;
  b.sweepGuests();
  assert.ok(b.guests.has(gs[0].token), 'conectado continua com o token (reconexão funciona)');
  assert.ok(gs[0].w.identity, 'e continua identificado');
  // convidado em partida, desconectado e antigo: fica
  const mg = b.guests.get(gs[2].token); b.onClose(gs[2].w); mg.seen = Date.now() - 25 * 3600e3;
  const orig = b.inMatch.bind(b); b.inMatch = uid => uid === mg.id || orig(uid);
  b.sweepGuests();
  assert.ok(b.guests.has(gs[2].token), 'em partida (mesmo desconectado) não é removido');
  b.inMatch = orig;
  // realmente inativo: desconectado há > 24 h e fora de partida → sai
  b.sweepGuests();
  assert.ok(!b.guests.has(gs[2].token), 'desconectado há mais de 24 h e fora de partida: descartado');
  // desconectado AGORA não sai, mesmo que o último uso tenha sido há muito tempo (inatividade conta do fechamento)
  const g3 = b.guests.get(gs[3].token); g3.seen = Date.now() - 30 * 3600e3; b.onClose(gs[3].w);
  b.sweepGuests();
  assert.ok(b.guests.has(gs[3].token), 'acabou de desconectar: ainda pode reconectar');
  // teto continua valendo (aqui 5 no lugar de 20.000): só sai quem não está conectado
  const w6 = sock('test-ip'); await ask(w6, { type: 'guest_auth' });
  const w7 = sock('test-ip'); await ask(w7, { type: 'guest_auth' });
  assert.ok(b.guests.size <= 5, 'teto respeitado');
  for (const i of [0, 1, 4]) assert.ok(b.guests.has(gs[i].token), 'conectados nunca saem pelo teto');
  assert.equal(new Backend({ env: {}, send: () => {} }).maxGuests, 20000, 'teto padrão continua 20.000');
});

// ---------------------------------------------------------------- SEC-004
const sum = (o = {}) => ({ match_id: '', mode: 'bot', played_at: Math.floor(Date.now() / 1000), accuracy: 80, color: 'w', result: 'win', counts: { best: 2 },
  moves: [{ u: 'e2e4', c: 'best', l: 0, b: 'e2e4' }, { u: 'e7e5', c: 'best', l: 0, b: 'e7e5' }], engine: 'local', depth: 12, ...o });
async function account(t, f, name) {
  const w = f.sock('ip-' + name);
  await f.ask(w, { type: 'acct_auth', access_token: 'dev:' + name }); await f.ask(w, { type: 'acct_create_profile', nickname: name });
  return w;
}

test('SEC-004: passos do Orca — grant sem partida, partida inventada, Ranked inventado e horário trocado não gravam', async t => {
  const f = fixture(t); const { b, ask } = f;
  const size = () => (b.store.analyses || []).length;
  const A = await account(t, f, 'analysisA');
  await ask(A, { type: 'analysis_record', summary: sum({ match_id: 'nonexistent-match-01' }) });
  assert.equal(size(), 0, 'sem grant: nada');
  await ask(A, { type: 'analysis_request' });   // grant SEM dizer a partida (como no harness do Orca)
  await ask(A, { type: 'analysis_record', summary: sum({ match_id: 'nonexistent-match-01' }), user_id: 'victim-id' });
  assert.equal(size(), 0, 'grant que não diz a partida não grava nada; id inventado contra bot é recusado');
  await ask(A, { type: 'analysis_request', match_id: 'invented-ranked-match', mode: 'ranked' });
  await ask(A, { type: 'analysis_record', summary: sum({ match_id: 'invented-ranked-match', mode: 'ranked' }) });
  assert.equal(size(), 0, 'Ranked inventado (o servidor não viu essa partida): nada');
  // bot legítimo: 1 gravação; mudar o horário não duplica
  await ask(A, { type: 'analysis_request', match_id: '', mode: 'bot' });
  await ask(A, { type: 'analysis_record', summary: sum() });
  assert.equal(size(), 1);
  for (let i = 1; i <= 3; i++) { await ask(A, { type: 'analysis_request', match_id: '', mode: 'bot' }); await ask(A, { type: 'analysis_record', summary: sum({ played_at: sum().played_at + i }) }); }
  assert.equal(size(), 1, 'mesma partida com horário trocado: continua 1 gravação');
  assert.equal(b.store.analyses[0].user_id, A.user.id, 'sempre na conta de quem pediu');
});

test('SEC-004: grant ligado à partida certa e ao usuário certo; Casual real grava 1 vez com horário do servidor', async t => {
  const f = fixture(t); const { b, ask } = f;
  const size = () => (b.store.analyses || []).length;
  const A = await account(t, f, 'casA'), B = await account(t, f, 'casB'), C = await account(t, f, 'casC');
  await ask(A, { type: 'casual_queue', mode: 'casual_3min' }); await ask(B, { type: 'casual_queue', mode: 'casual_3min' });
  for (let i = 0; i < 20 && !A.out.some(m => m.type === 'casual_found'); i++) { await new Promise(r => setTimeout(r, 10)); b.casual.tick(); }
  const found = A.out.find(m => m.type === 'casual_found');
  assert.ok(found, 'partida Casual real criada');
  const id = found.match_id;
  for (let i = 0; i < 5; i++) { await new Promise(r => setTimeout(r, 5)); b.casual.tick(); }
  await ask(A, { type: 'casual_resign', match_id: id });
  await new Promise(r => setTimeout(r, 20));
  assert.ok(A.out.some(m => m.type === 'casual_result'), 'partida terminou');
  // grant de OUTRA partida não serve
  await ask(A, { type: 'analysis_request', match_id: 'outra-partida', mode: 'casual' });
  await ask(A, { type: 'analysis_record', summary: sum({ match_id: id, mode: 'casual' }) });
  assert.equal(size(), 0, 'grant ligado a outra partida não grava esta');
  // C não jogou a partida: mesmo com grant para ela, não grava
  await ask(C, { type: 'analysis_request', match_id: id, mode: 'casual' });
  await ask(C, { type: 'analysis_record', summary: sum({ match_id: id, mode: 'casual' }) });
  assert.equal(size(), 0, 'quem não jogou a partida não grava');
  // modo trocado (Casual declarado como Ranked) não serve
  await ask(A, { type: 'analysis_request', match_id: id, mode: 'ranked' });
  await ask(A, { type: 'analysis_record', summary: sum({ match_id: id, mode: 'ranked' }) });
  assert.equal(size(), 0, 'partida Casual não vira Ranked no histórico');
  // A, partida certa, grant certo: grava 1 vez, horário do servidor
  await ask(A, { type: 'analysis_request', match_id: id, mode: 'casual' });
  await ask(A, { type: 'analysis_record', summary: sum({ match_id: id, mode: 'casual', played_at: 1700000000 }) });
  assert.equal(size(), 1);
  assert.notEqual(b.store.analyses[0].played_at, 1700000000, 'horário vem do servidor, não do jogo');
  for (let i = 0; i < 3; i++) { await ask(A, { type: 'analysis_request', match_id: id, mode: 'casual' }); await ask(A, { type: 'analysis_record', summary: sum({ match_id: id, mode: 'casual', played_at: 1700000000 + i * 99 }) }); }
  assert.equal(size(), 1, 'mesma partida, horário trocado: 1 gravação só');
  // B (o adversário) também pode gravar a SUA análise da mesma partida, uma vez
  await ask(B, { type: 'analysis_request', match_id: id, mode: 'casual' });
  await ask(B, { type: 'analysis_record', summary: sum({ match_id: id, mode: 'casual', color: 'b' }) });
  assert.equal(size(), 2);
  assert.deepEqual(b.store.analyses.map(x => x.user_id).sort(), [A.user.id, B.user.id].sort());
});

test('SEC-004: limite diário de gravações continua (60/dia por conta)', async t => {
  const f = fixture(t, { FRAIHA_ANALYSIS_RECORDS_DAY: '60' }); const { b, ask } = f;
  const A = await account(t, f, 'dailyA');
  await b.store.setEntitlements(A.user.id, { club_active: true });
  for (let i = 0; i < 65; i++) {
    await ask(A, { type: 'analysis_request', match_id: '', mode: 'bot' });
    await ask(A, { type: 'analysis_record', summary: sum({ moves: [{ u: 'e2e4' }, { u: 'a7a' + ((i % 2) + 5) }, { u: 'x' + i }] }) });
  }
  assert.equal((b.store.analyses || []).length, 60);
});

// ---------------------------------------------------------------- SEC-006
const req = id => ({ url: '/webhooks/payments?type=payment&data.id=' + id, headers: {} });
test('SEC-006: consulta sem assinatura que FALHOU não vira "processada" — a nova tentativa consulta de novo (passos do Orca)', async () => {
  const quiet = console.warn; console.warn = () => {};
  try {
    const mp = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'LOCAL_TEST', FRAIHA_PUBLIC_URL: 'https://invalid.local' });
    let calls = 0;
    mp.lookup = async () => { calls++; if (calls === 1) throw new Error('simulated transient provider outage'); return { providerRef: 'r1', status: 'paid', amountCents: 1990, currency: 'BRL' }; };
    await assert.rejects(mp.verifyWebhook(req('retry-me'), ''));
    const retry = await mp.verifyWebhook(req('retry-me'), '');
    assert.equal(calls, 2, 'a 2ª tentativa consultou o provedor');
    assert.ok(!retry.ignore && retry.status === 'paid', 'e trouxe o evento (não "ignorado")');
  } finally { console.warn = quiet; }
});

test('SEC-006 (serviço): falha na consulta → 500; falha ao aplicar → 500; retry entrega; depois do sucesso, repetição é ignorada', async () => {
  const quiet = [console.warn, console.error, console.log]; console.warn = console.error = console.log = () => {};
  try {
    const store = new MemoryStore();
    const pay = new Payments({ send: () => {}, backend: { store, socketsOf: () => [], state: async () => {} }, env: { FRAIHA_PAYMENT_PROVIDER: '' } });
    const mp = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'LOCAL_TEST', FRAIHA_PUBLIC_URL: 'https://invalid.local' });
    pay.provider = mp;
    store.payments = [{ payment_id: 'p1', user_id: 'u1', product_id: 'club_monthly', method: 'pix', provider: mp.name, provider_ref: 'ref1', amount_cents: 1990, status: 'pending', created_at: new Date().toISOString() }];
    let mode = 'fail', calls = 0;
    mp.lookup = async () => { calls++; if (mode === 'fail') throw new Error('timeout'); return { providerRef: 'ref1', status: 'paid', amountCents: 1990, currency: 'BRL', providerPaymentId: '42' }; };
    const hook = async () => { try { return (await pay.webhook(req('42'), '')).status; } catch { return 500; } };
    assert.equal(await hook(), 500, 'consulta falhou: erro (o Mercado Pago tenta de novo)');
    mode = 'ok';
    const origGrant = store.payAndGrant.bind(store); let failGrant = true;
    store.payAndGrant = async (...a) => { if (failGrant) { failGrant = false; throw new Error('banco fora'); } return origGrant(...a); };
    assert.equal(await hook(), 500, 'consulta ok mas aplicar falhou: erro, nada marcado');
    assert.equal(await hook(), 200, 'nova tentativa: aplica');
    assert.equal(store.payments[0].status, 'paid');
    const before = calls;
    assert.equal(await hook(), 200);
    assert.equal(calls, before, 'depois de aplicado, o mesmo aviso em menos de 1 min não consulta de novo');
  } finally { [console.warn, console.error, console.log] = quiet; }
});

test('SEC-006: aviso repetido ENQUANTO o primeiro ainda consulta → 503 (tenta depois), nunca 200 calado', async () => {
  const quiet = console.warn; console.warn = () => {};
  try {
    const mp = new MercadoPago({ FRAIHA_MP_ACCESS_TOKEN: 'LOCAL_TEST', FRAIHA_PUBLIC_URL: 'https://invalid.local' });
    let release; const gate = new Promise(r => { release = r; });
    mp.lookup = async () => { await gate; throw new Error('falhou'); };
    const first = mp.verifyWebhook(req('dup'), '').catch(e => e);
    const second = await mp.verifyWebhook(req('dup'), '');
    assert.deepEqual(second, { busy: true });
    release(); await first;
    mp.lookup = async () => ({ ignore: true });
    assert.deepEqual(await mp.verifyWebhook(req('dup'), ''), { ignore: true }, 'depois da falha, consulta normalmente');
  } finally { console.warn = quiet; }
});
