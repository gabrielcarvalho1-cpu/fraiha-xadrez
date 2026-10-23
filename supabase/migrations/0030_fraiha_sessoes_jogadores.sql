-- FRAIHA Xadrez — 0030: SESSÕES DOS JOGADORES (Admin → Sessões) (R180).
-- ADITIVA. Aplicar no SQL Editor ANTES de publicar o servidor R180 (sem a tabela o servidor R180 funciona igual,
-- mas as sessões ficam só na memória e somem quando o Render reinicia).
--
-- public.player_sessions: uma linha por visita ao jogo (conta ou convidado): início, fim, duração, a tela onde a
-- pessoa estava ao sair, aparelho (celular/computador, navegador, tamanho da tela) e a linha do tempo (telas por onde
-- passou + ações: fila, convite, compra, mensagem no chat — SEM o texto das mensagens).
-- Guardado por 30 dias (o servidor apaga as mais antigas de hora em hora). Excluir a conta apaga as sessões dela.
-- Só o servidor (service_role) lê e escreve: RLS ligado e nenhuma política para anon/authenticated.
--
-- Reverter:
--   drop table if exists public.player_sessions;

create table if not exists public.player_sessions (
  session_id    uuid primary key,
  player        text not null,                 -- uuid da conta ou guest:<uuid>
  user_id       uuid,                          -- null para convidado
  nickname      text not null default '',
  kind          text not null default 'account' check (kind in ('account', 'new_account', 'guest', 'guest_new')),
  started_at    timestamptz not null,
  ended_at      timestamptz,
  last_seen_at  timestamptz not null,
  duration_s    integer not null default 0,
  last_screen   text not null default '',
  device        jsonb not null default '{}'::jsonb,
  events        jsonb not null default '[]'::jsonb,
  updated_at    timestamptz not null default now()
);
create index if not exists player_sessions_started on public.player_sessions (started_at desc);
create index if not exists player_sessions_user on public.player_sessions (user_id, started_at desc);
alter table public.player_sessions enable row level security;
revoke all on table public.player_sessions from anon, authenticated;
