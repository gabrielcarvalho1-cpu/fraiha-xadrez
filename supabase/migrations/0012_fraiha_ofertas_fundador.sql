-- FRAIHA Xadrez — 0012: nova oferta (R103) e pagamento que nunca "cobra sem entregar".
-- ADITIVA. Aplicar no SQL Editor ANTES de publicar o servidor R103 (o servidor antigo continua funcionando com ela).
--
-- 1) Produtos novos aceitos em payments: founder_legend (Fundador Lendário) e club_yearly (Club anual).
-- 2) payments.granted_at: quando a vantagem foi entregue (permite conferir "pago sem vantagem").
-- 3) entitlements.founder_number (Fundador #N, numerado pela ordem de compra) e founder_tier ('founder' | 'legend').
-- 4) fraiha_grant_entitlement passa a aceitar os 4 produtos:
--      founder        → Fundador + 90 dias de Club
--      founder_legend → Fundador Lendário + 365 dias de Club
--      club_monthly   → +30 dias de Club
--      club_yearly    → +365 dias de Club
-- 5) fraiha_revoke_entitlement (reembolso/contestação) com os mesmos prazos.
-- 6) fraiha_pay_and_grant(provider, ref, source): marca o pagamento como pago E entrega a vantagem na MESMA
--    transação. Se a entrega falhar, nada muda (o pedido continua 'pending') e a próxima notificação do
--    Mercado Pago tenta de novo — acaba o caso "pagou e não recebeu".
--    fraiha_grant_paid_missing(): entrega o que ficou pago sem vantagem (pedidos antigos), chamada pelo servidor.
-- Só service_role executa as funções.
--
-- Reverter:
--   drop function if exists public.fraiha_pay_and_grant(text, text, text);
--   drop function if exists public.fraiha_grant_paid_missing();
--   (as funções grant/revoke voltam às versões da 0007/0010 reaplicando aqueles arquivos)
--   alter table public.payments drop column if exists granted_at;
--   alter table public.entitlements drop column if exists founder_number, drop column if exists founder_tier;

alter table public.payments drop constraint if exists payments_product_id_check;
alter table public.payments add constraint payments_product_id_check
  check (product_id in ('founder', 'founder_legend', 'club_monthly', 'club_yearly'));
alter table public.payments add column if not exists granted_at timestamptz;
-- o que já estava pago antes desta migração foi entregue pelo fluxo antigo
update public.payments set granted_at = coalesce(paid_at, now()) where status in ('paid', 'refunded') and granted_at is null;

create sequence if not exists public.fraiha_founder_seq;
alter table public.entitlements add column if not exists founder_number integer;
alter table public.entitlements add column if not exists founder_tier text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'entitlements_founder_tier_check') then
    alter table public.entitlements add constraint entitlements_founder_tier_check check (founder_tier is null or founder_tier in ('founder', 'legend'));
  end if;
end $$;
create unique index if not exists entitlements_founder_number_unique on public.entitlements (founder_number) where founder_number is not null;
-- Fundadores que já existem recebem número pela ordem em que viraram Fundador
do $$ declare r record; begin
  for r in select user_id from public.entitlements where is_founder and founder_number is null order by founder_since nulls last, updated_at loop
    update public.entitlements set founder_number = nextval('public.fraiha_founder_seq'), founder_tier = coalesce(founder_tier, 'founder') where user_id = r.user_id;
  end loop;
end $$;

create or replace function public.fraiha_club_days(p_product text) returns integer language sql immutable as $$
  select case p_product when 'founder' then 90 when 'founder_legend' then 365 when 'club_monthly' then 30 when 'club_yearly' then 365 else 0 end
$$;

create or replace function public.fraiha_grant_entitlement(p_user uuid, p_product text, p_source text)
returns void language plpgsql security definer set search_path = public as $$
declare
  cur public.entitlements%rowtype;
  base timestamptz;
  founderish boolean := p_product in ('founder', 'founder_legend');
begin
  if p_product not in ('founder', 'founder_legend', 'club_monthly', 'club_yearly') then
    raise exception 'product_invalid:%', p_product;
  end if;
  insert into public.entitlements (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into cur from public.entitlements where user_id = p_user for update;
  base := greatest(now(), coalesce(case when cur.club_active then cur.club_expires_at end, now()));
  update public.entitlements set
    is_founder      = cur.is_founder or founderish,
    founder_since   = case when founderish then coalesce(cur.founder_since, now()) else cur.founder_since end,
    founder_number  = case when founderish then coalesce(cur.founder_number, nextval('public.fraiha_founder_seq')) else cur.founder_number end,
    founder_tier    = case when p_product = 'founder_legend' then 'legend'
                           when p_product = 'founder' then coalesce(cur.founder_tier, 'founder')
                           else cur.founder_tier end,
    club_active     = true,
    club_expires_at = base + make_interval(days => public.fraiha_club_days(p_product)),
    club_source     = case when founderish then
                        (case when cur.club_active and coalesce(cur.club_source, '') not in ('', 'founder_bonus') then cur.club_source else 'founder_bonus' end)
                      else coalesce(nullif(p_source, ''), 'manual') end,
    updated_at      = now()
  where user_id = p_user;
end $$;

create or replace function public.fraiha_revoke_entitlement(p_user uuid, p_product text)
returns void language plpgsql security definer set search_path = public as $$
declare
  cur public.entitlements%rowtype;
  new_exp timestamptz;
begin
  if p_product not in ('founder', 'founder_legend', 'club_monthly', 'club_yearly') then
    raise exception 'product_invalid:%', p_product;
  end if;
  select * into cur from public.entitlements where user_id = p_user for update;
  if not found then return; end if;
  new_exp := case when cur.club_expires_at is null then null else cur.club_expires_at - make_interval(days => public.fraiha_club_days(p_product)) end;
  if new_exp is not null and new_exp <= now() then new_exp := null; end if;
  update public.entitlements set
    is_founder      = case when p_product in ('founder', 'founder_legend') then false else is_founder end,
    founder_since   = case when p_product in ('founder', 'founder_legend') then null else founder_since end,
    founder_tier    = case when p_product in ('founder', 'founder_legend') then null else founder_tier end,
    -- o número fica reservado (não volta para a fila): um número nunca é dado a duas pessoas
    club_expires_at = new_exp,
    club_active     = (new_exp is not null),
    updated_at      = now()
  where user_id = p_user;
end $$;

create or replace function public.fraiha_pay_and_grant(p_provider text, p_ref text, p_source text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  pay public.payments%rowtype;
begin
  update public.payments set status = 'paid', paid_at = now()
   where provider = p_provider and provider_ref = p_ref and status = 'pending'
   returning * into pay;
  if not found then return null; end if;
  perform public.fraiha_grant_entitlement(pay.user_id, pay.product_id, p_source);
  update public.payments set granted_at = now() where payment_id = pay.payment_id;
  return jsonb_build_object('payment_id', pay.payment_id, 'user_id', pay.user_id, 'product_id', pay.product_id, 'status', 'paid');
end $$;

create or replace function public.fraiha_grant_paid_missing()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r record; n integer := 0;
begin
  for r in select payment_id, user_id, product_id, provider from public.payments
            where status = 'paid' and granted_at is null for update skip locked loop
    perform public.fraiha_grant_entitlement(r.user_id, r.product_id, r.provider);
    update public.payments set granted_at = now() where payment_id = r.payment_id;
    n := n + 1;
  end loop;
  return jsonb_build_object('granted', n);
end $$;

revoke all on function public.fraiha_club_days(text) from public, anon, authenticated;
grant execute on function public.fraiha_club_days(text) to service_role;
revoke all on function public.fraiha_grant_entitlement(uuid, text, text) from public, anon, authenticated;
grant execute on function public.fraiha_grant_entitlement(uuid, text, text) to service_role;
revoke all on function public.fraiha_revoke_entitlement(uuid, text) from public, anon, authenticated;
grant execute on function public.fraiha_revoke_entitlement(uuid, text) to service_role;
revoke all on function public.fraiha_pay_and_grant(text, text, text) from public, anon, authenticated;
grant execute on function public.fraiha_pay_and_grant(text, text, text) to service_role;
revoke all on function public.fraiha_grant_paid_missing() from public, anon, authenticated;
grant execute on function public.fraiha_grant_paid_missing() to service_role;
