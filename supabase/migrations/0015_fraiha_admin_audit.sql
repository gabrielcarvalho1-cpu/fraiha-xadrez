-- FRAIHA Xadrez — 0015: Admin Log gravado no banco (R110).
-- ADITIVA. Pode ser aplicada antes ou depois de publicar o servidor R110: sem ela o Admin Log continua só na
-- memória (some quando o servidor reinicia), como hoje.
--
-- public.admin_audit: cada ação real feita no FRAIHA Admin (ligar/desligar filas, Clube/Fundador, conferir
-- pagamentos, denúncias, suspensões) — quem, o quê, quando, alvo, antes/depois, resultado e motivo.
-- Sem segredos ou tokens. Só o servidor (service_role) lê e escreve.
--
-- Reverter:
--   drop table if exists public.admin_audit;

create table if not exists public.admin_audit (
  id      uuid primary key,
  at      timestamptz not null default now(),
  actor   jsonb,
  action  text not null,
  target  jsonb,
  before  jsonb,
  after   jsonb,
  result  text not null default 'ok',
  reason  text not null default '',
  meta    jsonb
);
create index if not exists admin_audit_at on public.admin_audit (at desc);
create index if not exists admin_audit_action_at on public.admin_audit (action, at desc);
alter table public.admin_audit enable row level security;
revoke all on table public.admin_audit from anon, authenticated;
