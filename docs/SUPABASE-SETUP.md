# Supabase — o que configurar (contas FRAIHA)

1. **Criar projeto** em supabase.com (região São Paulo). Guardar a senha do banco.
2. **Banco**: SQL Editor → New query → colar `supabase/migrations/0001_fraiha_accounts_ranked.sql` → Run.
3. **Authentication → URL Configuration**
   - Site URL: `https://jogar.fraihaxadrez.com`
   - Redirect URLs: `https://jogar.fraihaxadrez.com/**` e `http://127.0.0.1:8129/**` (teste local)
4. **Authentication → Providers → Email**: ligado. "Confirm email" pode ficar ligado (o jogo avisa para confirmar).
   Para produção, configure SMTP próprio (o e-mail padrão do Supabase tem limite baixo por hora).
5. **Google**: no Google Cloud Console → APIs & Services → Credentials → OAuth client ID (Web application).
   - Authorized JavaScript origins: `https://jogar.fraihaxadrez.com`
   - Authorized redirect URI: `https://<SEU-PROJETO>.supabase.co/auth/v1/callback`
   - Copiar Client ID e Client Secret para Supabase → Authentication → Providers → Google.
6. **Chaves** (Project Settings → API Keys):
   - Chave **publicável** (`sb_publishable_…` ou `anon`) + URL do projeto → `online.cfg` seção `[accounts]` (vai no jogo; é pública).
   - Chave **secreta** (`sb_secret_…` ou `service_role`) → SOMENTE no Render, variáveis:
     `SUPABASE_URL`, `SUPABASE_SECRET_KEY`. Nunca no Godot, no repositório ou no navegador.
7. Sem essas variáveis o servidor responde "Contas ainda não configuradas" e o jogo segue como convidado.
   `FRAIHA_DEV_AUTH=1` / `FRAIHA_DEV_STORE=memory` são apenas para teste local (nada é salvo).

## Estado atual (projeto real)

- Projeto: `fraiha-xadrez` (org FRAIHA, plano Free), região São Paulo (sa-east-1).
- Project URL: `https://xbdkrrbppbhpufplnsbw.supabase.co` — já em `online.cfg`.
- Publishable key: já em `online.cfg` (pública, protegida por RLS).
- Migration 0001 aplicada; verificado: RLS ativo nas 3 tabelas, cliente só lê,
  cliente não executa `fraiha_record_ranked_match`, servidor (service_role) escreve, trigger das 4 modalidades.
- Auth: e-mail/senha ativo, "Confirm email" ativo, senha mínima 8.
- Site URL `https://jogar.fraihaxadrez.com`; Redirect URLs: jogo + `127.0.0.1:8129` + `localhost:8129`.

## Staging (29/09/2026)
- Render `fraiha-xadrez-staging` (Free, branch `dev/web-alpha`): `wss://fraiha-xadrez-staging.onrender.com`.
  Env: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable), `SUPABASE_SECRET_KEY` (sb_secret_, inserida pelo dono).
  Atenção: publishable no lugar da secret = "permission denied for table profiles" (papel anon).
- Validado com e-mail: login, nickname, profiles + 4 ranked_stats, Ranked 3min e 5min, desistência, matches e PL.
- Cliente nativo contra staging: `_entrega_staging/ABRIR-CLIENTE-STAGING.cmd` (FRAIHA_SERVER_URL, sem mudar arquivos).

## Google Auth (auditoria 29/09/2026): código pronto, sem alteração
- Botão: `account/account_ui.gd` (CONTINUAR COM GOOGLE) → `account_service.sign_in_google()`.
- Redirect: `/auth/v1/authorize?provider=google&redirect_to=<site_url>`; `site_url` vazio no online.cfg → na Web usa
  `location.origin + pathname` (ex.: `http://127.0.0.1:8129/`, coberto pela allowlist).
- Retorno: `_adopt_redirect_session()` lê `#access_token/refresh_token` (fluxo implícito), limpa a URL, busca
  `/auth/v1/user`, salva o refresh token (user://) e autentica no servidor (`acct_auth`).
- Sem profile → servidor responde `needs_nickname` → tela de nome → `acct_create_profile` (mesmo caminho do e-mail).
- Já cadastrado → `acct_state` com profile → entra direto. `fraiha_after_login` volta para a Ranked.
- Nativo: mensagem "disponível na versão Web".
- Para testar: build Web com `server_url` do staging SÓ no pacote de teste, servido em `127.0.0.1:8129`.
- TESTADO E APROVADO (29/09/2026, build local de staging `_entrega_google_web`): login Google na Web, retorno ao jogo,
  conta existente reconhecida, conta Google nova com nickname, profile + 4 ranked_stats criados.

## Pendente
1. Teste de reconexão da Ranked (ainda não feito).
2. SMTP próprio antes do lançamento público.
3. Remover as Redirect URLs locais antes do lançamento; publicar o app Google (sair de "Testando").
4. Produção: só apontar para o backend novo depois de validar o staging.
