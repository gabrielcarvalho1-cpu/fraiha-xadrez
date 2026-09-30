'use strict';
// Convites para partida Casual entre amigos (Etapa 6). Servidor real com FRAIHA_DEV_AUTH (MemoryStore).
// TTL de teste: 4 s (FRAIHA_TEST_INVITE_TTL_MS). Em produção: 60 s.
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const TTL = 4000;
const ENV = { FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_TEST_INVITE_TTL_MS: String(TTL), FRAIHA_MM_EXPAND_MS: '60000' };
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; c.nick = name; c.ranked = st.ranked; return c;
}
const pause = () => sleep(70); // servidor fecha sockets com mais de 20 mensagens/s
async function social(c, type, user_id) { await pause(); c.send({ type, user_id }); return c.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000); }
async function friends(a, b) { await social(a, 'social_request', b.id); await social(b, 'social_accept', a.id); }
async function invite(c, to, mode) { await pause(); c.send({ type: 'invite_send', user_id: to.id || to, mode }); return c.next(m => m.type === 'invite_sent' || m.type === 'invite_error', 5000); }
async function act(c, type, id) { await pause(); c.send({ type, invite_id: id }); }
const updated = (c, id, status) => c.next(m => m.type === 'invite_updated' && m.invite.id === id && (!status || m.invite.status === status), 6000);
const received = c => c.next(m => m.type === 'invite_received', 5000);
async function finish(c, other) {
  const st = await c.next(m => m.type === 'casual_state' && m.status === 'playing', 5000);
  c.send({ type: 'casual_resign', match_id: st.match_id });
  const r1 = await c.next('casual_result', 5000); await other.next('casual_result', 5000);
  await sleep(150);
  return r1;
}
const drain = (...cs) => cs.forEach(c => c.inbox.splice(0));

(async () => {
  let s = await startServer(ENV);
  const A = await login(s.port, 'AnaConv'), B = await login(s.port, 'BiaConv'), C = await login(s.port, 'CaduConv'), D = await login(s.port, 'DudaConv'), E = await login(s.port, 'EduConv');
  await friends(A, B); await friends(A, C); await friends(B, E); await friends(C, E);
  const rankedBefore = JSON.stringify(A.ranked);
  drain(A, B, C, D, E);
  // Validações
  check((await invite(A, A, 'casual_3min')).code === 'self', 'não convida a si mesmo');
  check((await invite(A, B, 'casual_7min')).code === 'bad_mode', 'tempo inválido é rejeitado');
  check((await invite(A, B, 'ranked_5min')).code === 'bad_mode', 'modalidade Ranked não vale para convite');
  check((await invite(A, D, 'casual_3min')).code === 'not_friends', 'sem amizade: convite negado');
  check((await invite(A, 'xyz', 'casual_3min')).code === 'bad_user', 'id inválido é rejeitado');
  const g = client(s.port); await g.open(); g.send({ type: 'guest_auth' }); await g.next('guest_state');
  g.send({ type: 'invite_send', user_id: B.id, mode: 'casual_3min' }); check((await g.next('invite_error')).code === 'auth_required', 'convidado não convida');
  g.close();
  // Os 4 tempos: enviar, receber, aceitar, partida Casual criada
  for (const [mode, min] of [['casual_3min', 3], ['casual_5min', 5], ['casual_10min', 10], ['casual_20min', 20]]) {
    drain(A, B);
    const sent = await invite(A, B, mode);
    const rec = await received(B);
    check(sent.type === 'invite_sent' && rec.invite.id === sent.invite.id && rec.invite.from.nickname === 'AnaConv' && rec.invite.minutes === min && rec.invite.expires_in_ms > TTL - 1500 && !('email' in rec.invite.from),
      `${min} min: convite enviado e recebido (nickname, tempo, expiração; sem e-mail)`);
    await act(B, 'invite_accept', rec.invite.id);
    const fa = await A.next('casual_found', 5000), fb = await B.next('casual_found', 5000);
    const acc = await updated(A, rec.invite.id, 'accepted');
    check(fa.match_id === fb.match_id && fa.mode === mode && acc.invite.match_id === fa.match_id, `${min} min: aceitar cria UMA partida Casual para os dois`);
    const r = await finish(A, B);
    check(r.pl_change === undefined || r.pl_change === 0, `${min} min: resultado Casual sem PL`);
  }
  // Clique duplo em aceitar / pacote repetido: uma partida só
  drain(A, B);
  let inv = (await invite(A, B, 'casual_3min')).invite; await received(B);
  B.send({ type: 'invite_accept', invite_id: inv.id }); B.send({ type: 'invite_accept', invite_id: inv.id }); B.send({ type: 'invite_accept', invite_id: inv.id });
  await A.next('casual_found', 5000); await sleep(800);
  check(!A.inbox.some(m => m.type === 'casual_found') && !B.inbox.filter(m => m.type === 'casual_found').slice(1).length, 'aceite repetido (3x) cria só UMA partida');
  await finish(A, B);
  // Convite duplicado
  drain(A, B);
  inv = (await invite(A, B, 'casual_5min')).invite; await received(B);
  const dup = await invite(A, B, 'casual_5min');
  check(dup.duplicate === true && dup.invite.id === inv.id, 'reenviar o mesmo convite devolve o existente (sem duplicar)');
  check((await invite(A, C, 'casual_5min')).code === 'pending_exists', 'um convite pendente por jogador (remetente)');
  // Convites cruzados e mesmo destinatário
  check((await invite(B, A, 'casual_5min')).code === 'pending_exists', 'convite cruzado não é aceito automaticamente (o primeiro prevalece)');
  check((await invite(E, B, 'casual_5min')).code === 'target_busy', 'dois convidando o mesmo destinatário: o segundo é recusado');
  // Aceitar convite de outra pessoa / cancelar alheio
  await act(C, 'invite_accept', inv.id); check((await C.next('invite_error', 4000)).code === 'not_found', 'terceiro não aceita convite alheio');
  await act(A, 'invite_accept', inv.id); check((await A.next('invite_error', 4000)).code === 'not_recipient', 'remetente não aceita o próprio convite');
  // Recusar
  await act(B, 'invite_decline', inv.id);
  const dA = await updated(A, inv.id, 'declined'); await updated(B, inv.id, 'declined');
  check(dA.invite.status === 'declined', 'recusar: os dois recebem "declined"');
  await act(B, 'invite_accept', inv.id); check((await updated(B, inv.id)).invite.status === 'declined', 'aceitar depois de recusar não cria partida');
  // Cancelar
  drain(A, B);
  inv = (await invite(A, B, 'casual_10min')).invite; await received(B);
  await act(A, 'invite_cancel', inv.id);
  check((await updated(B, inv.id, 'cancelled')).invite.reason === 'sender', 'remetente cancela: destinatário é avisado');
  await act(B, 'invite_accept', inv.id); await sleep(400);
  check(!B.inbox.some(m => m.type === 'casual_found'), 'aceitar convite cancelado não cria partida');
  // Aceitar x cancelar ao mesmo tempo: nunca os dois
  drain(A, B);
  inv = (await invite(A, B, 'casual_3min')).invite; await received(B);
  B.send({ type: 'invite_accept', invite_id: inv.id }); A.send({ type: 'invite_cancel', invite_id: inv.id });
  await sleep(1200);
  const fin = [...A.inbox, ...B.inbox].filter(m => m.type === 'invite_updated' && m.invite.id === inv.id).map(m => m.invite.status).pop();
  const found = B.inbox.filter(m => m.type === 'casual_found').length;
  check((fin === 'accepted' && found === 1) || (fin === 'cancelled' && found === 0), `aceitar x cancelar simultâneos: resultado único (${fin}, partidas=${found})`);
  if (found) await finish(A, B);
  // Expirar
  drain(A, B);
  inv = (await invite(A, B, 'casual_3min')).invite; await received(B);
  const ex = await updated(B, inv.id, 'expired'); await updated(A, inv.id, 'expired');
  check(ex.invite.status === 'expired', 'convite expira sozinho (TTL) e avisa os dois');
  await act(B, 'invite_accept', inv.id); await sleep(400);
  check(!B.inbox.some(m => m.type === 'casual_found'), 'aceitar convite expirado não cria partida');
  // Aceitar perto do fim do prazo
  drain(A, B);
  inv = (await invite(A, B, 'casual_3min')).invite; await received(B);
  await sleep(TTL - 900); await act(B, 'invite_accept', inv.id);
  check((await B.next('casual_found', 4000)).mode === 'casual_3min', 'aceitar perto do fim do prazo ainda funciona');
  await finish(A, B);
  // Bloqueio depois de enviar
  drain(A, C);
  inv = (await invite(A, C, 'casual_3min')).invite; await received(C);
  await social(C, 'social_block', A.id);
  check((await updated(A, inv.id, 'cancelled')).invite.reason === 'relation', 'bloquear depois de enviar cancela o convite');
  await act(C, 'invite_accept', inv.id); await sleep(400); check(!C.inbox.some(m => m.type === 'casual_found'), 'sem partida após bloqueio');
  check((await invite(A, C, 'casual_3min')).code === 'unavailable', 'bloqueado não convida');
  check((await invite(C, A, 'casual_3min')).code === 'blocked', 'quem bloqueou também não convida');
  await social(C, 'social_unblock', A.id);
  // Remover amizade depois de enviar
  drain(A, B);
  inv = (await invite(A, B, 'casual_3min')).invite; await received(B);
  await social(A, 'social_remove', B.id);
  check((await updated(B, inv.id, 'cancelled')).invite.reason === 'relation', 'remover amizade depois de enviar cancela o convite');
  await friends(A, B);
  // Fila Casual / Ranked
  drain(A, B);
  inv = (await invite(A, B, 'casual_3min')).invite; await received(B);
  await pause(); B.send({ type: 'casual_queue', mode: 'casual_5min' }); await B.next('casual_queued', 4000);
  check((await updated(A, inv.id, 'cancelled')).invite.reason === 'queue', 'entrar na fila Casual cancela o convite pendente');
  check((await invite(A, B, 'casual_3min')).code === 'target_in_queue', 'amigo na fila não recebe convite');
  await pause(); B.send({ type: 'casual_cancel' }); await B.next('casual_cancelled', 4000);
  inv = (await invite(A, B, 'casual_3min')).invite; await received(B);
  await pause(); A.send({ type: 'ranked_queue', mode: 'ranked_3min' }); await A.next('ranked_queued', 4000);
  check((await updated(B, inv.id, 'cancelled')).invite.reason === 'queue', 'entrar na fila Ranked cancela o convite pendente');
  check((await invite(A, B, 'casual_3min')).code === 'in_queue', 'na fila Ranked não envia convite');
  await pause(); A.send({ type: 'ranked_cancel' }); await A.next('ranked_cancelled', 4000);
  // Ocupado em partida
  drain(B, E);
  inv = (await invite(E, B, 'casual_3min')).invite; await received(B);
  await act(B, 'invite_accept', inv.id); await B.next('casual_found', 4000); await E.next('casual_found', 4000);
  check((await invite(A, B, 'casual_3min')).code === 'target_in_match', 'amigo em partida não recebe convite');
  check((await invite(B, A, 'casual_3min')).code === 'in_match', 'quem está em partida não envia convite');
  await finish(E, B);
  // Reconexão: convite pendente volta no snapshot e pode ser aceito
  drain(A, B);
  inv = (await invite(A, B, 'casual_5min')).invite; await received(B);
  B.close(); await sleep(300);
  const B2 = await login(s.port, 'BiaConv');
  const snap = await B2.next('invite_snapshot', 4000);
  check(snap.invites.length === 1 && snap.invites[0].id === inv.id && snap.invites[0].status === 'pending', 'reconectar: invite_snapshot devolve o convite pendente');
  await act(B2, 'invite_accept', inv.id);
  check((await B2.next('casual_found', 4000)).mode === 'casual_5min', 'reconectado aceita e a partida começa');
  await finish(A, B2);
  // Offline
  D.close(); await friends(A, E); drain(A, E); E.close(); await sleep(300);
  check((await invite(A, E, 'casual_3min')).code === 'target_offline', 'amigo offline não recebe convite');
  // Ranked/PL não mudam com convites
  A.send({ type: 'acct_refresh' }); const st = await A.next('acct_state', 4000);
  check(JSON.stringify(st.ranked) === rankedBefore, 'Ranked/PL do jogador não mudaram depois de 9 partidas por convite');
  A.close(); B2.close(); C.close();
  // Servidor reinicia: convites em memória somem (snapshot vazio, sem convite fantasma)
  s.stop(); s = await startServer(ENV);
  const A2 = await login(s.port, 'AnaConv');
  A2.send({ type: 'invite_sync' });
  check((await A2.next('invite_snapshot', 4000)).invites.length === 0, 'servidor reiniciado: snapshot vazio (sem convite fantasma)');
  A2.close(); s.stop();

  // Revalidação no aceite (sem os ganchos de cancelamento): amizade desfeita direto no banco.
  const { Backend } = require('../../online_v021/backend');
  const out = [];
  const be = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (ws, o) => out.push([ws.name, o]) });
  clearInterval(be.sweeper); be.invites.stop();
  const { Ranked } = require('../../online_v021/ranked/service');
  const cas = new Ranked({ send: (ws, o) => out.push([ws.name, o]), kind: 'casual' }); be.attachCasual(cas); cas.stop();
  const u1 = '11111111-1111-4111-a111-111111111111', u2 = '22222222-2222-4222-a222-222222222222';
  await be.store.createProfile(u1, 'ReA', 'warrior'); await be.store.createProfile(u2, 'ReB', 'warrior');
  await be.store.addFriendship(u1, u2);
  const w1 = { name: 'w1', readyState: 1, user: { id: u1 }, profile: { nickname: 'ReA', avatar_id: 'warrior' } };
  const w2 = { name: 'w2', readyState: 1, user: { id: u2 }, profile: { nickname: 'ReB', avatar_id: 'warrior' } };
  be.setIdentity(w1, { id: u1, nickname: 'ReA', avatar: 'warrior' }); be.setIdentity(w2, { id: u2, nickname: 'ReB', avatar: 'warrior' });
  await be.handle(w1, { type: 'invite_send', user_id: u2, mode: 'casual_3min' });
  const id = out.find(([n, o]) => n === 'w2' && o.type === 'invite_received')[1].invite.id;
  await be.store.removeFriendship(u1, u2);             // sem gancho: só a revalidação pode barrar
  await be.handle(w2, { type: 'invite_accept', invite_id: id });
  const last = out.filter(([n, o]) => o.type === 'invite_updated').pop()[1];
  check(last.invite.status === 'failed' && last.invite.reason === 'not_friends' && cas.matches.size === 0 && !be.invites.reserved(u1) && !be.invites.reserved(u2), 'aceite revalida amizade: falha sem criar partida e libera as reservas');
  // Bloqueio no banco + revalidação
  await be.store.addFriendship(u1, u2);
  await be.handle(w1, { type: 'invite_send', user_id: u2, mode: 'casual_3min' });
  const id2 = out.filter(([n, o]) => n === 'w2' && o.type === 'invite_received').pop()[1].invite.id;
  await be.store.addBlock(u1, u2);
  await be.handle(w2, { type: 'invite_accept', invite_id: id2 });
  const last2 = out.filter(([n, o]) => o.type === 'invite_updated').pop()[1];
  check(last2.invite.status === 'failed' && cas.matches.size === 0, 'aceite revalida bloqueio: falha sem criar partida');
  summary('INVITES');
})().catch(e => { console.error(e); process.exit(1); });
