'use strict';
// R144 · FILA ONLINE de MARCHA REAL e XEQUE (servidor real, FRAIHA_DEV_AUTH + MemoryStore).
// 4 pessoas → mesa na hora; 2 pessoas → mesa com bots depois da espera; sozinho → continua esperando;
// convite JOGAR ONLINE → os dois entram juntos (na MARCHA, dupla no mesmo time); cancelar; ocupado.
const { startServer, client, check, summary } = require('./helpers.cjs');
const { seatGroups } = require('../../online_v021/modes/party_queue');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ENV = { FRAIHA_DEV_AUTH: '1', FRAIHA_PARTY_QUEUE_FILL_MS: '1200', FRAIHA_PARTY_QUEUE_TICK_MS: '100', FRAIHA_PARTY_INTRO_MS: '5', FRAIHA_PARTY_MESA_MS: '5' };
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; c.nick = name; return c;
}
const pause = () => sleep(80);
const drain = (...cs) => cs.forEach(c => c.inbox.splice(0));
const humanSeats = st => st.players.map((p, i) => (p.bot ? -1 : i)).filter(i => i >= 0);

(async () => {
  // lugares (função pura)
  const M = (id) => ({ user_id: id });
  let seats = seatGroups('marcha', [{ members: [M('a')] }, { members: [M('b'), M('c')] }, { members: [M('d')] }]);
  const at = id => seats.find(x => x.member.user_id === id).seat;
  check(at('b') % 2 === at('c') % 2 && at('a') % 2 !== at('b') % 2 && at('d') % 2 === at('a') % 2, 'MARCHA: dupla de amigos no mesmo time; os dois sozinhos formam o outro');
  seats = seatGroups('marcha', [{ members: [M('a')] }, { members: [M('b')] }]);
  check(seats.map(x => x.seat).join() === '0,1', 'MARCHA: 2 sozinhos ficam em times opostos (cada um com um bot de dupla)');
  seats = seatGroups('xeque', [{ members: [M('a'), M('b')] }, { members: [M('c')] }]);
  check(seats.map(x => x.seat).join() === '0,1,2', 'XEQUE: cada um num lugar');

  const s = await startServer(ENV);
  const [A, B, C, D] = await Promise.all(['FilaAna', 'FilaBia', 'FilaCaio', 'FilaDuda'].map(n => login(s.port, n)));
  drain(A, B, C, D);
  // ---------- XEQUE: 4 pessoas → mesa na hora ----------
  for (const c of [A, B, C, D]) { await pause(); c.send({ type: 'party_queue', game: 'xeque' }); }
  const q = await A.next('party_queued', 3000);
  check(q.game === 'xeque', 'entrou na fila do XEQUE');
  const starts = await Promise.all([A, B, C, D].map(c => c.next('party_start', 4000)));
  check(starts.every(st => st.game === 'xeque' && st.room_id === starts[0].room_id), '4 pessoas na fila → a mesma mesa de XEQUE para os quatro');
  check(starts.every(st => st.players.filter(p => !p.bot).length === 4), 'mesa de 4 pessoas, sem bots');
  for (const c of [A, B, C, D]) { await pause(); c.send({ type: 'party_leave' }); }
  await sleep(300); drain(A, B, C, D);
  // ---------- MARCHA: 2 pessoas → espera e começa com bots ----------
  await pause(); A.send({ type: 'party_queue', game: 'marcha' });
  await pause(); B.send({ type: 'party_queue', game: 'marcha' });
  const st2 = await B.next(m => m.type === 'party_queue_status' && m.waiting === 2, 3000).catch(() => null);
  check(!!st2 && st2.fill_ms === 1200, 'status da fila: 2 esperando');
  const t0 = Date.now();
  const [ma, mb] = await Promise.all([A.next('party_start', 5000), B.next('party_start', 5000)]);
  check(Date.now() - t0 >= 600 && ma.room_id === mb.room_id && ma.players.filter(p => p.bot).length === 2, '2 pessoas → depois da espera a mesa começa com 2 bots');
  check(humanSeats(ma).length === 2 && humanSeats(ma).every(i => i === 0 || i === 1 || i === 3), 'MARCHA com 2 sozinhos: adversários (o outro não é a sua dupla)');
  for (const c of [A, B]) { await pause(); c.send({ type: 'party_leave' }); }
  await sleep(300); drain(A, B, C, D);
  // ---------- sozinho: espera; cancelar; ocupado ----------
  await pause(); C.send({ type: 'party_queue', game: 'xeque' });
  await C.next('party_queued', 3000);
  await sleep(1600);
  check(!C.inbox.some(m => m.type === 'party_start'), 'sozinho na fila: continua esperando (não começa só com bots)');
  await pause(); C.send({ type: 'party_queue', game: 'marcha' });
  check((await C.next('party_queue_error', 3000)).code === 'already_queued', 'não entra em duas filas');
  await pause(); C.send({ type: 'casual_queue', mode: 'casual_5min' });
  const busy = await C.next(m => m.type === 'casual_error' || m.type === 'casual_queued', 3000);
  check(busy.type === 'casual_error', 'na fila da MARCHA/XEQUE não entra na fila do xadrez');
  await pause(); C.send({ type: 'party_queue_cancel', game: 'xeque' });
  check((await C.next('party_queue_cancelled', 3000)).game === 'xeque', 'cancelar a busca');
  drain(A, B, C, D);
  // ---------- convite JOGAR ONLINE (amigos juntos, MARCHA = dupla) ----------
  const social = async (c, type, user_id) => { await pause(); c.send({ type, user_id }); return c.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000); };
  await social(A, 'social_request', B.id); await social(B, 'social_accept', A.id);
  drain(A, B, C, D);
  await pause(); A.send({ type: 'invite_send', user_id: B.id, game: 'marcha', table: 'online' });
  const rec = await B.next('invite_received', 4000);
  check(rec.invite.table === 'online', 'convite diz que é para jogar ONLINE');
  await pause(); B.send({ type: 'invite_accept', invite_id: rec.invite.id });
  const [qa, qb] = await Promise.all([A.next('party_queued', 4000), B.next('party_queued', 4000)]);
  check(qa.group === 2 && qb.group === 2, 'aceitou → os dois entram juntos na fila');
  await pause(); C.send({ type: 'party_queue', game: 'marcha' });
  await pause(); D.send({ type: 'party_queue', game: 'marcha' });
  const tbl = await Promise.all([A, B, C, D].map(c => c.next('party_start', 4000)));
  check(tbl.every(t => t.room_id === tbl[0].room_id) && tbl[0].players.every(p => !p.bot), 'dupla + 2 da fila = mesa de 4 pessoas');
  // cada um se vê no lugar 0; a dupla dele está no lugar 2 (MARCHA: 0+2 contra 1+3)
  const partnerOf = t => t.players[2].name;
  check(partnerOf(tbl[0]) === 'FilaBia' && partnerOf(tbl[1]) === 'FilaAna', 'Ana e Bia são dupla na mesa');
  check(partnerOf(tbl[2]) === 'FilaDuda' && partnerOf(tbl[3]) === 'FilaCaio', 'Caio e Duda formam a outra dupla');
  s.stop();
  summary('PARTY_QUEUE');
  process.exit();
})().catch(e => { console.error(e); process.exit(1); });
