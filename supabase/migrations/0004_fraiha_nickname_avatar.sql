-- FRAIHA Xadrez — 0004: nickname público (único, troca a cada 30 dias) + foto de perfil.
-- ADITIVA e segura: não apaga nem reescreve dados existentes.
-- NÃO aplicar automaticamente: staging e produção usam o MESMO projeto Supabase.
-- Revisar e executar manualmente no SQL Editor quando aprovado.

-- 1) Colunas novas em profiles (evolui a tabela existente; nada de segunda tabela de perfil).
alter table public.profiles
  add column if not exists nickname_changed_at timestamptz,          -- última escolha/troca do nome
  add column if not exists avatar_url          text,                 -- foto no Storage (bucket avatars); null = avatar padrão (avatar_id)
  add column if not exists avatar_updated_at   timestamptz;

-- Coluna normalizada (minúsculas) só para leitura/relatórios; a unicidade continua garantida
-- pelo índice único profiles_nickname_unique em lower(nickname) criado na 0001.
alter table public.profiles
  add column if not exists nickname_normalized text generated always as (lower(nickname)) stored;
create unique index if not exists profiles_nickname_normalized_unique on public.profiles (nickname_normalized);

-- 2) Regra do nome: 3 a 20 caracteres. O conjunto de caracteres continua um SUPERCONJUNTO do
-- antigo (letras, números, _ . - e acentos) para não invalidar nomes já existentes; nomes NOVOS
-- ou trocados passam pela regra estrita do servidor (apenas letras, números e _).
alter table public.profiles drop constraint if exists nickname_format;
alter table public.profiles add constraint nickname_format check (
  char_length(nickname) between 3 and 20
  and nickname ~ '^[A-Za-z0-9_.À-ÖØ-öø-ÿ-]+$'
);

-- 3) Troca de nome com cooldown de 30 dias decidido pelo RELÓGIO DO BANCO (now()).
-- Chamada só pelo servidor Node (service_role). Retorna o perfil atualizado.
create or replace function public.fraiha_change_nickname(p_user uuid, p_nick text)
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  cur public.profiles;
  next_at timestamptz;
begin
  select * into cur from public.profiles where user_id = p_user for update;
  if cur is null then raise exception 'profile_missing'; end if;
  if lower(cur.nickname) = lower(p_nick) and cur.nickname = p_nick then
    return cur;  -- nada mudou
  end if;
  next_at := coalesce(cur.nickname_changed_at, cur.created_at) + interval '30 days';
  if cur.nickname_changed_at is not null and now() < next_at then
    raise exception 'nickname_cooldown:%', to_char(next_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  end if;
  update public.profiles
     set nickname = p_nick, nickname_changed_at = now(), updated_at = now()
   where user_id = p_user
   returning * into cur;
  return cur;
exception
  when unique_violation then raise exception 'nickname_taken';
  when check_violation  then raise exception 'nickname_invalid';
end $$;

-- Disponibilidade (case-insensitive). Também só pelo servidor.
create or replace function public.fraiha_nickname_available(p_nick text, p_user uuid default null)
returns boolean language sql security definer set search_path = public as $$
  select not exists (
    select 1 from public.profiles
     where lower(nickname) = lower(p_nick) and (p_user is null or user_id <> p_user)
  );
$$;

revoke all on function public.fraiha_change_nickname(uuid, text) from public, anon, authenticated;
revoke all on function public.fraiha_nickname_available(text, uuid) from public, anon, authenticated;
grant execute on function public.fraiha_change_nickname(uuid, text) to service_role;
grant execute on function public.fraiha_nickname_available(text, uuid) to service_role;

-- 4) Foto de perfil: bucket público de leitura "avatars". Só o servidor (service_role) grava;
-- o arquivo é sempre <user_id>.webp (512x512, já recortado e comprimido pelo cliente e
-- revalidado pelo servidor). O cliente NUNCA recebe credencial de escrita.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 524288, array['image/webp','image/png','image/jpeg'])
on conflict (id) do nothing;

-- Leitura: o bucket é público, então as URLs /storage/v1/object/public/avatars/<id>.webp funcionam
-- SEM policy. Não criamos policy de SELECT em storage.objects de propósito: ela permitiria LISTAR
-- todos os arquivos do bucket (expondo os user_id). Sem policy de insert/update/delete para
-- anon/authenticated: só a service_role (servidor) grava e apaga.
