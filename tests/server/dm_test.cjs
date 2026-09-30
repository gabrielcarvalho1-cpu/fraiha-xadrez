'use strict';
// Mensagens privadas (Etapa 5): só entre amigos, tempo real, histórico persistente, não lidas, bloqueio e validação.
// Padrão: FRAIHA_DEV_AUTH (MemoryStore). Com tests/server/supabase_stack.cjs roda contra Postgres+PostgREST reais.
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
// Uma resposta por pedido, respeitando os limites do servidor (20 msg/s por socket; DM: 1 envio a cada 0,4 s).
async function ask(c, msg, pred, gap = 450) {
  await sleep(gap);
  c.send(msg);
  return c.next(x => pred(x) || x.type === 'dm_error' || x.type === 'social_error', 6000);
}
const social = (c, type, user_id) => ask(c, { type, user_id }, m => m.type === 'social_ok', 80);
const dmSend = (c, to, text, ref = '') => ask(c, { type: 'dm_send', user_id: to, text, client_ref: ref }, m => m.type === 'dm_msg' && m.user_id === to && m.message.sender_id === c.id && (!ref || m.client_ref === ref));
const dmOpen = (c, to, before_id) => ask(c, { type: 'dm_open', user_id: to, before_id }, m => m.type === 'dm_history' && m.user_id === to, 80);
const unreadIn = async c => { c.inbox.splice(0); const l = await ask(c, { type: 'social_list' }, m => m.type === 'social_list', 80); const o = {}; for (const f of l.friends) o[f.user_id] = f.unread; return o; };

(async () => {
  const s = await startServer({ FRAIHA_TEST_DM_BURST: '1000', ...ENV });
  const A = await login(s.port, 'AnaDM'), B = await login(s.port, 'BiaDM'), C = await login(s.port, 'CaduDM');
  // Amizade A <-> B (C não é amigo de ninguém)
  await social(A, 'social_request', B.id); await social(B, 'social_accept', A.id);
  // Convidado não usa DM
  const g = client(s.port); await g.open(); g.send({ type: 'guest_auth' }); await g.next('guest_state');
  g.send({ type: 'dm_send', user_id: B.id, text: 'oi' }); check((await g.next('dm_error')).code === 'auth_required', 'convidado não usa mensagens privadas');
  // Enviar e receber em tempo real
  B.inbox.splice(0);
  const echo = await dmSend(A, B.id, '  Olá, Bia!  Tudo bem? ', 'r1');
  check(echo.type === 'dm_msg' && echo.message.body === 'Olá, Bia! Tudo bem?' && echo.message.sender_id === A.id && echo.client_ref === 'r1', 'A envia DM (espaços aparados) e recebe a confirmação');
  const got = await B.next(m => m.type === 'dm_msg', 4000);
  check(got.message.body === 'Olá, Bia! Tudo bem?' && got.user_id === A.id && got.from.nickname === 'AnaDM' && !('email' in got.from), 'B recebe em tempo real com nickname (sem e-mail)');
  const un = await B.next(m => m.type === 'dm_unread', 4000);
  check(un.counts[A.id] === 1, 'B recebe contagem de não lidas em tempo real (1)');
  const emoji = await dmSend(B, A.id, 'Tudo ótimo! 😀♟️ ação, pão, coração');
  check(emoji.message.body === 'Tudo ótimo! 😀♟️ ação, pão, coração', 'acentos e emojis preservados');
  // Histórico persistente e ordenado
  const h = await dmOpen(A, B.id);
  check(h.messages.length === 2 && h.messages[0].body.startsWith('Olá') && h.messages[1].body.startsWith('Tudo ótimo') && h.peer.nickname === 'BiaDM' && h.can_send === true && !h.has_more, 'dm_open devolve o histórico em ordem, com o perfil do amigo');
  check(h.messages.every(m => m.id && m.created_at && 'read_at' in m && !('email' in m)), 'mensagens têm id, data e estado de leitura (nunca e-mail)');
  // Não lidas
  let ub = await unreadIn(B);
  check(ub[A.id] === 1, 'social_list mostra 1 não lida de A para B');
  const r = await ask(B, { type: 'dm_read', user_id: A.id }, m => m.type === 'dm_read_ok');
  check(r.marked === 1, 'dm_read marca a recebida como lida');
  ub = await unreadIn(B); check(ub[A.id] === 0, 'depois de ler, não lidas = 0');
  // Reconexão: histórico e contagem continuam corretos
  await dmSend(A, B.id, 'mensagem enquanto você estava fora');
  B.close(); await sleep(300);
  const B2 = await login(s.port, 'BiaDM');
  ub = await unreadIn(B2); check(ub[A.id] === 1, 'após reconectar: contagem de não lidas correta (1)');
  const h2 = await dmOpen(B2, A.id);
  check(h2.messages.length === 3 && h2.messages[2].body === 'mensagem enquanto você estava fora', 'após reconectar: histórico persistido volta completo');
  await ask(B2, { type: 'dm_read', user_id: A.id }, m => m.type === 'dm_read_ok');
  // Validação
  check((await dmSend(A, B.id, '    ')).code === 'empty', 'mensagem vazia é rejeitada');
  check((await dmSend(A, B.id, 'x'.repeat(501))).code === 'too_long', '501 caracteres é rejeitado');
  check((await dmSend(A, B.id, 'y'.repeat(500))).message.body.length === 500, '500 caracteres é aceito');
  check((await ask(A, { type: 'dm_send', user_id: B.id, text: { x: 1 } }, () => false)).code === 'invalid', 'payload não-texto é rejeitado');
  check((await dmSend(A, B.id, 'z'.repeat(5000))).code === 'too_long', 'payload enorme é rejeitado');
  check((await dmSend(A, A.id, 'eu')).code === 'self', 'não manda DM para si mesmo');
  check((await dmSend(A, 'nao-e-uuid', 'oi')).code === 'bad_user', 'id inválido é rejeitado');
  check((await dmSend(A, '00000000-0000-4000-a000-000000000000', 'oi')).code === 'not_found', 'perfil inexistente é rejeitado');
  // Não amigos
  check((await dmSend(C, A.id, 'oi estranho')).code === 'not_friends', 'não amigo não consegue mandar DM');
  const hc = await dmOpen(C, A.id);
  check(hc.can_send === false && hc.reason_code === 'not_friends' && hc.messages.length === 0, 'conversa com não amigo abre vazia e sem envio');
  // Rate limit de envio
  A.inbox.splice(0); A.send({ type: 'dm_send', user_id: B.id, text: 'rápida 1' }); A.send({ type: 'dm_send', user_id: B.id, text: 'rápida 2' });
  const rl = await A.next(m => m.type === 'dm_error', 4000);
  check(rl.code === 'rate_limited', 'duas mensagens seguidas: a segunda é limitada');
  await A.next(m => m.type === 'dm_msg' && m.message.body === 'rápida 1', 4000);
  // Histórico com limite de 50 + paginação
  await sleep(500);
  for (let i = 0; i < 52; i++) await dmSend(B2, A.id, 'lote ' + i);
  const page1 = await dmOpen(A, B.id);
  check(page1.messages.length === 50 && page1.has_more === true && page1.messages[49].body === 'lote 51', 'histórico inicial limitado às últimas 50 (has_more = true)');
  const page2 = await dmOpen(A, B.id, page1.messages[0].id);
  check(page2.messages.length > 0 && page2.messages[page2.messages.length - 1].id < page1.messages[0].id, 'carregar anteriores (before_id) traz mensagens mais antigas');
  // Bloqueio
  await social(B2, 'social_block', A.id);
  const blk = await dmSend(A, B.id, 'ainda aí?');
  check(blk.code === 'unavailable', 'bloqueado não consegue enviar DM (servidor recusa)');
  check((await dmSend(B2, A.id, 'tchau')).code === 'blocked', 'quem bloqueou também não envia (precisa desbloquear)');
  const hb = await dmOpen(B2, A.id);
  check(hb.messages.length > 0 && hb.can_send === false, 'histórico antigo continua visível para quem bloqueou, sem envio');
  // Amizade removida: histórico fica, envio não
  await social(B2, 'social_unblock', A.id);
  check((await dmSend(A, B.id, 'voltamos?')).code === 'not_friends', 'desbloqueado mas sem amizade: sem DM');
  A.close(); B2.close(); C.close(); g.close(); s.stop();

  // Migration 0003 pendente: erro claro, cliente não quebra (store sem a tabela).
  const { Backend } = require('../../online_v021/backend');
  const sent = [];
  const be = new Backend({ env: { FRAIHA_DEV_AUTH: '1' }, send: (ws, o) => sent.push(o) });
  clearInterval(be.sweeper);
  const missing = () => { const e = new Error('relation "public.direct_messages" does not exist'); e.code = '42P01'; throw e; };
  be.store.getConversation = missing; be.store.unreadCounts = missing;
  const uidA = '11111111-1111-4111-a111-111111111111', uidB = '22222222-2222-4222-a222-222222222222';
  await be.store.createProfile(uidA, 'SemTabelaA', 'warrior'); await be.store.createProfile(uidB, 'SemTabelaB', 'warrior');
  const fakeWs = { user: { id: uidA }, profile: { nickname: 'SemTabelaA', avatar_id: 'warrior' }, readyState: 1 };
  await be.handle(fakeWs, { type: 'dm_open', user_id: uidB });
  check(sent.at(-1).type === 'dm_error' && sent.at(-1).code === 'not_configured' && /0003/.test(sent.at(-1).message), 'tabela ausente: "migração 0003 pendente" (sem derrubar o servidor)');
  await be.handle(fakeWs, { type: 'social_list' });
  check(sent.at(-1).type === 'social_list', 'tabela ausente: lista de amigos continua funcionando');
  summary('DM');
})().catch(e => { console.error(e); process.exit(1); });
