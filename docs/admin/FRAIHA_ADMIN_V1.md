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
