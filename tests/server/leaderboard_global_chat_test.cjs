'use strict';
// R96 · RANKING (troféu) e CHAT GLOBAL: ordem por aproveitamento, mínimo de partidas, sua posição,
// placar sem a 0009, e o chat global (ler/escrever, limites, denúncia, histórico).
const { startServer, client, check, summary } = require('./helpers.cjs');
const { MemoryStore } = require('../../online_v021/accounts/store');
const { Leaderboard, MIN_MATCHES } = require('../../online_v021/social/leaderboard');
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
  c.send({ type: 'guest_auth' }); await c.next('guest_state'); return c;
}

(async () => {
  // ---------- unidade: ordem e regras do placar ----------
  const st = new MemoryStore();
  const mk = async (id, nick, r3, xq) => {
    await st.createProfile(id, nick, 'warrior');
    Object.assign(st.stats.get(id).ranked_3min, r3);
    if (xq) { st.modeStats = st.modeStats || new Map(); st.modeStats.set(id, { xeque: xq }); }
  };
  await mk('u1', 'Muitas', { wins: 30, losses: 20, draws: 0, pl: 50 }, { wins: 9, losses: 1, draws: 0 });   // 60%
  await mk('u2', 'Media', { wins: 8, losses: 2, draws: 0, pl: 10 }, { wins: 3, losses: 3, draws: 0 });     // 80%
  await mk('u3', 'Sorte', { wins: 2, losses: 0, draws: 0, pl: 5 }, null);                                 // 2 partidas: fora
  await mk('u4', 'Empate', { wins: 7, losses: 1, draws: 2, pl: 0 }, null);                                // (7+1)/10 = 80%
  const lb = new Leaderboard({ send: () => {}, backend: { store: st } });
  const b = await lb.build('ranked_3min', 'u3');
  check(b.available && b.rows.map(r => r.nickname).join(',') === 'Media,Empate,Muitas', 'ordem por aproveitamento (empate vale ½); empate de % desempata por vitórias: ' + b.rows.map(r => r.nickname + ' ' + r.rate).join(' | '));
  check(b.rows[0].pos === 1 && b.rows[0].rate === 80 && b.rows[2].rate === 60, 'posição e % arredondada');
  check(!b.rows.some(r => r.user_id === 'u3'), 'quem tem menos de ' + MIN_MATCHES + ' partidas não entra (2 vitórias em 2 não vira 100% no topo)');
  check(b.me && b.me.pos === 0 && b.me.missing === MIN_MATCHES - 2, 'fora do placar: "sua posição" mostra quantas partidas faltam');
  const bme = await lb.build('ranked_3min', 'u1');
  check(bme.me && bme.me.pos === 3 && bme.me.nickname === 'Muitas', 'dentro do placar: sua posição');
  const x = await lb.build('xeque', null);
  check(x.rows.map(r => r.nickname).join(',') === 'Muitas,Media' && x.me === null, 'XEQUE: placar próprio; convidado sem "sua posição"');
  const nc = new Leaderboard({ send: () => {}, backend: { store: { leaderboardRows: async () => ({ not_configured: true }) } } });
  check((await nc.build('marcha', 'u1')).available === false, 'sem a migração 0009: placar indisponível (não quebra)');
  st.stats.get('u3').ranked_3min.losses = 8;
  check((await lb.build('ranked_3min', null)).rows.length === 3, 'cache de 1 min: mudança não aparece na hora');
  lb.invalidate('ranked_3min');
  check((await lb.build('ranked_3min', null)).rows.length === 4, 'depois do cache: entra quem completou as partidas');

  // ---------- integração pelo WebSocket ----------
  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  try {
    const a = await login(s.port, 'GlobalAna'), c = await login(s.port, 'GlobalCaio'), g = await guest(s.port);
    a.send({ type: 'leaderboard_get', board: 'ranked_20min' });
    const lr = await a.next('leaderboard');
    check(lr.board === 'ranked_20min' && lr.available === true && Array.isArray(lr.rows) && lr.me && lr.me.missing === MIN_MATCHES, 'leaderboard_get (Convencional): placar e sua posição pelo servidor');
    a.send({ type: 'leaderboard_get', board: 'xadrez_inexistente' });
    check((await a.next('leaderboard')).error === 'invalid_board', 'placar desconhecido é recusado');
    g.send({ type: 'leaderboard_get', board: 'marcha' });
    const lg = await g.next('leaderboard');
    check(lg.available === true && lg.me === null, 'convidado vê o placar');

    for (const w of [a, c, g]) w.send({ type: 'gchat_join' });
    const ha = await a.next('gchat_history'), hg = await g.next('gchat_history'); await c.next('gchat_history');
    check(ha.can_send === true && hg.can_send === false && ha.online >= 1, 'entrar no chat global: conta escreve, convidado só lê');
    a.send({ type: 'gchat_send', text: 'Olá servidor!' });
    const mc = await c.next('gchat_msg'), mg = await g.next('gchat_msg'), ma = await a.next('gchat_msg');
    check(mc.text === 'Olá servidor!' && mc.nickname === 'GlobalAna' && mg.id === mc.id && ma.id === mc.id, 'mensagem chega para todos que estão no chat global');
    g.send({ type: 'gchat_send', text: 'oi' });
    check((await g.next('gchat_error')).code === 'auth_required', 'convidado não escreve');
    a.send({ type: 'gchat_send', text: 'de novo rápido' });
    check((await a.next('gchat_error')).code === 'rate_limited', 'intervalo mínimo entre mensagens');
    a.send({ type: 'gchat_send', text: 'x'.repeat(201) });
    check((await a.next('gchat_error')).code === 'too_long', 'mais de 200 caracteres é recusado');
    c.send({ type: 'gchat_report', id: mc.id });
    check((await c.next('gchat_reported')).id === mc.id, 'denunciar mensagem: confirmado');
    await sleep(200);
    check(/\[gchat-report\]/.test(s.log()) && /Olá servidor!/.test(s.log()), 'denúncia vai para o log do servidor (moderação)');
    c.send({ type: 'gchat_leave' });
    await sleep(2600);
    a.send({ type: 'gchat_send', text: 'segunda' });
    await g.next(m => m.type === 'gchat_msg' && m.text === 'segunda');
    await sleep(300);
    check(!c.inbox.some(m => m.type === 'gchat_msg' && m.text === 'segunda'), 'quem saiu do chat global não recebe mais');
    const d = await login(s.port, 'GlobalDani');
    d.send({ type: 'gchat_join' });
    const hd = await d.next('gchat_history');
    check(hd.messages.map(m => m.text).join('|') === 'Olá servidor!|segunda', 'quem entra depois recebe o histórico recente');
    g.close(); await sleep(200);
    await sleep(2600);
    a.send({ type: 'gchat_send', text: 'terceira' });
    check((await d.next(m => m.type === 'gchat_msg' && m.text === 'terceira')).text === 'terceira', 'conexão fechada sai da sala sem quebrar o envio');
    for (const w of [a, c, d]) w.close();
  } finally { s.stop(); }
  summary('leaderboard_global_chat');
})().catch(e => { console.error(e); process.exitCode = 1; });
