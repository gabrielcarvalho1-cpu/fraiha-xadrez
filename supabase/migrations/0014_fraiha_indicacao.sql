-- FRAIHA Xadrez — 0014: convite por link e recompensa por indicação (R105).
-- ADITIVA. Aplicar no SQL Editor ANTES de publicar o servidor R105 (sem ela o link de convite continua
-- funcionando para trazer gente, mas a indicação não é registrada nem premiada).
--
-- 1) profiles.ref_code: código curto e único do link de convite de cada conta (criado na primeira vez que a
--    pessoa abre "CONVIDAR AMIGOS").
-- 2) public.referrals: quem convidou quem (uma linha por conta NOVA criada pelo link), quantas partidas online
--    a conta nova já terminou e quando cada recompensa foi entregue:
--      5 partidas online → os dois ganham 7 dias de Club (até 10 indicações premiadas por mês para quem convida);
--      primeira compra da conta nova → quem convidou ganha +30 dias de Club.
--    Só o servidor (service_role) lê e escreve.
-- 3) fraiha_grant_club_days(user, dias, origem): soma dias de Club ao que ainda resta, numa transação.
--
-- Reverter:
--   drop function if exists public.fraiha_grant_club_days(uuid, integer, text);
--   drop table if exists public.referrals;
--   alter table public.profiles drop column if exists ref_code;

alter table public.profiles add column if not exists ref_code text;
create unique index if not exists profiles_ref_code_unique on public.profiles (ref_code) where ref_code is not null;

create table if not exists public.referrals (
  referred_id          uuid primary key,             -- a conta nova (só pode ter sido convidada por uma pessoa)
  referrer_id          uuid not null,
  games                integer not null default 0,
  created_at           timestamptz not null default now(),
  qualified_at         timestamptz,                  -- chegou a 5 partidas
  rewarded_at          timestamptz,                  -- 7 dias de Club entregues aos dois
  purchase_rewarded_at timestamptz,                  -- +30 dias de Club para quem convidou
  check (referred_id <> referrer_id)
);
create index if not exists referrals_referrer on public.referrals (referrer_id, created_at desc);
alter table public.referrals enable row level security;
revoke all on table public.referrals from anon, authenticated;

create or replace function public.fraiha_grant_club_days(p_user uuid, p_days integer, p_source text)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  cur public.entitlements%rowtype;
  new_exp timestamptz;
begin
  if p_days is null or p_days < 1 or p_days > 400 then raise exception 'dias_invalidos:%', p_days; end if;
  insert into public.entitlements (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into cur from public.entitlements where user_id = p_user for update;
  new_exp := greatest(now(), coalesce(case when cur.club_active then cur.club_expires_at end, now())) + make_interval(days => p_days);
  update public.entitlements set
    club_active = true,
    club_expires_at = new_exp,
    club_source = case when cur.club_active and coalesce(cur.club_source, '') <> '' then cur.club_source else coalesce(nullif(p_source, ''), 'referral') end,
    updated_at = now()
  where user_id = p_user;
  return new_exp;
end $$;
revoke all on function public.fraiha_grant_club_days(uuid, integer, text) from public, anon, authenticated;
grant execute on function public.fraiha_grant_club_days(uuid, integer, text) to service_role;
