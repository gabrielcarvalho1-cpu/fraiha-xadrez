'use strict';
// R177 · CHAT EXCLUSIVO pelo servidor de verdade (WebSocket): o roteador do server.js manda dchat_* ao backend.
const { startServer, client, check, summary } = require('./helpers.cjs');
(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  const c = client(s.port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:dchat' });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: 'Dchat1', avatar_id: 'warrior' }); await c.next('acct_state'); }
  c.send({ type: 'dchat_send', text: 'oi' });
  const e = await c.next('dchat_error');
  check(e && e.code === 'not_open', 'dchat_* chega ao backend (sem chat aberto: not_open)');
  c.close(); await s.stop();
  summary('DCHAT_WS');
})();
