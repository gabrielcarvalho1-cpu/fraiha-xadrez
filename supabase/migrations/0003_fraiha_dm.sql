-- FRAIHA Xadrez — Mensagens privadas (DM) entre amigos.
-- Aplicar no Supabase (SQL Editor) DEPOIS da 0001 e da 0002. Idempotente.
-- Sem DROP/DELETE/TRUNCATE: só cria o que ainda não existe. Não altera nenhuma tabela existente.
-- Escrita SOMENTE pelo servidor FRAIHA (service_role, secret key no Render); o servidor valida
-- amizade, bloqueio e tamanho. Clientes (authenticated) só LEEM as próprias conversas.

create table if not exists public.direct_messages (
  id           bigint generated always as identity primary key,
  sender_id    uuid not null references public.profiles(user_id) on delete cascade,
  recipient_id uuid not null references public.profiles(user_id) on delete cascade,
  body         text not null,
  created_at   timestamptz not null default now(),
  read_at      timestamptz,
  constraint direct_messages_not_self check (sender_id <> recipient_id),
  constraint direct_messages_body_len check (char_length(body) between 1 and 500)
);
-- Histórico da conversa (nos dois sentidos) e contagem de não lidas.
create index if not exists direct_messages_pair_idx on public.direct_messages (sender_id, recipient_id, id desc);
create index if not exists direct_messages_unread_idx on public.direct_messages (recipient_id, sender_id) where read_at is null;

-- RLS: leitura só das mensagens em que o usuário é remetente ou destinatário; nenhuma escrita para clientes.
alter table public.direct_messages enable row level security;
revoke all on public.direct_messages from anon, authenticated;
grant select on public.direct_messages to authenticated;
grant select, insert, update, delete on public.direct_messages to service_role;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'direct_messages' and policyname = 'direct_messages_read_own') then
    create policy direct_messages_read_own on public.direct_messages for select to authenticated
      using (auth.uid() = sender_id or auth.uid() = recipient_id);
  end if;
end $$;
