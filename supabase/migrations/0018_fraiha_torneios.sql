-- FRAIHA Xadrez — 0018: TORNEIO DA SEMANA de XEQUE e de MARCHA REAL (R118). Entrada grátis; prêmio em Coroas.
-- ADITIVA; depende da 0016 (Coroas). Sem ela o jogo funciona e o torneio aparece indisponível.
--
-- 1) public.tournament_scores: pontos de cada conta por semana (horário de Brasília, segunda → domingo) e modo.
--    Vitória 3 pontos, partida terminada 1 (mesa online com pelo menos 2 pessoas; até 8 partidas por dia contam).
-- 2) fraiha_tourn_add(semana, modo, conta, pontos, vitória): soma numa transação e devolve o total da conta.
-- O prêmio (1º 500, 2º 300, 3º 200, 4º–10º 100 Coroas) é pago pelo servidor com fraiha_crown_award
-- (motivo 'tournament', ref semana:modo): nunca paga duas vezes.
--
-- Reverter:
--   drop function if exists public.fraiha_tourn_add(text, text, uuid, integer, boolean);
--   drop table if exists public.tournament_scores;

create table if not exists public.tournament_scores (
  week       text not null,            -- ex.: 2026-W42
  game       text not null check (game in ('xeque', 'marcha')),
  user_id    uuid not null,
  points     integer not null default 0,
  games      integer not null default 0,
  wins       integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (week, game, user_id)
);
create index if not exists tournament_scores_rank on public.tournament_scores (week, game, points desc, wins desc, updated_at asc);
alter table public.tournament_scores enable row level security;
revoke all on table public.tournament_scores from anon, authenticated;
grant select, insert, update on table public.tournament_scores to service_role;

create or replace function public.fraiha_tourn_add(p_week text, p_game text, p_user uuid, p_pts integer, p_win boolean)
returns integer language plpgsql security definer set search_path = public as $$
declare
  total integer;
begin
  if p_pts is null or p_pts < 0 or p_pts > 10 then raise exception 'pontos_invalidos:%', p_pts; end if;
  insert into public.tournament_scores (week, game, user_id, points, games, wins)
    values (p_week, p_game, p_user, p_pts, 1, case when p_win then 1 else 0 end)
  on conflict (week, game, user_id) do update set
    points = public.tournament_scores.points + excluded.points,
    games = public.tournament_scores.games + 1,
    wins = public.tournament_scores.wins + excluded.wins,
    updated_at = now()
  returning points into total;
  return total;
end $$;
revoke all on function public.fraiha_tourn_add(text, text, uuid, integer, boolean) from public, anon, authenticated;
grant execute on function public.fraiha_tourn_add(text, text, uuid, integer, boolean) to service_role;
