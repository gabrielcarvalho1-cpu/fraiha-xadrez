# FRAIHA Admin V1 — painel administrativo (primeira rodada)

Estado: **IMPLEMENTADO LOCALMENTE + TESTADO LOCAL** na branch `admin/v1` (worktree isolada, base `bb83f5f`).
Sem push, sem deploy, sem migration aplicada, produção intacta, Voice/Agora intacto.

## Arquitetura

```
FRAIHA Game (Godot Web/Windows)  ──WebSocket──►  servidor Node (online_v021, instância única no Render)
                                                  ├─ estado ao vivo em memória (online, filas, partidas, voz)
                                                  ├─ Supabase (service role SÓ aqui)
                                                  └─ /admin/api/*  ◄──HTTPS + Bearer──  FRAIHA Admin (app web separado: admin/)
```

- **Por que a API mora no mesmo processo do jogo:** o estado ao vivo (online, filas, partidas, voz) só existe
  na memória dessa instância (`numInstances: 1`). A API é um módulo isolado (`online_v021/admin/`) com
  rotas HTTP próprias, separadas do protocolo WebSocket do jogo. Se o jogo crescer para várias instâncias, a
  telemetria passa a ser publicada (ex.: `metric_samples`) e o Admin pode virar serviço próprio sem mudar o app.
- **App FRAIHA Admin** (`admin/`): HTML + ES modules, sem build e sem dependências; não faz parte do jogo
  (`admin/.gdignore` impede o Godot de importar/exportar). Hospedagem prevista: domínio próprio (ex.:
  `admin.fraihaxadrez.com`) atrás de Cloudflare Access (2ª camada), com a origem na allowlist do servidor.
- **Endereços de API fixos** em `admin/src/config.js` (local/staging/production). O Admin nunca aceita API
  vinda da URL (link malicioso não consegue mandar o token para outro servidor).

### Autoridade e permissões (servidor)
1. O admin entra com a **conta FRAIHA** (Supabase Auth, chave publicável). Em LOCAL, conta DEV (`FRAIHA_DEV_AUTH=1`).
2. Cada requisição leva `Authorization: Bearer <access_token>`; o servidor valida no Supabase Auth.
3. O servidor confere a allowlist **`FRAIHA_ADMIN_USERS`** (`<uuid>=owner,<uuid>=viewer`, variável de ambiente
   do servidor — só o NOME aqui). Sem a variável o Admin fica **desligado (503)**.
4. Papel → permissões (`owner`, `operator`, `viewer`); cada rota exige a sua (`queues.write` etc.).
   Pronto para virar tabela (`admin_users`, proposta 0011) sem mudar as rotas.
5. Ações reais passam pelo **Admin Log** antes de responder.

Variáveis do servidor (NOMES): `FRAIHA_ADMIN_USERS`, `FRAIHA_ADMIN_ORIGINS` (origens permitidas do Admin),
`FRAIHA_ENV` (`local|dev|staging|production`, mostrado em destaque no Admin).

## Inventário — o que o Admin mostra e de onde vem

| Dado | Classificação | Fonte / dependência |
| --- | --- | --- |
| Online agora (contas + convidados) | **REAL** | `backend.online` (memória) |
| Em partida / Home-Lobby / Em fila | **REAL** | partidas Ranked/Casual + mesas XEQUE/MARCHA + filas (memória) |
| Partidas ativas por modo, jogadores por modo | **REAL** | `ranked/casual.matches`, `party.rooms` |
| Fila por modo (quantos, maior espera agora) | **REAL** | `mm.queues` (`since` de cada entrada) |
| Usando Voice | **REAL** | `voice.present` |
| Usuários cadastrados / novos hoje | **REAL** | `profiles` (contagem via service role, sem e-mail) |
| Status ATIVO/DESATIVADO dos modos | **REAL** (novo) | `ModeControls` — memória; durável = MIGRATION |
| Tempo médio de fila | **PARCIAL** (instrumentado) | espera real de cada pareamento, desde o último reinício |
| Pico online hoje, série do Ao Vivo (1h/6h/24h) | **PARCIAL** (instrumentado) | amostra a cada 15 s em memória |
| Partidas iniciadas/concluídas/abandonos hoje | **PARCIAL** (instrumentado) | eventos em memória desde o reinício |
| Admin Log | **PARCIAL** | memória + linha `[admin-audit]` no log do Render; durável = MIGRATION |
| Perfil: cadastro, último login, status da conta | **REAL** | `profiles` |
| Perfil: Ranked por modo (liga, PL, V/D/E, maior liga) | **REAL** | `ranked_stats` (FRAIHA usa liga+PL, não Elo) |
| Perfil: Casual/XEQUE/MARCHA V/D | **REAL** | `mode_stats` |
| Clube: status, origem, expiração / Founder: sim/não, desde | **REAL** (leitura) | `entitlements` |
| Clube: plano, início, renovação, observação | **MIGRATION** + decisão de produto | — |
| Conceder/alterar/revogar Clube e Founder | **BACKEND** (área protegida) | endpoint de entitlement + audit durável |
| Partidas recentes (terminadas) | **BACKEND/MIGRATION** | só Ranked grava em `matches`; Casual/XEQUE/MARCHA não |
| Jogadores únicos hoje, retorno | **INSTRUMENTAÇÃO + MIGRATION** | `game_sessions` (proposta) |
| Plataforma (Web/Windows/Android/Steam), versão do cliente | **INSTRUMENTAÇÃO** | o cliente precisa informar no `acct_auth`/`guest_auth` |
| Erros/reconexões | **INSTRUMENTAÇÃO** | contadores no servidor |
| Busca por e-mail | **BACKEND** | Supabase Auth Admin (dado pessoal; não feito na V1) |
| Funil campanha (anúncio → cadastro) | **INSTRUMENTAÇÃO** | UTM no cadastro + eventos |
| Gráficos 7/30 dias | **MIGRATION** | `metric_samples` (proposta) |

Nada é MOCK: o QA usa um servidor LOCAL com atividade de jogo real (`tests/admin/seed_dev.cjs`).

## Filas — regra implementada
Desativar um modo (Ranked, Casual, XEQUE, MARCHA):
- recusa novas entradas na fila (`*_error` code `mode_disabled`; o cliente atual já mostra a mensagem);
- para de parear quem estava esperando e **tira da fila com aviso**;
- XEQUE/MARCHA (sem fila pública): recusa convite novo e não inicia mesa de convite já enviado;
- Casual: vale para a fila e para convites de xadrez entre amigos;
- **partidas em andamento continuam** (testado: lance aceito depois de desativar).
Exige motivo + digitar o nome do modo; validado no servidor; registrado no Admin Log. Estado em memória:
reinício volta tudo para ATIVO (durável = `admin_mode_controls`, proposta). Agenda/eventos/manutenção: campo
`schedule` já previsto no contrato e na proposta.

## Threat model (resumo)
| Ameaça | Mitigação V1 |
| --- | --- |
| Usuário comum chamando `/admin/api` | 403 `not_admin` (allowlist no servidor); testado em todas as rotas |
| Manipular o frontend / esconder botão | toda decisão no servidor; botão escondido não é autorização |
| Token roubado/reusado | tokens curtos do Supabase; verificação no Auth (cache ≤ 60 s); token só na memória da aba (sem storage); papel conferido a cada request |
| Privilege escalation / IDOR | papel vem da allowlist do servidor, nunca do request; rotas validam UUID; sem rota de escrita em jogador na V1 |
| Request alterada (tipos, família, confirmação) | validação estrita (boolean, motivo ≥ 3, confirm = família, 404 família desconhecida, 413 corpo grande, JSON inválido 400) |
| Service role vazando | fica só no servidor; Admin usa só chave publicável; nenhum secret no app |
| CSRF | sem cookies (Bearer em header) → não aplicável; CORS por allowlist (localhost só em local/dev) |
| Abuso/flood | rate limit por IP (240/min) e escrita por admin (20/min) |
| XSS no Admin | DOM via `textContent` (nada vira HTML), CSP `script-src 'self'`, `connect-src` restrito |
| Phishing de API | endereços de API fixos no build do Admin |
| Logs | sem token/segredo; dados pessoais mínimos (sem e-mail) |
| Restante | revogação imediata de admin depende do cache de 60 s; audit não é durável sem a migration; recomendado Cloudflare Access na frente do Admin |

## Como rodar (local)
```
tests/admin/run_admin_qa.sh            # sobe servidor DEV + atividade real + Admin e roda o QA no Chromium
```
Manual: `PORT=8140 FRAIHA_DEV_AUTH=1 FRAIHA_ENV=local FRAIHA_ADMIN_USERS=<uuid>=owner node online_v021/server.js`,
`node tests/admin/seed_dev.cjs 8140`, servir `admin/` (ex.: `python3 -m http.server 8150`) e entrar como `boss` em LOCAL.

## Testes
- `tests/server/admin_api_test.cjs` (8): não-admin recusado em todas as rotas; Admin desligado sem allowlist;
  viewer não escreve; requests manipuladas; CORS; números reais × indisponíveis; desativar Ranked (fila esvaziada,
  entrada recusada, partida continua com lance aceito, Casual intocado, audit); desativar XEQUE; espera real.
- `tests/admin/admin_ui_test.py` (23, Chromium): login não-admin; loading; dashboard = número do servidor;
  INDISPONÍVEL sem número; confirmação do toggle; toggle real + partida continua; Admin Log; empty; erro do
  backend; reconexão; timeout; 1280/1920 sem rolagem; sem erro de JS/CSP.
- Regressão: suíte inteira `tests/server/*_test.cjs` verde.

## Próximos passos recomendados
1. Decidir hospedagem do Admin (domínio + Cloudflare Access) e configurar `FRAIHA_ADMIN_USERS`/`FRAIHA_ADMIN_ORIGINS`/`FRAIHA_ENV` no **staging**.
2. Aprovar (ou ajustar) a proposta `docs/admin/proposals/0011_fraiha_admin_v1.sql` → Admin Log e controles duráveis.
3. Instrumentar o cliente: plataforma + versão no `acct_auth`/`guest_auth` → `game_sessions`.
4. Endpoint de entitlement manual (Clube/Founder) com audit durável — área protegida, precisa de autorização.
5. Histórico de partidas Casual/XEQUE/MARCHA na camada comum de histórico.

## Retorno da auditoria Orca (sobre `1ef1ec1`) — correções locais, sem commit
| Finding | Correção | Prova |
| --- | --- | --- |
| MEDIUM logout/estado privilegiado | `endSession()` fail-closed: época da sessão muda, timers param, cliente da API é revogado (aborta requisições em voo, recusa novas, apaga o token da memória), confirmações abertas são fechadas e nunca resolvem como "confirmar"; respostas tardias são ignoradas; 401 encerra tudo; logout no Supabase (melhor esforço, staging/prod) | `admin_ui_test.py`: confirmação aberta → logout → clique antigo → nenhuma mutação/sem Admin Log; 401 com confirmação aberta; poll lento → logout → sessão não volta; zero requisições após logout. `api_client_test.mjs`: revoke |
| MEDIUM timeout | prazo cobre conexão + cabeçalhos + leitura/parse do corpo; corpo vazio/inválido com 200 = erro | `api_client_test.mjs` (o cliente antigo fica pendurado no corpo travado) |
| MEDIUM Clube/Founder fail-closed | leitura com prazo; erro/timeout → `INDISPONÍVEL`/`null` + `entitlements_read`; sem linha = legítimo INATIVO/false; Ranked/modos com erro aparecem como erro | `admin_api_test.cjs` (true/false/sem registro/erro/timeout) + tela |
| MEDIUM 0011 | privilégios explícitos (REVOKE de anon/authenticated/PUBLIC; service_role mínimo), TRUNCATE tratado (sem privilégio + trigger), append-only com trigger, RLS forçada, FKs, checks, índices, retenção, rollback | `tests/admin/test_0011_proposal.sh` (PostgreSQL 16 local descartável com papéis do Supabase; a proposta antiga permitia TRUNCATE por anon) |
| LOW mobile | layout sem largura mínima estrutural; topo quebra linha; menu horizontal rolável | 393×852, 852×393, 1280, 1920 em todas as telas |
| LOW race de convite | revalida o modo depois das consultas e antes de criar o convite | `admin_api_test.cjs` Casual/XEQUE/MARCHA (falha no código antigo) |

## Correção final (retorno Orca sobre `e9232c7`) — 401 em ação administrativa
| Gap | Correção | Prova |
| --- | --- | --- |
| 401 numa AÇÃO (ex.: fila) só mostrava toast; a tela privilegiada continuava aberta | Tratamento **centralizado** no cliente da API (`Api.unauthorized`): qualquer resposta 401 de uma sessão instalada (polling, ação, leitura; corpo JSON, vazio ou inválido) revoga o cliente (aborta o que está em voo, recusa novas, apaga o token) e chama `sessionRejected` uma única vez → `endSession()` (timers, confirmações, época) + volta ao login com o motivo. 401 de cliente antigo não derruba sessão nova. 400/403/5xx/timeout/rede NÃO encerram a sessão | `api_client_test.mjs` (401 GET/POST/corpo vazio/inválido; 400/403/404/500/503/timeout não revogam; login sem sessão); `admin_ui_test.py` (ação 401 com outra confirmação aberta → login, sem shell/botões, nada aplicado, Admin Log igual, polling parado; 400/403/500 na ação mantêm a sessão; 401 vazio em outra tela; novo login funciona) — os testes novos falham no código de `e9232c7` |

## Frontend servido em `/admin/` pelo próprio servidor (staging visual, decisão "Opção A")
- `online_v021/admin/static.js`: na inicialização lê `admin/` (só `.html/.css/.js`, sem ocultos, sem
  `package.json`, sem symlink) para um mapa em memória; cada request é lookup de caminho EXATO → sem acesso
  ao disco, sem path traversal, sem listagem. Só GET/HEAD; CSP (`frame-ancestors 'none'`), `X-Frame-Options: DENY`,
  `nosniff`, `no-referrer`.
- Rotas: `/admin` → 301 `/admin/`; `/admin/` e `/admin/index.html` → app; `/admin/assets/*`, `/admin/src/*` → assets;
  qualquer outro `/admin/*` → 404 curto. `/admin/api/*` continua no `AdminService` (tratado ANTES). Rotas do app são
  por hash (`#/filas`): recarregar sempre pede `/admin/`, sem fallback.
- **Sem `FRAIHA_ADMIN_USERS` → 404 também para a tela** (produção sem a variável não mostra nada).
- Mesma origem: em staging, `FRAIHA_ADMIN_ORIGINS` deve conter `https://fraiha-xadrez-staging.onrender.com`
  (o navegador manda `Origin` nas ações POST). No login, escolher o ambiente **STAGING**.
- Testes: `tests/server/admin_static_test.cjs` (servidor real); `ADMIN_URL=http://127.0.0.1:8140/admin/ python3
  tests/admin/admin_ui_test.py` roda o QA completo do painel servido pelo próprio servidor.

## ENTRAR COM GOOGLE (mesmo fluxo do jogo Web)
- Reaproveita o fluxo do jogo (`account/account_service.gd`): REST do Supabase Auth, sem SDK —
  `/auth/v1/authorize?provider=google&redirect_to=<página>` → Google → Supabase → volta com `#access_token=…`
  (fluxo implícito). Só a URL do projeto e a chave publicável (já públicas no jogo).
- `admin/src/oauth.js`: `redirect_to` = endereço canônico desta página (origem + caminho, sem query/hash; nunca de
  parâmetro → sem open redirect). Marcador de uso único em `sessionStorage` (ambiente + horário, sem credencial,
  validade 10 min): retorno sem login iniciado nesta aba é ignorado. Tokens saem do endereço na hora; refresh token
  e token do Google são descartados; o access token fica só na memória.
- Depois do retorno o caminho é o MESMO do login por senha: `/admin/api/session` → servidor verifica o token no
  Supabase → UUID na `FRAIHA_ADMIN_USERS`. Conta Google comum = 403 `not_admin` (e a sessão Supabase dela é
  encerrada). Logout chama `/auth/v1/logout`. 401 continua encerrando a sessão.
- Só STAGING/PRODUCTION (LOCAL usa conta DEV).
- **Redirect URL necessária no Supabase (NÃO adicionada):** `https://fraiha-xadrez-staging.onrender.com/admin/`.
  Sem ela o Supabase devolve para a Site URL (o jogo) e o Admin não recebe o login. Google Cloud: nada muda (o
  callback continua o do Supabase).
- Testes: `tests/admin/oauth_test.mjs` (unitário) e `tests/admin/run_admin_google_qa.sh` (Chromium, Admin em
  `/admin/`). **Google e Supabase são MOCKADOS** no navegador; o token falso é um token DEV verificado pelo servidor
  local real (allowlist e 403 reais). O Google REAL ainda não foi testado.

## Clube FRAIHA e Fundador — escrita administrativa (sem migration)
- Modelo REAL (0005, `public.entitlements`): `is_founder`, `founder_since` (Fundador PERMANENTE) ·
  `club_active`, `club_expires_at` (null = sem expiração), `club_source` · `updated_at`. O jogo lê pelo `acct_state`
  (`store.getEntitlements`: Clube ativo = `club_active` e sem data ou data futura). Nenhuma migration nova.
- `online_v021/admin/entitlements.js`: grava SÓ no servidor (service role). Clube: `grant` (7/30/90/365 dias, sem
  expiração, data personalizada ≤10 anos), `change`, `revoke`; origem `manual` (valor já previsto na 0005).
  Fundador: `grant`/`revoke` (sem validade; não há campo editável → sem ALTERAR). **Independentes:** conceder/revogar
  Fundador não mexe no Clube (o bônus de 30 dias do Clube é regra da COMPRA, só nos pagamentos — não tocados).
- Endpoints: `GET /admin/api/online` (contas online agora + estado real) · `POST /admin/api/players/:uuid/club`
  `{action, duration, expires_at?, reason, confirm:uuid, expect_version}` · `POST /admin/api/players/:uuid/founder`
  `{action, reason, confirm, expect_version}`. Payload estrito (campo desconhecido = 400), motivo obrigatório,
  versão esperada (`updated_at`: tela velha/clique duplo = 409), alvo precisa ter perfil (404), erro de leitura =
  503 sem gravar, PATCH condicionado à versão no Supabase.
- Permissão `entitlements.write`: SÓ owner (operator/viewer não). Admin Log: `clube_grant|clube_change|clube_revoke|
  founder_grant|founder_revoke` com admin, alvo, UUID, antes/depois, motivo (memória + `[admin-audit]`).
- Jogador online recebe `acct_state` novo na hora (mesmo caminho do webhook de pagamento).
- Limite de vagas de Fundador (`FRAIHA_FOUNDER_LIMIT`, vendas) NÃO bloqueia concessão manual: o owner decide.

## Ritmos do Ranked (liquidez) — servidor é a fonte de verdade
- `ModeControls`: além das famílias, cada ritmo do Ranked (`ranked_3min|5min|10min|20min`) tem ON/OFF. Fila aberta =
  família Ranked ON **e** ritmo ON. Desligar: entrada recusada (`mode_disabled`), quem esperava sai com aviso,
  partidas em andamento continuam, sem pareamento no ritmo fechado.
- O jogo recebe a lista de ritmos ABERTOS no `acct_state.ranked_modes` e no aviso `{type:'ranked_modes', modes}` enviado
  a TODAS as contas conectadas a cada mudança. A tela JOGAR RANQUEADO mostra só os abertos, sem buracos (4 = 2x2,
  3 = 2+1 centralizado, 2 = lado a lado, 1 = centralizado, 0 = "RANQUEADA TEMPORARIAMENTE INDISPONÍVEL").
  Cliente antigo (sem a lista) continua mostrando os 4 — o servidor recusa o ritmo fechado do mesmo jeito.
- Admin: tela Filas → card Ranked → ritmos com Ativar/Desativar (motivo + palavra). API
  `POST /admin/api/queues/ranked/:mode {enabled, reason, confirm:mode}` (perm `queues.write`). Log `queue.mode_*`.
- **Persistência:** estado em memória. Reinício/sono do Render volta ao padrão de boot `FRAIHA_RANKED_MODES_OPEN`
  (ex.: `ranked_5min,ranked_10min`; sem a variável = os 4 abertos; só valores inválidos = nenhum aberto).
