#!/bin/bash
# FRAIHA Admin · prova LOCAL da proposta 0011 num PostgreSQL descartável (NUNCA no Supabase).
# Simula os papéis do Supabase (anon, authenticated, service_role com BYPASSRLS), o schema auth.users e o
# privilégio padrão do Supabase (ALL em tabelas novas do public para anon/authenticated/service_role).
# Uso: tests/admin/test_0011_proposal.sh
set -u
cd "$(dirname "$0")/../.."
SQL=docs/admin/proposals/0011_fraiha_admin_v1.sql
BIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)
[ -x "$BIN/initdb" ] || { echo "SKIP: PostgreSQL local não encontrado"; exit 2; }
D=$(mktemp -d); PORT=$((55000 + RANDOM % 5000)); ME=$(id -un)
RUNAS=""; [ "$(id -u)" = "0" ] && { id pgtest >/dev/null 2>&1 || useradd -M pgtest; chown -R pgtest "$D"; RUNAS="runuser -u pgtest --"; }
$RUNAS "$BIN/initdb" -D "$D/data" -A trust -U owner >/dev/null || exit 1
$RUNAS "$BIN/pg_ctl" -D "$D/data" -o "-p $PORT -k $D -c listen_addresses=''" -l "$D/log" start -w >/dev/null || { cat "$D/log"; exit 1; }
trap '$RUNAS "$BIN/pg_ctl" -D "$D/data" stop -m fast >/dev/null; rm -rf "$D"' EXIT
Q() { $RUNAS psql -h "$D" -p $PORT -U owner -d postgres -v ON_ERROR_STOP=1 -qtA "$@"; }
fails=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fails=$((fails+1)); }
# expect_fail ROLE "SQL" "label" ["erro esperado"]
expect_fail() { out=$(Q -c "set role $1; $2" 2>&1); if [ $? -ne 0 ] && { [ -z "${4:-}" ] || echo "$out" | grep -q "$4"; }; then ok "$3"; else bad "$3 :: $out"; fi; }
expect_ok()   { out=$(Q -c "set role $1; $2" 2>&1); if [ $? -eq 0 ]; then ok "$3"; else bad "$3 :: $out"; fi; }

Q <<'SQL' >/dev/null
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create schema auth; create table auth.users (id uuid primary key);
grant usage on schema public, auth to anon, authenticated, service_role;
grant references on auth.users to owner;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
insert into auth.users values ('11111111-1111-4111-a111-111111111111');
SQL
Q -f "$SQL" >/dev/null 2>"$D/apply.err" && ok "proposta aplica sem erro" || { bad "proposta aplica: $(cat $D/apply.err)"; }
Q -f "$SQL" >/dev/null 2>"$D/apply2.err" && ok "proposta é idempotente (2ª aplicação)" || bad "reaplicar: $(cat $D/apply2.err)"

TABLES="admin_users admin_audit_log admin_mode_controls game_sessions metric_samples"
for r in anon authenticated; do
  for t in $TABLES; do
    expect_fail $r "select * from public.$t" "$r NÃO lê $t" "permission denied"
    expect_fail $r "truncate public.$t" "$r NÃO faz TRUNCATE em $t" "permission denied"
  done
  expect_fail $r "insert into public.admin_audit_log(actor_id,actor_role,action,result) values (gen_random_uuid(),'owner','x.y','ok')" "$r NÃO insere no Admin Log" "permission denied"
done
# privilégios exatos (catálogo): ninguém além do dono tem TRUNCATE; anon/authenticated sem nada
P=$(Q -c "select grantee||':'||table_name||':'||privilege_type from information_schema.role_table_grants where table_schema='public' and table_name in ('admin_users','admin_audit_log','admin_mode_controls','game_sessions','metric_samples') and grantee<>'owner' order by 1")
echo "$P" | grep -qE '^(anon|authenticated|PUBLIC):' && bad "anon/authenticated/PUBLIC ainda têm privilégio: $(echo "$P" | grep -E '^(anon|authenticated|PUBLIC):' | tr '\n' ' ')" || ok "anon/authenticated/PUBLIC sem nenhum privilégio (catálogo)"
echo "$P" | grep -q ':TRUNCATE$' && bad "alguém além do dono tem TRUNCATE: $(echo "$P" | grep TRUNCATE | tr '\n' ' ')" || ok "TRUNCATE: só o dono"
EXPECT="service_role:admin_audit_log:INSERT
service_role:admin_audit_log:SELECT
service_role:admin_mode_controls:INSERT
service_role:admin_mode_controls:SELECT
service_role:admin_mode_controls:UPDATE
service_role:admin_users:INSERT
service_role:admin_users:SELECT
service_role:admin_users:UPDATE
service_role:game_sessions:DELETE
service_role:game_sessions:INSERT
service_role:game_sessions:SELECT
service_role:game_sessions:UPDATE
service_role:metric_samples:DELETE
service_role:metric_samples:INSERT
service_role:metric_samples:SELECT"
[ "$P" = "$EXPECT" ] && ok "service_role: exatamente os privilégios da tabela de política" || bad "privilégios service_role divergem: $(echo "$P" | tr '\n' ' ')"
F=$(Q -c "select count(*) from information_schema.role_routine_grants where routine_name='fraiha_admin_append_only' and grantee in ('anon','authenticated','PUBLIC','service_role')")
[ "$F" = "0" ] && ok "função de proteção sem EXECUTE para anon/authenticated/service_role" || bad "EXECUTE na função de proteção: $F"

# service_role (servidor): append-only de verdade
expect_ok service_role "insert into public.admin_audit_log(actor_id,actor_role,action,result,reason) values (gen_random_uuid(),'owner','queue.disable','ok','teste')" "service_role insere no Admin Log"
expect_ok service_role "select count(*) from public.admin_audit_log" "service_role lê o Admin Log"
expect_fail service_role "update public.admin_audit_log set reason='x'" "service_role NÃO altera o Admin Log" "permission denied"
expect_fail service_role "delete from public.admin_audit_log" "service_role NÃO apaga o Admin Log" "permission denied"
expect_fail service_role "truncate public.admin_audit_log" "service_role NÃO faz TRUNCATE no Admin Log" "permission denied"
expect_fail service_role "truncate public.admin_users" "service_role NÃO faz TRUNCATE em admin_users" "permission denied"
expect_fail service_role "delete from public.admin_users" "service_role NÃO apaga admin (revoga com revoked_at)" "permission denied"
expect_fail service_role "insert into public.admin_audit_log(actor_id,actor_role,action,result) values (gen_random_uuid(),'owner','DROP TABLE','ok')" "Admin Log recusa ação fora do formato" "check constraint"
expect_ok service_role "insert into public.admin_users(user_id,role) values ('11111111-1111-4111-a111-111111111111','owner')" "service_role cadastra admin"
expect_fail service_role "insert into public.admin_users(user_id,role) values (gen_random_uuid(),'owner')" "admin precisa ser conta existente (FK auth.users)" "foreign key"
expect_fail service_role "update public.admin_users set revoked_at=now()" "revogar exige revoked_by" "check constraint"
expect_ok service_role "insert into public.game_sessions(platform) values ('web'); delete from public.game_sessions where started_at < now() - interval '180 days'" "service_role grava sessão e roda limpeza por retenção"
expect_fail service_role "insert into public.game_sessions(platform) values ('playstation')" "plataforma fora da lista recusada" "check constraint"
expect_ok service_role "insert into public.admin_mode_controls(family,enabled) values ('ranked',false) on conflict (family) do update set enabled=excluded.enabled" "service_role grava controle de modo"
expect_fail service_role "insert into public.admin_mode_controls(family) values ('poker')" "família desconhecida recusada" "check constraint"
expect_ok service_role "insert into public.metric_samples values (now(),1,0,0,1,0,'{}'::jsonb,0); delete from public.metric_samples where at < now() - interval '35 days'" "service_role grava/limpa amostras"

# até o DONO é barrado pelo append-only (só via desligar trigger conscientemente, fora do servidor)
expect_fail owner "update public.admin_audit_log set reason='x'" "dono: UPDATE no Admin Log recusado pelo trigger" "somente inserção"
expect_fail owner "delete from public.admin_audit_log" "dono: DELETE no Admin Log recusado pelo trigger" "somente inserção"
expect_fail owner "truncate public.admin_audit_log" "dono: TRUNCATE no Admin Log recusado pelo trigger" "somente inserção"
# RLS ligada e forçada
R=$(Q -c "select count(*) from pg_class where relname in ('admin_users','admin_audit_log','admin_mode_controls','game_sessions','metric_samples') and relrowsecurity and relforcerowsecurity")
[ "$R" = "5" ] && ok "RLS ligada e forçada nas 5 tabelas (sem policy = nega para quem não tem BYPASSRLS)" || bad "RLS: $R/5"
# rollback documentado funciona
RB=$(sed -n '/^-- begin;/,/^-- commit;/p' "$SQL" | sed 's/^-- //')
Q -c "$RB" >/dev/null 2>&1 && ok "rollback documentado executa" || bad "rollback falhou"
echo "RESULT $([ $fails -eq 0 ] && echo OK || echo FALHAS=$fails)"
exit $fails
