'use strict';
// OPCIONAL (Postgres 16 + PostgREST locais, nada de Supabase real): migração 0007 + SupabaseStore R31.
// Uso: node tests/server/premium_stack_test.cjs   (requer /tmp/pgtest.sh e /tmp/postgrest)
const crypto = require('crypto'), { spawn, execSync } = require('child_process'), fs = require('fs');
const { SupabaseStore } = require('../../online_v021/accounts/store');
const { check, summary } = require('./helpers.cjs');
const SECRET = crypto.randomBytes(32).toString('hex');
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const jwt = c => { const h = b64({ alg: 'HS256', typ: 'JWT' }), p = b64(c); return h + '.' + p + '.' + crypto.createHmac('sha256', SECRET).update(h + '.' + p).digest('base64url'); };
const PSQL = 'psql -h /tmp -p 55432 -U postgres -q -v ON_ERROR_STOP=1';
const sql = q => execSync(`${PSQL} -At -c "${q.replace(/"/g, '\\"')}"`).toString().trim();
(async () => {
  execSync('bash /tmp/pgtest.sh', { stdio: 'inherit' });
  const port = 31000 + Math.floor(Math.random() * 3000), cfg = '/tmp/postgrest_r31.conf';
  fs.writeFileSync(cfg, `db-uri = "postgres://postgres@/postgres?host=/tmp&port=55432"\ndb-schemas = "public"\ndb-anon-role = "anon"\njwt-secret = "${SECRET}"\nserver-port = ${port}\n`);
  const rest = spawn('/tmp/postgrest', [cfg], { stdio: 'ignore' });
  await new Promise(r => setTimeout(r, 1500));
  // SupabaseStore fala com /rest/v1: um pequeno proxy tira o prefixo.
  const http = require('http');
  const front = http.createServer((req, res) => {
    const headers = { ...req.headers }; delete headers.host; delete headers.apikey;
    const up = http.request({ host: '127.0.0.1', port, path: req.url.replace(/^\/rest\/v1/, ''), method: req.method, headers }, r2 => { res.writeHead(r2.statusCode, r2.headers); r2.pipe(res); });
    req.pipe(up);
  });
  await new Promise(r => front.listen(0, '127.0.0.1', r));
  const st = new SupabaseStore({ url: 'http://127.0.0.1:' + front.address().port, serviceKey: jwt({ role: 'service_role' }) });
  const A = crypto.randomUUID(), B = crypto.randomUUID();
  sql(`insert into auth.users(id) values ('${A}'),('${B}')`);
  await st.createProfile(A, 'AnaStack', 'peao_branco');
  await st.createProfile(B, 'BiaStack', 'warrior');
  check((await st.getProfile(A)).avatar_id === 'peao_branco', 'perfil criado com avatar gratuito novo (peão)');
  // 1) liberar Fundador (função 0007)
  let e = await st.grantEntitlement(A, 'founder', 'pix');
  const d1 = (new Date(e.club_expires_at) - Date.now()) / 86400e3;
  check(e.is_founder && e.club_active && d1 > 29.9 && d1 < 30.1, 'fraiha_grant_entitlement(founder): Fundador + 30 dias de Club');
  check(sql(`select club_source from public.entitlements where user_id='${A}'`) === 'founder_bonus', 'origem do Club = founder_bonus');
  e = await st.grantEntitlement(A, 'club_monthly', 'pix');
  const d2 = (new Date(e.club_expires_at) - Date.now()) / 86400e3;
  check(d2 > 59.9 && d2 < 60.1 && sql(`select club_source from public.entitlements where user_id='${A}'`) === 'pix', 'club_monthly soma +30 (60) e grava a origem');
  const since1 = sql(`select founder_since from public.entitlements where user_id='${A}'`);
  await st.grantEntitlement(A, 'founder', 'pix');
  check(sql(`select founder_since from public.entitlements where user_id='${A}'`) === since1, 'founder_since mantém a 1ª data');
  let bad = null; try { await st.grantEntitlement(A, 'xyz', 'pix'); } catch (x) { bad = x; }
  check(bad && /product_invalid/.test(bad.message), 'produto inválido recusado no banco');
  // RLS/privilégios: cliente comum não executa a função
  const anonRes = await fetch('http://127.0.0.1:' + port + '/rpc/fraiha_grant_entitlement', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + jwt({ role: 'authenticated', sub: B }) }, body: JSON.stringify({ p_user: B, p_product: 'founder', p_source: 'x' }) });
  check(anonRes.status === 401 || anonRes.status === 403 || anonRes.status === 404, 'jogador autenticado NÃO consegue se dar Fundador (%d)'.replace('%d', anonRes.status));
  // 2) pagamentos
  const pay = await st.createPayment({ user_id: B, product_id: 'club_monthly', method: 'pix', provider: 'test', provider_ref: 'ch_9', amount_cents: 1990 });
  check(pay && pay.status === 'pending', 'payments: cobrança pendente gravada');
  const m1 = await st.markPayment('test', 'ch_9', 'paid'), m2 = await st.markPayment('test', 'ch_9', 'paid');
  check(m1 && m1.user_id === B && m2 === null, 'payments: pending → paid só uma vez');
  check((await st.getPayment('test', 'ch_9')).status === 'paid', 'payments: status consultado');
  // 3) cosméticos + Destaque social
  const r = await st.setCosmetics(A, { avatar_id: 'fundador', badge: 'fundador', title: 'fundador', frame: 'fundador' });
  check(r.profile && r.profile.profile_badge === 'fundador' && !r.partial, 'setCosmetics grava ícone/título/moldura/avatar');
  let bc = null; try { await st.setCosmetics(A, { badge: 'hack' }); } catch (x) { bc = x; }
  check(bc && /23514|check/i.test(String(bc.code) + bc.message), 'CHECK do banco recusa ícone inexistente');
  const [pa] = await st.getProfilesByIds([A]);
  check(pa.badge === 'fundador' && pa.title === 'fundador' && pa.founder === true && pa.club === true && pa.avatar_id === 'fundador', 'getProfilesByIds expõe selo/título e direitos (embed entitlements)');
  const found = await st.searchProfiles('AnaSt');
  check(found.length === 1 && found[0].badge === 'fundador', 'busca de Amigos expõe o selo');
  // Club vencido → selo do Club some, escolha fica
  await st.setCosmetics(A, { badge: 'club_b' });
  sql(`update public.entitlements set club_expires_at = now() - interval '1 minute' where user_id='${A}'`);
  const [pa2] = await st.getProfilesByIds([A]);
  check(pa2.badge === '' && pa2.club === false && pa2.founder === true && sql(`select profile_badge from public.profiles where user_id='${A}'`) === 'club_b', 'Club vencido: selo escondido, escolha guardada');
  // R32 · 0008: Marcha Real (limite diário)
  const today = new Date().toISOString().slice(0, 10);
  const c1 = await st.marchaConsume(B, today, 1), c2 = await st.marchaConsume(B, today, 1);
  check(c1.ok && c1.used === 1 && !c2.ok && c2.used === 1, '0008: fraiha_marcha_consume libera 1 e bloqueia a 2ª no dia');
  check((await st.marchaUsage(B, today)) === 1, '0008: marcha_usage registra o dia');
  const mres = await fetch('http://127.0.0.1:' + port + '/rpc/fraiha_marcha_consume', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + jwt({ role: 'authenticated', sub: B }) }, body: JSON.stringify({ p_user: B, p_day: today, p_limit: 99 }) });
  check(mres.status === 401 || mres.status === 403 || mres.status === 404, '0008: jogador não consegue zerar o próprio limite (%d)'.replace('%d', mres.status));
  sql('drop function public.fraiha_marcha_consume(uuid, date, integer); drop table public.marcha_usage');
  sql("notify pgrst, 'reload schema'");
  await new Promise(res => setTimeout(res, 800));
  const nc = await st.marchaConsume(B, today, 1);
  check(nc.not_configured === true, 'sem a 0008: not_configured (o aparelho controla o limite)');
  // 4) servidor novo + banco SEM a 0007: Amigos continua funcionando (cai para as colunas antigas)
  sql('alter table public.profiles drop column profile_badge, drop column profile_title');
  sql("notify pgrst, 'reload schema'");
  await new Promise(res => setTimeout(res, 800));
  const st2 = new SupabaseStore({ url: 'http://127.0.0.1:' + front.address().port, serviceKey: jwt({ role: 'service_role' }) });
  const [pb] = await st2.getProfilesByIds([A]);
  check(pb && pb.nickname === 'AnaStack' && pb.badge === '', 'sem 0007: getProfilesByIds cai para colunas antigas (sem quebrar Amigos)');
  const r2 = await st2.setCosmetics(A, { avatar_id: 'warrior', badge: 'fundador' });
  check(r2.profile && r2.partial === true && r2.profile.avatar_id === 'warrior', 'sem 0007: avatar salvo, ícone fica para depois (partial)');
  const r3 = await st2.setCosmetics(A, { badge: 'fundador' });
  check(r3.code === 'not_configured', 'sem 0007: só ícone → not_configured');
  rest.kill(); front.close();
  execSync("su postgres -c '/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata stop -m fast' >/dev/null");
  summary('PREMIUM_STACK');
  process.exit(process.exitCode || 0);
})().catch(e => { console.error(e); process.exit(1); });
