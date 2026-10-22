-- FRAIHA Xadrez — 0029: SUPORTE (tickets de reclamação, sugestão, dúvida, problema e pagamento) (R176.8).
-- ADITIVA. Aplicar no SQL Editor ANTES de publicar o servidor R176.8 (o servidor antigo ignora a tabela; sem ela,
-- o servidor R176.8 continua aceitando os tickets, mas só registra no log do Render e avisa o jogador que o suporte
-- está indisponível — nada se perde em silêncio).
--
-- public.support_tickets: cada mensagem enviada pelo jogo na tela SUPORTE. O dono lê e responde no Admin → Suporte;
-- a resposta aparece para o jogador em MEUS TICKETS (e chega na hora se ele estiver online).
-- Só o servidor (service_role) lê e escreve: RLS ligado e nenhuma política para anon/authenticated.
--
-- Reverter:
--   drop table if exists public.support_tickets;

create table if not exists public.support_tickets (
  ticket_id   uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  nickname    text not null default '',
  category    text not null check (category in ('reclamacao', 'sugestao', 'duvida', 'problema', 'pagamento')),
  subject     text not null default '' check (char_length(subject) <= 80),
  message     text not null check (char_length(message) between 5 and 2000),
  context     jsonb not null default '{}'::jsonb,   -- plataforma, versão do jogo, tela de origem
  status      text not null default 'open' check (status in ('open', 'answered', 'closed')),
  reply       text not null default '' check (char_length(reply) <= 2000),
  replied_by  text,
  replied_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists support_tickets_status_created on public.support_tickets (status, created_at desc);
create index if not exists support_tickets_user on public.support_tickets (user_id, created_at desc);
alter table public.support_tickets enable row level security;
revoke all on table public.support_tickets from anon, authenticated;
