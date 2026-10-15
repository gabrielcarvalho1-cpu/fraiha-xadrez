-- FRAIHA Xadrez — 0013: denúncias guardadas no banco e suspensão de conta com prazo (R104).
-- ADITIVA. Aplicar no SQL Editor ANTES de publicar o servidor R104 (o servidor antigo continua funcionando com ela;
-- sem ela, o servidor R104 continua aceitando denúncias, mas só registra no log, e a suspensão fica indisponível).
--
-- 1) public.reports: cada denúncia feita no jogo (partida = chat e voz, conversa privada, perfil, CHAT GLOBAL),
--    com um trecho do contexto (mensagens recentes de quem foi denunciado) para a moderação analisar no Admin.
--    Só o servidor (service_role) lê e escreve: RLS ligado e nenhuma política para anon/authenticated.
-- 2) profiles.suspended_until / suspension_reason: conta suspensa ('suspended') não entra no jogo até o prazo
--    (suspended_until nulo = suspensão por tempo indeterminado). O próprio servidor volta a conta para 'active'
--    quando o prazo passa.
-- 3) Perfis deixam de ser legíveis por QUALQUER conta logada direto no Supabase (a 0001 liberava todos os perfis,
--    com configurações, último login e agora o motivo de suspensão). O jogo não lê perfis direto do banco:
--    tudo passa pelo servidor (service_role), que só mostra a parte pública. Cada conta continua lendo o próprio perfil.
--
-- Reverter:
--   drop table if exists public.reports;
--   alter table public.profiles drop column if exists suspended_until, drop column if exists suspension_reason;
--   drop policy if exists profiles_read on public.profiles;
--   create policy profiles_read on public.profiles for select to authenticated using (true);

create table if not exists public.reports (
  report_id   uuid primary key default gen_random_uuid(),
  reporter_id uuid not null,
  reported_id uuid not null,
  kind        text not null check (kind in ('match', 'dm', 'profile', 'global_chat')),
  ref         text not null default '',            -- partida, conversa ou mensagem de origem
  reason      text not null default '',
  context     jsonb not null default '{}'::jsonb,  -- nicknames e mensagens recentes de quem foi denunciado
  status      text not null default 'open' check (status in ('open', 'dismissed', 'actioned')),
  handled_by  text,
  handled_at  timestamptz,
  note        text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists reports_status_created on public.reports (status, created_at desc);
create index if not exists reports_reported on public.reports (reported_id, created_at desc);
alter table public.reports enable row level security;
revoke all on table public.reports from anon, authenticated;

alter table public.profiles add column if not exists suspended_until timestamptz;
alter table public.profiles add column if not exists suspension_reason text;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (auth.uid() = user_id);
