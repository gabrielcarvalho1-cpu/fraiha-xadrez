-- FRAIHA Xadrez — 0016: COROAS, a moeda do jogo (R112). Por enquanto só se GANHA jogando (sem venda).
-- ADITIVA. Aplicar no SQL Editor ANTES de publicar o servidor R112 (sem ela o jogo funciona normalmente;
-- só as Coroas ficam indisponíveis — o servidor avisa "COROAS EM BREVE").
--
-- 1) public.crown_wallets: saldo de cada conta (nunca negativo), total já ganho e sequência de dias seguidos.
-- 2) public.crown_ledger: extrato. Cada ganho tem (motivo, referência) ÚNICOS por conta — a mesma partida,
--    missão ou entrada do dia nunca paga duas vezes, mesmo com reconexão ou servidor reiniciando.
-- 3) public.crown_daily: contadores do dia (horário de Brasília) para as missões e o limite diário de partidas.
-- 4) Funções (só o servidor / service_role):
--      fraiha_crown_award(conta, valor, motivo, ref)  → novo saldo, ou NULL se aquele (motivo, ref) já foi pago
--                                                       (valor 0 = só marca, ex.: partida acima do limite do dia);
--      fraiha_crown_bump(conta, dia, contadores)       → soma os contadores do dia e devolve todos (jsonb);
--      fraiha_crown_checkin(conta, dia)                → sequência de dias (1, 2, 3…) ou NULL se já entrou hoje.
--
-- Reverter:
--   drop function if exists public.fraiha_crown_checkin(uuid, date);
--   drop function if exists public.fraiha_crown_bump(uuid, date, jsonb);
--   drop function if exists public.fraiha_crown_award(uuid, integer, text, text);
--   drop table if exists public.crown_daily;
--   drop table if exists public.crown_ledger;
--   drop table if exists public.crown_wallets;

create table if not exists public.crown_wallets (
  user_id      uuid primary key,
  balance      integer not null default 0 check (balance >= 0),
  earned_total integer not null default 0,
  streak       integer not null default 0,
  last_daily   date,
  updated_at   timestamptz not null default now()
);

create table if not exists public.crown_ledger (
  id         bigserial primary key,
  user_id    uuid not null,
  delta      integer not null,
  reason     text not null,
  ref        text not null default '',
  created_at timestamptz not null default now(),
  unique (user_id, reason, ref)
);
create index if not exists crown_ledger_user on public.crown_ledger (user_id, created_at desc);

create table if not exists public.crown_daily (
  user_id  uuid not null,
  day      date not null,
  counters jsonb not null default '{}'::jsonb,
  primary key (user_id, day)
);

alter table public.crown_wallets enable row level security;
alter table public.crown_ledger enable row level security;
alter table public.crown_daily enable row level security;
revoke all on table public.crown_wallets, public.crown_ledger, public.crown_daily from anon, authenticated;

create or replace function public.fraiha_crown_award(p_user uuid, p_delta integer, p_reason text, p_ref text)
returns integer language plpgsql security definer set search_path = public as $$
declare
  nb integer;
begin
  if p_delta is null or abs(p_delta) > 100000 then raise exception 'valor_invalido:%', p_delta; end if;
  if coalesce(p_reason, '') = '' then raise exception 'motivo_vazio'; end if;
  insert into public.crown_ledger (user_id, delta, reason, ref) values (p_user, p_delta, p_reason, coalesce(p_ref, ''))
    on conflict (user_id, reason, ref) do nothing;
  if not found then return null; end if;   -- já pago
  insert into public.crown_wallets (user_id) values (p_user) on conflict (user_id) do nothing;
  update public.crown_wallets set
    balance = balance + p_delta,
    earned_total = earned_total + greatest(p_delta, 0),
    updated_at = now()
  where user_id = p_user
  returning balance into nb;   -- saldo negativo → check falha → a transação inteira volta (nada é gasto)
  return nb;
end $$;

create or replace function public.fraiha_crown_bump(p_user uuid, p_day date, p_inc jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  cur jsonb;
  k text;
  v jsonb;
begin
  insert into public.crown_daily (user_id, day) values (p_user, p_day) on conflict (user_id, day) do nothing;
  select counters into cur from public.crown_daily where user_id = p_user and day = p_day for update;
  for k, v in select * from jsonb_each(coalesce(p_inc, '{}'::jsonb)) loop
    cur := jsonb_set(cur, array[k], to_jsonb(coalesce((cur ->> k)::integer, 0) + (v #>> '{}')::integer));
  end loop;
  update public.crown_daily set counters = cur where user_id = p_user and day = p_day;
  return cur;
end $$;

create or replace function public.fraiha_crown_checkin(p_user uuid, p_day date)
returns integer language plpgsql security definer set search_path = public as $$
declare
  w public.crown_wallets%rowtype;
  s integer;
begin
  insert into public.crown_wallets (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into w from public.crown_wallets where user_id = p_user for update;
  if w.last_daily is not null and w.last_daily >= p_day then return null; end if;
  s := case when w.last_daily = p_day - 1 then w.streak + 1 else 1 end;
  update public.crown_wallets set streak = s, last_daily = p_day, updated_at = now() where user_id = p_user;
  return s;
end $$;

revoke all on function public.fraiha_crown_award(uuid, integer, text, text) from public, anon, authenticated;
revoke all on function public.fraiha_crown_bump(uuid, date, jsonb) from public, anon, authenticated;
revoke all on function public.fraiha_crown_checkin(uuid, date) from public, anon, authenticated;
grant execute on function public.fraiha_crown_award(uuid, integer, text, text) to service_role;
grant execute on function public.fraiha_crown_bump(uuid, date, jsonb) to service_role;
grant execute on function public.fraiha_crown_checkin(uuid, date) to service_role;
grant select, insert, update on table public.crown_wallets, public.crown_ledger, public.crown_daily to service_role;
grant usage on sequence public.crown_ledger_id_seq to service_role;
