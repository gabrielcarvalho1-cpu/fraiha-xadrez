-- FRAIHA 0010 · R39 — reembolso / contestação retira o direito liberado pelo pagamento.
--
-- PREPARADA, NÃO APLICADA. Aplicar só com autorização (o Supabase é o mesmo de staging e produção).
-- Depende de: 0005 (entitlements, payments) e 0007 (fraiha_grant_entitlement).
--
--   fraiha_revoke_entitlement(user, product): chamada pelo servidor quando o provedor avisa que um
--   pagamento PAGO foi reembolsado ou contestado (payments: paid → refunded). Uma transação, com lock:
--     • founder      → is_founder = false, founder_since = null, tira os 30 dias de Club do bônus;
--     • club_monthly → tira 30 dias de Club;
--     • se o Club acabar (expira <= agora) → club_active = false.
--   Só service_role executa.
--
-- Impacto: aditivo (1 função). Não altera tabelas nem dados existentes.
-- Servidor sem esta migração: continua funcionando; num reembolso o pagamento fica 'refunded',
-- mas o direito NÃO é retirado (o log do servidor avisa "aplique a migração 0010").
-- Reverter:
--   drop function if exists public.fraiha_revoke_entitlement(uuid, text);

create or replace function public.fraiha_revoke_entitlement(p_user uuid, p_product text)
returns void language plpgsql security definer set search_path = public as $$
declare
  cur public.entitlements%rowtype;
  new_exp timestamptz;
begin
  if p_product not in ('founder', 'club_monthly') then
    raise exception 'product_invalid:%', p_product;
  end if;
  select * into cur from public.entitlements where user_id = p_user for update;
  if not found then return; end if;
  new_exp := case when cur.club_expires_at is null then null else cur.club_expires_at - interval '30 days' end;
  if new_exp is not null and new_exp <= now() then new_exp := null; end if;
  update public.entitlements set
    is_founder      = case when p_product = 'founder' then false else is_founder end,
    founder_since   = case when p_product = 'founder' then null else founder_since end,
    club_expires_at = new_exp,
    club_active     = (new_exp is not null),
    updated_at      = now()
  where user_id = p_user;
end $$;

revoke all on function public.fraiha_revoke_entitlement(uuid, text) from public, anon, authenticated;
grant execute on function public.fraiha_revoke_entitlement(uuid, text) to service_role;
