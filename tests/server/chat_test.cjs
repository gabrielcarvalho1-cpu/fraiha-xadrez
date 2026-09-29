'use strict';
// Chat da partida (Casual e Ranked): entrega, histórico na reconexão, limites e segurança.
const { startServer, client, check, summary } = require('./helpers.cjs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function guest(port, token) {
  const c = client(port); await c.open();
  c.send({ type: 'guest_auth', token }); c.guest = await c.next('guest_state'); return c;
}
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); await c.next('acct_state'); }
  return c;
}
async function pair(a, b, kind, mode) {
  a.send({ type: kind + '_queue', mode }); await a.next(kind + '_queued');
  b.send({ type: kind + '_queue', mode }); await b.next(kind + '_queued');
  const fa = await a.next(kind + '_found', 4000); await b.next(kind + '_found', 4000);
  await a.next(m => m.type === kind + '_state' && m.status === 'playing', 4000);
  return fa.match_id;
}
const say = (c, id, text) => c.send({ type: 'chat_send', match_id: id, text });

(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '200', FRAIHA_RANKED_RECONNECT_MS: '3000', FRAIHA_MM_EXPAND_MS: '60000' });
  const a = await guest(s.port), b = await guest(s.port);
  const id = await pair(a, b, 'casual', 'casual_3min');
  say(a, id, 'Boa partida!');
  const mb = await b.next('chat_msg'), ma = await a.next('chat_msg');
  check(mb.text === 'Boa partida!' && mb.nickname === a.guest.nickname && mb.match_id === id && ma.id === mb.id, 'A envia, B recebe (com nickname), A vê a própria mensagem');
  say(b, id, 'Igualmente');
  const rep1 = await a.next("chat_msg");
  check(rep1.text === "Igualmente" && rep1.nickname === b.guest.nickname, 'B responde, A recebe');
  // Chat não mexe na partida
  a.inbox.splice(0); await sleep(900); say(a, id, 'teste relógio');
  await a.next('chat_msg'); await sleep(300);
  check(!a.inbox.some(m => m.type === 'casual_state'), 'chat não gera atualização de relógio/estado da partida');
  // Rate limit / spam
  await sleep(800); say(a, id, 'um'); say(a, id, 'dois');
  const e1 = await a.next('chat_error');
  check(e1.code === 'rate_limited', 'duas mensagens em sequência: a segunda é limitada');
  await sleep(800); say(a, id, 'um');
  check((await a.next('chat_error')).code === 'spam', 'mensagem repetida em 30 s é bloqueada como spam');
  // Tamanho, payload inválido e sanitização
  await sleep(800); say(a, id, 'x'.repeat(5000));
  check((await a.next('chat_error')).code === 'too_long', 'mensagem enorme é rejeitada');
  say(a, id, 'y'.repeat(201));
  check((await a.next('chat_error')).code === 'too_long', 'mais de 200 caracteres é rejeitado');
  a.send({ type: 'chat_send', match_id: id, text: { evil: true } });
  check((await a.next('chat_error')).code === 'invalid', 'payload não-texto é rejeitado');
  say(a, id, '   \u0000\u200b  ');
  check((await a.next('chat_error')).code === 'empty', 'mensagem só com invisíveis/controles é rejeitada');
  await sleep(800); say(a, id, 'oi\u202e\u0007  tudo   bem? [b]x[/b]');
  const clean = await b.next(m => m.type === 'chat_msg' && m.text.startsWith('oi'));
  check(clean.text === 'oi tudo bem? [b]x[/b]', 'controles/bidi removidos e espaços normalizados (texto exibido como texto puro)');
  // Burst: no máximo 5 em 10 s
  let limited = false;
  b.inbox.splice(0);
  for (let i = 0; i < 6; i++) { await sleep(750); say(b, id, 'rajada ' + i); }
  const got = [];
  for (let i = 0; i < 6; i++) { const m = await b.next(x => (x.type === 'chat_msg' && x.text.startsWith('rajada')) || x.type === 'chat_error'); if (m.type === 'chat_error') limited = m.code === 'rate_limited'; else got.push(m); }
  check(limited && got.length <= 5 && got.length >= 4, 'rajada: no máximo 5 mensagens a cada 10 s');
  // Denúncia (V1: log do servidor)
  a.send({ type: 'chat_report', match_id: id });
  const rep = await a.next('chat_report_ok');
  await sleep(200);
  check(!rep.duplicate && s.log().includes('chat_report') && s.log().includes('rajada'), 'DENUNCIAR registra a denúncia no log do servidor');
  a.send({ type: 'chat_report', match_id: id }); check((await a.next('chat_report_ok')).duplicate === true, 'denúncia repetida não duplica');
  // Reconexão: histórico da partida volta
  const tok = b.guest.token; b.close(); await sleep(400);
  const b2 = await guest(s.port, tok);
  await b2.next('casual_found');
  const hist = await b2.next('chat_history');
  check(hist.match_id === id && hist.messages.some(m => m.text === 'Boa partida!') && hist.messages.some(m => m.text === 'Igualmente'), 'reconexão devolve o chat da partida');
  // Terceiro sem partida não conversa
  const c = await guest(s.port);
  say(c, id, 'intruso'); check((await c.next('chat_error')).code === 'no_match', 'quem não está na partida não envia mensagem');
  const d = client(s.port); await d.open(); d.send({ type: 'chat_send', match_id: id, text: 'x' });
  check((await d.next('chat_error')).code === 'identity_required', 'conexão sem identidade não usa o chat');
  a.send({ type: 'casual_resign', match_id: id }); await a.next('casual_result');
  a.close(); b2.close(); c.close(); d.close();
  // Ranked também tem chat
  const r1 = await login(s.port, 'chatRankA'), r2 = await login(s.port, 'chatRankB');
  const rid = await pair(r1, r2, 'ranked', 'ranked_5min');
  say(r2, rid, 'gl hf');
  const rm = await r1.next('chat_msg');
  check(rm.text === 'gl hf' && rm.nickname === 'chatRankB', 'chat funciona no Ranked');
  r1.send({ type: 'ranked_resign', match_id: rid });
  const res = await r1.next('ranked_result');
  check(res.pl_change === 0 && res.reason === 'resign', 'resultado Ranked segue normal com chat');
  r1.close(); r2.close(); s.stop();
  summary('CHAT');
})().catch(e => { console.error(e); process.exit(1); });
