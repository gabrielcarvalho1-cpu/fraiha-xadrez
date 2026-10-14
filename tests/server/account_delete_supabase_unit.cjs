'use strict';
// R100 · EXCLUIR CONTA no SupabaseStore (fetch falso): ordem das chamadas, e-mail/ban no Auth e a liberação do
// login (rpc fraiha_release_deleted_auth, migration 0011) DEPOIS do Auth; sem a 0011 a exclusão não quebra.
const { SupabaseStore } = require('../../online_v021/accounts/store');
let checks = 0, fails = 0;
const check = (ok, m) => { checks++; if (!ok) fails++; console.log((ok ? 'PASS ' : 'FAIL ') + m); };
const UID = 'cf7389e9-cb10-44b1-a6b0-e96da0982c22';
function fake(rpcMissing) {
  const calls = [];
  const f = async (url, opts = {}) => {
    calls.push({ url: String(url), method: opts.method || 'GET', body: opts.body ? JSON.parse(opts.body) : null });
    const ok = (b, s = 200) => ({ ok: s < 300, status: s, text: async () => (b === undefined ? '' : JSON.stringify(b)) });
    if (/rpc\/fraiha_release_deleted_auth/.test(url)) return rpcMissing ? ok({ code: 'PGRST202', message: 'Could not find the function' }, 404) : ok({ identities_removed: 1 });
    if (/storage|avatars/.test(url)) return ok([]);
    if (/\/profiles\?/.test(url) && (opts.method || 'GET') === 'GET') return ok([{ user_id: UID, avatar_url: null }]);
    return ok([]);
  };
  return { calls, f };
}
(async () => {
  const quiet = console.error; console.error = () => {};
  const a = fake(false);
  const r = await new SupabaseStore({ url: 'https://x.supabase.co', serviceKey: 'sb_secret_test', fetchImpl: a.f }).deleteAccount(UID);
  check(r.ok, 'exclusão conclui');
  const iAuth = a.calls.findIndex(c => /\/auth\/v1\/admin\/users\//.test(c.url) && c.method === 'PUT');
  const iRpc = a.calls.findIndex(c => /rpc\/fraiha_release_deleted_auth/.test(c.url));
  const iProf = a.calls.findIndex(c => /\/profiles\?/.test(c.url) && c.method === 'PATCH' && c.body && c.body.account_status === 'deleted');
  check(iProf >= 0 && iAuth > iProf, 'perfil marcado como excluído antes do Auth');
  check(iAuth >= 0 && /fraihaxadrez\.invalid$/.test(a.calls[iAuth].body.email) && a.calls[iAuth].body.ban_duration, 'Auth: e-mail trocado e login bloqueado');
  check(iRpc > iAuth && a.calls[iRpc].body.p_user === UID, 'login liberado (rpc 0011) depois do Auth');
  const b = fake(true);
  const r2 = await new SupabaseStore({ url: 'https://x.supabase.co', serviceKey: 'sb_secret_test', fetchImpl: b.f }).deleteAccount(UID);
  check(r2.ok, 'banco sem a migration 0011: a exclusão continua funcionando');
  console.error = quiet;
  console.log(`ACCOUNT_DELETE_SUPABASE CHECKS=${checks} FAILURES=${fails}`); process.exitCode = fails ? 1 : 0;
})();
