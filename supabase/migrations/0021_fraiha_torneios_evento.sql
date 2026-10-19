-- FRAIHA Xadrez — 0021: TORNEIOS DE EVENTO (R157). Torneio de XADREZ criado no Admin, com CÓDIGO de inscrição:
-- só entra quem tem o código. O Admin monta as CHAVES (eliminação simples) e marca os vencedores.
-- ADITIVA: só cria duas tabelas novas (sem mexer em nada que já existe). Sem ela o jogo funciona e a aba
-- XADREZ do Torneio mostra "ainda não ligado".
--
-- 1) public.event_tournaments: o torneio (nome, código, ritmo, data, vagas, situação, chaves em JSON).
-- 2) public.event_entries: quem se inscreveu (uma linha por conta por torneio).
-- Leitura e escrita SÓ pelo servidor (service_role); o cliente nunca acessa direto.
--
-- Reverter:
--   drop table if exists public.event_entries;
--   drop table if exists public.event_tournaments;

create table if not exists public.event_tournaments (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (code ~ '^[A-Z0-9]{4,20}$'),
  name        text not null check (char_length(name) between 3 and 60),
  game        text not null default 'chess' check (game in ('chess')),
  mode        text not null default 'casual_10min',
  starts_at   timestamptz,
  max_players integer not null default 16 check (max_players between 2 and 256),
  status      text not null default 'open' check (status in ('open', 'closed', 'running', 'finished', 'cancelled')),
  notes       text not null default '' check (char_length(notes) <= 500),
  bracket     jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.event_tournaments enable row level security;
revoke all on table public.event_tournaments from anon, authenticated;
grant select, insert, update on table public.event_tournaments to service_role;

create table if not exists public.event_entries (
  event_id  uuid not null references public.event_tournaments (id) on delete cascade,
  user_id   uuid not null,
  joined_at timestamptz not null default now(),
  primary key (event_id, user_id)
);
create index if not exists event_entries_user on public.event_entries (user_id);
alter table public.event_entries enable row level security;
revoke all on table public.event_entries from anon, authenticated;
grant select, insert, delete on table public.event_entries to service_role;
