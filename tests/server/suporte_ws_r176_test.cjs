'use strict';
// R176.8c · SUPORTE pelo servidor de verdade (WebSocket): o roteador do server.js precisa mandar ticket_* ao backend
// (na R176.8 faltava e o jogo ficava sem resposta: "O servidor não respondeu").
const { startServer, client, check, summary } = require('./helpers.cjs');
(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  const c = client(s.port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:suporte' });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: 'Suporte1', avatar_id: 'warrior' }); await c.next('acct_state'); }
  c.send({ type: 'ticket_send', category: 'reclamacao', subject: 'Bugou', message: 'A partida travou no fim.' });
  const ok = await c.next('ticket_ok');
  check(ok && ok.ticket && ok.ticket.status === 'open', 'ticket enviado chega ao servidor e volta ticket_ok');
  const list = await c.next('ticket_list');
  check(list.available && list.items.length === 1, 'MEUS TICKETS com o ticket');
  const g = client(s.port); await g.open(); g.send({ type: 'guest_auth' }); await g.next('guest_state');
  g.send({ type: 'ticket_send', category: 'duvida', message: 'Como jogo?' });
  const e = await g.next('ticket_error');
  check(e.code === 'login_required', 'convidado recebe resposta (entrar na conta)');
  c.close(); g.close(); await s.stop();
  summary('SUPORTE_WS');
})();
