-- R173 · RANKED: resultado PRECOCE (desistência/abandono antes de 10 meios-lances) não entra no placar.
-- Regra aprovada pelo dono: o PL muda (perdedor perde o normal; vencedor recebe no máximo o que saiu do outro),
-- a Força não muda, e a partida NÃO conta como partida/vitória/derrota/empate (não infla o aproveitamento).
--
-- Aditiva e segura:
--   • mesma função da 0020, com UM campo opcional novo no pedido: "count_stats" (padrão = true);
--     sem o campo (servidor antigo) tudo continua exatamente igual;
--   • uma coluna nova em public.matches, "counts_stats" (padrão true): as partidas antigas ficam como estão
--     (nada é recalculado nem alterado retroativamente); só as precoces novas gravam false;
--   • mesma checagem do PL/liga "antes" (corrida) e mesma chave de partida (replay continua deduplicado).
-- Ordem: pode ser aplicada antes ou depois do servidor R173. Servidor R173 sem a 0025: a função antiga ignora
-- "count_stats" e conta a partida no placar (como antes) — o PL continua certo; só o placar conta a precoce.

alter table public.matches add column if not exists counts_stats boolean not null default true;

create or replace function public.fraiha_record_ranked_match(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  w record; b record; mid uuid;
  wr text := case p->>'result' when 'white' then 'win' when 'black' then 'loss' else 'draw' end;
  br text := case p->>'result' when 'black' then 'win' when 'white' then 'loss' else 'draw' end;
  k int := case when coalesce((p->>'count_stats')::boolean, true) then 1 else 0 end;   -- R173
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
    matches = matches + k, wins = wins + k * (wr = 'win')::int, losses = losses + k * (wr = 'loss')::int, draws = draws + k * (wr = 'draw')::int,
    highest_league = greatest(highest_league, (p->>'white_league_after')::int), updated_at = now(),
    forca = coalesce((p->>'white_forca_after')::real, forca), forca_rd = coalesce((p->>'white_forca_rd_after')::real, forca_rd)
  where user_id = w.user_id and mode = w.mode;
  update public.ranked_stats set
    league = (p->>'black_league_after')::int, pl = (p->>'black_pl_after')::int,
    matches = matches + k, wins = wins + k * (br = 'win')::int, losses = losses + k * (br = 'loss')::int, draws = draws + k * (br = 'draw')::int,
    highest_league = greatest(highest_league, (p->>'black_league_after')::int), updated_at = now(),
    forca = coalesce((p->>'black_forca_after')::real, forca), forca_rd = coalesce((p->>'black_forca_rd_after')::real, forca_rd)
  where user_id = b.user_id and mode = b.mode;
  insert into public.matches (match_id, mode, white_user_id, black_user_id, started_at, finished_at, result, result_reason,
    white_pl_before, black_pl_before, white_pl_change, black_pl_change, white_pl_after, black_pl_after,
    white_league_before, black_league_before, white_league_after, black_league_after, moves, counts_stats)
  values (coalesce((p->>'match_id')::uuid, gen_random_uuid()), p->>'mode', w.user_id, b.user_id,
    (p->>'started_at')::timestamptz, (p->>'finished_at')::timestamptz, p->>'result', p->>'result_reason',
    (p->>'white_pl_before')::int, (p->>'black_pl_before')::int, (p->>'white_pl_change')::int, (p->>'black_pl_change')::int,
    (p->>'white_pl_after')::int, (p->>'black_pl_after')::int,
    (p->>'white_league_before')::int, (p->>'black_league_before')::int, (p->>'white_league_after')::int, (p->>'black_league_after')::int,
    coalesce(p->>'moves',''), k = 1)
  returning match_id into mid;
  return mid;
end $$;
revoke all on function public.fraiha_record_ranked_match(jsonb) from public, anon, authenticated;
grant execute on function public.fraiha_record_ranked_match(jsonb) to service_role;
