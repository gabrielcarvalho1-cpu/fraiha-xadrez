-- R143 · RANKED: FORÇA oculta (Glicko) por jogador e ritmo.
-- Aditiva e segura: só ACRESCENTA duas colunas (nulas = "ainda sem Força": o servidor estima pela liga) e passa a
-- gravar a Força junto com o resultado. Nada é apagado; liga, PL e histórico continuam iguais.
-- O servidor R143 funciona com ou sem esta migração (sem ela, a Força é estimada a cada partida pela liga atual).
-- Ordem: pode ser aplicada antes ou depois do deploy do servidor R143.

alter table public.ranked_stats add column if not exists forca    real;
alter table public.ranked_stats add column if not exists forca_rd real;

-- Mesma função da 0001 + Força (white/black_forca_after, white/black_forca_rd_after). Sem esses campos no
-- pedido (servidor antigo), a Força fica como está (coalesce).
create or replace function public.fraiha_record_ranked_match(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  w record; b record; mid uuid;
  wr text := case p->>'result' when 'white' then 'win' when 'black' then 'loss' else 'draw' end;
  br text := case p->>'result' when 'black' then 'win' when 'white' then 'loss' else 'draw' end;
begin
  select * into w from public.ranked_stats where user_id = (p->>'white_user_id')::uuid and mode = p->>'mode' for update;
  select * into b from public.ranked_stats where user_id = (p->>'black_user_id')::uuid and mode = p->>'mode' for update;
  if w is null or b is null then raise exception 'ranked_stats ausente'; end if;
  if w.pl <> (p->>'white_pl_before')::int or w.league <> (p->>'white_league_before')::int
     or b.pl <> (p->>'black_pl_before')::int or b.league <> (p->>'black_league_before')::int then
    raise exception 'estado Ranked mudou durante a partida';
  end if;
  update public.ranked_stats set
    league = (p->>'white_league_after')::int, pl = (p->>'white_pl_after')::int,
    matches = matches + 1, wins = wins + (wr = 'win')::int, losses = losses + (wr = 'loss')::int, draws = draws + (wr = 'draw')::int,
    highest_league = greatest(highest_league, (p->>'white_league_after')::int), updated_at = now(),
    forca = coalesce((p->>'white_forca_after')::real, forca), forca_rd = coalesce((p->>'white_forca_rd_after')::real, forca_rd)
  where user_id = w.user_id and mode = w.mode;
  update public.ranked_stats set
    league = (p->>'black_league_after')::int, pl = (p->>'black_pl_after')::int,
    matches = matches + 1, wins = wins + (br = 'win')::int, losses = losses + (br = 'loss')::int, draws = draws + (br = 'draw')::int,
    highest_league = greatest(highest_league, (p->>'black_league_after')::int), updated_at = now(),
    forca = coalesce((p->>'black_forca_after')::real, forca), forca_rd = coalesce((p->>'black_forca_rd_after')::real, forca_rd)
  where user_id = b.user_id and mode = b.mode;
  insert into public.matches (match_id, mode, white_user_id, black_user_id, started_at, finished_at, result, result_reason,
    white_pl_before, black_pl_before, white_pl_change, black_pl_change, white_pl_after, black_pl_after,
    white_league_before, black_league_before, white_league_after, black_league_after, moves)
  values (coalesce((p->>'match_id')::uuid, gen_random_uuid()), p->>'mode', w.user_id, b.user_id,
    (p->>'started_at')::timestamptz, (p->>'finished_at')::timestamptz, p->>'result', p->>'result_reason',
    (p->>'white_pl_before')::int, (p->>'black_pl_before')::int, (p->>'white_pl_change')::int, (p->>'black_pl_change')::int,
    (p->>'white_pl_after')::int, (p->>'black_pl_after')::int,
    (p->>'white_league_before')::int, (p->>'black_league_before')::int, (p->>'white_league_after')::int, (p->>'black_league_after')::int,
    coalesce(p->>'moves',''))
  returning match_id into mid;
  return mid;
end $$;
revoke all on function public.fraiha_record_ranked_match(jsonb) from public, anon, authenticated;
grant execute on function public.fraiha_record_ranked_match(jsonb) to service_role;

-- A Força é OCULTA. ranked_stats tem leitura para contas logadas (policy ranked_read da 0001); no Postgres,
-- tirar só as colunas novas não basta quando a tabela inteira está liberada. Então: tira a leitura da tabela
-- e devolve coluna por coluna, SEM forca/forca_rd (o servidor usa service role e continua lendo tudo).
revoke select on public.ranked_stats from anon, authenticated;
grant select (user_id, mode, league, pl, matches, wins, losses, draws, highest_league, updated_at)
  on public.ranked_stats to authenticated;
