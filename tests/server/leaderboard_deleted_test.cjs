'use strict';
// R102 · contas excluídas saem do RANKING e da busca de jogadores (memória + consulta do Supabase).
const { MemoryStore, SupabaseStore } = require('../../online_v021/accounts/store');
const { Leaderboard } = require('../../online_v021/social/leaderboard');
let checks = 0, fails = 0;
const check = (ok, m) => { checks++; if (!ok) fails++; console.log((ok ? 'PASS ' : 'FAIL ') + m); };
(async () => {
  const st = new MemoryStore();
  for (const [id, nick, w] of [['u1', 'Fica', 30], ['u2', 'Sai', 40]]) {
    await st.createProfile(id, nick, 'warrior');
    Object.assign(st.stats.get(id).ranked_3min, { wins: w, losses: 5, draws: 0, matches: w + 5 });
  }
  const lb = new Leaderboard({ send: () => {}, backend: { store: st } });
  let r = await lb.build('ranked_3min', null);
  check(r.rows.length === 2, 'antes: 2 no ranking');
  await st.deleteAccount('u2'); lb.invalidate();
  r = await lb.build('ranked_3min', null);
  check(r.rows.length === 1 && r.rows[0].nickname === 'Fica', 'excluída sai do ranking');
  check(!(await st.searchProfiles('excluido')).length, 'excluída não aparece na busca');
  // Supabase: o filtro vai no banco (embed profiles!inner com account_status != deleted) e o embed não vaza
  const urls = [];
  const sb = new SupabaseStore({ url: 'https://x.supabase.co', serviceKey: 'sb_secret_t', fetchImpl: async u => {
    urls.push(String(u)); return { ok: true, status: 200, text: async () => JSON.stringify([{ user_id: 'a', wins: 1, losses: 0, draws: 0, profiles: { account_status: 'active' } }]) }; } });
  const rows = await sb.leaderboardRows('ranked_3min', 'ranked', 5);
  check(/profiles!inner\(account_status\)/.test(urls[0]) && /profiles\.account_status=neq\.deleted/.test(urls[0]), 'Supabase: filtra excluídas na consulta');
  check(rows.length === 1 && rows[0].profiles === undefined, 'Supabase: resposta sem o campo do perfil');
  console.log(`LEADERBOARD_DELETED CHECKS=${checks} FAILURES=${fails}`); process.exitCode = fails ? 1 : 0;
})();
