'use strict';
// R181 · TODAS AS FILAS: FRAIHA_QUEUE_AI_WAIT_MS (padrão 30 s) de busca por pessoa; sem ninguém → rival de IA
// (Ranked/Casual) ou bots na mesa (Xeque/Marcha). Pessoa que chega durante a espera enfrenta a pessoa (prioridade).
const { startServer, client, check, summary } = require('./helpers.cjs');
const { QueueAI } = require('../../online_v021/ranked/queue_ai');
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); await c.next('acct_state'); }
  return c;
}
(async () => {
  // padrão e leitura a cada verificação (sem build/restart)
  const env = {};
  const q = new QueueAI({ rated: true }, { env });
  check(q.waitMs === 15000, 'padrão (R184): 15 s de busca por pessoa antes da IA');
  env.FRAIHA_QUEUE_AI_WAIT_MS = '45000';
  check(q.waitMs === 45000, 'FRAIHA_QUEUE_AI_WAIT_MS muda o tempo na hora (lido a cada verificação)');
  // mesa (Xeque/Marcha): sozinho → bots depois do tempo
  { const old = process.env.FRAIHA_QUEUE_AI_WAIT_MS; delete process.env.FRAIHA_QUEUE_AI_WAIT_MS;
    const { PartyQueue: PQ } = require('../../online_v021/modes/party_queue'); const p0 = Object.create(PQ.prototype);
    const s0 = [{ id: 'g0', game: 'xeque', members: [{ user_id: 'z' }], since: 0 }];
    check(p0.pick(s0, 14000) === null && Array.isArray(p0.pick(s0, 15000)), 'padrão (R184): mesa sozinho começa com bots aos 15 s');
    if (old !== undefined) process.env.FRAIHA_QUEUE_AI_WAIT_MS = old; }
  process.env.FRAIHA_QUEUE_AI_WAIT_MS = '30000';
  const { PartyQueue } = require('../../online_v021/modes/party_queue');
  const pq = Object.create(PartyQueue.prototype);
  const solo = [{ id: 'g1', game: 'xeque', members: [{ user_id: 'a' }], since: 0 }];
  check(pq.pick(solo, 29000) === null, 'mesa sozinho aos 29 s: ainda espera pessoa');
  check(Array.isArray(pq.pick(solo, 30000)), 'mesa sozinho aos 30 s: começa com bots nos lugares vazios');
  // Ranked: pessoa que chega durante a espera enfrenta a pessoa (não a IA)
  const s = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_QUEUE_AI_WAIT_MS: '3000' });
  try {
    const a = await login(s.port, 'EsperaUm'), b = await login(s.port, 'ChegaDepois');
    a.send({ type: 'ranked_queue', mode: 'ranked_10min' }); await a.next('ranked_queued');
    await sleep(1800);
    b.send({ type: 'ranked_queue', mode: 'ranked_10min' }); await b.next('ranked_queued');
    const fa = await a.next('ranked_found', 6000);
    check(!fa.vs_ai && fa.opponent.nickname === 'ChegaDepois', 'chegou outra pessoa aos 1,8 s: as duas se enfrentam (pessoa tem prioridade)');
    a.send({ type: 'ranked_resign', match_id: fa.match_id }); await sleep(300); a.ws.close(); b.ws.close();
    const c = await login(s.port, 'Sozinho30');
    const t0 = Date.now();
    c.send({ type: 'ranked_queue', mode: 'ranked_10min' }); await c.next('ranked_queued');
    const fc = await c.next('ranked_found', 8000);
    check(fc.vs_ai && Date.now() - t0 >= 2900, `sozinho: rival de IA só depois do tempo configurado (${Date.now() - t0} ms)`);
    c.ws.close();
    // Casual com CONVIDADO (convidado não joga Ranked): mesmo tempo, rival de IA, sem PL
    const g = client(s.port); await g.open();
    g.send({ type: 'guest_auth' }); await g.next('guest_state');
    const tg = Date.now();
    g.send({ type: 'casual_queue', mode: 'casual_5min' }); await g.next('casual_queued');
    const fg = await g.next('casual_found', 8000);
    check(fg.vs_ai && fg.opponent.ai && Date.now() - tg >= 2900 && fg.opponent.pl === undefined, 'convidado no Casual: rival de IA depois do tempo, sem PL');
    g.ws.close();
  } finally { s.stop(); }
  summary('FILAS_30S');
})().catch(e => { console.error(e); process.exit(1); });
