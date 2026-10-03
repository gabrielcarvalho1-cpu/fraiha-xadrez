-- FRAIHA Xadrez — 0009: vitórias / derrotas por MODO (Casual online, Marcha Real online, Xeque online).
-- NÃO APLICADA. Aplicar só com autorização explícita (staging e produção compartilham o banco).
-- Requer 0001 (profiles).
--
-- O que faz:
--   • cria public.mode_stats: placar de cada conta em cada modo (o Ranked continua em ranked_stats);
--   • fraiha_mode_record(user, mode, result): soma 1 vitória / derrota / empate (atômico). Só service_role.
--     O servidor Node chama no fim de cada partida autoritativa (casual online e mesas MARCHA/XEQUE com amigo).
-- RLS ligado: placar é público para leitura (aparece no cartão de perfil); nenhum cliente grava.
-- Impacto: aditivo (1 tabela + 1 função). Servidor sem esta migração: o cartão mostra o Ranked e
-- "placar deste modo ainda não disponível" nos outros modos; nada quebra.
-- Reverter: drop function if exists public.fraiha_mode_record(uuid, text, text); drop table if exists public.mode_stats;

create table if not exists public.mode_stats (
  user_id    uuid not null references public.profiles(user_id) on delete cascade,
  mode_id    text not null check (mode_id in ('casual', 'marcha', 'xeque')),
  wins       integer not null default 0 check (wins >= 0),
  losses     integer not null default 0 check (losses >= 0),
  draws      integer not null default 0 check (draws >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, mode_id)
);
alter table public.mode_stats enable row level security;
revoke insert, update, delete, truncate on public.mode_stats from anon, authenticated;
drop policy if exists mode_stats_read on public.mode_stats;
create policy mode_stats_read on public.mode_stats for select to anon, authenticated using (true);

create or replace function public.fraiha_mode_record(p_user uuid, p_mode text, p_result text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_result not in ('win', 'loss', 'draw') then raise exception 'resultado inválido: %', p_result; end if;
  insert into public.mode_stats (user_id, mode_id, wins, losses, draws)
  values (p_user, p_mode, (p_result = 'win')::int, (p_result = 'loss')::int, (p_result = 'draw')::int)
  on conflict (user_id, mode_id) do update set
    wins = mode_stats.wins + (p_result = 'win')::int,
    losses = mode_stats.losses + (p_result = 'loss')::int,
    draws = mode_stats.draws + (p_result = 'draw')::int,
    updated_at = now();
end $$;
revoke all on function public.fraiha_mode_record(uuid, text, text) from public, anon, authenticated;
grant execute on function public.fraiha_mode_record(uuid, text, text) to service_role;
