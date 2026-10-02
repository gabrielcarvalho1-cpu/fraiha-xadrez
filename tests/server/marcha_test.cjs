'use strict';
// R32 · MARCHA REAL: sem Club = 1 partida por dia (servidor); Club = ilimitado.
const { startServer, client, check, summary } = require('./helpers.cjs');
(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  const c = client(s.port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:marcha' }); await c.next('acct_state');
  c.send({ type: 'acct_create_profile', nickname: 'Marchador' }); await c.next('acct_state');
  c.send({ type: 'marcha_status' });
  let m = await c.next('marcha_state');
  check(m.unlimited === false && m.used === 0 && m.limit === 1 && m.resets_at, 'sem Club: 0 de 1 partida hoje');
  c.send({ type: 'marcha_start' });
  m = await c.next(x => x.type === 'marcha_granted' || x.type === 'marcha_denied');
  check(m.type === 'marcha_granted' && m.used === 1, '1ª partida do dia liberada');
  c.send({ type: 'marcha_start' });
  m = await c.next(x => x.type === 'marcha_granted' || x.type === 'marcha_denied');
  check(m.type === 'marcha_denied' && m.code === 'daily_limit', '2ª partida no mesmo dia: bloqueada pelo servidor');
  c.send({ type: 'marcha_status' });
  m = await c.next('marcha_state');
  check(m.used === 1 && m.unlimited === false, 'status: 1 de 1 usada');
  c.send({ type: 'dev_set_entitlements', club_active: true, club_expires_at: new Date(Date.now() + 86400e3).toISOString() });
  await c.next('acct_state');
  for (let i = 0; i < 3; i++) {
    c.send({ type: 'marcha_start' });
    m = await c.next(x => x.type === 'marcha_granted' || x.type === 'marcha_denied');
    check(m.type === 'marcha_granted' && m.unlimited === true, `Club: partida ${i + 1} liberada (ilimitado)`);
  }
  const g = client(s.port); await g.open();
  g.send({ type: 'marcha_start' });
  m = await g.next(x => x.type === 'acct_error' || x.type === 'marcha_denied');
  check(m.code === 'auth_required', 'sem conta: o servidor não decide (o aparelho controla)');
  c.close(); g.close(); s.stop();
  summary('MARCHA');
})().catch(e => { console.error(e); process.exitCode = 1; });
