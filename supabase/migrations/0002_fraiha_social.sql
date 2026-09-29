-- FRAIHA Xadrez — Amigos: pedidos de amizade, amizades e bloqueios.
-- Aplicar no Supabase (SQL Editor) DEPOIS da 0001. Idempotente.
-- Escrita SOMENTE pelo servidor FRAIHA (service_role, secret key no Render).
-- Clientes (anon/authenticated) só podem LER as próprias linhas; nunca escrevem.

create table if not exists public.friend_requests (
  from_user  uuid not null references public.profiles(user_id) on delete cascade,
  to_user    uuid not null references public.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  constraint friend_requests_not_self check (from_user <> to_user)
);
create index if not exists friend_requests_to_idx on public.friend_requests (to_user);

-- Uma linha por par, sempre com user_a < user_b (sem duplicidade A-B / B-A).
create table if not exists public.friendships (
  user_a     uuid not null references public.profiles(user_id) on delete cascade,
  user_b     uuid not null references public.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  constraint friendships_ordered check (user_a < user_b)
);
create index if not exists friendships_b_idx on public.friendships (user_b);

create table if not exists public.blocks (
  blocker    uuid not null references public.profiles(user_id) on delete cascade,
  blocked    uuid not null references public.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  constraint blocks_not_self check (blocker <> blocked)
);
create index if not exists blocks_blocked_idx on public.blocks (blocked);

-- RLS: leitura só das próprias linhas; nenhuma policy de escrita para clientes.
alter table public.friend_requests enable row level security;
alter table public.friendships     enable row level security;
alter table public.blocks          enable row level security;
revoke all on public.friend_requests, public.friendships, public.blocks from anon, authenticated;
grant select on public.friend_requests, public.friendships, public.blocks to authenticated;
grant select, insert, update, delete on public.friend_requests, public.friendships, public.blocks to service_role;

drop policy if exists friend_requests_read_own on public.friend_requests;
create policy friend_requests_read_own on public.friend_requests for select to authenticated
  using (auth.uid() = from_user or auth.uid() = to_user);
drop policy if exists friendships_read_own on public.friendships;
create policy friendships_read_own on public.friendships for select to authenticated
  using (auth.uid() = user_a or auth.uid() = user_b);
drop policy if exists blocks_read_own on public.blocks;
create policy blocks_read_own on public.blocks for select to authenticated
  using (auth.uid() = blocker);
