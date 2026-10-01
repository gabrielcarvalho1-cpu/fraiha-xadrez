-- FRAIHA Xadrez — 0006: progresso da escada de bots (JOGAR CONTRA O COMPUTADOR).
-- NÃO APLICADA. Aplicar só com autorização explícita (staging e produção compartilham o banco).
--
-- O que faz:
--   • cria public.bot_progress: 1 linha por (conta, bot) = PRIMEIRA vitória válida contra aquele bot;
--   • os avatares desbloqueados NÃO são uma tabela: derivam desta (bot derrotado → recompensa do
--     bot/bot_ladder.json), então não há como "ganhar avatar" sem ter a vitória registrada;
--   • RLS ligado: o jogador só LÊ as próprias linhas; nenhum cliente (anon/authenticated) grava.
--     Quem grava é só o servidor Node (service_role), depois de refazer a partida com as regras
--     do servidor e conferir xeque-mate do lado do bot, na ordem da escada.
-- Impacto: aditivo. Não altera nem lê tabelas existentes além da FK para profiles.
-- Reverter: drop table public.bot_progress;

create table if not exists public.bot_progress (
  user_id      uuid        not null references public.profiles(user_id) on delete cascade,
  bot_id       text        not null,
  defeated_at  timestamptz not null default now(),
  plies        integer     not null default 0 check (plies between 0 and 600),
  human_color  text        not null default 'w' check (human_color in ('w','b')),
  primary key (user_id, bot_id),
  constraint bot_progress_bot_id check (bot_id in (
    'madeira','ferro','bronze','prata','ouro','platina','esmeralda','diamante','mestre','grande_mestre','challenger'))
);

alter table public.bot_progress enable row level security;

drop policy if exists bot_progress_read_own on public.bot_progress;
create policy bot_progress_read_own on public.bot_progress
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- Clientes não gravam (sem policies de insert/update/delete) e não têm privilégio de escrita.
revoke insert, update, delete on public.bot_progress from anon, authenticated;
grant select on public.bot_progress to authenticated;
