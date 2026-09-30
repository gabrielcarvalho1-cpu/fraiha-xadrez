'use strict';
// Amigos (Etapa 4): busca por nickname, perfil público, pedidos, amizade, remoção e bloqueio.
// Por padrão usa FRAIHA_DEV_AUTH (MemoryStore). SOCIAL_STACK_ENV='{"SUPABASE_URL":...}' roda contra Postgres+PostgREST reais.
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ENV = process.env.SOCIAL_STACK_ENV ? JSON.parse(process.env.SOCIAL_STACK_ENV) : { FRAIHA_DEV_AUTH: '1' };
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: (process.env.SOCIAL_TOKEN_PAD || '') + 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; c.nick = name; return c;
}
// Respeita o limite de ações do servidor (20 a cada 10 s): se limitado, espera e tenta de novo.
async function paced(c, msg, pred) {
  for (let i = 0; i < 15; i++) {
    await sleep(60); // o servidor fecha sockets com mais de 20 mensagens por segundo
    c.send(msg);
    const m = await c.next(x => pred(x) || x.type === 'social_error', 5000);
    if (m.type === 'social_error' && m.code === 'rate_limited') { await sleep(1000); continue; }
    return m;
  }
  throw new Error('rate limited forever');
}
const act = (c, type, extra = {}) => paced(c, { type, ...extra }, m => m.type === 'social_ok');
const list = async c => { c.inbox.splice(0); return paced(c, { type: 'social_list' }, m => m.type === 'social_list'); };
const ids = arr => arr.map(p => p.user_id);

(async () => {
  const s = await startServer({ FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_PRESENCE_GRACE_MS: '300', FRAIHA_PRESENCE_TICK_MS: '100', ...ENV });
  const A = await login(s.port, 'AnaSocial'), B = await login(s.port, 'BrunoSocial'), C = await login(s.port, 'CarlaSocial');
  // Convidado e sem identidade não usam Amigos
  const g = client(s.port); await g.open(); g.send({ type: 'guest_auth' }); await g.next('guest_state');
  g.send({ type: 'social_list' }); check((await g.next('social_error')).code === 'auth_required', 'convidado recebe "entre ou crie uma conta"');
  // Busca
  let r = await paced(A, { type: 'social_search', query: 'social' }, m => m.type === 'social_search');
  check(r.results.length === 2 && !ids(r.results).includes(A.id), 'busca por parte do nickname encontra os outros e não inclui a si mesmo');
  check(r.results.every(p => !('email' in p) && p.nickname && p.user_id), 'resultado da busca nunca expõe e-mail');
  r = await paced(A, { type: 'social_search', query: 'NinguemAquiXYZ' }, m => m.type === 'social_search');
  check(r.results.length === 0, 'nickname inexistente: lista vazia');
  check((await paced(A, { type: 'social_search', query: 'a' }, () => false)).code === 'bad_query', 'busca com 1 caractere é rejeitada');
  check((await paced(A, { type: 'social_search', query: "x%'*,()" }, () => false)).code === 'bad_query', 'busca com caracteres especiais é rejeitada');
  // Perfil
  const pb = (await paced(A, { type: 'social_profile', user_id: B.id }, m => m.type === 'social_profile')).profile;
  check(pb.nickname === 'BrunoSocial' && pb.presence === '' && pb.relation === 'none' && pb.ranked && 'ranked_5min' in pb.ranked && typeof pb.highest_league === 'number' && !('email' in pb), 'perfil público: nickname, ranked por modo, maior liga, sem e-mail (presença só para amigos)');
  check((await act(A, 'social_request', { user_id: A.id })).code === 'self', 'não adiciona a si mesmo');
  check((await act(A, 'social_request', { user_id: '00000000-0000-4000-a000-000000000000' })).code === 'not_found', 'jogador inexistente');
  check((await act(A, 'social_request', { user_id: 'drop table' })).code === 'bad_user', 'id inválido é rejeitado');
  // Pedido A -> B
  const okReq = await act(A, 'social_request', { user_id: B.id });
  check(okReq.type === 'social_ok' && okReq.relation === 'request_sent', 'A envia pedido para B');
  const ev = await B.next(m => m.type === 'social_event', 5000);
  check(ev.event === 'request_received' && ev.user.user_id === A.id, 'B é avisado em tempo real do pedido');
  check((await act(A, 'social_request', { user_id: B.id })).code === 'already_sent', 'pedido duplicado não é criado');
  const rev = await act(B, 'social_request', { user_id: A.id });
  check(rev.code === 'reverse_pending' && rev.user_id === A.id, 'B tentando adicionar A: oferece aceitar o pedido existente');
  let lb = await list(B), la = await list(A);
  check(ids(lb.received).includes(A.id) && ids(la.sent).includes(B.id) && !lb.friends.length, 'listas: recebidos (B) e enviados (A)');
  // Cancelar e recusar
  check((await act(A, 'social_cancel', { user_id: B.id })).relation === 'none', 'A cancela o pedido enviado');
  lb = await list(B); check(!lb.received.length, 'pedido cancelado some para B');
  await act(A, 'social_request', { user_id: B.id });
  check((await act(B, 'social_decline', { user_id: A.id })).relation === 'none', 'B recusa o pedido');
  check((await act(B, 'social_accept', { user_id: A.id })).code === 'no_request', 'não aceita pedido que não existe mais');
  // Aceitar
  await act(A, 'social_request', { user_id: B.id });
  A.inbox.splice(0);
  check((await act(B, 'social_accept', { user_id: A.id })).relation === 'friend', 'B aceita: agora são amigos');
  check((await A.next(m => m.type === 'social_event', 5000)).event === 'request_accepted', 'A é avisado que o pedido foi aceito');
  la = await list(A); lb = await list(B);
  const fb = la.friends.find(f => f.user_id === B.id);
  check(fb && fb.presence === 'online' && ids(lb.friends).includes(A.id) && !la.sent.length && !lb.received.length, 'amizade aparece para os dois, com status online, sem pedidos pendentes');
  check((await act(A, 'social_request', { user_id: B.id })).code === 'already_friends', 'já amigos: não cria pedido');
  check((await paced(A, { type: 'social_profile', user_id: B.id }, m => m.type === 'social_profile')).profile.relation === 'friend', 'perfil mostra relação "amigo"');
  // Offline
  B.close(); await sleep(900);
  la = await list(A); check(la.friends.find(f => f.user_id === B.id).presence === 'offline', 'amigo desconectado aparece offline');
  const B2 = await login(s.port, 'BrunoSocial');
  la = await list(A); check(la.friends.find(f => f.user_id === B.id).presence === 'online', 'amigo reconectado volta a online');
  // Remover
  check((await act(A, 'social_remove', { user_id: B.id })).relation === 'none', 'A remove B da amizade');
  lb = await list(B2); check(!lb.friends.length, 'remoção vale para os dois lados');
  check((await act(A, 'social_remove', { user_id: B.id })).code === 'not_friends', 'remover quem não é amigo é recusado');
  // Bloqueio
  await act(A, 'social_request', { user_id: C.id }); await act(C, 'social_accept', { user_id: A.id });
  check((await act(C, 'social_block', { user_id: A.id })).relation === 'blocked', 'C bloqueia A (desfaz amizade)');
  la = await list(A); const lc = await list(C);
  check(!ids(la.friends).includes(C.id) && ids(lc.blocked).includes(A.id), 'amizade desfeita e A na lista de bloqueados de C');
  check((await act(A, 'social_request', { user_id: C.id })).code === 'not_found', 'bloqueado não consegue enviar pedido (C some para A)');
  check((await paced(A, { type: 'social_search', query: 'CarlaSocial' }, m => m.type === 'social_search')).results.length === 0, 'quem bloqueou não aparece na busca de quem foi bloqueado');
  check((await act(C, 'social_request', { user_id: A.id })).code === 'blocked', 'quem bloqueou precisa desbloquear para adicionar');
  check((await act(C, 'social_unblock', { user_id: A.id })).relation === 'none', 'C desbloqueia A');
  check((await act(A, 'social_request', { user_id: C.id })).type === 'social_ok', 'depois do desbloqueio, pedido volta a ser possível');
  // Bloquear com pedido pendente limpa o pedido
  await act(C, 'social_block', { user_id: A.id });
  la = await list(A); check(!la.sent.length, 'bloqueio apaga pedidos pendentes');
  // Limite de ações
  let limited = false;
  for (let i = 0; i < 25 && !limited; i++) { await sleep(80); B2.send({ type: 'social_list' }); const m = await B2.next(x => x.type === 'social_list' || x.type === 'social_error', 5000); if (m.type === 'social_error' && m.code === 'rate_limited') limited = true; }
  check(limited, 'rajada de ações é limitada');
  A.close(); B2.close(); C.close(); g.close(); s.stop();
  summary('SOCIAL');
})().catch(e => { console.error(e); process.exit(1); });
