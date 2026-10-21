-- FRAIHA Xadrez — 0028 (R175E · pagamento): NO MÁXIMO UMA TENTATIVA DE CARTÃO ATIVA POR CONTA.
-- ADITIVA. Aplicar no SQL Editor ANTES de publicar o servidor R175E (sem ela o servidor novo NÃO envia cobrança de
-- cartão: falha fechado com "cartão temporariamente indisponível"; PIX e o resto do jogo seguem normais).
-- Numeração: 0026 é do Admin (ainda não aplicada) e 0027 está reservada (audit log). Esta é independente de ambas.
--
-- Problema (auditoria Orca da R175D): a tentativa de cartão era gravada no PEDIDO (payments.raw.card_attempt) com
-- compare-and-set por linha. Dois pedidos DIFERENTES da mesma conta (A e B), em duas instâncias ao mesmo tempo, cada
-- um gravava a sua tentativa na sua linha → 2 cobranças. E requisições que ficavam esperando (fila) cobravam depois
-- que a anterior terminava.
--
-- Solução:
--   card_charge_guard   1 linha por conta: geração (generation) que sobe a cada tentativa de cartão iniciada.
--                       Toda abertura de tentativa trava ESTA linha (FOR UPDATE): uma por conta de cada vez.
--   fraiha_card_guard_generation(user)
--                       o servidor lê a geração NO RECEBIMENTO do pedido de pagamento (antes de qualquer espera).
--   fraiha_card_attempt_begin(user, provider, ref, attempt, geração vista, recebido_em)
--                       porta ÚNICA para iniciar cobrança de cartão. Numa transação, com a conta travada:
--                         1. o pedido existe, é DESTA conta, é de cartão e está 'pending' (nada vem do cliente:
--                            valor, produto e dono saem do banco);
--                         2. nenhuma tentativa ativa/incerta em QUALQUER pedido da conta;
--                         3. requisição ANTIGA é recusada (mesmo que a outra tentativa já tenha terminado/aprovado):
--                            a) a geração atual é diferente da que o servidor leu ao receber o pedido, OU
--                            b) a última tentativa da conta começou depois de p_received_at (horário de recebimento no
--                               servidor) menos 2 s de margem para diferença de relógio servidor × banco. A leitura da
--                               geração é assíncrona (pode atrasar); o horário de recebimento cobre esse atraso.
--                            p_received_at mais de 2 s no futuro (relógio do servidor adiantado) → recusa (fail closed);
--                         4. grava a tentativa no pedido (raw.card_attempt + histórico) e sobe a geração.
--                       Só quem recebe ok=true pode enviar o POST ao Mercado Pago.
--   payments_one_card_attempt_per_user
--                       índice único parcial: invariante final — uma conta NUNCA tem duas linhas com tentativa de
--                       cartão ativa (pending/cancelled/failed com raw.card_attempt objeto), mesmo que alguma
--                       escrita contorne a função.
-- Liberação: a tentativa sai do pedido quando o Mercado Pago confirma recusa/cancelamento (o servidor limpa
-- raw.card_attempt com compare-and-set) ou quando o pedido vira paid/sold_out/refunded (sai do índice).
-- Compatível com 0023 (fraiha_pay_and_grant/reserva não mudam) e 0025.
--
-- Reverter:
--   drop function if exists public.fraiha_card_attempt_begin(uuid, text, text, text, bigint, timestamptz);
--   drop function if exists public.fraiha_card_guard_generation(uuid);
--   drop index if exists public.payments_one_card_attempt_per_user;
--   drop table if exists public.card_charge_guard;

-- segurança: não cria o índice por cima de dados que já violam a regra (aborta com mensagem clara)
do $chk$
declare dup record;
begin
  select user_id, count(*) as n into dup from public.payments
   where jsonb_typeof(raw -> 'card_attempt') = 'object' and status in ('pending', 'cancelled', 'failed')
   group by user_id having count(*) > 1 limit 1;
  if found then
    raise exception '0028: a conta % tem % tentativas de cartão ativas — reconcilie antes de aplicar', dup.user_id, dup.n;
  end if;
end $chk$;

create table if not exists public.card_charge_guard (
  user_id         uuid primary key references public.profiles(user_id) on delete cascade,
  generation      bigint not null default 0 check (generation >= 0),
  last_ref        text,
  last_attempt    text,
  last_started_at timestamptz,
  updated_at      timestamptz not null default now()
);
alter table public.card_charge_guard enable row level security;
revoke all on public.card_charge_guard from public, anon, authenticated;
grant select, insert, update, delete on public.card_charge_guard to service_role;

create unique index if not exists payments_one_card_attempt_per_user
  on public.payments (user_id)
  where jsonb_typeof(raw -> 'card_attempt') = 'object' and status in ('pending', 'cancelled', 'failed');

create or replace function public.fraiha_card_guard_generation(p_user uuid)
returns bigint language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select g.generation from public.card_charge_guard g where g.user_id = p_user), 0)::bigint
$$;

create or replace function public.fraiha_card_attempt_begin(p_user uuid, p_provider text, p_ref text, p_attempt text, p_seen_generation bigint,
  p_received_at timestamptz)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  g    public.card_charge_guard%rowtype;
  pay  public.payments%rowtype;
  busy public.payments%rowtype;
  cur  jsonb;
  rev  integer;
  att  jsonb;
begin
  if p_user is null or coalesce(p_ref, '') = '' or coalesce(p_provider, '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'bad_request');
  end if;
  if p_attempt is null or p_attempt !~ '^[0-9a-fA-F-]{36}$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_attempt');
  end if;
  if p_received_at is null or p_received_at > now() + interval '2 seconds' then   -- sem horário ou relógio adiantado: fail closed
    return jsonb_build_object('ok', false, 'reason', 'payment_in_progress', 'detail', 'received_at');
  end if;
  -- 1. exclusão por conta: a linha-guarda da conta (criada na primeira vez) fica travada até o fim da transação
  insert into public.card_charge_guard (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into g from public.card_charge_guard where user_id = p_user for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'bad_request'); end if;
  -- 2. o pedido: desta conta, cartão, aguardando (valores vêm do banco, nunca do cliente)
  select * into pay from public.payments where provider = p_provider and provider_ref = p_ref for update;
  if not found or pay.user_id is distinct from p_user then return jsonb_build_object('ok', false, 'reason', 'order_not_found'); end if;
  if pay.method is distinct from 'card' then return jsonb_build_object('ok', false, 'reason', 'order_not_card'); end if;
  if pay.status <> 'pending' then return jsonb_build_object('ok', false, 'reason', 'order_closed', 'status', pay.status); end if;
  -- 3. qualquer tentativa ativa/incerta em QUALQUER pedido da conta (mesmo vencido/cancelado) bloqueia
  select * into busy from public.payments
   where user_id = p_user and jsonb_typeof(raw -> 'card_attempt') = 'object' and status in ('pending', 'cancelled', 'failed')
   limit 1;
  if found then
    return jsonb_build_object('ok', false, 'reason', 'previous_attempt_unconfirmed', 'ref', busy.provider_ref);
  end if;
  -- 4. requisição antiga: outra tentativa começou depois que esta foi recebida → recusada (não cobra "acordando")
  if p_seen_generation is null or g.generation <> p_seen_generation then
    return jsonb_build_object('ok', false, 'reason', 'payment_in_progress', 'generation', g.generation);
  end if;
  if g.last_started_at is not null and g.last_started_at >= p_received_at - interval '2 seconds' then
    return jsonb_build_object('ok', false, 'reason', 'payment_in_progress', 'detail', 'started_after_received');
  end if;
  -- 5. grava a tentativa vencedora no pedido e sobe a geração da conta
  cur := case when jsonb_typeof(pay.raw) = 'object' then pay.raw else '{}'::jsonb end;
  rev := case when jsonb_typeof(cur -> 'rev') = 'number' then (cur ->> 'rev')::integer else 0 end;
  att := jsonb_build_object('id', p_attempt, 'state', 'inflight', 'at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
                            'by', p_user::text, 'generation', g.generation + 1);
  update public.payments
     set raw = cur || jsonb_build_object('card_attempt', att, 'rev', rev + 1,
                 'history', (case when jsonb_typeof(cur -> 'history') = 'array' then cur -> 'history' else '[]'::jsonb end)
                            || jsonb_build_array(jsonb_build_object('at', att -> 'at', 'event', 'card_attempt_started', 'attempt', p_attempt)))
   where payment_id = pay.payment_id;
  update public.card_charge_guard
     set generation = g.generation + 1, last_ref = p_ref, last_attempt = p_attempt, last_started_at = now(), updated_at = now()
   where user_id = p_user;
  -- 6. só o vencedor recebe autorização para o POST
  return jsonb_build_object('ok', true, 'generation', g.generation + 1, 'attempt', p_attempt, 'rev', rev + 1);
end $$;

revoke all on function public.fraiha_card_guard_generation(uuid) from public, anon, authenticated;
grant execute on function public.fraiha_card_guard_generation(uuid) to service_role;
revoke all on function public.fraiha_card_attempt_begin(uuid, text, text, text, bigint, timestamptz) from public, anon, authenticated;
grant execute on function public.fraiha_card_attempt_begin(uuid, text, text, text, bigint, timestamptz) to service_role;
