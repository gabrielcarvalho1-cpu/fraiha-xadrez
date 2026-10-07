'use strict';
const { startServer, client, check, summary } = require('./helpers.cjs');
const sq = s => ['abcdefgh'.indexOf(s[0]), 8 - Number(s[1])];
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); await c.next('acct_state'); }
  return c;
}
async function pair(port, mode, n1, n2) {
  const a = await login(port, n1), b = await login(port, n2);
  a.send({ type: 'ranked_queue', mode }); await a.next('ranked_queued');
  b.send({ type: 'ranked_queue', mode }); await b.next('ranked_queued');
  const fa = await a.next('ranked_found', 4000), fb = await b.next('ranked_found', 4000);
  const white = fa.you === 'w' ? a : b, black = fa.you === 'w' ? b : a;
  return { a, b, fa, fb, white, black, id: fa.match_id };
}
const state = (c, pred = () => true, ms) => c.next(m => m.type === 'ranked_state' && pred(m), ms);
const latest = async c => { await sleep(200); const all = c.inbox.filter(m => m.type === 'ranked_state'); c.inbox.splice(0, c.inbox.length, ...c.inbox.filter(m => m.type !== 'ranked_state')); return all[all.length - 1]; };
const mv = (c, id, f, t, promotion) => c.send({ type: 'ranked_move', match_id: id, from: sq(f), to: sq(t), promotion });

(async () => {
  const base = { FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '300', FRAIHA_RANKED_RECONNECT_MS: '1500', FRAIHA_MM_EXPAND_MS: '60000' };
  let s = await startServer(base);
  // 1. Quatro filas independentes
  for (const [i, mode] of ['ranked_3min', 'ranked_5min', 'ranked_10min', 'ranked_20min'].entries()) {
    const g = await pair(s.port, mode, 'fila' + i + 'a', 'fila' + i + 'b');
    check(g.fa.match_id === g.fb.match_id && g.fa.mode === mode && g.fa.you !== g.fb.you, `fila ${mode}: jogadores da mesma modalidade se encontram com cores opostas`);
    const st = await state(g.white, m => m.status === 'playing');
    const minutes = { ranked_3min: 3, ranked_5min: 5, ranked_10min: 10, ranked_20min: 20 }[mode];
    check(st.clock.b_ms === minutes * 60000 && st.clock.w_ms <= minutes * 60000 && st.clock.active === 'w', `${mode}: relógios ${minutes}:00 e Brancas começam`);
    g.a.send({ type: 'ranked_resign', match_id: g.id });
    const ra = await g.a.next('ranked_result'), rb = await g.b.next('ranked_result');
    check(ra.outcome === 'loss' && rb.outcome === 'win' && ra.reason === 'resign', `${mode}: desistência = derrota`);
    check(ra.pl_change === 0 && rb.pl_change === 15 && rb.pl_after === 15 && ra.league_after === 0 && !ra.demoted && ra.saved && rb.saved, `${mode}: +15 para o vencedor; Madeira com 0 PL não perde nem rebaixa`);
    g.a.send({ type: 'acct_refresh' }); const acc = await g.a.next('acct_state');
    const others = Object.entries(acc.ranked).filter(([k]) => k !== mode);
    check(acc.ranked[mode].losses === 1 && acc.ranked[mode].matches === 1 && others.every(([, v]) => v.matches === 0), `${mode}: estatística só na modalidade correta`);
    g.a.close(); g.b.close();
  }
  // 2. Modalidades diferentes não se encontram
  const x = await login(s.port, 'cruzA'), y = await login(s.port, 'cruzB');
  x.send({ type: 'ranked_queue', mode: 'ranked_3min' }); await x.next('ranked_queued');
  y.send({ type: 'ranked_queue', mode: 'ranked_5min' }); await y.next('ranked_queued');
  let crossed = false; try { await x.next('ranked_found', 1200); crossed = true; } catch {}
  check(!crossed, '3 min e 5 min NÃO se encontram');
  x.send({ type: 'ranked_queue', mode: 'ranked_10min' }); check((await x.next('ranked_error')).code === 'already_queued', 'não entra em duas filas ao mesmo tempo');
  x.send({ type: 'ranked_cancel' }); check((await x.next('ranked_cancelled')).was_queued === true, 'cancelar busca antes do match');
  x.close(); y.close();

  // 3. Relógio + jogadas + xeque-mate
  const g = await pair(s.port, 'ranked_5min', 'relA', 'relB');
  mv(g.white, g.id, 'e2', 'e4'); check((await g.white.next('ranked_error')).message.includes('instantes'), 'jogada antes do início é recusada');
  let st = await state(g.white, m => m.status === 'playing');
  await sleep(400);
  mv(g.black, g.id, 'e7', 'e5'); check((await g.black.next('ranked_error')).message.includes('turno'), 'jogada fora de turno recusada');
  mv(g.white, g.id, 'e2', 'e5'); check((await g.white.next('ranked_error')).code === 'move_rejected', 'movimento ilegal recusado');
  st = await latest(g.white); check(st.clock.active === 'w' && st.position.turn === 'w', 'movimento ilegal NÃO troca o relógio');
  const wBefore = st.clock.w_ms;
  mv(g.white, g.id, 'f2', 'f3'); st = await state(g.black, m => m.position.turn === 'b');
  check(st.clock.active === 'b' && st.clock.w_ms <= wBefore && st.clock.b_ms === 300000, 'jogada legal para Brancas e inicia Pretas');
  check(st.you === 'b' && st.white.nickname && st.black.nickname, 'estado informa cor do jogador (tabuleiro das Pretas invertido no cliente)');
  mv(g.black, g.id, 'e7', 'e5'); await state(g.white, m => m.position.turn === 'w');
  mv(g.white, g.id, 'g2', 'g4'); await state(g.black, m => m.position.turn === 'b');
  mv(g.black, g.id, 'd8', 'h4');
  const rw = await g.white.next('ranked_result'), rbk = await g.black.next('ranked_result');
  check(rbk.outcome === 'win' && rw.outcome === 'loss' && rw.reason === 'checkmate', 'xeque-mate encerra com vitória das Pretas');
  g.a.close(); g.b.close();

  // 4. Reconexão: relógio continua; estado completo reenviado
  const r = await pair(s.port, 'ranked_10min', 'recA', 'recB');
  await state(r.white, m => m.status === 'playing');
  mv(r.white, r.id, 'e2', 'e4'); await state(r.black, m => m.position.turn === 'b');
  const blackName = r.fa.you === 'b' ? 'recA' : 'recB';
  r.black.close(); await sleep(600);
  const back = await login(s.port, blackName);
  const resumed = await back.next('ranked_found'); const rs = await state(back);
  check(resumed.resumed && resumed.match_id === r.id, 'reconectar devolve à mesma partida');
  check(rs.position.turn === 'b' && rs.clock.active === 'b' && rs.clock.b_ms <= 600000 - 500, 'relógio correu durante a desconexão; estado completo recebido');
  mv(back, r.id, 'e7', 'e5'); st = await state(r.white, m => m.position.turn === 'w' && m.position.ply === 2); check(st.last_move && st.last_move.to[1] === 3, 'partida continua após reconexão');
  // 5. Abandono após tolerância
  back.close();
  const ab = await r.white.next('ranked_result', 4000);
  check(ab.outcome === 'win' && ab.reason === 'abandon', 'sem retorno dentro da tolerância = abandono/derrota');
  r.white.close(); s.stop();

  // 6. Timeout
  s = await startServer({ ...base, FRAIHA_TEST_BASE_MS: '1200' });
  const t = await pair(s.port, 'ranked_3min', 'tempoA', 'tempoB');
  const rt = await t.white.next('ranked_result', 5000), rtb = await t.black.next('ranked_result', 5000);
  check(rt.outcome === 'loss' && rtb.outcome === 'win' && rt.reason === 'timeout', 'relógio em 00:00 = derrota por tempo');
  t.a.close(); t.b.close();

  // 7. Online Casual continua
  const h = client(s.port), j = client(s.port); await h.open(); await j.open();
  h.send({ type: 'create' }); const wel = await h.next('welcome');
  j.send({ type: 'join', room: wel.room }); await j.next('welcome');
  const cs = await h.next(m => m.type === 'state' && m.started);
  h.send({ type: 'move', revision: cs.revision, from: sq('f1').map(v => v), to: sq('f1') });
  h.send({ type: 'move', revision: cs.revision, from: sq('e2'), to: sq('e4') });
  const cs2 = await h.next(m => m.type === 'state' && m.move_count === 1, 4000);
  check(cs2.turn === 'b', 'Online Casual: sala por código e jogada continuam funcionando');
  h.close(); j.close(); s.stop();
  summary('RANKED_FLOW');
})().catch(e => { console.error(e); process.exit(1); });
