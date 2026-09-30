'use strict';
// Presença (Etapa 7): offline / online / in_match calculada pelo servidor, com tolerância,
// heartbeat, várias sessões, partidas (Ranked, Casual, Convite, reconexão) e privacidade (só amigos).
// Tempos curtos de teste: suspeito 0,6 s; morto 1,2 s; tolerância 0,8 s; checagem 0,1 s.
const WebSocket = require('ws');
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const GRACE = 800;
const ENV = { FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_MM_EXPAND_MS: '60000', FRAIHA_PRESENCE_SUSPECT_MS: '600', FRAIHA_PRESENCE_DEAD_MS: '1200', FRAIHA_PRESENCE_GRACE_MS: String(GRACE), FRAIHA_PRESENCE_TICK_MS: '100' };
async function login(port, name, opts) {
  // opts: cliente "cru" (ex.: sem pong automático) para simular conexão silenciosa
  const c = opts ? rawApi(new WebSocket('ws://127.0.0.1:' + port, opts)) : client(port);
  await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; c.nick = name; return c;
}
function rawApi(ws) {
  const inbox = [], waiters = [];
  ws.on('message', raw => { const m = JSON.parse(raw); const i = waiters.findIndex(w => w.pred(m)); if (i >= 0) waiters.splice(i, 1)[0].resolve(m); else inbox.push(m); });
  return { ws, inbox, open: () => new Promise(r => ws.readyState === 1 ? r() : ws.once('open', r)), send: o => ws.send(JSON.stringify(o)), close: () => ws.close(),
    next(pred, ms = 3000) { const p = typeof pred === 'string' ? (m => m.type === pred) : pred; const i = inbox.findIndex(p); if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
      return new Promise((resolve, reject) => { const w = { pred: p, resolve }; waiters.push(w); setTimeout(() => { const k = waiters.indexOf(w); if (k >= 0) { waiters.splice(k, 1); reject(new Error('timeout ' + (typeof pred === 'string' ? pred : 'pred'))); } }, ms); }); } };
}
const pause = () => sleep(70);
async function social(c, type, user_id) { await pause(); c.send({ type, user_id }); return c.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000); }
async function friends(a, b) { await social(a, 'social_request', b.id); await social(b, 'social_accept', a.id); }
const upd = (c, who, state, ms = 4000) => c.next(m => m.type === 'presence_update' && m.user_id === who.id && (!state || m.state === state), ms);
const updatesAbout = (c, who) => c.inbox.filter(m => m.type === 'presence_update' && m.user_id === who.id);
async function finishCasual(a, b) {
  const st = await a.next(m => m.type === 'casual_state' && m.status === 'playing', 5000);
  a.send({ type: 'casual_resign', match_id: st.match_id }); await a.next('casual_result', 5000); await b.next('casual_result', 5000);
}

(async () => {
  const s = await startServer(ENV);
  const O = await login(s.port, 'ObsPres');          // observador: amigo de A e B
  const B = await login(s.port, 'BiaPres'), C = await login(s.port, 'CaduPres'), D = await login(s.port, 'DudaPres');
  let A = await login(s.port, 'AnaPres');
  await friends(A, O); await friends(B, O); await friends(A, B); await friends(A, D);
  await social(D, 'social_block', A.id);              // bloqueio: D e A não trocam presença
  await sleep(200); for (const c of [A, B, C, D, O]) c.inbox.splice(0);

  // 2 + 1/4: última sessão some -> mantém durante a tolerância -> offline; volta -> online
  A.close();
  await sleep(GRACE / 3);
  check(!updatesAbout(O, A).some(m => m.state === 'offline'), 'última sessão fechou: durante a tolerância NÃO publica offline');
  const off = await upd(O, A, 'offline');
  check(off.state === 'offline' && off.epoch && off.rev > 0, 'depois da tolerância: amigo recebe offline (com revisão)');
  A = await login(s.port, 'AnaPres');
  const on = await upd(O, A, 'online');
  check(on.rev > off.rev, 'nova sessão: offline -> online, revisão maior');
  const snap = await A.next('presence_snapshot', 3000);
  const ids = snap.friends.map(f => f.user_id);
  check(ids.includes(O.id) && ids.includes(B.id) && snap.friends.find(f => f.user_id === B.id).state === 'online', 'snapshot após login: amigos com presença correta');
  check(!ids.includes(C.id) && !ids.includes(D.id), 'snapshot não inclui não amigo nem bloqueado');
  // 3: reconexão dentro da tolerância não pisca
  O.inbox.splice(0);
  A.close(); await sleep(GRACE / 3);
  A = await login(s.port, 'AnaPres'); await sleep(GRACE + 400);
  check(updatesAbout(O, A).length === 0, 'reconectar antes da tolerância: nenhum offline/online publicado');
  // 7/8: duas sessões; fechar uma (a antiga) não deixa offline nem remove a nova
  const A2 = await login(s.port, 'AnaPres');
  A.close(); await sleep(GRACE + 400);
  check(updatesAbout(O, A).length === 0, 'duas sessões: fechar a antiga não deixa offline');
  A = A2;
  // 6/20: heartbeat mantém viva uma sessão sem pong automático; sem spam de updates
  const H = await login(s.port, 'HeitorPres', { autoPong: false });
  await friends(H, O); await sleep(200); O.inbox.splice(0);
  const beat = setInterval(() => H.send({ type: 'ping' }), 300);
  await sleep(3000);
  clearInterval(beat);
  check(H.ws.readyState === 1, 'heartbeat (ping a cada 0,3 s) mantém a sessão viva por 3 s (> limite de 1,2 s)');
  check(updatesAbout(O, H).length === 0, 'heartbeat repetido não gera updates de presença');
  // 5: silêncio -> suspeito -> encerrado -> offline
  const closed = new Promise(r => H.ws.once('close', () => r(Date.now())));
  const t0 = Date.now();
  const offH = await upd(O, H, 'offline', 6000);
  const tc = await closed;
  check(tc - t0 >= 850 && offH.state === 'offline', `silêncio: conexão encerrada pelo servidor (~${tc - t0} ms) e depois offline`);
  // 9/10/12: Casual por fila
  O.inbox.splice(0);
  await pause(); A.send({ type: 'casual_queue', mode: 'casual_3min' }); await A.next('casual_queued');
  await sleep(300);
  check(updatesAbout(O, A).length === 0, 'estar na fila não muda presença (continua online)');
  await pause(); B.send({ type: 'casual_queue', mode: 'casual_3min' });
  check((await upd(O, A, 'in_match')).state === 'in_match' && (await upd(O, B, 'in_match')).state === 'in_match', 'Casual pela fila: online -> in_match (os dois)');
  await finishCasual(A, B);
  check((await upd(O, A, 'online')).state === 'online' && (await upd(O, B, 'online')).state === 'online', 'fim da partida: in_match -> online (mesmo na tela de resultado)');
  // 11: Ranked
  await pause(); A.send({ type: 'ranked_queue', mode: 'ranked_5min' }); await A.next('ranked_queued');
  await pause(); B.send({ type: 'ranked_queue', mode: 'ranked_5min' });
  check((await upd(O, A, 'in_match', 6000)).state === 'in_match', 'Ranked: in_match');
  const rs = await A.next(m => m.type === 'ranked_state' && m.status === 'playing', 5000);
  // 14: partida recuperada por reconexão (sem sessão: pode aparecer offline, mas continua ocupado)
  A.close();
  const offM = await upd(O, A, 'offline', 4000);
  check(offM.state === 'offline', 'em partida e sem nenhuma sessão: aparece offline depois da tolerância');
  await pause(); B.send({ type: 'invite_send', user_id: A.id, mode: 'casual_3min' });
  const busy = await B.next('invite_error', 3000);
  check(busy.code === 'target_in_match' || busy.code === 'in_match', 'mesmo "offline", continua ocupado para convites enquanto a partida existe');
  A = await login(s.port, 'AnaPres');
  await A.next('ranked_found', 3000);
  check((await upd(O, A, 'in_match')).state === 'in_match', 'reconectou na partida: in_match');
  A.send({ type: 'ranked_resign', match_id: rs.match_id }); await A.next('ranked_result', 5000);
  check((await upd(O, A, 'online')).state === 'online', 'fim do Ranked: online');
  // 13/21: Casual por convite; presença online não é autorização (fila)
  await sleep(200); O.inbox.splice(0);
  await pause(); B.send({ type: 'casual_queue', mode: 'casual_5min' }); await B.next('casual_queued');
  await pause(); A.send({ type: 'social_list' }); const la = await A.next('social_list');
  check(la.friends.find(f => f.user_id === B.id).presence === 'online', 'amigo na fila aparece Online');
  await pause(); A.send({ type: 'invite_send', user_id: B.id, mode: 'casual_3min' });
  check((await A.next('invite_error')).code === 'target_in_queue', 'convite continua validando fila (presença online não autoriza)');
  await pause(); B.send({ type: 'casual_cancel' }); await B.next('casual_cancelled');
  await pause(); A.send({ type: 'invite_send', user_id: B.id, mode: 'casual_3min' });
  const inv = await B.next('invite_received');
  await sleep(300);
  check(updatesAbout(O, A).length === 0, 'convite enviado/pendente não muda presença');
  await pause(); B.send({ type: 'invite_accept', invite_id: inv.invite.id });
  check((await upd(O, A, 'in_match')).state === 'in_match' && (await upd(O, B, 'in_match')).state === 'in_match', 'Casual por convite: in_match só quando a partida existe');
  await finishCasual(A, B);
  await upd(O, A, 'online'); await upd(O, B, 'online');
  // 15/16/17: privacidade
  check(!C.inbox.some(m => m.type.startsWith('presence_')), 'não amigo nunca recebe presença');
  check(!D.inbox.some(m => m.type === 'presence_update' && m.user_id === A.id) && !A.inbox.some(m => m.type === 'presence_update' && m.user_id === D.id), 'bloqueio: nenhuma presença entre as contas');
  await pause(); C.send({ type: 'social_profile', user_id: A.id }); const pc = await C.next('social_profile');
  check(pc.profile.presence === '', 'perfil de não amigo não revela presença');
  // Amizade nova passa a receber; removida deixa de receber
  await friends(A, C); await sleep(200); C.inbox.splice(0);
  B.close();
  check((await upd(C, B, 'offline', 3000).catch(() => null)) === null, 'amigo de amigo não recebe presença');
  const A3 = await login(s.port, 'AnaPres'); A3.close();
  await sleep(200); C.inbox.splice(0);
  A.close();
  await sleep(GRACE + 600);
  A = await login(s.port, 'AnaPres');
  check((await upd(C, A, 'online')).state === 'online', 'amizade aceita: passa a receber presença');
  await social(A, 'social_remove', C.id); await sleep(200); C.inbox.splice(0);
  A.close(); await sleep(GRACE + 600);
  check(updatesAbout(C, A).length === 0, 'amizade removida: deixa de receber presença');
  // 19: revisões crescentes na mesma época
  const revs = O.inbox.filter(m => m.type === 'presence_update' && m.user_id === A.id).map(m => m.rev);
  const epochs = new Set(O.inbox.filter(m => m.type === 'presence_update').map(m => m.epoch));
  check(revs.every((r, i) => i === 0 || r > revs[i - 1]) && epochs.size <= 1, 'revisões sempre crescentes e mesma época (cliente descarta update antigo)');
  // 22: DM não carrega presença
  A = await login(s.port, 'AnaPres'); const B3 = await login(s.port, 'BiaPres');
  await pause(); A.send({ type: 'dm_send', user_id: B3.id, text: 'oi' });
  const dm = await B3.next('dm_msg');
  check(!('presence' in dm) && !('state' in dm) && !('presence' in dm.message), 'DM não mistura presença com mensagem');
  for (const c of [A, B3, C, D, O]) c.close();
  s.stop();
  summary('PRESENCE');
})().catch(e => { console.error(e); process.exit(1); });
