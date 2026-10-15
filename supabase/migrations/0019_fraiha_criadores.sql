-- FRAIHA Xadrez — 0019: CÓDIGO DE CRIADOR ("Apoie um Criador", R121). ADITIVA.
-- Sem ela o jogo funciona normalmente; só o campo do código de criador aparece indisponível.
--
-- 1) public.creators: os criadores parceiros (cadastrados no FRAIHA Admin). code em MAIÚSCULAS (3–20 letras/números),
--    pct = comissão sobre cada compra (padrão 10%), gift_crowns = presente para quem usa o código pela 1ª vez.
-- 2) public.creator_links: qual criador cada jogador apoia agora (um por vez; vale 30 dias e renova ao digitar de novo).
-- 3) public.creator_sales: uma linha por COMPRA PAGA feita por quem apoiava um criador: valor, comissão e situação
--    (due = a pagar, paid = paga ao criador, cancelled = compra reembolsada antes de pagar). A compra (payment_ref)
--    nunca entra duas vezes.
-- Só o servidor (service_role) lê e escreve.
--
-- Reverter:
--   drop table if exists public.creator_sales; drop table if exists public.creator_links; drop table if exists public.creators;

create table if not exists public.creators (
  code         text primary key check (code ~ '^[A-Z0-9]{3,20}$'),
  name         text not null,
  pct          integer not null default 10 check (pct between 0 and 50),
  gift_crowns  integer not null default 200 check (gift_crowns between 0 and 5000),
  contact      text not null default '',
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table if not exists public.creator_links (
  user_id     uuid primary key,
  code        text not null references public.creators (code) on update cascade,
  linked_at   timestamptz not null default now(),
  expires_at  timestamptz not null
);
create index if not exists creator_links_code on public.creator_links (code);

create table if not exists public.creator_sales (
  payment_ref       text primary key,
  code              text not null references public.creators (code) on update cascade,
  user_id           uuid not null,
  product_id        text not null,
  amount_cents      integer not null check (amount_cents >= 0),
  commission_cents  integer not null check (commission_cents >= 0),
  status            text not null default 'due' check (status in ('due', 'paid', 'cancelled', 'refunded_after_paid')),
  created_at        timestamptz not null default now(),
  paid_at           timestamptz,
  paid_note         text not null default ''
);
create index if not exists creator_sales_code on public.creator_sales (code, status, created_at desc);

alter table public.creators enable row level security;
alter table public.creator_links enable row level security;
alter table public.creator_sales enable row level security;
revoke all on table public.creators, public.creator_links, public.creator_sales from anon, authenticated;
grant select, insert, update on table public.creators, public.creator_links, public.creator_sales to service_role;
