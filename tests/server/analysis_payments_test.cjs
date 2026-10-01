'use strict';
// 0005: cota de análise (3/dia no servidor, Club ilimitado), direitos no acct_state,
// histórico, e pagamentos preparados (sem provedor configurado → erro claro, nada ativa).
const { startServer, client, check, summary } = require('./helpers.cjs');
(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1', FRAIHA_ANALYSIS_FREE_PER_DAY: '3', FRAIHA_PAYMENT_PROVIDER: '' });
  const c = client(s.port); await c.open();
  c.send({ type: 'analysis_request' });
  let m = await c.next(x => x.type === 'analysis_denied' || x.type === 'acct_error');
  check(m.code === 'auth_required', 'análise sem login é negada');
  c.send({ type: 'acct_auth', access_token: 'dev:ana' }); await c.next('acct_state');
  c.send({ type: 'acct_create_profile', nickname: 'AnaAnalise' });
  let st = await c.next('acct_state');
  check(st.entitlements && st.entitlements.club_active === false && st.entitlements.is_founder === false, 'acct_state traz entitlements (vazios)');
  check(st.analysis && st.analysis.unlimited === false && st.analysis.used === 0 && st.analysis.limit === 3 && st.analysis.resets_at, 'acct_state traz cota 0/3 com renovação');
  for (let i = 1; i <= 3; i++) {
    c.send({ type: 'analysis_request' });
    m = await c.next('analysis_granted');
    check(m.used === i && m.limit === 3 && m.unlimited === false, `análise ${i}/3 concedida`);
  }
  c.send({ type: 'analysis_request' });
  m = await c.next('analysis_denied');
  check(m.code === 'quota' && m.used === 3 && m.resets_at, '4ª análise bloqueada pelo servidor (quota)');
  c.send({ type: 'analysis_status' });
  m = await c.next('analysis_state');
  check(m.used === 3 && m.unlimited === false, 'analysis_status reflete 3/3');
  // histórico
  c.send({ type: 'analysis_record', summary: { mode: 'bot', accuracy: 81.2, counts: { best: 2 }, moves: [] } });
  await new Promise(r => setTimeout(r, 100));
  // Club (dev): servidor passa a ilimitado
  c.send({ type: 'dev_set_entitlements', club_active: true, club_expires_at: new Date(Date.now() + 86400e3).toISOString() });
  st = await c.next('acct_state');
  check(st.entitlements.club_active === true && st.analysis.unlimited === true, 'Club ativo no servidor → ilimitado');
  c.send({ type: 'analysis_request' });
  m = await c.next('analysis_granted');
  check(m.unlimited === true, 'com Club a análise é concedida sem contador');
  // Club expirado → volta ao limite
  c.send({ type: 'dev_set_entitlements', club_active: true, club_expires_at: new Date(Date.now() - 1000).toISOString() });
  st = await c.next('acct_state');
  check(st.entitlements.club_active === false && st.analysis.unlimited === false, 'Club expirado não conta');
  // pagamentos: sem provedor, nada ativa e o erro é claro
  c.send({ type: 'payment_create', product_id: 'club_monthly', method: 'pix' });
  m = await c.next('payment_error');
  check(m.code === 'provider_not_configured', 'pagamento real sem provedor: provider_not_configured');
  c.send({ type: 'payment_create', product_id: 'xyz', method: 'pix' });
  m = await c.next('payment_error');
  check(m.code === 'bad_request', 'produto inválido recusado');
  c.send({ type: 'acct_refresh' });
  st = await c.next('acct_state');
  check(st.entitlements.club_active === false, 'tentativa de pagamento não ativou nada');
  // webhook HTTP sem provedor → 400 (nunca ativa)
  const http = require('http');
  const code = await new Promise(resolve => {
    const req = http.request({ host: '127.0.0.1', port: s.port, path: '/webhooks/payments', method: 'POST' }, res => resolve(res.statusCode));
    req.on('error', () => resolve(-1)); req.end('{}');
  });
  check(code === 400, 'webhook sem provedor responde 400');
  c.close(); s.stop();
  summary('ANALYSIS_PAYMENTS');
})().catch(e => { console.error(e); process.exitCode = 1; });
