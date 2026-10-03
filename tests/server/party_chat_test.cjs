'use strict';
// R37.3 · chat das mesas MARCHA REAL / XEQUE com amigo: todos, ou só o aliado (Marcha).
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ENV = { FRAIHA_DEV_AUTH: '1', FRAIHA_PARTY_TURN_MS: '60000', FRAIHA_PARTY_MARCHA_BOT_MS: '60000', FRAIHA_PARTY_XEQUE_BOT_MIN_MS: '60000', FRAIHA_PARTY_XEQUE_BOT_MAX_MS: '60000',
  FRAIHA_PARTY_MESA_MS: '5', FRAIHA_PARTY_INTRO_MS: '5' };
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; return c;
}
async function soc(c, type, uid) { await sleep(80); c.send({ type, user_id: uid }); return c.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000); }
async function party(A, B, game) {
  await sleep(100); A.send({ type: 'invite_send', user_id: B.id, game });
  const rec = await B.next('invite_received', 5000);
  await sleep(100); B.send({ type: 'invite_accept', invite_id: rec.invite.id });
  const sa = await A.next('party_start', 5000); await B.next('party_start', 5000);
  return sa.room_id;
}
(async () => {
  const s = await startServer(ENV);
  const A = await login(s.port, 'AnaChat'), B = await login(s.port, 'BiaChat'), C = await login(s.port, 'CaioChat');
  await soc(A, 'social_request', B.id); await soc(B, 'social_accept', A.id);
  const room = await party(A, B, 'marcha');
  A.send({ type: 'party_chat', room_id: room, text: 'oi time', to: 'ally' });
  const ma = await A.next('party_chat_msg', 4000), mb = await B.next('party_chat_msg', 4000);
  check(ma.text === 'oi time' && ma.from_seat === 0 && ma.to === 'ally', 'MARCHA: quem mandou vê a própria mensagem (para o aliado)');
  check(mb.text === 'oi time' && mb.from_seat === 2 && mb.nickname === 'AnaChat', 'MARCHA: o aliado recebe, vinda do lugar dele de cima (girado)');
  await sleep(800);
  B.send({ type: 'party_chat', room_id: room, text: 'boa jogada', to: 'all' });
  const ra = await A.next('party_chat_msg', 4000);
  check(ra.to === 'all' && ra.from_seat === 2, 'MARCHA: mensagem para todos chega');
  await sleep(800);
  A.send({ type: 'party_chat', room_id: room, text: '   ' });
  check((await A.next('party_chat_error', 4000)).code === 'empty', 'mensagem vazia é recusada');
  C.send({ type: 'party_chat', room_id: room, text: 'intruso' });
  check((await C.next('party_error', 4000)).code === 'not_player', 'quem não está na mesa não conversa');
  await sleep(800);
  A.send({ type: 'party_chat_sync', room_id: room });
  const h = await A.next('party_chat_history', 4000);
  check(h.messages.length === 2, 'reconectar devolve as mensagens da mesa');
  A.send({ type: 'party_leave', room_id: room }); await A.next('party_left', 4000);
  B.send({ type: 'party_leave', room_id: room }); await B.next('party_left', 4000);
  await sleep(300);
  const xr = await party(A, B, 'xeque');
  await sleep(800);
  A.send({ type: 'party_chat', room_id: xr, text: 'xeque!', to: 'ally' });
  const xm = await B.next(m => m.type === 'party_chat_msg' && m.text === 'xeque!', 4000);
  check(xm.to === 'all' && xm.text === 'xeque!', 'XEQUE: o chat é sempre para todos');
  A.close(); B.close(); C.close(); s.stop();
  summary('PARTY_CHAT');
})().catch(e => { console.error(e); process.exit(1); });
