-- FRAIHA Xadrez — 0022: NOVIDADES (R161). O que o dono publica no Admin → Novidades:
--   atualização, notícia, campeonato, evento (aparecem na tela NOVIDADES do jogo, em abas) e
--   'banner' = frase do OUTDOOR embaixo da logo da Home (a faixa "ESTRATÉGIA PARA IR MAIS LONGE").
-- ADITIVA: só cria uma tabela nova. Sem ela o jogo funciona (o outdoor mostra a frase original).
-- Leitura e escrita SÓ pelo servidor (service_role); o jogo lê pelo servidor (GET /news).
--
-- Reverter:
--   drop table if exists public.news_items;

create table if not exists public.news_items (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('atualizacao', 'noticia', 'campeonato', 'evento', 'banner')),
  title         text not null check (char_length(title) between 2 and 90),
  body          text not null default '' check (char_length(body) <= 4000),
  button_label  text not null default '' check (char_length(button_label) <= 30),
  button_action text not null default '' check (char_length(button_action) <= 300),
  pinned        boolean not null default false,
  published     boolean not null default true,
  published_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists news_items_pub on public.news_items (published, published_at desc);
alter table public.news_items enable row level security;
revoke all on table public.news_items from anon, authenticated;
grant select, insert, update, delete on table public.news_items to service_role;
