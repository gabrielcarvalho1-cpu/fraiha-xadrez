'use strict';
// R97 · EXCLUIR CONTA: confirmação pelo nome, anonimiza, apaga amizades, bloqueia novo login.
const { startServer, client, check, summary } = require('./helpers.cjs');
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  const st = await c.next(m => m.type === 'acct_state' || m.type === 'acct_deleted');
  if (st.type === 'acct_deleted') { c.deleted = st; return c; }
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); c.state = await c.next('acct_state'); } else c.state = st;
  return c;
}
(async () => {
  const s = await startServer({ FRAIHA_DEV_AUTH: '1' });
  try {
    const a = await login(s.port, 'ApagaAna'), b = await login(s.port, 'FicaBia');
    // amizade A <-> B
    a.send({ type: 'social_search', query: 'FicaBia' });
    const found = await a.next('social_search').catch(() => null);
    const bid = found && found.results && found.results[0] && found.results[0].user_id;
    if (bid) {
      a.send({ type: 'social_request', user_id: bid }); await a.next(m => m.type.startsWith('social_')).catch(() => {});
    }
    a.send({ type: 'acct_delete', confirm: 'outro nome' });
    check((await a.next('acct_delete_error')).code === 'confirm_mismatch', 'nome errado na confirmação: não exclui');
    a.send({ type: 'acct_delete', confirm: 'apagaana' });
    const del = await a.next('acct_deleted');
    check(!!del, 'nome certo (sem diferenciar maiúsculas): conta excluída');
    const again = await login(s.port, 'ApagaAna');
    check(!!again.deleted, 'login de novo com a mesma conta é recusado (acct_deleted)');
    if (bid) {
      b.send({ type: 'social_search', query: 'ApagaAna' });
      const r = await b.next('social_search').catch(() => ({ results: [] }));
      check(!(r.results || []).some(x => x.nickname === 'ApagaAna'), 'o nome antigo some da busca');
    }
    b.send({ type: 'acct_delete', confirm: 'FicaBia' });
    await b.next('acct_deleted');
    check(/\[acct-delete\]/.test(s.log()), 'exclusão registrada no log do servidor');
    for (const w of [a, b, again]) w.close();
  } finally { s.stop(); }
  summary('ACCOUNT_DELETE');
})().catch(e => { console.error(e); process.exitCode = 1; });
