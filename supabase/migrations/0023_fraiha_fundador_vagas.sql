-- FRAIHA Xadrez — 0023 (R171 · SEC-009): LIMITE DE VAGAS DO FUNDADOR ATÔMICO.
-- ADITIVA. Aplicar no SQL Editor IMEDIATAMENTE ANTES de publicar o servidor R171b. Com ela e o servidor antigo (R170)
-- ainda no ar, Club/compras normais seguem iguais, mas a ENTREGA de Fundador fica em espera (fechada, sem perda: o
-- pagamento continua pendente e é entregue quando o servidor novo configurar o limite) — ver "NASCE FECHADA" abaixo.
--
-- Problema (auditoria): o limite FRAIHA_FOUNDER_LIMIT só era contado ao CRIAR o pedido; a entrega (fraiha_pay_and_grant)
-- não conferia vagas. Dois pedidos abertos com 1 vaga restante, pagos juntos, viravam 2 Fundadores.
--
-- Solução (tudo dentro do banco, numa transação, serializado por um lock):
--   founder_capacity   1 linha com o limite (o servidor grava o valor de FRAIHA_FOUNDER_LIMIT; 0 = sem limite).
--                      Toda reserva e toda entrega de Fundador trava ESTA linha (FOR UPDATE): uma de cada vez.
--   reserva            ao criar um pedido de Fundador (fraiha_founder_reserve) a vaga fica guardada por um tempo
--                      (payments.seat_hold_until, padrão 30 min = validade do PIX). Ocupadas = Fundadores atuais
--                      + reservas vivas de quem ainda não é Fundador. Sem vaga → o pedido nem é criado.
--   entrega            fraiha_pay_and_grant trava o pagamento (repetições/webhook duplicado esperam e saem sem efeito)
--                      e, para Fundador, trava a capacidade e confere de novo: Fundadores atuais + reservas vivas de
--                      OUTRAS pessoas. Se não couber, o pagamento vira 'sold_out' (pago, SEM vantagem, precisa de
--                      reembolso) — nunca 'paid' sem entrega e nunca Fundador além do limite.
--   upgrade            quem já é Fundador (ex.: Fundador → Lendário) não ocupa vaga nova.
--   reconciliação      fraiha_grant_paid_missing aplica a mesma regra.
-- Garantia: Fundadores (is_founder) entregues por pagamento <= founder_capacity.seat_limit, em qualquer ordem/concorrência.
-- R171b · NASCE FECHADA (reteste Orca): a capacidade começa "não configurada" (configured=false). Enquanto o servidor
-- não gravar o limite (fraiha_founder_set_limit, chamado ao iniciar), NENHUMA entrega/reserva de Fundador acontece:
-- fraiha_pay_and_grant levanta erro (o pagamento continua 'pending' e o aviso é repetido depois) e a reconciliação
-- pula os Fundadores. Assim não existe janela de boot em que o limite valha 0 (= sem limite) por engano.
-- Consequência prática: aplique a 0023 junto com a publicação do servidor R171b (o servidor antigo nunca configura;
-- entregas de Fundador ficam em espera — sem perda — até o servidor novo subir).
-- (Concessão manual pelo Admin continua sendo decisão do dono e não passa por aqui.)
--
-- Reverter:
--   drop function if exists public.fraiha_founder_reserve(uuid, text, text, text, text, integer, integer, integer);
--   drop function if exists public.fraiha_founder_set_limit(integer);
--   drop function if exists public.fraiha_founder_taken(uuid);
--   (fraiha_pay_and_grant / fraiha_grant_paid_missing voltam reaplicando a 0012)
--   alter table public.payments drop column if exists seat_hold_until;
--   drop table if exists public.founder_capacity;
--   (status: reaplicar a constraint sem 'sold_out' só se não houver linhas 'sold_out')

alter table public.payments drop constraint if exists payments_status_check;
alter table public.payments add constraint payments_status_check
  check (status in ('pending', 'paid', 'failed', 'refunded', 'cancelled', 'sold_out'));
alter table public.payments add column if not exists seat_hold_until timestamptz;
create index if not exists payments_founder_hold_idx on public.payments (seat_hold_until)
  where status = 'pending' and product_id in ('founder', 'founder_legend');

create table if not exists public.founder_capacity (
  id          smallint primary key default 1 check (id = 1),
  seat_limit  integer not null default 0 check (seat_limit >= 0),
  configured  boolean not null default false,   -- R171b: false = servidor ainda não gravou o limite → Fundador FECHADO
  updated_at  timestamptz not null default now()
);
alter table public.founder_capacity add column if not exists configured boolean not null default false;
insert into public.founder_capacity (id) values (1) on conflict (id) do nothing;
alter table public.founder_capacity enable row level security;
revoke all on public.founder_capacity from anon, authenticated;

-- vagas ocupadas agora: Fundadores atuais + reservas vivas de quem ainda não é Fundador (exceto p_except_user)
create or replace function public.fraiha_founder_taken(p_except_user uuid)
returns integer language sql stable security definer set search_path = public as $$
  select (select count(*) from public.entitlements where is_founder)::integer
       + (select count(distinct p.user_id) from public.payments p
           where p.status = 'pending' and p.product_id in ('founder', 'founder_legend')
             and p.seat_hold_until is not null and p.seat_hold_until > now()
             and p.user_id is distinct from p_except_user
             and not exists (select 1 from public.entitlements e where e.user_id = p.user_id and e.is_founder))::integer
$$;

-- o servidor grava o limite configurado (FRAIHA_FOUNDER_LIMIT) ao iniciar e a cada reserva
create or replace function public.fraiha_founder_set_limit(p_limit integer)
returns integer language plpgsql security definer set search_path = public as $$
begin
  update public.founder_capacity set seat_limit = greatest(0, coalesce(p_limit, 0)), configured = true, updated_at = now() where id = 1;
  return greatest(0, coalesce(p_limit, 0));
end $$;

-- cria o pedido de Fundador SÓ se houver vaga, guardando a vaga por p_hold_s segundos
create or replace function public.fraiha_founder_reserve(p_user uuid, p_product text, p_method text, p_provider text,
  p_ref text, p_amount integer, p_limit integer, p_hold_s integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  cap public.founder_capacity%rowtype;
  already boolean;
  taken integer;
begin
  if p_product not in ('founder', 'founder_legend') then raise exception 'product_invalid:%', p_product; end if;
  update public.founder_capacity set seat_limit = greatest(0, coalesce(p_limit, 0)), configured = true, updated_at = now() where id = 1;
  select * into cap from public.founder_capacity where id = 1 for update;   -- uma reserva/entrega de cada vez
  select coalesce(bool_or(is_founder), false) into already from public.entitlements where user_id = p_user;
  if not already and cap.seat_limit > 0 then
    taken := public.fraiha_founder_taken(p_user);
    if taken >= cap.seat_limit then
      return jsonb_build_object('ok', false, 'reason', 'sold_out', 'taken', taken, 'limit', cap.seat_limit);
    end if;
  end if;
  insert into public.payments (user_id, product_id, method, provider, provider_ref, amount_cents, status, seat_hold_until)
  values (p_user, p_product, p_method, p_provider, p_ref, p_amount, 'pending',
          case when already then null else now() + make_interval(secs => greatest(60, coalesce(p_hold_s, 1800))) end);
  return jsonb_build_object('ok', true, 'already_founder', already);
end $$;

-- paga E entrega numa transação; para Fundador confere a vaga sob lock (substitui a versão da 0012)
create or replace function public.fraiha_pay_and_grant(p_provider text, p_ref text, p_source text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  pay public.payments%rowtype;
  cap public.founder_capacity%rowtype;
  already boolean;
begin
  -- trava o pedido: webhook duplicado / JÁ PAGUEI / reconciliação ao mesmo tempo esperam aqui e saem sem efeito
  select * into pay from public.payments where provider = p_provider and provider_ref = p_ref for update;
  if not found or pay.status <> 'pending' then return null; end if;
  if pay.product_id in ('founder', 'founder_legend') then
    select * into cap from public.founder_capacity where id = 1 for update;   -- serializa TODAS as entregas de Fundador
    -- R171b: limite ainda não configurado pelo servidor → não entrega (erro = transação desfeita, pedido segue pendente)
    if not found or not cap.configured then
      raise exception 'founder_capacity_not_configured' using errcode = 'P0001';
    end if;
    select coalesce(bool_or(is_founder), false) into already from public.entitlements where user_id = pay.user_id;
    if not already and coalesce(cap.seat_limit, 0) > 0 and public.fraiha_founder_taken(pay.user_id) >= cap.seat_limit then
      update public.payments set status = 'sold_out', paid_at = now() where payment_id = pay.payment_id;
      return jsonb_build_object('payment_id', pay.payment_id, 'user_id', pay.user_id, 'product_id', pay.product_id,
        'status', 'sold_out', 'amount_cents', pay.amount_cents);
    end if;
  end if;
  update public.payments set status = 'paid', paid_at = now(), seat_hold_until = null where payment_id = pay.payment_id;
  perform public.fraiha_grant_entitlement(pay.user_id, pay.product_id, p_source);
  update public.payments set granted_at = now() where payment_id = pay.payment_id;
  return jsonb_build_object('payment_id', pay.payment_id, 'user_id', pay.user_id, 'product_id', pay.product_id, 'status', 'paid');
end $$;

-- reconciliação (pagos sem vantagem): mesma regra de vagas
create or replace function public.fraiha_grant_paid_missing()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r record; n integer := 0; s integer := 0;
  cap public.founder_capacity%rowtype;
  already boolean;
begin
  for r in select payment_id, user_id, product_id, provider from public.payments
            where status = 'paid' and granted_at is null for update skip locked loop
    if r.product_id in ('founder', 'founder_legend') then
      select * into cap from public.founder_capacity where id = 1 for update;
      if not found or not cap.configured then continue; end if;   -- R171b: sem limite configurado, Fundador espera
      select coalesce(bool_or(is_founder), false) into already from public.entitlements where user_id = r.user_id;
      if not already and coalesce(cap.seat_limit, 0) > 0 and public.fraiha_founder_taken(r.user_id) >= cap.seat_limit then
        update public.payments set status = 'sold_out' where payment_id = r.payment_id;
        s := s + 1;
        continue;
      end if;
    end if;
    perform public.fraiha_grant_entitlement(r.user_id, r.product_id, r.provider);
    update public.payments set granted_at = now() where payment_id = r.payment_id;
    n := n + 1;
  end loop;
  return jsonb_build_object('granted', n, 'sold_out', s);
end $$;

revoke all on function public.fraiha_founder_taken(uuid) from public, anon, authenticated;
grant execute on function public.fraiha_founder_taken(uuid) to service_role;
revoke all on function public.fraiha_founder_set_limit(integer) from public, anon, authenticated;
grant execute on function public.fraiha_founder_set_limit(integer) to service_role;
revoke all on function public.fraiha_founder_reserve(uuid, text, text, text, text, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.fraiha_founder_reserve(uuid, text, text, text, text, integer, integer, integer) to service_role;
revoke all on function public.fraiha_pay_and_grant(text, text, text) from public, anon, authenticated;
grant execute on function public.fraiha_pay_and_grant(text, text, text) to service_role;
revoke all on function public.fraiha_grant_paid_missing() from public, anon, authenticated;
grant execute on function public.fraiha_grant_paid_missing() to service_role;
