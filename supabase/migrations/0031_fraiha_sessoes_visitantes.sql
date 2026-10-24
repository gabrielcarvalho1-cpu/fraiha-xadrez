-- FRAIHA Xadrez — 0031: SESSÕES DE VISITANTES + FUNIL (Admin → Sessões / Funil) (R181).
-- ADITIVA. Pode ser aplicada antes ou depois de publicar o servidor R181:
--   · sem ela, o servidor R181 continua gravando as sessões (sem as colunas novas; visitante entra como 'guest');
--   · com ela, o painel mostra quem veio do anúncio (utm), o funil por dia e quem voltou outro dia.
--
-- O que muda em public.player_sessions (0030):
--   · vid   : código ALEATÓRIO do navegador (gerado no próprio navegador, sem dado pessoal) → "voltou outro dia";
--   · utm   : {source, campaign, medium, ad} lidos da URL de entrada (anúncio);
--   · flags : {loaded, passed, played} → etapas do funil (carregou / passou da tela de entrada / jogou 1 partida);
--   · kind  : aceita também 'visitor' (abriu o jogo e ainda não entrou como convidado nem na conta).
-- Continua: só o servidor (service_role) lê e escreve; RLS ligado; guardado 30 dias.
--
-- Reverter:
--   alter table public.player_sessions drop column if exists vid, drop column if exists utm, drop column if exists flags;
--   delete from public.player_sessions where kind = 'visitor';
--   alter table public.player_sessions drop constraint if exists player_sessions_kind_check;
--   alter table public.player_sessions add constraint player_sessions_kind_check
--     check (kind in ('account', 'new_account', 'guest', 'guest_new'));

alter table public.player_sessions add column if not exists vid   text;
alter table public.player_sessions add column if not exists utm   jsonb not null default '{}'::jsonb;
alter table public.player_sessions add column if not exists flags jsonb not null default '{}'::jsonb;

alter table public.player_sessions drop constraint if exists player_sessions_kind_check;
alter table public.player_sessions add constraint player_sessions_kind_check
  check (kind in ('account', 'new_account', 'guest', 'guest_new', 'visitor'));

-- vid: só letras/números (o servidor já valida; aqui é a segunda trava)
alter table public.player_sessions drop constraint if exists player_sessions_vid_check;
alter table public.player_sessions add constraint player_sessions_vid_check
  check (vid is null or vid ~ '^[0-9a-f]{32}$');

create index if not exists player_sessions_vid on public.player_sessions (vid, started_at desc);

-- conferência (deve listar as 3 colunas novas)
select column_name, data_type from information_schema.columns
 where table_schema = 'public' and table_name = 'player_sessions' and column_name in ('vid', 'utm', 'flags');
