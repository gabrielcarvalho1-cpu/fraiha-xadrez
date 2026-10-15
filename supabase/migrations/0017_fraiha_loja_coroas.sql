-- FRAIHA Xadrez — 0017: LOJA DE COROAS (R116). Itens só visuais (títulos, molduras, avatares, emotes): nunca
-- vantagem de jogo. ADITIVA; depende da 0016 (Coroas). Sem ela o jogo funciona e a loja aparece indisponível.
--
-- 1) public.crown_items: o que cada conta comprou (uma linha por item, para sempre).
-- 2) fraiha_crown_buy(conta, item, preço): numa transação só — confere o saldo, registra o item e desconta
--    as Coroas (lançamento 'buy' no extrato). Devolve 'ok' | 'ja_tem' | 'saldo_insuficiente'.
--    O preço vem do catálogo do SERVIDOR (o cliente só diz qual item quer).
--
-- 3) profiles.profile_title: a lista fixa da 0007 ('', fundador, club) barrava o título "lendario" (R103) e os
--    títulos da loja. Passa a aceitar qualquer código curto; QUEM decide se a conta pode usar é o servidor
--    (online_v021/accounts/cosmetics.js), como já acontece com o avatar e a moldura.
--
-- Reverter:
--   alter table public.profiles drop constraint if exists profiles_profile_title_check;
--   alter table public.profiles add constraint profiles_profile_title_check check (profile_title in ('', 'fundador', 'club'));
--   drop function if exists public.fraiha_crown_buy(uuid, text, integer);
--   drop table if exists public.crown_items;

create table if not exists public.crown_items (
  user_id   uuid not null,
  item_id   text not null,
  price     integer not null check (price >= 0),
  bought_at timestamptz not null default now(),
  primary key (user_id, item_id)
);
alter table public.crown_items enable row level security;
revoke all on table public.crown_items from anon, authenticated;
grant select, insert on table public.crown_items to service_role;

create or replace function public.fraiha_crown_buy(p_user uuid, p_item text, p_price integer)
returns text language plpgsql security definer set search_path = public as $$
declare
  bal integer;
begin
  if coalesce(p_item, '') = '' or p_price is null or p_price < 0 or p_price > 100000 then raise exception 'compra_invalida'; end if;
  insert into public.crown_wallets (user_id) values (p_user) on conflict (user_id) do nothing;
  select balance into bal from public.crown_wallets where user_id = p_user for update;   -- uma compra por vez por conta
  if exists (select 1 from public.crown_items where user_id = p_user and item_id = p_item) then return 'ja_tem'; end if;
  if bal < p_price then return 'saldo_insuficiente'; end if;
  insert into public.crown_items (user_id, item_id, price) values (p_user, p_item, p_price);
  if p_price > 0 then perform public.fraiha_crown_award(p_user, -p_price, 'buy', p_item); end if;
  return 'ok';
end $$;
revoke all on function public.fraiha_crown_buy(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.fraiha_crown_buy(uuid, text, integer) to service_role;

alter table public.profiles drop constraint if exists profiles_profile_title_check;
alter table public.profiles add constraint profiles_profile_title_check check (profile_title ~ '^[a-z0-9_]{0,40}$');
