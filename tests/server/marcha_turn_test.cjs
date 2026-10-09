'use strict';
// R54 · MARCHA REAL: 15 s por vez, prazo controlado pelo SERVIDOR. O cliente humano fica parado (como uma aba
// em segundo plano, que não manda nada) e o servidor resolve a vez dele sozinho quando o prazo vence.
// XEQUE continua com 30 s. Sem FRAIHA_PARTY_TURN_MS (padrões de produção).
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ENV = { FRAIHA_DEV_AUTH: '1' };
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; return c;
}
const pause = () => sleep(70);
async function friends(A, B) {
  await pause(); A.send({ type: 'social_request', user_id: B.id }); await A.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000);
  await pause(); B.send({ type: 'social_accept', user_id: A.id }); await B.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000);
}
async function party(A, B, game) {
  A.inbox.splice(0); B.inbox.splice(0);
  await pause(); A.send({ type: 'invite_send', user_id: B.id, game });
  const rec = await B.next('invite_received', 5000);
  await pause(); B.send({ type: 'invite_accept', invite_id: rec.invite.id });
  return [await A.next('party_start', 5000), await B.next('party_start', 5000)];
}
(async () => {
  const s = await startServer(ENV);
  const A = await login(s.port, 'TurnoAna'), B = await login(s.port, 'TurnoBia');
  await friends(A, B);
  const [sa] = await party(A, B, 'marcha');
  check(sa.turn_ms === 15000, 'MARCHA REAL: 15 s por vez (turn_ms ' + sa.turn_ms + ')');
  // espera a vez de A (lugar 0 na visão dele) e NÃO joga: o prazo é do servidor
  let turn = null; const t0 = Date.now();
  while (!turn && Date.now() - t0 < 30000) {
    const ev = await A.next('party_event', 30000);
    if (ev.snapshot && ev.snapshot.my_turn) turn = { at: Date.now(), left: ev.snapshot.turn_left_ms };
  }
  check(turn && turn.left > 13000 && turn.left <= 15000, 'vez do humano começa com o prazo do servidor (' + (turn && turn.left) + ' ms)');
  let auto = null;
  while (!auto && Date.now() - turn.at < 22000) {
    const ev = await A.next('party_event', 22000);
    if (ev.ev === 'move' && ev.reason === 'timeout') auto = Date.now() - turn.at;
  }
  check(auto !== null && auto >= 14000 && auto <= 17000, 'cliente parado: o servidor joga a vez dele ao fim dos 15 s (' + auto + ' ms)');
  // XEQUE mantém 30 s
  const C = await login(s.port, 'TurnoCaio'), D = await login(s.port, 'TurnoDani');
  await friends(C, D);
  const [sc] = await party(C, D, 'xeque');
  check(sc.turn_ms === 30000, 'XEQUE continua com 30 s por vez');
  summary(); s.stop && s.stop(); process.exit(process.exitCode || 0);
})().catch(e => { console.error(e); process.exit(1); });
