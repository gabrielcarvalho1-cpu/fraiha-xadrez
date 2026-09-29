'use strict';
// Online Casual: filas por modalidade, convidado, regras completas do motor Ranked, reconexão, sem PL.
const { startServer, client, check, summary } = require('./helpers.cjs');
const sq = s => ['abcdefgh'.indexOf(s[0]), 8 - Number(s[1])];
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function guest(port, token) {
  const c = client(port); await c.open();
  c.send({ type: 'guest_auth', token }); const g = await c.next('guest_state');
  c.guest = g; return c;
}
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state'); }
  c.acct = st; return c;
}
async function pair(a, b, mode) {
  a.send({ type: 'casual_queue', mode }); await a.next('casual_queued');
  b.send({ type: 'casual_queue', mode }); await b.next('casual_queued');
  const fa = await a.next('casual_found', 4000), fb = await b.next('casual_found', 4000);
  const white = fa.you === 'w' ? a : b, black = fa.you === 'w' ? b : a;
  await white.next(m => m.type === 'casual_state' && m.status === 'playing', 4000);
  return { fa, fb, white, black, id: fa.match_id };
}
const mv = (c, id, f, t, promotion) => c.send({ type: 'casual_move', match_id: id, from: sq(f), to: sq(t), promotion });
const ply = (c, n) => c.next(m => m.type === 'casual_state' && m.position.ply === n, 3000);
async function play(g, moves) {
  let st;
  for (let i = 0; i < moves.length; i++) {
    const [f, t, p] = moves[i]; const who = i % 2 === 0 ? g.white : g.black;
    mv(who, g.id, f, t, p); st = await ply(g.white, i + 1); await ply(g.black, i + 1);
  }
  return st;
}
const at = (st, s) => { const [x, y] = sq(s); const e = st.position.board.find(b => b[0] === x && b[1] === y); return e ? e[2] : ''; };

(async () => {
  const base = { FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_RANKED_RECONNECT_MS: '1500', FRAIHA_MM_EXPAND_MS: '60000' };
  const s = await startServer(base);
  // 1. Convidados na fila Casual 3 min
  const a = await guest(s.port), b = await guest(s.port);
  check(/^Convidado \d{4}$/.test(a.guest.nickname) && a.guest.token.length === 48, 'convidado recebe nome e token de reconexão');
  let g = await pair(a, b, 'casual_3min');
  check(g.fa.match_id === g.fb.match_id && g.fa.you !== g.fb.you && g.fa.mode === 'casual_3min', 'Casual 3 min: dois jogadores se encontram com cores opostas');
  check(g.fa.opponent.league === undefined && g.fa.opponent.pl === undefined, 'Casual não expõe liga/PL');
  let st;
  // 2. Roque
  st = await play(g, [['e2','e4'],['e7','e5'],['g1','f3'],['b8','c6'],['f1','c4'],['g8','f6'],['e1','g1']]);
  check(at(st, 'g1') === 'wK' && at(st, 'f1') === 'wR' && at(st, 'e1') === '' && at(st, 'h1') === '', 'roque pequeno funciona no Casual');
  check(st.clock.active === 'b' && st.clock.w_ms < 180000 && st.clock.b_ms <= 180000, 'relógio de 3 min corre e alterna');
  // 3. Reconexão com o token do convidado
  const blackTok = g.black === a ? a.guest.token : b.guest.token;
  g.black.close(); await sleep(400);
  const back = await guest(s.port, blackTok);
  const res = await back.next('casual_found');
  const rs = await back.next('casual_state');
  check(res.resumed && res.match_id === g.id && rs.position.ply === 7, 'convidado reconecta na mesma partida e posição');
  g.black = back;
  // 4. Desistência → resultado sem PL
  g.black.send({ type: 'casual_resign', match_id: g.id });
  const rb = await g.black.next('casual_result'), rw = await g.white.next('casual_result');
  check(rb.outcome === 'loss' && rw.outcome === 'win' && rb.reason === 'resign' && rb.rated === false && rb.pl_change === 0 && rb.pl_after === undefined, 'desistência encerra sem PL');
  g.white.close(); g.black.close();

  // 5. En passant e promoção (motor oficial)
  const c = await guest(s.port), d = await guest(s.port);
  g = await pair(c, d, 'casual_5min');
  st = await play(g, [['e2','e4'],['a7','a6'],['e4','e5'],['d7','d5'],['e5','d6']]);
  check(at(st, 'd6') === 'wP' && at(st, 'd5') === '', 'en passant funciona no Casual');
  g.white.send({ type: 'casual_resign', match_id: g.id }); await g.white.next('casual_result'); await g.black.next('casual_result');
  g.white.close(); g.black.close();
  const e = await guest(s.port), f = await guest(s.port);
  g = await pair(e, f, 'casual_10min');
  st = await play(g, [['a2','a4'],['b7','b5'],['a4','b5'],['a7','a6'],['b5','a6'],['h7','h6'],['a6','a7'],['h6','h5'],['a7','b8','N']]);
  check(at(st, 'b8') === 'wN', 'promoção (escolha de peça) funciona no Casual');
  g.white.send({ type: 'casual_resign', match_id: g.id }); await g.white.next('casual_result'); await g.black.next('casual_result');
  g.white.close(); g.black.close();

  // 6. Xeque-mate
  const h = await guest(s.port), i = await guest(s.port);
  g = await pair(h, i, 'casual_20min');
  mv(g.white, g.id, 'f2', 'f3'); await ply(g.black, 1); mv(g.black, g.id, 'e7', 'e5'); await ply(g.white, 2);
  mv(g.white, g.id, 'g2', 'g4'); await ply(g.black, 3); mv(g.black, g.id, 'd8', 'h4');
  const mate = await g.white.next('casual_result');
  check(mate.outcome === 'loss' && mate.reason === 'checkmate', 'xeque-mate encerra a partida Casual');
  h.close(); i.close();

  // 7. Modalidades diferentes não se encontram; Casual não encontra Ranked
  const x = await guest(s.port), y = await guest(s.port);
  x.send({ type: 'casual_queue', mode: 'casual_3min' }); await x.next('casual_queued');
  y.send({ type: 'casual_queue', mode: 'casual_5min' }); await y.next('casual_queued');
  let crossed = false; try { await x.next('casual_found', 1000); crossed = true; } catch {}
  check(!crossed, 'Casual 3 min NÃO encontra Casual 5 min');
  const r1 = await login(s.port, 'mistoA'), r2 = await login(s.port, 'mistoB');
  r1.send({ type: 'ranked_queue', mode: 'ranked_3min' }); await r1.next('ranked_queued');
  r2.send({ type: 'casual_queue', mode: 'casual_3min' });
  const r2f = await r2.next('casual_found', 3000);
  check(r2f.opponent.nickname === x.guest.nickname, 'fila Casual casa só com Casual (conta encontra convidado da mesma modalidade)');
  let rankedCross = false; try { await r1.next('ranked_found', 800); rankedCross = true; } catch {}
  check(!rankedCross, 'Casual NÃO encontra Ranked');
  r1.send({ type: 'casual_queue', mode: 'casual_5min' });
  check((await r1.next('casual_error')).code === 'busy', 'não entra no Casual enquanto está na fila Ranked');
  r2.send({ type: 'ranked_queue', mode: 'ranked_5min' });
  check((await r2.next('ranked_error')).code === 'busy', 'não entra no Ranked enquanto está numa partida Casual');
  // 8. Conta logada no Casual: PL não muda
  const r2m = r2f.match_id;
  r2.send({ type: 'casual_resign', match_id: r2m }); await r2.next('casual_result');
  r2.send({ type: 'acct_refresh' }); const acc = await r2.next('acct_state');
  check(Object.values(acc.ranked).every(v => v.pl === 0 && v.matches === 0), 'Casual não altera PL/estatísticas Ranked');
  // 9. Convidado não joga Ranked
  x.send({ type: 'ranked_queue', mode: 'ranked_3min' });
  check((await x.next('acct_error')).code === 'auth_required', 'convidado não entra no Ranked');
  const z = client(s.port); await z.open(); z.send({ type: 'casual_queue', mode: 'casual_3min' });
  check((await z.next('casual_error')).code === 'identity_required', 'Casual exige identidade (convidado ou conta)');
  for (const k of [x, y, r1, r2, z]) k.close();

  // 10. Abandono do convidado após a tolerância
  const p = await guest(s.port), q = await guest(s.port);
  g = await pair(p, q, 'casual_3min');
  g.black.close();
  const ab = await g.white.next('casual_result', 4000);
  check(ab.outcome === 'win' && ab.reason === 'abandon', 'sem retorno = abandono');
  g.white.close(); s.stop();

  // 11. Tempo esgotado
  const s2 = await startServer({ ...base, FRAIHA_TEST_BASE_MS: '1200' });
  const t1 = await guest(s2.port), t2 = await guest(s2.port);
  g = await pair(t1, t2, 'casual_3min');
  const to = await g.white.next('casual_result', 5000);
  check(to.outcome === 'loss' && to.reason === 'timeout', 'relógio zerado = derrota por tempo');
  t1.close(); t2.close(); s2.stop();
  summary('CASUAL_FLOW');
})().catch(e => { console.error(e); process.exit(1); });
