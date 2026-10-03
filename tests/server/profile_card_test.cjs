'use strict';
// R37 · cartão de perfil durante a partida (passar o mouse no avatar): perfil público, relação para o botão
// ADICIONAR AMIGO e o placar do MODO em jogo (Ranked = ranked_stats; Casual / Marcha / Xeque = mode_stats).
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const STACK = process.env.SOCIAL_STACK_ENV ? JSON.parse(process.env.SOCIAL_STACK_ENV) : { FRAIHA_DEV_AUTH: '1' };
const ENV = { ...STACK, FRAIHA_RANKED_START_DELAY_MS: '100', FRAIHA_PARTY_TURN_MS: '1500', FRAIHA_PARTY_MARCHA_BOT_MS: '5',
  FRAIHA_PARTY_AWAY_MS: '30', FRAIHA_PARTY_STEP_MS: '0', FRAIHA_PARTY_EXIT_MS: '0', FRAIHA_PARTY_CAPTURE_MS: '0', FRAIHA_PARTY_CROWN_MS: '0',
  FRAIHA_PARTY_SWAP_MS: '5', FRAIHA_PARTY_MESA_MS: '5', FRAIHA_PARTY_INTRO_MS: '5' };
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: (process.env.SOCIAL_TOKEN_PAD || '') + 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; return c;
}
async function card(c, uid, mode) {
  await sleep(80);
  c.send({ type: 'social_card', user_id: uid, mode });
  return c.next(m => (m.type === 'social_card' && m.user_id === uid) || m.type === 'social_error', 5000);
}
async function soc(c, type, uid) { await sleep(80); c.send({ type, user_id: uid }); return c.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000); }

(async () => {
  const s = await startServer(ENV);
  const A = await login(s.port, 'AnaCard'), B = await login(s.port, 'BiaCard');
  let r = await card(A, A.id, 'marcha');
  check(r.type === 'social_card' && r.card.relation === 'self' && r.card.stats_ready && r.card.stats.wins === 0, 'cartão da própria conta: relação "self" e placar zerado do modo');
  r = await card(A, B.id, 'casual');
  check(r.card.nickname === 'BiaCard' && r.card.relation === 'none' && !('email' in r.card), 'cartão de outro jogador: nickname, relação (botão ADICIONAR AMIGO) e sem e-mail');
  // Casual: Bia desiste → placar casual dos dois
  A.send({ type: 'casual_queue', mode: 'casual_3min' }); await A.next('casual_queued');
  B.send({ type: 'casual_queue', mode: 'casual_3min' }); await B.next('casual_queued');
  const fa = await A.next('casual_found', 5000); await B.next('casual_found', 5000);
  check(fa.opponent && fa.opponent.user_id === B.id, 'partida casual entrega o user_id do adversário (para abrir o cartão)');
  await sleep(300);
  B.send({ type: 'casual_resign', match_id: fa.match_id });
  await A.next('casual_result', 5000); await B.next('casual_result', 5000);
  await sleep(150);
  r = await card(A, B.id, 'casual');
  check(r.card.stats.losses === 1 && r.card.stats.wins === 0, 'Casual: derrota da Bia aparece no cartão dela');
  r = await card(B, A.id, 'casual');
  check(r.card.stats.wins === 1, 'Casual: vitória da Ana aparece no cartão dela');
  // Ranked: placar do modo ranqueado
  r = await card(A, B.id, 'ranked_5min');
  check(r.card.stats_ready && 'league' in r.card.stats && r.card.stats.wins === 0, 'Ranked: cartão mostra o placar daquele modo ranqueado');
  // Amizade pelo cartão
  r = await soc(A, 'social_request', B.id);
  check(r.type === 'social_ok' && r.relation === 'request_sent', 'ADICIONAR AMIGO do cartão envia o pedido');
  await soc(B, 'social_accept', A.id);
  r = await card(A, B.id, 'marcha');
  check(r.card.relation === 'friend', 'depois de aceito o cartão mostra AMIGOS');
  // Marcha com amigo: os dois saem → os dois perdem (placar marcha)
  await sleep(100); A.send({ type: 'invite_send', user_id: B.id, game: 'marcha' });
  const rec = await B.next('invite_received', 5000);
  await sleep(100); B.send({ type: 'invite_accept', invite_id: rec.invite.id });
  const sa = await A.next('party_start', 5000); await B.next('party_start', 5000);
  check(sa.players && sa.players[0].user_id === A.id && sa.players.some(p => p.user_id === B.id) && sa.players.filter(p => p.bot).every(p => p.user_id === ''), 'mesa MARCHA: cada jogador humano vem com user_id; bots sem');
  await sleep(100); A.send({ type: 'party_leave', room_id: sa.room_id }); await A.next('party_left', 4000);
  await sleep(100); B.send({ type: 'party_leave', room_id: sa.room_id }); await B.next('party_left', 4000);
  await sleep(200);
  r = await card(A, B.id, 'marcha');
  check(r.card.stats.losses === 1, 'Marcha: quem sai da mesa leva derrota no placar do modo');
  r = await card(A, B.id, 'xeque');
  check(r.card.stats.wins === 0 && r.card.stats.losses === 0, 'placar do Xeque separado do da Marcha');
  r = await card(A, '00000000-0000-4000-8000-000000000000', 'xeque');
  check(r.type === 'social_card' && r.missing, 'jogador inexistente: cartão sem dados (sem erro)');
  A.close(); B.close(); s.stop();
  summary('PROFILE_CARD');
})().catch(e => { console.error(e); process.exit(1); });
