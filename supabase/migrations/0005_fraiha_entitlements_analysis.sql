-- FRAIHA Xadrez — 0005: direitos (Fundador / Club) + cota diária de análise + histórico de análise.
-- ADITIVA e segura. NÃO aplicar automaticamente (staging e produção compartilham o projeto).

-- 1) Direitos reais. Escrita SÓ pelo servidor (webhook de pagamento / backend). O cliente lê
-- via acct_state (o servidor Node lê com service_role). Nunca pelo estado local dev_mock_*.
create table if not exists public.entitlements (
  user_id          uuid primary key references public.profiles(user_id) on delete cascade,
  is_founder       boolean not null default false,
  founder_since    timestamptz,
  club_active      boolean not null default false,
  club_expires_at  timestamptz,
  club_source      text,                    -- 'pix' | 'card' | 'founder_bonus' | 'manual'
  updated_at       timestamptz not null default now()
);
alter table public.entitlements enable row level security;
revoke insert, update, delete, truncate on public.entitlements from anon, authenticated;
drop policy if exists entitlements_read_own on public.entitlements;
create policy entitlements_read_own on public.entitlements for select to authenticated using (auth.uid() = user_id);

-- 2) Pagamentos (preparação para a V2 real; nada grava aqui nesta fase).
create table if not exists public.payments (
  payment_id       uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles(user_id) on delete cascade,
  product_id       text not null check (product_id in ('founder','club_monthly','club_yearly')),
  method           text not null check (method in ('pix','card')),
  provider         text not null,                     -- ex.: 'mercadopago', 'stripe', 'pagarme'
  provider_ref     text,                              -- id da cobrança no provedor
  amount_cents     integer not null check (amount_cents >= 0),
  status           text not null default 'pending' check (status in ('pending','paid','failed','refunded','cancelled')),
  created_at       timestamptz not null default now(),
  paid_at          timestamptz,
  raw              jsonb
);
create index if not exists payments_user_idx on public.payments (user_id, created_at desc);
create unique index if not exists payments_provider_ref_unique on public.payments (provider, provider_ref) where provider_ref is not null;
alter table public.payments enable row level security;
revoke insert, update, delete, truncate on public.payments from anon, authenticated;
drop policy if exists payments_read_own on public.payments;
create policy payments_read_own on public.payments for select to authenticated using (auth.uid() = user_id);

-- 3) Cota de análise: contador por dia UTC. O servidor chama fraiha_analysis_consume;
-- retorna o total usado (>= 0) quando concedido, ou negativo (-usado) quando esgotado.
create table if not exists public.analysis_usage (
  user_id  uuid not null references public.profiles(user_id) on delete cascade,
  day      date not null,
  used     integer not null default 0 check (used >= 0),
  primary key (user_id, day)
);
alter table public.analysis_usage enable row level security;
revoke insert, update, delete, truncate on public.analysis_usage from anon, authenticated;
drop policy if exists analysis_usage_read_own on public.analysis_usage;
create policy analysis_usage_read_own on public.analysis_usage for select to authenticated using (auth.uid() = user_id);

create or replace function public.fraiha_analysis_consume(p_user uuid, p_day date, p_limit integer)
returns integer language plpgsql security definer set search_path = public as $$
declare cur integer;
begin
  insert into public.analysis_usage (user_id, day, used) values (p_user, p_day, 0) on conflict do nothing;
  select used into cur from public.analysis_usage where user_id = p_user and day = p_day for update;
  if cur >= p_limit then return -cur; end if;
  update public.analysis_usage set used = used + 1 where user_id = p_user and day = p_day;
  return cur + 1;
end $$;
revoke all on function public.fraiha_analysis_consume(uuid, date, integer) from public, anon, authenticated;
grant execute on function public.fraiha_analysis_consume(uuid, date, integer) to service_role;

-- 4) Histórico de análise (alimenta estatísticas, relatório semanal e treinador no futuro).
create table if not exists public.analysis_history (
  analysis_id    uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(user_id) on delete cascade,
  match_id       uuid,                        -- matches.match_id quando Ranked; null para bot/casual
  mode           text not null,
  played_at      timestamptz,
  analyzed_at    timestamptz not null default now(),
  color          text check (color in ('w','b')),
  result         text,
  accuracy       numeric(5,2),
  counts         jsonb not null default '{}'::jsonb,   -- {"best":2,"excellent":5,...}
  critical_ply   integer,
  best_ply       integer,
  moves          jsonb,                                  -- por lance: {uci,class,loss,best} (compacto)
  engine         text,
  depth          integer
);
create index if not exists analysis_history_user_idx on public.analysis_history (user_id, analyzed_at desc);
alter table public.analysis_history enable row level security;
revoke insert, update, delete, truncate on public.analysis_history from anon, authenticated;
drop policy if exists analysis_history_read_own on public.analysis_history;
create policy analysis_history_read_own on public.analysis_history for select to authenticated using (auth.uid() = user_id);
