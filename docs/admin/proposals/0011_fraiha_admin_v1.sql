-- FRAIHA 0011 · FRAIHA Admin V1 — PROPOSTA (fora de supabase/migrations de propósito).
--
-- PROPOSTA, NÃO APLICADA, NÃO É MIGRATION ATIVA. Só vira migration com autorização explícita do dono
-- (o Supabase é o MESMO de staging e produção). Antes de aplicar: auditoria READ-ONLY do banco real.
-- Revisão R2 (auditoria Orca do Admin V1): privilégios EXPLÍCITOS, TRUNCATE tratado, append-only real.
--
-- O que resolve (hoje tudo isso vive só na memória do servidor e some num reinício):
--   1. admin_users         → papéis administrativos no banco (substituirá FRAIHA_ADMIN_USERS);
--   2. admin_audit_log     → Admin Log durável, APPEND-ONLY;
--   3. admin_mode_controls → estado ATIVO/DESATIVADO dos modos sobrevive a reinício + agenda futura;
--   4. game_sessions       → sessões de jogo (únicos/dia, retorno, plataforma, versão do cliente);
--   5. metric_samples      → série do "Ao Vivo" para 7/30 dias.
--
-- MODELO DE PRIVILÉGIOS (menor privilégio):
--   • anon / authenticated / PUBLIC: NENHUM privilégio (nem SELECT, nem TRUNCATE, nem REFERENCES/TRIGGER).
--     RLS fica ligada SEM policy como segunda barreira (RLS não cobre TRUNCATE → por isso o REVOKE).
--   • service_role (só o servidor Node): apenas o necessário por tabela (tabela abaixo).
--   • TRUNCATE: ninguém além do dono recebe; nas tabelas append-only um trigger BEFORE TRUNCATE recusa até
--     para quem tiver o privilégio por engano.
--   • O dono das tabelas (postgres/supabase_admin) continua podendo tudo — é o caminho de manutenção
--     manual/auditada (ex.: arquivamento), nunca usado pelo servidor.
--
--   tabela               | service_role                    | append-only | retenção sugerida
--   admin_users          | SELECT, INSERT, UPDATE           | não (revoga com revoked_at, sem DELETE) | permanente
--   admin_audit_log      | SELECT, INSERT                   | SIM (trigger UPDATE/DELETE/TRUNCATE) | permanente (arquivar pelo dono)
--   admin_mode_controls  | SELECT, INSERT, UPDATE           | não         | 4 linhas fixas
--   game_sessions        | SELECT, INSERT, UPDATE, DELETE   | não         | 180 dias (job de limpeza, futuro)
--   metric_samples       | SELECT, INSERT, DELETE           | não         | 35 dias (job de limpeza, futuro)
--
-- Impacto: aditivo (tabelas/funções novas). Não altera tabelas existentes nem dados.
-- Servidor sem esta migração: continua como hoje (memória + log do Render). Código que use estas tabelas
-- deve tolerar a ausência delas (mesmo padrão de 0005/0010).
--
-- Rollback (ordem): ver o bloco no FIM do arquivo.

begin;

-- ---------------------------------------------------------------- funções de proteção (append-only)
create or replace function public.fraiha_admin_append_only() returns trigger
language plpgsql set search_path = pg_catalog, public as $$
begin
  raise exception 'tabela % é somente inserção (operação % recusada)', tg_table_name, tg_op
    using errcode = 'insufficient_privilege';
end $$;
revoke all on function public.fraiha_admin_append_only() from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------- 1. admin_users
create table if not exists public.admin_users (
  user_id    uuid primary key references auth.users(id) on delete restrict,
  role       text not null check (role in ('owner','operator','viewer')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete restrict,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete restrict,
  check (revoked_at is null or revoked_by is not null)
);
alter table public.admin_users enable row level security;
alter table public.admin_users force row level security;

-- ---------------------------------------------------------------- 2. admin_audit_log (append-only)
create table if not exists public.admin_audit_log (
  id         uuid primary key default gen_random_uuid(),
  at         timestamptz not null default now(),
  actor_id   uuid not null,                       -- sem FK: o registro sobrevive à conta (histórico)
  actor_role text not null check (actor_role in ('owner','operator','viewer')),
  action     text not null check (action ~ '^[a-z][a-z0-9_.]{1,63}$'),
  target     jsonb,
  before     jsonb,
  after      jsonb,
  result     text not null check (result in ('ok','noop','denied','error')),
  reason     text check (char_length(reason) <= 300),
  meta       jsonb,
  check (pg_column_size(target) + coalesce(pg_column_size(before),0) + coalesce(pg_column_size(after),0) + coalesce(pg_column_size(meta),0) <= 16384)
);
create index if not exists admin_audit_log_at_idx on public.admin_audit_log (at desc);
create index if not exists admin_audit_log_actor_idx on public.admin_audit_log (actor_id, at desc);
create index if not exists admin_audit_log_action_idx on public.admin_audit_log (action, at desc);
alter table public.admin_audit_log enable row level security;
alter table public.admin_audit_log force row level security;
drop trigger if exists admin_audit_log_no_update_delete on public.admin_audit_log;
create trigger admin_audit_log_no_update_delete before update or delete on public.admin_audit_log
  for each row execute function public.fraiha_admin_append_only();
drop trigger if exists admin_audit_log_no_truncate on public.admin_audit_log;
create trigger admin_audit_log_no_truncate before truncate on public.admin_audit_log
  for each statement execute function public.fraiha_admin_append_only();

-- ---------------------------------------------------------------- 3. admin_mode_controls
create table if not exists public.admin_mode_controls (
  family     text primary key check (family in ('ranked','casual','xeque','marcha')),
  enabled    boolean not null default true,
  reason     text check (char_length(reason) <= 300),
  changed_by uuid,
  changed_at timestamptz not null default now(),
  schedule   jsonb not null default '[]'::jsonb check (jsonb_typeof(schedule) = 'array' and pg_column_size(schedule) <= 8192)
);
alter table public.admin_mode_controls enable row level security;
alter table public.admin_mode_controls force row level security;
drop trigger if exists admin_mode_controls_no_truncate on public.admin_mode_controls;
create trigger admin_mode_controls_no_truncate before truncate on public.admin_mode_controls
  for each statement execute function public.fraiha_admin_append_only();

-- ---------------------------------------------------------------- 4. game_sessions
create table if not exists public.game_sessions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references auth.users(id) on delete set null,   -- null = convidado / conta apagada
  guest          boolean not null default false,
  platform       text not null default 'unknown' check (platform in ('web','windows','android','ios','steam','unknown')),
  client_version text check (char_length(client_version) <= 32),
  started_at     timestamptz not null default now(),
  ended_at       timestamptz,
  check (ended_at is null or ended_at >= started_at)
);
create index if not exists game_sessions_started_idx on public.game_sessions (started_at desc);
create index if not exists game_sessions_user_idx on public.game_sessions (user_id, started_at desc) where user_id is not null;
alter table public.game_sessions enable row level security;
alter table public.game_sessions force row level security;

-- ---------------------------------------------------------------- 5. metric_samples
create table if not exists public.metric_samples (
  at        timestamptz primary key,
  online    int not null check (online >= 0),
  in_match  int not null check (in_match >= 0),
  in_queue  int not null check (in_queue >= 0),
  lobby     int not null check (lobby >= 0),
  matches   int not null check (matches >= 0),
  by_family jsonb not null check (jsonb_typeof(by_family) = 'object'),
  voice     int not null default 0 check (voice >= 0)
);
alter table public.metric_samples enable row level security;
alter table public.metric_samples force row level security;

-- ---------------------------------------------------------------- PRIVILÉGIOS EXPLÍCITOS
-- Zera tudo (inclui o default do Supabase que dá ALL a anon/authenticated em tabelas novas do schema public).
revoke all on table public.admin_users, public.admin_audit_log, public.admin_mode_controls,
  public.game_sessions, public.metric_samples from public, anon, authenticated, service_role;

grant select, insert, update on table public.admin_users         to service_role;
grant select, insert         on table public.admin_audit_log     to service_role;
grant select, insert, update on table public.admin_mode_controls to service_role;
grant select, insert, update, delete on table public.game_sessions  to service_role;
grant select, insert, delete on table public.metric_samples      to service_role;
-- (nenhum TRUNCATE, REFERENCES ou TRIGGER para ninguém além do dono)

commit;

-- ---------------------------------------------------------------- ROLLBACK (manual, pelo dono)
-- begin;
--   drop table if exists public.metric_samples, public.game_sessions, public.admin_mode_controls,
--     public.admin_audit_log, public.admin_users;
--   drop function if exists public.fraiha_admin_append_only();
-- commit;
-- Atenção: o rollback APAGA o histórico do Admin Log — exportar antes (pg_dump da tabela).
