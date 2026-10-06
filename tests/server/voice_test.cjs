'use strict';
// FRAIHA Voice v1 · autorização de voz no servidor (token Agora AccessToken2, só áudio, só humanos).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const zlib = require('zlib');
const { Backend } = require('../../online_v021/backend');
const { Ranked } = require('../../online_v021/ranked/service');
const { buildRtcAudioToken } = require('../../online_v021/voice/agora_token');

const A = '11111111-1111-4111-a111-111111111111';
const B = '22222222-2222-4222-a222-222222222222';
const C = '33333333-3333-4333-a333-333333333333';
// Valores FICTÍCIOS (formato hex de 32), só para teste. Nunca usar credenciais reais aqui.
const FAKE_APP = '0123456789abcdef0123456789abcdef';
const FAKE_CERT = 'fedcba9876543210fedcba9876543210';
const user = id => ({ id, email: 'local@dev.invalid', provider: 'dev' });
const flush = async () => { for (let i = 0; i < 50; i++) await Promise.resolve(); };

// Decodifica o token (sem verificar assinatura) para conferir canal/uid/privilégios.
function decode(tok) {
  assert.equal(tok.slice(0, 3), '007');
  const b = zlib.inflateSync(Buffer.from(tok.slice(3), 'base64'));
  let o = 0;
  const u16 = () => { const v = b.readUInt16LE(o); o += 2; return v; };
  const u32 = () => { const v = b.readUInt32LE(o); o += 4; return v; };
  const bytes = () => { const n = u16(); const v = b.subarray(o, o + n); o += n; return v; };
  const sig = bytes(); const appId = bytes().toString(); const issueTs = u32(); const expire = u32(); u32(); const n = u16();
  const services = [];
  for (let i = 0; i < n; i++) {
    const type = u16(); const privs = {}; const k = u16();
    for (let j = 0; j < k; j++) { const key = u16(); privs[key] = u32(); }
    services.push({ type, privs, channel: bytes().toString(), uid: bytes().toString() });
  }
  return { sigLen: sig.length, appId, issueTs, expire, services };
}

async function fixture(t, env = { FRAIHA_AGORA_APP_ID: FAKE_APP, FRAIHA_AGORA_APP_CERTIFICATE: FAKE_CERT }) {
  const messages = [], logs = [];
  const sockets = [A, B, C].map(() => ({ readyState: 1 }));
  const origLog = console.log; console.log = (...a) => logs.push(a.join(' '));
  t.after(() => { console.log = origLog; });
  const backend = new Backend({ env: { FRAIHA_DEV_AUTH: '1', ...env }, send: (socket, message) => messages.push({ socket, ...message }) });
  backend.auth = { verify: async token => [A, B, C].includes(token) ? user(token) : null };
  backend.attachRanked(new Ranked({ send: backend.send }));
  backend.attachCasual(new Ranked({ send: backend.send, kind: 'casual' }));
  backend.ranked.stop(); backend.casual.stop(); clearInterval(backend.sweeper); backend.presence.stop(); backend.invites.stop();
  for (const [i, id] of [A, B, C].entries()) {
    await backend.store.createProfile(id, ['AliceTest', 'BobTest', 'CarolTest'][i], 'warrior');
    await backend.handle(sockets[i], { type: 'acct_auth', access_token: id });
  }
  t.after(() => { for (const s of sockets) backend.onClose(s); backend.party.stop(); });
  const entry = id => ({ userId: id, nickname: id === A ? 'AliceTest' : id === B ? 'BobTest' : 'CarolTest', avatar: 'warrior', stats: { elo: 1200 } });
  const ask = async (i, msg) => {
    messages.length = 0;
    await backend.handle(sockets[i], msg); await flush();
    const r = messages.filter(m => m.socket === sockets[i] && String(m.type).startsWith('voice_')).pop();
    if (!r) return r;
    const { socket, ...out } = r; return out;
  };
  return { backend, sockets, messages, logs, entry, ask };
}

test('token: byte a byte igual ao agora-token oficial (vetor fixo, credenciais fictícias)', () => {
  // Gerado com agora-token 2.0.6 (AccessToken2 + ServiceRtc, privilégios 1 e 2 = 600 s), salt/issueTs fixos.
  const VECTOR = '007eJxTYLhWtSNm+d+HX2esVynODip5kOPpLM3Pm7B4reatxtP/9j9XYDAwNDI2MTUzt7BMTEpOSU1D5zfEPsyIYGJg8Evcw8DIwMjAxMDIAOIzgUk9hrSK+KLEvOzUlHiLJMNkoxTjVF0DAwMDXRMQYQEiDBDAkJHBEABCPStY';
  const tok = buildRtcAudioToken({ appId: FAKE_APP, appCertificate: FAKE_CERT, channel: 'fx_ranked_8b1c2d3e-0000-4000-8000-000000000001', uid: 1, ttl: 600, privilegeTtl: 600, issueTs: 1759600000, salt: 12345678 });
  assert.equal(tok, VECTOR);
  const d = decode(tok);
  assert.deepEqual(d.services[0].privs, { 1: 600, 2: 600 }, 'só Join + PublishAudio (sem vídeo/data)');
  assert.throws(() => buildRtcAudioToken({ appId: 'x', appCertificate: FAKE_CERT, channel: 'c', uid: 1 }));
  assert.throws(() => buildRtcAudioToken({ appId: FAKE_APP, appCertificate: FAKE_CERT, channel: 'x'.repeat(65), uid: 1 }));
});

test('sem variáveis de ambiente: not_configured (partida segue normal)', async t => {
  const h = await fixture(t, {});
  const m = h.backend.ranked.startMatch('ranked_3min', h.entry(A), h.entry(B));
  const r = await h.ask(0, { type: 'voice_join', match_id: m.id });
  assert.equal(r.type, 'voice_denied'); assert.equal(r.code, 'not_configured');
  assert.equal(m.status !== 'finished', true);
});

test('Ranked: participantes recebem token do próprio assento; terceiro e partida errada recusados', async t => {
  const h = await fixture(t);
  const m = h.backend.ranked.startMatch('ranked_3min', h.entry(A), h.entry(B));
  const before = JSON.stringify({ status: m.status, players: m.players });
  const ra = await h.ask(0, { type: 'voice_join', kind: 'ranked', match_id: m.id });
  const rb = await h.ask(1, { type: 'voice_join', kind: 'ranked', match_id: m.id });
  for (const [r, id] of [[ra, A], [rb, B]]) {
    assert.equal(r.type, 'voice_granted');
    assert.equal(r.channel, 'fx_ranked_' + m.id);
    assert.equal(r.app_id, FAKE_APP);
    assert.equal(r.uid, m.colorOf(id) === 'w' ? 1 : 2);
    assert.equal(r.ttl, 600);
    assert.deepEqual(r.participants.map(p => p.uid).sort(), [1, 2]);
    const d = decode(r.token);
    assert.equal(d.services[0].channel, r.channel); assert.equal(d.services[0].uid, String(r.uid)); assert.equal(d.expire, 600);
    assert.ok(!JSON.stringify(r).includes(FAKE_CERT), 'certificado nunca sai do servidor');
    assert.ok(!JSON.stringify(r).includes(id), 'id de usuário não vai para a voz');
  }
  assert.notEqual(ra.uid, rb.uid);
  // aviso para a mesa: B entrou → A recebe voice_peer (só assento + nome público)
  h.messages.length = 0;
  await h.backend.handle(h.sockets[1], { type: 'voice_join', match_id: m.id }); await flush();
  const peer = h.messages.find(x => x.socket === h.sockets[0] && x.type === 'voice_peer');
  assert.ok(peer && peer.joined === true && peer.uid === rb.uid && peer.name === 'BobTest');
  assert.ok(!h.messages.some(x => x.socket === h.sockets[2] && x.type === 'voice_peer'), 'terceiro não recebe aviso');
  h.messages.length = 0;
  await h.backend.handle(h.sockets[1], { type: 'voice_leave', match_id: m.id, reason: 'user' }); await flush();
  const gone = h.messages.find(x => x.socket === h.sockets[0] && x.type === 'voice_peer');
  assert.ok(gone && gone.joined === false);
  assert.equal((await h.ask(2, { type: 'voice_join', match_id: m.id })).code, 'not_in_match', 'terceiro não entra');
  assert.equal((await h.ask(0, { type: 'voice_join', match_id: '99999999-1111-4111-a111-111111111111' })).code, 'not_in_match');
  assert.equal((await h.ask(0, { type: 'voice_join', match_id: '../x' })).code, 'bad_request');
  assert.equal((await h.ask(0, { type: 'voice_join' })).code, 'bad_request');
  assert.equal(JSON.stringify({ status: m.status, players: m.players }), before, 'voz não altera a partida');
  const all = h.logs.join('\n');
  assert.ok(all.includes('[voice] token granted kind=ranked'));
  assert.ok(all.includes('[voice] token rejected code=not_in_match'));
  assert.ok(!all.includes(FAKE_CERT) && !all.includes(ra.token) && !all.includes(ra.token.slice(3, 40)), 'log sem segredo nem token');
});

test('fim da partida: join e renovação recusados (match_over)', async t => {
  const h = await fixture(t);
  const m = h.backend.ranked.startMatch('ranked_3min', h.entry(A), h.entry(B));
  assert.equal((await h.ask(0, { type: 'voice_renew', match_id: m.id })).type, 'voice_granted');
  m.status = 'finished';
  const r = await h.ask(0, { type: 'voice_renew', match_id: m.id });
  assert.equal(r.type, 'voice_denied'); assert.equal(r.code, 'match_over'); assert.equal(r.renew, true);
  assert.equal((await h.ask(1, { type: 'voice_join', match_id: m.id })).code, 'match_over');
});

test('Casual (fila ou convite de amigo): canal casual', async t => {
  const h = await fixture(t);
  const m = h.backend.casual.startMatch('casual_10min', h.entry(A), h.entry(C));
  const r = await h.ask(2, { type: 'voice_join', kind: 'casual', match_id: m.id });
  assert.equal(r.type, 'voice_granted'); assert.equal(r.channel, 'fx_casual_' + m.id);
  assert.equal((await h.ask(1, { type: 'voice_join', match_id: m.id })).code, 'not_in_match');
});

test('Party (XEQUE/Marcha online): só humanos, assento = uid; bots nunca; sozinho = solo', async t => {
  const h = await fixture(t);
  const room = h.backend.party.start('xeque', [{ user_id: A, nickname: 'AliceTest' }, { user_id: B, nickname: 'BobTest' }], { seed: 7 });
  const ra = await h.ask(0, { type: 'voice_join', kind: 'xeque', match_id: room.id });
  assert.equal(ra.type, 'voice_granted'); assert.equal(ra.channel, 'fx_xeque_' + room.id);
  const humans = room.seats.map((s, i) => s.kind === 'human' ? i + 1 : 0).filter(Boolean);
  assert.deepEqual(ra.participants.map(p => p.uid), humans, 'só os assentos humanos');
  assert.equal(ra.uid, h.backend.party.seatOf(room, A) + 1);
  assert.equal((await h.ask(2, { type: 'voice_join', match_id: room.id })).code, 'not_in_match');
  h.backend.party.leave(room, B);
  assert.equal((await h.ask(1, { type: 'voice_join', match_id: room.id })).code, 'not_in_match', 'quem saiu não volta para a voz');
  assert.equal((await h.ask(0, { type: 'voice_renew', match_id: room.id })).code, 'solo', 'sem outro humano não gasta minutos');
  const marcha = h.backend.party.start('marcha', [{ user_id: C, nickname: 'CarolTest' }], { seed: 3 });
  assert.equal((await h.ask(2, { type: 'voice_join', match_id: marcha.id })).code, 'solo', 'humano + bots: sem voz');
});

test('convidado não entra em voz; limite de tentativas', async t => {
  const h = await fixture(t);
  const g = { readyState: 1 };
  await h.backend.handle(g, { type: 'guest_auth' }); await flush();
  h.messages.length = 0;
  await h.backend.handle(g, { type: 'voice_join', match_id: '12345678-aaaa' }); await flush();
  const r = h.messages.filter(m => m.socket === g).pop();
  assert.equal(r.type, 'voice_denied'); assert.equal(r.code, 'auth_required');
  h.backend.onClose(g);
  const m = h.backend.ranked.startMatch('ranked_3min', h.entry(A), h.entry(B));
  let last;
  for (let i = 0; i < 13; i++) last = await h.ask(0, { type: 'voice_renew', match_id: m.id });
  assert.equal(last.code, 'rate_limited');
});
