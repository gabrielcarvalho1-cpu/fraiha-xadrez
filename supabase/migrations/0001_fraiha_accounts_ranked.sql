-- FRAIHA Xadrez: contas, perfil, Ranked e partidas.
-- Execute no Supabase: SQL Editor > New query > colar > Run (uma vez).
-- Clientes (anon/authenticated) só LEEM. Toda escrita competitiva é feita pelo
-- servidor Node com a service_role / secret key (que ignora RLS).

create table if not exists public.profiles (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  nickname       text not null,
  avatar_id      text not null default 'warrior',
  profile_frame  text not null default 'madeira',
  settings       jsonb not null default '{}'::jsonb,
  account_status text not null default 'active' check (account_status in ('active','suspended','deleted')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  last_login_at  timestamptz,
  constraint nickname_format check (
    char_length(nickname) between 3 and 16
    and nickname ~ '^[A-Za-z0-9_.À-ÖØ-öø-ÿ-]+$'
  )
);
create unique index if not exists profiles_nickname_unique on public.profiles (lower(nickname));

create table if not exists public.ranked_stats (
  user_id        uuid not null references public.profiles(user_id) on delete cascade,
  mode           text not null check (mode in ('ranked_3min','ranked_5min','ranked_10min','ranked_20min')),
  league         smallint not null default 0 check (league between 0 and 10),
  pl             smallint not null default 0 check (pl between 0 and 100),
  matches        integer not null default 0 check (matches >= 0),
  wins           integer not null default 0 check (wins >= 0),
  losses         integer not null default 0 check (losses >= 0),
  draws          integer not null default 0 check (draws >= 0),
  highest_league smallint not null default 0 check (highest_league between 0 and 10),
  updated_at     timestamptz not null default now(),
  primary key (user_id, mode),
  check (matches = wins + losses + draws),
  check (highest_league >= league)
);

create table if not exists public.matches (
  match_id            uuid primary key default gen_random_uuid(),
  mode                text not null check (mode in ('ranked_3min','ranked_5min','ranked_10min','ranked_20min')),
  white_user_id       uuid not null references public.profiles(user_id),
  black_user_id       uuid not null references public.profiles(user_id),
  started_at          timestamptz not null,
  finished_at         timestamptz not null,
  result              text not null check (result in ('white','black','draw')),
  result_reason       text not null,
  white_pl_before     smallint not null, black_pl_before     smallint not null,
  white_pl_change     smallint not null, black_pl_change     smallint not null,
  white_pl_after      smallint not null, black_pl_after      smallint not null,
  white_league_before smallint not null, black_league_before smallint not null,
  white_league_after  smallint not null, black_league_after  smallint not null,
  moves               text not null default '',  -- lances em notação de coordenadas: "e2e4 e7e5 ..."
  created_at          timestamptz not null default now(),
  check (white_user_id <> black_user_id)
);
create index if not exists matches_white_idx on public.matches (white_user_id, finished_at desc);
create index if not exists matches_black_idx on public.matches (black_user_id, finished_at desc);

-- Cada perfil nasce com as quatro classificações independentes (Madeira 0 PL).
create or replace function public.fraiha_init_ranked_stats() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.ranked_stats (user_id, mode)
  select new.user_id, m from unnest(array['ranked_3min','ranked_5min','ranked_10min','ranked_20min']) as m
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists profiles_init_ranked on public.profiles;
create trigger profiles_init_ranked after insert on public.profiles
  for each row execute function public.fraiha_init_ranked_stats();

-- Gravação atômica de uma partida Ranked concluída. Os valores são calculados
-- pelo servidor Node; aqui só se confere que o "antes" ainda é o estado atual.
create or replace function public.fraiha_record_ranked_match(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  w record; b record; mid uuid;
  wr text := case p->>'result' when 'white' then 'win' when 'black' then 'loss' else 'draw' end;
  br text := case p->>'result' when 'black' then 'win' when 'white' then 'loss' else 'draw' end;
begin
  select * into w from public.ranked_stats where user_id = (p->>'white_user_id')::uuid and mode = p->>'mode' for update;
  select * into b from public.ranked_stats where user_id = (p->>'black_user_id')::uuid and mode = p->>'mode' for update;
  if w is null or b is null then raise exception 'ranked_stats ausente'; end if;
  if w.pl <> (p->>'white_pl_before')::int or w.league <> (p->>'white_league_before')::int
     or b.pl <> (p->>'black_pl_before')::int or b.league <> (p->>'black_league_before')::int then
    raise exception 'estado Ranked mudou durante a partida';
  end if;
  update public.ranked_stats set
    league = (p->>'white_league_after')::int, pl = (p->>'white_pl_after')::int,
    matches = matches + 1, wins = wins + (wr = 'win')::int, losses = losses + (wr = 'loss')::int, draws = draws + (wr = 'draw')::int,
    highest_league = greatest(highest_league, (p->>'white_league_after')::int), updated_at = now()
  where user_id = w.user_id and mode = w.mode;
  update public.ranked_stats set
    league = (p->>'black_league_after')::int, pl = (p->>'black_pl_after')::int,
    matches = matches + 1, wins = wins + (br = 'win')::int, losses = losses + (br = 'loss')::int, draws = draws + (br = 'draw')::int,
    highest_league = greatest(highest_league, (p->>'black_league_after')::int), updated_at = now()
  where user_id = b.user_id and mode = b.mode;
  insert into public.matches (match_id, mode, white_user_id, black_user_id, started_at, finished_at, result, result_reason,
    white_pl_before, black_pl_before, white_pl_change, black_pl_change, white_pl_after, black_pl_after,
    white_league_before, black_league_before, white_league_after, black_league_after, moves)
  values (coalesce((p->>'match_id')::uuid, gen_random_uuid()), p->>'mode', w.user_id, b.user_id,
    (p->>'started_at')::timestamptz, (p->>'finished_at')::timestamptz, p->>'result', p->>'result_reason',
    (p->>'white_pl_before')::int, (p->>'black_pl_before')::int, (p->>'white_pl_change')::int, (p->>'black_pl_change')::int,
    (p->>'white_pl_after')::int, (p->>'black_pl_after')::int,
    (p->>'white_league_before')::int, (p->>'black_league_before')::int, (p->>'white_league_after')::int, (p->>'black_league_after')::int,
    coalesce(p->>'moves',''))
  returning match_id into mid;
  return mid;
end $$;

-- Somente leitura para clientes; nenhuma policy de escrita = cliente não grava.
revoke insert, update, delete, truncate on public.profiles, public.ranked_stats, public.matches from anon, authenticated;
alter table public.profiles     enable row level security;
alter table public.ranked_stats enable row level security;
alter table public.matches      enable row level security;
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (true);
drop policy if exists ranked_read on public.ranked_stats;
create policy ranked_read on public.ranked_stats for select to authenticated using (true);
drop policy if exists matches_read_own on public.matches;
create policy matches_read_own on public.matches for select to authenticated
  using (auth.uid() = white_user_id or auth.uid() = black_user_id);

revoke all on function public.fraiha_record_ranked_match(jsonb) from public, anon, authenticated;
revoke all on function public.fraiha_init_ranked_stats() from public, anon, authenticated;
grant execute on function public.fraiha_record_ranked_match(jsonb) to service_role;
