-- FRAIHA 0011 · FRAIHA Admin V1 — PROPOSTA (fora de supabase/migrations de propósito).
--
-- PROPOSTA, NÃO APLICADA, NÃO É MIGRATION ATIVA. Só vira migration com autorização explícita do dono
-- (o Supabase é o MESMO de staging e produção). Antes de aplicar: auditoria READ-ONLY do banco real.
--
-- O que resolve (hoje tudo isso vive só na memória do servidor e some num reinício):
--   1. admin_users        → papéis administrativos no banco (substitui a variável FRAIHA_ADMIN_USERS);
--   2. admin_audit_log    → Admin Log durável (append-only);
--   3. admin_mode_controls→ estado ATIVO/DESATIVADO dos modos sobrevive a reinício + agenda futura;
--   4. game_sessions      → sessões de jogo (jogadores únicos/dia, retorno, plataforma, versão do cliente);
--   5. metric_samples     → série do "Ao Vivo" para 7/30 dias.
-- Segurança: RLS LIGADA e NENHUMA policy → só a service role (servidor Node) lê/escreve.
-- O cliente do jogo e o FRAIHA Admin NUNCA acessam essas tabelas direto: sempre pela API do servidor.
-- Impacto: aditivo (tabelas novas). Não altera tabelas existentes.
-- Servidor sem esta migração: continua como hoje (memória + log do Render).
-- Reverter:
--   drop table if exists public.metric_samples, public.game_sessions, public.admin_mode_controls,
--     public.admin_audit_log, public.admin_users;

create table if not exists public.admin_users (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  role       text not null check (role in ('owner','operator','viewer')),
  created_at timestamptz not null default now(),
  created_by uuid,
  revoked_at timestamptz
);
alter table public.admin_users enable row level security;

create table if not exists public.admin_audit_log (
  id         uuid primary key default gen_random_uuid(),
  at         timestamptz not null default now(),
  actor_id   uuid not null,
  actor_role text not null,
  action     text not null check (length(action) <= 64),
  target     jsonb,
  before     jsonb,
  after      jsonb,
  result     text not null check (result in ('ok','noop','denied','error')),
  reason     text check (length(reason) <= 300),
  meta       jsonb
);
create index if not exists admin_audit_log_at_idx on public.admin_audit_log (at desc);
alter table public.admin_audit_log enable row level security;
-- append-only: sem update/delete nem para a service role (correções = novo registro)
create or replace function public.fraiha_admin_audit_immutable() returns trigger language plpgsql as $$
begin raise exception 'admin_audit_log é somente inserção'; end $$;
drop trigger if exists admin_audit_log_immutable on public.admin_audit_log;
create trigger admin_audit_log_immutable before update or delete on public.admin_audit_log
  for each row execute function public.fraiha_admin_audit_immutable();

create table if not exists public.admin_mode_controls (
  family     text primary key check (family in ('ranked','casual','xeque','marcha')),
  enabled    boolean not null default true,
  reason     text,
  changed_by uuid,
  changed_at timestamptz not null default now(),
  schedule   jsonb not null default '[]'::jsonb   -- futuro: [{from,to,enabled,label}] (eventos/manutenção)
);
alter table public.admin_mode_controls enable row level security;

create table if not exists public.game_sessions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid,                         -- null = convidado
  guest          boolean not null default false,
  platform       text check (platform in ('web','windows','android','ios','steam','unknown')),
  client_version text check (length(client_version) <= 32),
  started_at     timestamptz not null default now(),
  ended_at       timestamptz
);
create index if not exists game_sessions_started_idx on public.game_sessions (started_at desc);
create index if not exists game_sessions_user_idx on public.game_sessions (user_id, started_at desc);
alter table public.game_sessions enable row level security;

create table if not exists public.metric_samples (
  at        timestamptz not null,
  online    int not null, in_match int not null, in_queue int not null, lobby int not null,
  matches   int not null, by_family jsonb not null, voice int not null default 0,
  primary key (at)
);
alter table public.metric_samples enable row level security;
