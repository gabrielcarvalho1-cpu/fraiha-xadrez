-- FRAIHA Xadrez — 0008: MARCHA REAL (novo modo de cartas e corrida) — limite diário de quem não é do Club.
-- NÃO APLICADA. Aplicar só com autorização explícita (staging e produção compartilham o banco).
-- Requer 0001 (profiles).
--
-- O que faz:
--   • cria public.marcha_usage: partidas da Marcha Real começadas por (conta, dia UTC);
--   • fraiha_marcha_consume(user, day, limit): soma 1 se ainda houver partida no dia (lock na linha);
--     devolve o novo total, ou o total NEGATIVO quando o limite já foi atingido. Só service_role executa.
--   • Club FRAIHA = ilimitado: decidido no servidor Node (entitlements) antes de chamar a função.
-- RLS ligado: o jogador só LÊ as próprias linhas; nenhum cliente grava.
-- Impacto: aditivo (1 tabela + 1 função). Servidor sem esta migração: o limite fica no aparelho do jogador.
-- Reverter: drop function if exists public.fraiha_marcha_consume(uuid, date, integer); drop table if exists public.marcha_usage;

create table if not exists public.marcha_usage (
  user_id  uuid not null references public.profiles(user_id) on delete cascade,
  day      date not null,
  used     integer not null default 0 check (used >= 0),
  primary key (user_id, day)
);
alter table public.marcha_usage enable row level security;
revoke insert, update, delete, truncate on public.marcha_usage from anon, authenticated;
drop policy if exists marcha_usage_read_own on public.marcha_usage;
create policy marcha_usage_read_own on public.marcha_usage for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.fraiha_marcha_consume(p_user uuid, p_day date, p_limit integer)
returns integer language plpgsql security definer set search_path = public as $$
declare cur integer;
begin
  insert into public.marcha_usage (user_id, day, used) values (p_user, p_day, 0) on conflict do nothing;
  select used into cur from public.marcha_usage where user_id = p_user and day = p_day for update;
  if cur >= p_limit then return -cur; end if;
  update public.marcha_usage set used = used + 1 where user_id = p_user and day = p_day;
  return cur + 1;
end $$;
revoke all on function public.fraiha_marcha_consume(uuid, date, integer) from public, anon, authenticated;
grant execute on function public.fraiha_marcha_consume(uuid, date, integer) to service_role;
