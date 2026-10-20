-- FRAIHA Xadrez — 0024 (R171b · SEC-008, reteste Orca): A MESMA PARTIDA CONTRA BOT VALE PARA UMA CONTA SÓ.
-- ADITIVA. Antes: o servidor lembrava as partidas já usadas só na memória — depois de reiniciar (ou com outra
-- instância) a mesma partida (lances idênticos) podia liberar o bot para outra conta.
-- Agora: bot_progress guarda o resumo da partida (game_hash = sha256(bot + lances)) com índice ÚNICO.
--   • a 1ª vitória de cada (conta, bot) grava o game_hash;
--   • outra conta enviando a mesma partida → o servidor encontra o dono no banco e recusa (bot_game_reused);
--   • duas contas ao mesmo tempo → o índice único deixa só uma gravar (a outra recebe 23505 → recusada).
-- Linhas antigas ficam com game_hash nulo (o índice ignora nulos). Nenhum dado existente muda.
-- Reverter: drop index if exists public.bot_progress_game_hash_uq; alter table public.bot_progress drop column if exists game_hash;

alter table public.bot_progress add column if not exists game_hash text;
alter table public.bot_progress drop constraint if exists bot_progress_game_hash_fmt;
alter table public.bot_progress add constraint bot_progress_game_hash_fmt check (game_hash is null or game_hash ~ '^[0-9a-f]{64}$');
create unique index if not exists bot_progress_game_hash_uq on public.bot_progress (game_hash) where game_hash is not null;
