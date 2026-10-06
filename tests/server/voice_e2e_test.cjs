'use strict';
// FRAIHA Voice v1 · ponta a ponta pelo server.js real (WebSocket): voice_* chega ao backend,
// participantes recebem token; a partida continua igual depois de pedidos/recusas de voz.
const { startServer, client, check, summary } = require('./helpers.cjs');
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  const st = await c.next('acct_state');
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); await c.next('acct_state'); }
  return c;
}
(async () => {
  // credenciais FICTÍCIAS (formato válido) só para o teste local
  const s = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_RANKED_START_DELAY_MS: '300', FRAIHA_MM_EXPAND_MS: '60000',
    FRAIHA_AGORA_APP_ID: '0123456789abcdef0123456789abcdef', FRAIHA_AGORA_APP_CERTIFICATE: 'fedcba9876543210fedcba9876543210' });
  try {
    const a = await login(s.port, 'vozA'), b = await login(s.port, 'vozB'), c = await login(s.port, 'vozC');
    a.send({ type: 'ranked_queue', mode: 'ranked_5min' }); await a.next('ranked_queued');
    b.send({ type: 'ranked_queue', mode: 'ranked_5min' }); await b.next('ranked_queued');
    const fa = await a.next('ranked_found', 4000); await b.next('ranked_found', 4000);
    a.send({ type: 'voice_join', kind: 'ranked', match_id: fa.match_id });
    const ga = await a.next(m => m.type === 'voice_granted' || m.type === 'voice_denied');
    check(ga.type === 'voice_granted' && ga.token.startsWith('007') && ga.channel === 'fx_ranked_' + fa.match_id, 'Ranked pelo WebSocket: token de voz concedido');
    c.send({ type: 'voice_join', match_id: fa.match_id });
    const gc = await c.next('voice_denied');
    check(gc.code === 'not_in_match', 'quem não está na partida é recusado');
    a.send({ type: 'voice_leave', match_id: fa.match_id, reason: 'user' });
    a.send({ type: 'ranked_resign', match_id: fa.match_id });
    const ra = await a.next('ranked_result', 5000);
    check(ra.outcome === 'loss' && ra.reason === 'resign', 'partida termina pelo fluxo normal (voz não interfere)');
    b.send({ type: 'voice_renew', match_id: fa.match_id });
    const rb = await b.next('voice_denied');
    check(rb.code === 'match_over' || rb.code === 'not_in_match', 'renovação depois do fim: recusada (' + rb.code + ')');
    const log = s.log();
    check(log.includes('[voice] token granted kind=ranked') && log.includes('[voice] leave'), 'log de voz registrado');
    check(!log.includes('fedcba9876543210fedcba9876543210') && !log.includes(ga.token.slice(3, 30)), 'log sem certificado nem token');
    for (const x of [a, b, c]) x.close();
  } finally { s.stop(); summary('voice_e2e'); }
})();
