'use strict';
// R100 · aceite dos Termos ao criar o perfil: a versão aceita fica gravada em profiles.settings.terms.
const { startServer, client, check, summary } = require('./helpers.cjs');
(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  try {
    const c = client(s.port); await c.open();
    c.send({ type: 'acct_auth', access_token: 'dev:TermoAna' });
    const st = await c.next('acct_state');
    check(!!st.needs_nickname, 'conta nova pede o nome');
    c.send({ type: 'acct_create_profile', nickname: 'TermoAna', terms: '14 de outubro de 2026' });
    const done = await c.next(m => m.type === 'acct_state' && !m.needs_nickname);
    check(!!done.profile, 'perfil criado com o aceite');
    c.send({ type: 'acct_refresh' });
    const again = await c.next('acct_state');
    check(again.profile && again.profile.nickname === 'TermoAna', 'perfil continua válido');
    const b = client(s.port); await b.open();
    b.send({ type: 'acct_auth', access_token: 'dev:SemTermo' }); await b.next('acct_state');
    b.send({ type: 'acct_create_profile', nickname: 'SemTermo' });
    check(!!(await b.next(m => m.type === 'acct_state' && !m.needs_nickname)).profile, 'cliente antigo (sem aceite) continua criando o perfil');
    c.close(); b.close();
  } finally { s.stop(); }
  summary('TERMS_ACCEPT');
})().catch(e => { console.error(e); process.exitCode = 1; });
