-- FRAIHA Xadrez — 0007: identidade premium (ícone e título) + liberação atômica de direitos.
-- NÃO APLICADA. Aplicar só com autorização explícita (staging e produção compartilham o banco).
-- Requer 0001 (profiles) e 0005 (entitlements, payments).
--
-- O que faz:
--   1) profiles.profile_badge / profiles.profile_title: ícone (selo) e título escolhidos pelo jogador.
--      Quem grava é só o servidor Node (service_role), depois de conferir os direitos da conta
--      (acct_set_cosmetics). O avatar continua em profiles.avatar_id e a moldura em profiles.profile_frame.
--      O servidor só EXIBE o item enquanto o direito estiver ativo (Club vencido → some, sem apagar).
--   2) fraiha_grant_entitlement(user, product, source): chamada pelo servidor quando o webhook do
--      provedor confirma um pagamento (pending → paid). Uma transação, com lock na linha:
--        • founder      → is_founder = true, founder_since (mantém o 1º), +30 dias de Club (founder_bonus);
--        • club_monthly → +30 dias de Club somados ao que ainda resta.
--      Só service_role executa.
-- Impacto: aditivo (2 colunas com default '' e 1 função). Não altera dados existentes.
-- Servidor sem esta migração: continua funcionando (ícone/título não são salvos; avatar sim).
-- Reverter:
--   alter table public.profiles drop column if exists profile_badge, drop column if exists profile_title;
--   drop function if exists public.fraiha_grant_entitlement(uuid, text, text);

alter table public.profiles
  add column if not exists profile_badge text not null default '',
  add column if not exists profile_title text not null default '';

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_profile_badge_check') then
    alter table public.profiles add constraint profiles_profile_badge_check
      check (profile_badge in ('', 'fundador', 'club_a', 'club_b', 'club_c'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_profile_title_check') then
    alter table public.profiles add constraint profiles_profile_title_check
      check (profile_title in ('', 'fundador', 'club'));
  end if;
end $$;

create or replace function public.fraiha_grant_entitlement(p_user uuid, p_product text, p_source text)
returns void language plpgsql security definer set search_path = public as $$
declare
  cur public.entitlements%rowtype;
  base timestamptz;
begin
  if p_product not in ('founder', 'club_monthly') then
    raise exception 'product_invalid:%', p_product;
  end if;
  insert into public.entitlements (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into cur from public.entitlements where user_id = p_user for update;
  base := greatest(now(), coalesce(case when cur.club_active then cur.club_expires_at end, now()));
  if p_product = 'founder' then
    update public.entitlements set
      is_founder = true,
      founder_since = coalesce(cur.founder_since, now()),
      club_active = true,
      club_expires_at = base + interval '30 days',
      club_source = case when cur.club_active and coalesce(cur.club_source, '') not in ('', 'founder_bonus') then cur.club_source else 'founder_bonus' end,
      updated_at = now()
    where user_id = p_user;
  else
    update public.entitlements set
      club_active = true,
      club_expires_at = base + interval '30 days',
      club_source = coalesce(nullif(p_source, ''), 'manual'),
      updated_at = now()
    where user_id = p_user;
  end if;
end $$;

revoke all on function public.fraiha_grant_entitlement(uuid, text, text) from public, anon, authenticated;
grant execute on function public.fraiha_grant_entitlement(uuid, text, text) to service_role;
