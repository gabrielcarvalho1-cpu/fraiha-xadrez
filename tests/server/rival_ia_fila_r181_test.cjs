'use strict';
// R181 · RIVAL DE IA NA FILA: servidor de verdade (dev auth + MemoryStore).
//  • 1 jogador sozinho no Ranked: depois da espera recebe um rival de IA da mesma liga (selo ai, nome de personagem);
//  • a partida começa e a IA joga lances legais sozinha, com relógio;
//  • resultado: METADE do PL, placar V/D/E e Força intactos, marcado vs_ai; a IA não vira conta;
//  • desistência precoce contra a IA: 0 PL;
//  • Casual sozinho também recebe IA; revanche contra IA é recusada com aviso;
//  • dois humanos na fila se encontram entre si (IA não entra); FRAIHA_QUEUE_AI=off: sem IA.
const { Position } = require('../../online_v021/chess_rules');
const { startServer, client, check, summary } = require('./helpers.cjs');
const { applyResult } = require('../../online_v021/ranked/progression');
const { aiStats, PERSONAS, LEVELS } = require('../../online_v021/ranked/queue_ai');
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); await c.next('acct_state'); }
  return c;
}
async function play(c, p, found, plies, deadlineMs = 60000) {
  const me = found.you, id = found.match_id, pos = new Position();
  let aiMoves = 0, illegal = false; const deadline = Date.now() + deadlineMs;
  while (pos.ply < plies && Date.now() < deadline) {
    const st = await c.next(m => m.type === p + '_state' && m.match_id === id && m.status === 'playing' && (m.position.ply > pos.ply || (m.position.ply === pos.ply && m.position.turn === me)), 20000);
    if (st.position.ply > pos.ply) { const lm = st.last_move; if (!pos.play({ from: lm.from, to: lm.to, promotion: 'Q' })) illegal = true; aiMoves++; }
    if (pos.turn === me && st.position.turn === me && !pos.outcome()) {
      const legal = pos.legalMoves(); const m = legal[Math.floor(Math.random() * legal.length)];
      pos.play(m); c.send({ type: p + '_move', match_id: id, from: m.from, to: m.to, promotion: m.promotion });
    }
  }
  return { aiMoves, illegal, pos };
}

(async () => {
  const env = { FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_QUEUE_AI_WAIT_MS: '1500' };
  const s = await startServer(env);
  try {
    // 1. sozinho no Ranked → rival de IA depois da espera
    const a = await login(s.port, 'SozinhoR181');
    const t0 = Date.now();
    a.send({ type: 'ranked_queue', mode: 'ranked_5min' }); await a.next('ranked_queued');
    const found = await a.next('ranked_found', 8000);
    const waited = Date.now() - t0;
    check(found.vs_ai === true && found.opponent.ai === true && waited >= 1400, `sozinho na fila: rival de IA depois de ${waited} ms (selo IA ligado)`);
    check(PERSONAS.some(([n]) => n === found.opponent.nickname) && found.opponent.user_id === '' && found.opponent.league === 0, `IA com nome de personagem (${found.opponent.nickname}), sem conta, mesma liga (Madeira)`);
    check(found.ai_wait_ms >= 1400, 'servidor informa quanto tempo esperou (Admin: "Rival IA encontrado após Xs")');
    const r = await play(a, 'ranked', found, 14);
    check(r.aiMoves >= 6 && !r.illegal, `IA jogou ${r.aiMoves} lances sozinha, todos legais`);
    // estado público nunca expõe a Força da IA/dados internos
    a.send({ type: 'ranked_resign', match_id: found.match_id });
    const res = await a.next('ranked_result', 8000);
    const full = applyResult({ league: 0, pl: 0, matches: 0, wins: 0, losses: 0, draws: 0, highest_league: 0 }, aiStats(0), 'loss');
    check(res.outcome === 'loss' && res.vs_ai === true && res.saved === true && res.pl_change === 0 && full.change <= 0, 'derrota contra IA em 0 PL: gravada, marcada vs_ai (piso de 0 PL)');
    check(res.stats.matches === 0 && res.stats.losses === 0, 'placar V/D/E não conta partida contra IA');
    // 2. ganha PL contra IA = metade do normal
    const { applyResult: ap } = require('../../online_v021/ranked/progression');
    const st0 = { league: 0, pl: 40, matches: 3, wins: 2, losses: 1, draws: 0, highest_league: 0, forca: 1000, forca_rd: 200 };
    const norm = ap(st0, aiStats(0), 'win'), half = ap(st0, aiStats(0), 'win', { vsAI: true });
    const lnorm = ap(st0, aiStats(0), 'loss'), lhalf = ap(st0, aiStats(0), 'loss', { vsAI: true });
    check(half.change === Math.round(norm.change / 2) && lhalf.change === -Math.round(-lnorm.change / 2), `metade do PL: vitória ${norm.change}→${half.change}, derrota ${lnorm.change}→${lhalf.change}`);
    check(half.stats.forca === 1000 && half.stats.matches === 3 && half.stats.wins === 2, 'contra IA: Força oculta e placar intactos');
    // 3. desistência precoce contra IA: 0 PL
    a.inbox.length = 0;
    a.send({ type: 'ranked_queue', mode: 'ranked_5min' }); await a.next('ranked_queued');
    const f2 = await a.next('ranked_found', 8000);
    await a.next(m => m.type === 'ranked_state' && m.match_id === f2.match_id && m.status === 'playing', 5000);
    a.send({ type: 'ranked_resign', match_id: f2.match_id });
    const res2 = await a.next('ranked_result', 8000);
    check(res2.early && res2.vs_ai && res2.pl_change === 0, 'desistência precoce contra IA: 0 PL');
    a.ws.close();
    // 4. dois humanos: pareiam entre si (IA não entra)
    const h1 = await login(s.port, 'HumanoUm'), h2 = await login(s.port, 'HumanoDois');
    h1.send({ type: 'ranked_queue', mode: 'ranked_10min' }); await h1.next('ranked_queued');
    h2.send({ type: 'ranked_queue', mode: 'ranked_10min' }); await h2.next('ranked_queued');
    const fh = await h1.next('ranked_found', 5000);
    check(!fh.vs_ai && !fh.opponent.ai && fh.opponent.nickname === 'HumanoDois', 'dois humanos na fila: pareados entre si, sem IA');
    h1.send({ type: 'ranked_resign', match_id: fh.match_id }); await sleep(300); h1.ws.close(); h2.ws.close();
    // 5. Casual sozinho: IA também; revanche recusada com aviso
    const c = await login(s.port, 'CasualSoR181');
    c.send({ type: 'casual_queue', mode: 'casual_3min' }); await c.next('casual_queued');
    const fc = await c.next('casual_found', 8000);
    check(fc.vs_ai && fc.opponent.ai, 'Casual sozinho: rival de IA também');
    const rc = await play(c, 'casual', fc, 6);
    c.send({ type: 'casual_resign', match_id: fc.match_id });
    const resc = await c.next('casual_result', 8000);
    check(rc.aiMoves >= 2 && resc.vs_ai === true, 'Casual contra IA: jogou e terminou (vs_ai)');
    c.send({ type: 'casual_rematch', match_id: fc.match_id });
    const rm = await c.next('casual_rematch_status', 4000);
    check(rm.closed && /IA/.test(rm.message || ''), 'revanche contra IA: recusada com aviso');
    c.ws.close();
  } finally { s.stop(); }
  // 6. desligado
  const s2 = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_QUEUE_AI: 'off', FRAIHA_QUEUE_AI_WAIT_MS: '500' });
  try {
    const a = await login(s2.port, 'SemIA');
    a.send({ type: 'ranked_queue', mode: 'ranked_5min' }); await a.next('ranked_queued');
    let got = null; try { got = await a.next('ranked_found', 2500); } catch {}
    check(!got, 'FRAIHA_QUEUE_AI=off: continua só com pessoas');
    a.ws.close();
  } finally { s2.stop(); }
  check(LEVELS[0].approx === 1000 && LEVELS[1].approx === 1200, 'níveis: Madeira ≈1000, Ferro ≈1200');
  summary('RIVAL_IA_FILA');
})().catch(e => { console.error(e); process.exit(1); });
