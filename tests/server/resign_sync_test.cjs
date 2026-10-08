'use strict';
// R53 · Fim de partida online chega ao OUTRO jogador mesmo que a conexão dele tenha caído na hora
// (celular: troca de rede, tela bloqueada, app em segundo plano, link morto detectado depois).
// Bug real: o PC desistiu; o celular ficou preso na partida "em andamento" para sempre. Ao reconectar,
// o servidor já tinha esquecido a partida do jogador (byUser apagado na gravação do resultado) e o
// pedido de sincronia respondia "idle" — o cliente nunca recebia o fim.
// Uso: NODE_PATH=… node tests/server/resign_sync_test.cjs
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); await c.next('acct_state'); }
  return c;
}
async function guest(port) {
  const c = client(port); await c.open();
  c.send({ type: 'guest_auth' }); const g = await c.next('guest_state');
  c.token = g.token; return c;
}
async function pair(kind, a, b) {
  const mode = kind + '_3min';
  a.send({ type: kind + '_queue', mode }); await a.next(kind + '_queued');
  b.send({ type: kind + '_queue', mode }); await b.next(kind + '_queued');
  const fa = await a.next(kind + '_found', 4000); await b.next(kind + '_found', 4000);
  await a.next(m => m.type === kind + '_state' && m.status === 'playing', 4000);
  return fa.match_id;
}
const finishedState = (c, kind, id, ms = 3000) => c.next(m => m.type === kind + '_state' && m.match_id === id && m.status === 'finished', ms);
const result = (c, kind, id, ms = 3000) => c.next(m => m.type === kind + '_result' && m.match_id === id, ms);
const got = async p => { try { return await p; } catch { return null; } };

(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_RANKED_RECONNECT_MS: '20000', FRAIHA_MM_EXPAND_MS: '60000' });
  // A · conectado: o adversário desiste → o outro recebe fim + resultado (já funcionava)
  {
    const pc = await login(s.port, 'pcA'), cel = await login(s.port, 'celA');
    const id = await pair('ranked', cel, pc);
    pc.send({ type: 'ranked_resign', match_id: id });
    const st = await got(finishedState(cel, 'ranked', id)), r = await got(result(cel, 'ranked', id));
    check(!!st && !!r && r.outcome === 'win' && r.reason === 'resign', 'A · PC desiste → celular conectado recebe fim e VITÓRIA por desistência');
    pc.close(); cel.close();
  }
  // B · o celular caiu; o PC desiste enquanto ele está fora; o celular volta (conexão nova) e pede sincronia
  for (const kind of ['ranked', 'casual']) {
    const pc = kind === 'ranked' ? await login(s.port, 'pcB') : await guest(s.port);
    let cel = kind === 'ranked' ? await login(s.port, 'celB') : await guest(s.port);
    const id = await pair(kind, cel, pc);
    const celToken = cel.token;
    cel.close(); await sleep(150);
    pc.send({ type: kind + '_resign', match_id: id });
    const rp = await got(result(pc, kind, id));
    check(!!rp && rp.outcome === 'loss', `B · ${kind}: quem desistiu recebe DERROTA`);
    await sleep(300);   // gravação do resultado terminou com o celular fora
    cel = kind === 'ranked' ? await login(s.port, 'celB') : client(s.port);
    if (kind === 'casual') { await cel.open(); cel.send({ type: 'guest_auth', token: celToken }); await cel.next('guest_state'); }
    cel.send({ type: kind + '_sync', match_id: id });
    const st = await got(finishedState(cel, kind, id)), r = await got(result(cel, kind, id));
    check(!!st, `B · ${kind}: celular reconectado recebe o estado FINAL da partida`);
    check(!!r && r.outcome === 'win' && r.reason === 'resign', `B · ${kind}: celular reconectado recebe VITÓRIA por desistência`);
    pc.close(); cel.close();
  }
  // C · o inverso: o celular desiste com o PC fora; o PC volta e sincroniza
  {
    let pc = await login(s.port, 'pcC'); const cel = await login(s.port, 'celC');
    const id = await pair('ranked', cel, pc);
    pc.close(); await sleep(150);
    cel.send({ type: 'ranked_resign', match_id: id });
    await got(result(cel, 'ranked', id)); await sleep(300);
    pc = await login(s.port, 'pcC');
    pc.send({ type: 'ranked_sync', match_id: id });
    const r = await got(result(pc, 'ranked', id));
    check(!!r && r.outcome === 'win', 'C · celular desiste → PC reconectado recebe VITÓRIA');
    pc.close(); cel.close();
  }
  // D · sincronia de partida desconhecida (servidor reiniciou / expirou): resposta com o match_id pedido
  {
    const c = await login(s.port, 'pcD');
    c.send({ type: 'ranked_sync', match_id: '00000000-0000-4000-8000-0000000000aa' });
    const idle = await got(c.next('ranked_idle'));
    check(!!idle && idle.match_id === '00000000-0000-4000-8000-0000000000aa', 'D · partida desconhecida: ranked_idle traz o match_id (o cliente sai do estado preso)');
    c.close();
  }
  // E · ninguém de fora lê o resultado de uma partida alheia
  {
    const p1 = await login(s.port, 'pE1'), p2 = await login(s.port, 'pE2'), spy = await login(s.port, 'spyE');
    const id = await pair('ranked', p1, p2);
    p1.send({ type: 'ranked_resign', match_id: id }); await got(result(p2, 'ranked', id)); await sleep(300);
    spy.send({ type: 'ranked_sync', match_id: id });
    const leak = await got(spy.next(m => (m.type === 'ranked_result' || m.type === 'ranked_state') && m.match_id === id, 1200));
    check(!leak, 'E · terceiro não recebe estado/resultado da partida dos outros');
    p1.close(); p2.close(); spy.close();
  }
  s.stop();
  summary('RESIGN_SYNC');
})().catch(e => { console.error(e); process.exit(1); });
