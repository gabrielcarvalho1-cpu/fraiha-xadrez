'use strict';
// R98 · OFERTA DE EMPATE e REVANCHE online (Casual e Ranked).
const { startServer, client, check, summary } = require('./helpers.cjs');
const sq = s => ['abcdefgh'.indexOf(s[0]), 8 - Number(s[1])];
async function guest(port) { const c = client(port); await c.open(); c.send({ type: 'guest_auth' }); await c.next('guest_state'); return c; }
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state'); }
  return c;
}
async function pair(k, a, b, mode) {
  a.send({ type: k + '_queue', mode }); await a.next(k + '_queued');
  b.send({ type: k + '_queue', mode }); await b.next(k + '_queued');
  const fa = await a.next(k + '_found', 4000);
  const white = fa.you === 'w' ? a : b, black = fa.you === 'w' ? b : a;
  await white.next(m => m.type === k + '_state' && m.status === 'playing', 4000);
  return { white, black, id: fa.match_id };
}
const mv = (k, c, id, f, t) => c.send({ type: k + '_move', match_id: id, from: sq(f), to: sq(t) });
const st = (k, c, pred) => c.next(m => m.type === k + '_state' && pred(m), 3000);

(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '150', FRAIHA_MM_EXPAND_MS: '60000', FRAIHA_TEST_FIXED_COLORS: '1' });
  try {
    const K = 'casual';
    const a = await guest(s.port), b = await guest(s.port);
    let g = await pair(K, a, b, 'casual_3min');
    g.white.send({ type: 'casual_draw_offer', match_id: g.id });
    check((await g.white.next('casual_error')).code === 'draw_rejected', 'sem nenhum lance: não dá para oferecer empate');
    mv(K, g.white, g.id, 'e2', 'e4'); await st(K, g.black, m => m.position.ply === 1);
    mv(K, g.black, g.id, 'e7', 'e5'); await st(K, g.white, m => m.position.ply === 2);
    g.white.send({ type: 'casual_draw_offer', match_id: g.id });
    check((await st(K, g.black, m => m.draw_offer === 'w')).draw_offer === 'w', 'Brancas oferecem: Pretas veem a oferta');
    g.black.send({ type: 'casual_draw_decline', match_id: g.id });
    check(!!(await g.white.next('casual_draw_declined')), 'Pretas recusam: Brancas recebem o aviso');
    g.white.send({ type: 'casual_draw_offer', match_id: g.id });
    check(/mais um lance/.test((await g.white.next('casual_error')).message), 'não pode insistir sem jogar um lance');
    mv(K, g.white, g.id, 'g1', 'f3'); await st(K, g.black, m => m.position.ply === 3);
    g.white.send({ type: 'casual_draw_offer', match_id: g.id }); await st(K, g.black, m => m.draw_offer === 'w');
    mv(K, g.black, g.id, 'b8', 'c6');
    check((await st(K, g.white, m => m.position.ply === 4)).draw_offer === '', 'adversário jogou em vez de responder: oferta cai');
    g.black.send({ type: 'casual_draw_offer', match_id: g.id }); await st(K, g.white, m => m.draw_offer === 'b');
    g.white.send({ type: 'casual_draw_accept', match_id: g.id });
    const res = await g.white.next('casual_result', 4000);
    check(res.outcome === 'draw' && res.reason === 'agreement' && res.reason_text === 'Empate por acordo', 'aceitou: EMPATE POR ACORDO');
    await g.black.next('casual_result', 4000);
    // revanche
    const wasWhite = g.white, wasBlack = g.black, oldId = g.id;
    wasWhite.send({ type: 'casual_rematch', match_id: oldId });
    const ask = await wasBlack.next(m => m.type === 'casual_rematch_status' && m.theirs, 3000);
    check(ask.theirs && !ask.mine, 'pedido de revanche chega ao adversário');
    wasBlack.send({ type: 'casual_rematch_cancel', match_id: oldId });
    const dec = await wasWhite.next(m => m.type === 'casual_rematch_status' && m.declined, 3000);
    check(dec.declined && !dec.mine, 'adversário recusa: quem pediu é avisado');
    wasWhite.send({ type: 'casual_rematch', match_id: oldId }); await wasBlack.next(m => m.type === 'casual_rematch_status' && m.theirs, 3000);
    wasBlack.send({ type: 'casual_rematch', match_id: oldId });
    const f1 = await wasBlack.next(m => m.type === 'casual_found' && m.match_id !== oldId, 4000), f2 = await wasWhite.next(m => m.type === 'casual_found' && m.match_id !== oldId, 4000);
    check(f1.match_id === f2.match_id && f1.match_id !== oldId && f1.you === 'w' && f2.you === 'b', 'os dois aceitam: nova partida, cores trocadas');
    wasWhite.send({ type: 'casual_rematch', match_id: oldId });
    check((await wasWhite.next(m => m.type === 'casual_rematch_status' && m.closed, 3000)).closed, 'revanche já usada: fechada');
    for (const w of [a, b]) w.close();
    // Ranked
    const R = 'ranked';
    const ra = await login(s.port, 'EmpRa'), rb = await login(s.port, 'EmpRb');
    g = await pair(R, ra, rb, 'ranked_3min');
    mv(R, g.white, g.id, 'e2', 'e4'); await st(R, g.black, m => m.position.ply === 1);
    mv(R, g.black, g.id, 'e7', 'e5'); await st(R, g.white, m => m.position.ply === 2);
    g.white.send({ type: 'ranked_draw_offer', match_id: g.id });
    check(/10 lances/.test((await g.white.next('ranked_error')).message), 'Ranked: empate só depois de 10 lances de cada lado');
    g.black.send({ type: 'ranked_resign', match_id: g.id });
    await g.white.next('ranked_result', 5000); await g.black.next('ranked_result', 5000);
    g.white.send({ type: 'ranked_rematch', match_id: g.id }); await g.black.next(m => m.type === 'ranked_rematch_status' && m.theirs, 3000);
    g.black.send({ type: 'ranked_rematch', match_id: g.id });
    const rf = await g.black.next(m => m.type === 'ranked_found' && m.match_id !== g.id, 5000);
    check(rf.you === 'w' && rf.opponent.pl !== undefined, 'Ranked: revanche começa com cores trocadas e PL atualizado');
    check(/\[rematch\]/.test(s.log()), 'revanche registrada no log');
    for (const w of [ra, rb]) w.close();
  } finally { s.stop(); }
  summary('DRAW_REMATCH');
})().catch(e => { console.error(e); process.exitCode = 1; });
