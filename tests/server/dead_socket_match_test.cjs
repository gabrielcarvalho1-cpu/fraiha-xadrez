'use strict';
// H04 · socket morto DURANTE a partida: o servidor encerra a conexão que não responde ao ping de protocolo
// (antes isso só valia fora de partida e o jogador ficava "conectado" para sempre). Morte do socket ≠ abandono:
// o encerramento só inicia a tolerância de reconexão da partida; voltar dentro dela continua a partida; não voltar
// = abandono pela regra já existente. Socket vivo e calado (responde pong) NÃO é encerrado.
// Tempos de teste: suspeito 0,6 s; morto 1,2 s; tolerância de reconexão 2,5 s.
const WebSocket = require('ws');
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ENV = { FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_MM_EXPAND_MS: '60000', FRAIHA_RANKED_RECONNECT_MS: '2500',
  FRAIHA_PRESENCE_SUSPECT_MS: '600', FRAIHA_PRESENCE_DEAD_MS: '1200', FRAIHA_PRESENCE_TICK_MS: '100' };

function rawApi(ws) {
  const inbox = [], waiters = [];
  ws.on('message', raw => { const m = JSON.parse(raw); const i = waiters.findIndex(w => w.pred(m)); if (i >= 0) waiters.splice(i, 1)[0].resolve(m); else inbox.push(m); });
  return { ws, inbox, open: () => new Promise(r => ws.readyState === 1 ? r() : ws.once('open', r)), send: o => ws.send(JSON.stringify(o)), close: () => ws.close(),
    next(pred, ms = 3000) { const p = typeof pred === 'string' ? (m => m.type === pred) : pred; const i = inbox.findIndex(p); if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
      return new Promise((resolve, reject) => { const w = { pred: p, resolve }; waiters.push(w); setTimeout(() => { const k = waiters.indexOf(w); if (k >= 0) { waiters.splice(k, 1); reject(new Error('timeout ' + (typeof pred === 'string' ? pred : 'pred'))); } }, ms); }); } };
}
async function login(port, name, opts) {
  const c = opts ? rawApi(new WebSocket('ws://127.0.0.1:' + port, opts)) : client(port);
  await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; return c;
}
async function guest(port, opts) {
  const c = opts ? rawApi(new WebSocket('ws://127.0.0.1:' + port, opts)) : client(port);
  await c.open(); c.send({ type: 'guest_auth', token: '' }); await c.next(m => /guest|acct_state/.test(m.type), 5000); return c;
}
const kind = k => ({ q: k + '_queue', queued: k + '_queued', found: k + '_found', state: k + '_state', result: k + '_result' });
async function pair(k, port, a, b, mode) {
  const K = kind(k);
  a.send({ type: K.q, mode }); await a.next(K.queued); b.send({ type: K.q, mode }); await b.next(K.queued);
  const fa = await a.next(K.found, 4000); await b.next(K.found, 4000);
  await a.next(m => m.type === K.state && m.status === 'playing', 4000);
  return { id: fa.match_id, aColor: fa.you };
}
const oppConnected = (st, color) => (color === 'w' ? st.white : st.black).connected;

(async () => {
  const s = await startServer(ENV);
  // 1 · Ranked: socket morto em partida é encerrado e o adversário vê "desconectado"
  { const A = await login(s.port, 'MortoA', { autoPong: false }), B = await login(s.port, 'VivoB');
    const { id, aColor } = await pair('ranked', s.port, A, B, 'ranked_3min');
    B.inbox.splice(0);
    const closed = new Promise(r => A.ws.once('close', () => r(Date.now()))); const t0 = Date.now();
    const tc = await Promise.race([closed, sleep(5000).then(() => 0)]);
    check(tc > 0 && tc - t0 < 4000, `Ranked: socket sem pong EM PARTIDA é encerrado pelo servidor (${tc - t0} ms depois do início da partida)`);
    const st = await B.next(m => m.type === 'ranked_state' && m.match_id === id && oppConnected(m, aColor) === false, 3000).catch(() => null);
    check(!!st && st.status === 'playing', 'Ranked: adversário recebe "desconectado" e a partida CONTINUA (não é abandono imediato)');
    // 2 · volta dentro da tolerância: mesma partida, conectado de novo
    await sleep(500);
    const A2 = await login(s.port, 'MortoA');
    const f = await A2.next('ranked_found', 3000).catch(() => null);
    check(!!f && f.match_id === id && f.resumed === true, 'Ranked: reconectou dentro da tolerância → volta à MESMA partida');
    const back = await B.next(m => m.type === 'ranked_state' && m.match_id === id && oppConnected(m, aColor) === true, 3000).catch(() => null);
    check(!!back && back.status === 'playing', 'Ranked: adversário vê o jogador conectado de novo; partida segue');
    let ended = false; try { await B.next('ranked_result', 3000); ended = true; } catch {}
    check(!ended, 'Ranked: depois de voltar, a tolerância não gera abandono');
    A2.send({ type: 'ranked_resign', match_id: id }); await B.next('ranked_result', 4000); A2.close(); B.close(); }
  // 3 · Ranked: morto e não volta → abandono pela regra existente (tolerância de reconexão)
  { const A = await login(s.port, 'SomeA', { autoPong: false }), B = await login(s.port, 'FicaB');
    const { id } = await pair('ranked', s.port, A, B, 'ranked_3min');
    const r = await B.next(m => m.type === 'ranked_result' && m.match_id === id, 9000).catch(() => null);
    check(!!r && r.outcome === 'win' && r.reason === 'abandon', 'Ranked: morto e sem voltar → abandono depois da tolerância (vitória do adversário)');
    B.close(); }
  // 4 · vivo e calado (navegador em segundo plano responde pong sozinho) NÃO é encerrado em partida
  { const A = await login(s.port, 'CaladoA'), B = await login(s.port, 'CaladoB');
    const { id } = await pair('ranked', s.port, A, B, 'ranked_3min');
    await sleep(3500);
    check(A.ws.readyState === 1, 'Ranked: socket vivo e calado (responde ping de protocolo) continua conectado por 3,5 s');
    let r = null; try { r = await B.next('ranked_result', 300); } catch {}
    check(!r, 'Ranked: socket vivo e calado não gera abandono');
    A.send({ type: 'ranked_resign', match_id: id }); await B.next('ranked_result', 4000); A.close(); B.close(); }
  // 5 · Casual (convidado) segue a mesma regra
  { const A = await guest(s.port, { autoPong: false }), B = await guest(s.port);
    const { id, aColor } = await pair('casual', s.port, A, B, 'casual_3min');
    const closed = await Promise.race([new Promise(r => A.ws.once('close', () => r(true))), sleep(5000).then(() => false)]);
    check(closed, 'Casual (convidado): socket morto em partida é encerrado');
    const st = await B.next(m => m.type === 'casual_state' && m.match_id === id && oppConnected(m, aColor) === false, 3000).catch(() => null);
    check(!!st && st.status === 'playing', 'Casual: adversário vê "desconectado", partida continua na tolerância');
    B.close(); }
  s.stop();
  summary('dead_socket_match');
})().catch(e => { console.error(e); process.exit(1); });
