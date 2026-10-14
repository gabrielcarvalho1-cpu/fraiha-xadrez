-- R100 · EXCLUIR CONTA: libera o login para a pessoa voltar do zero (mesmo e-mail ou mesmo Google).
--
-- A exclusão (R97) anonimiza o perfil e bloqueia o usuário antigo do Supabase Auth, mas a identidade do Google
-- continuava presa a ele: entrar de novo com o mesmo Google caía no usuário bloqueado ("User is banned"), e os
-- dados do Google (nome, foto, id da conta Google) ficavam em auth.users.raw_user_meta_data.
--
-- Esta função, chamada SÓ pelo servidor (service_role) logo depois da exclusão:
--   1. apaga as identidades de login (auth.identities) do usuário antigo → o próximo login com o mesmo
--      Google/e-mail cria um usuário NOVO e limpo;
--   2. limpa raw_user_meta_data (nome, foto e id do Google).
-- Trava de segurança: só age em conta já marcada como excluída (profiles.account_status = 'deleted').
-- O usuário antigo continua existindo (anonimizado e bloqueado) só para segurar o histórico de partidas
-- e os registros de pagamento.
--
-- Não destrutivo para contas ativas. Idempotente.

create or replace function public.fraiha_release_deleted_auth(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  n_ident integer := 0;
begin
  if not exists (select 1 from public.profiles where user_id = p_user and account_status = 'deleted') then
    raise exception 'conta não está excluída' using errcode = 'P0001';
  end if;
  delete from auth.identities where user_id = p_user;
  get diagnostics n_ident = row_count;
  update auth.users set raw_user_meta_data = '{}'::jsonb where id = p_user;
  return jsonb_build_object('identities_removed', n_ident);
end;
$$;

revoke all on function public.fraiha_release_deleted_auth(uuid) from public, anon, authenticated;
grant execute on function public.fraiha_release_deleted_auth(uuid) to service_role;
