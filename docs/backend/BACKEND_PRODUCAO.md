# Backend de produção: legado × moderno

Estado: **diagnóstico + configuração no repositório**. Nada foi publicado: sem deploy, sem push e sem mudança no Render.

## 1. O que roda em cada lugar

| | Staging (`fraiha-xadrez-staging.onrender.com`) | Produção (`fraiha-xadrez.onrender.com`) |
|---|---|---|
| Branch | `dev/web-alpha` (docs/SUPABASE-SETUP.md) | `main`, criado como Blueprint pelo README V0.20 ("Use a branch `main` e o arquivo `render.yaml`") |
| Runtime | Node, `npm start` | Docker (`render.yaml` → `Dockerfile`) |
| Entrypoint | `node online_v021/server.js` (`package.json` desde `8b2129f`) | depende da branch publicada; nos dois casos é **legado** (ver abaixo) |
| Protocolo | moderno: `guest_auth`, `acct_*`, `casual_*`, `ranked_*`, `party_*`, `marcha_*`, `voice_*`, `payment_*`, Admin | legado: só salas `create`/`join`/`resume`/`move` |

## 2. Por que a produção responde o protocolo legado

- **`origin/main` parou em 28/09** (`3e398ef`). Ele não é ancestral do `dev/web-alpha`: são 232 commits divergentes.
- **O `Dockerfile` da `main`** roda `node online_v021/server.js`. Ali esse arquivo era o servidor **antigo de salas**, com 34 linhas, que só responde `welcome`/`state`/`pong`/`error`. Nada de contas, Casual moderno, Ranked etc.
- **O `Dockerfile` do `dev/web-alpha` (até este commit)** rodava o servidor ainda mais antigo em Godot (`online_v020/server.gd`). Ele é dos tempos da V0.20 e nunca foi atualizado, porque o staging moderno usa runtime Node com `npm start` e ignora o Dockerfile.
- **Conclusão:**
  - um serviço em runtime Docker sobe protocolo legado nos dois casos: da `main` sobe o Node antigo, do `dev/web-alpha` sobe o Godot V0.20;
  - o staging só é moderno porque foi criado em runtime Node com `npm start`;
  - a produção nunca recebeu o backend moderno.

> Sem acesso ao painel do Render a partir daqui, não dá para ver qual das duas opções legadas está no ar. O dono confere em Render > fraiha-xadrez > Settings, em "Branch" e "Runtime"/"Dockerfile Path".

## 3. Entrypoint moderno correto

`node online_v021/server.js`, a partir de uma branch com o backend atual. Hoje é o `dev/web-alpha`, depois do push aprovado destes commits.

O servidor precisa destes arquivos, e o `Dockerfile` novo copia só eles:
- `package.json` (dependência `ws`);
- `online_v021/`;
- `admin/` (frontend do Admin);
- `bot/bot_ladder.json` (escada de bots e cosméticos).

## 4. Configuração necessária no Render (ação MANUAL do dono, só quando autorizar)

Existem duas opções equivalentes. A recomendada é a A.

**A · Runtime Node (igual ao staging)**
- Branch: a branch moderna aprovada.
- Runtime: Node.
- Build Command: `npm ci --omit=dev` (R170: usa o package-lock.json; ws travado em 8.22.0).
- Start Command: `npm start`.

**B · Manter Docker**
- Branch: a branch moderna aprovada, que tem o `Dockerfile` novo deste commit. Ele usa `node:22` e sobe `online_v021/server.js`.

**Variáveis em Render > Environment.** Só nomes, nunca valores no Git. Copie do staging o que se aplica e troque o que precisa ser de produção:

| Grupo | Variáveis |
|---|---|
| Obrigatórias para contas/Ranked | `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable), `SUPABASE_SECRET_KEY` (sb_secret_). Supabase é o mesmo projeto do staging. |
| Pagamentos (produção = credenciais REAIS do Mercado Pago) | `FRAIHA_PAYMENT_PROVIDER`, `FRAIHA_MP_ACCESS_TOKEN`, `FRAIHA_MP_PUBLIC_KEY`, `FRAIHA_MP_WEBHOOK_SECRET`, `FRAIHA_PUBLIC_URL` (`https://fraiha-xadrez.onrender.com`), `FRAIHA_GAME_URL` (`https://jogar.fraihaxadrez.com`) |
| Voz | `FRAIHA_AGORA_APP_ID`, `FRAIHA_AGORA_APP_CERTIFICATE` |
| Admin (opcional) | `FRAIHA_ADMIN_USERS`, `FRAIHA_ADMIN_ORIGINS` (`https://fraiha-xadrez.onrender.com`) |
| Outras | `FRAIHA_ENV=production`, `FRAIHA_FOUNDER_LIMIT`, `FRAIHA_FOUNDER_WHATSAPP_URL` |

Nunca defina em produção as variáveis de teste:
- `FRAIHA_DEV_AUTH`, `FRAIHA_DEV_START_PL`;
- `FRAIHA_TEST_*`;
- tempos curtos `FRAIHA_*_MS`.

**Atenção a três pontos:**
- No Mercado Pago, o webhook de produção deve apontar para `https://fraiha-xadrez.onrender.com/webhooks/payments`.
- No Supabase, a redirect URL do Admin de produção precisa ser adicionada pelo dono.
- Staging e produção usam o **mesmo Supabase**.

**Conferência depois do deploy (quando autorizado):**
1. o log do Render mostra `FRAIHA accounts backend: supabase` e `FRAIHA WebSocket server listening on 10000`;
2. `guest_auth` responde `guest_state`, que é o protocolo moderno;
3. só então gerar a build Web pelo preset "Web Producao" (R59).

## 5. H03 · persistência do Ranked (este commit)

`online_v021/ranked/persist.js`. A RPC `fraiha_record_ranked_match` já é uma transação que nunca aplica PL duas vezes: confere o PL "antes" e usa `match_id` como chave primária. Faltava tratar a falha.

**Falha transitória** (rede, 5xx, tempo esgotado):
- nova tentativa com espera de 1, 2, 4, 8, 15 e 30 s, cerca de 60 s no total;
- `FRAIHA_RANKED_PERSIST_RETRY_MS` serve só para testes.

**Antes de cada nova tentativa e depois de cada erro**, o servidor consulta `matches` por `match_id` (`hasRankedMatch`, só leitura):
- se a partida já existe (o commit foi feito e a resposta se perdeu), é sucesso e nada é reaplicado;
- `23505` também conta como "já gravada".

**Erro permanente** (estado Ranked mudou, dado inválido): o servidor para.

**Durante as novas tentativas**, os dois jogadores não entram em outra partida Ranked: a fila e os convites recebem `ranked_error` com código `result_pending`. Sem isso, a próxima partida leria do banco o PL ainda sem esta e a gravação dela falharia.

**Se esgotar**, o resultado vai com `saved=false`, que o cliente já avisa. A partida completa vai para o log como `RANKED_PERSIST_GAVE_UP {json}`, para reconciliação.

Não precisa de migração. O protocolo não mudou: o resultado continua `ranked_result` com `saved`, e o código novo `result_pending` vem no `ranked_error`, que já existia.

## 6. H04 · socket morto durante a partida (este commit)

**Antes:** a presença encerrava sockets silenciosos só **fora** de partida. Em partida, um socket morto (Wi-Fi caiu sem FIN, app morto) ficava "conectado" para sempre: a tolerância de reconexão nunca começava e o adversário esperava o relógio acabar.

**Agora:** o socket que ficou em silêncio, recebeu o ping de protocolo e não respondeu é encerrado também em partida.
- Os tempos são os de antes: suspeito 30 s, morto 45 s.
- O encerramento só dispara o `onClose` normal.
- **Morte do socket ≠ abandono:**
  - o Ranked e o Casual marcam o jogador como desconectado e contam `FRAIHA_RANKED_RECONNECT_MS` (60 s);
  - quem volta dentro desse prazo continua na mesma partida; quem não volta perde por abandono, pela regra existente;
  - no XEQUE e na Marcha online, o bot joga a vez do ausente e ele retoma ao voltar.
- **Aba em segundo plano viva não morre:** o navegador responde o ping de protocolo sozinho.

## 7. XEQUE e Marcha Real: quando usam o backend

| Fluxo | Backend? |
|---|---|
| XEQUE contra bots (padrão) e tutorial | **Não.** Regras, bots e resultado ficam no aparelho; o histórico local está em `analysis/match_history.gd`. |
| Marcha Real contra bots e tutorial | Partida **local**. Com conta e servidor: só `marcha_status`/`marcha_start` (limite diário/Club, tabela `marcha_usage` da 0008). Hoje `TEST_PHASE_UNLIMITED` libera tudo. Sem conta ou sem servidor: o limite é contado no aparelho. |
| XEQUE ou Marcha **com amigos** (convite → mesa) | **Sim, o servidor é autoritativo**: `party_*` (`party_start`/`party_action`/`party_event`/`party_leave`). Regras rodam no servidor (`online_v021/modes/xeque_rules.js` e `marcha_rules.js`, portas 1:1 do `.gd`); chat da mesa; bots nas cadeiras vazias. Resultado em `recordModeResult` (estatística por modo, 0009). Exige conta (`auth_required`). |
| `xeque_sync` / `marcha_sync` | São **testes de paridade** (`tests/server/*_sync_test.cjs`): conferem se as regras do servidor batem com as do cliente Godot. Não são mensagens do protocolo. |

A frase anterior "XEQUE e Marcha não usam servidor" valia só para as partidas solo. As mesas com amigos usam o mesmo socket e o mesmo endpoint (`account_service`) do Casual e do Ranked. Por isso também seguem a escolha staging × produção da R59.
