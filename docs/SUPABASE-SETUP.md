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
