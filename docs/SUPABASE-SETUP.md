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

## Pendente
1. Google OAuth: CONFIGURADO. Projeto Google Cloud `fraiha-xadrez`; tela de consentimento Externa ("FRAIHA Xadrez",
   status Testando); domínios `fraihaxadrez.com` e `xbdkrrbppbhpufplnsbw.supabase.co` (o Google não aceita `supabase.co`);
   escopos openid/email/profile; cliente Web "FRAIHA Web (Supabase)" com origens do jogo e localhost:8129 e a callback
   do Supabase; provedor Google ativo no Supabase. Falta: adicionar Test users (Google Auth Platform > Público) ou
   publicar o app; teste completo de login pelo jogo (depende do servidor de staging).
2. Secret key: copiar SOMENTE para o Render de staging (`SUPABASE_URL`, `SUPABASE_SECRET_KEY`).
3. Staging no Render (precisa de `package.json` + branch no GitHub — aguardando autorização).
4. SMTP próprio antes do lançamento público.
5. Remover as Redirect URLs locais antes do lançamento.
