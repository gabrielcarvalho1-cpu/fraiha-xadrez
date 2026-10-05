# R42 — Integração do pacote de segurança (S01 + A+B+S11)

Revisão humana (Claude) do pacote Codex/Orca e integração controlada na `dev/web-alpha`.

## Base real

- Handoff do Codex validou contra `63ed940` (R40.1). A `dev/web-alpha` real já estava em
  **`b37e9ca` (R41)** — no GitHub e no PC.
- O R41 alterou 4 dos arquivos do pacote: `backend.js`, `ranked/service.js`, `social/dm.js`,
  `social/invites.js`. O gate "sem conflito" do Codex não cobria isso.

## Commits (em cima de b37e9ca)

| Commit | Origem | Conteúdo |
| --- | --- | --- |
| `fix(security): validate websocket input before dispatch` | cherry-pick -x `af54aea` (S01) | `server.js` + `ws_input_test.cjs`. Sem conflito. |
| `fix(security): reconcile session ranked and pvp guards` | cherry-pick -x `2d8f4b8` (A+B+S11) | 18 arquivos. Conflito com o R41 nos 4 arquivos acima. |
| `fix(security): R42 — ajustes de integração…` | revisão humana | 2 correções + gates manuais. |
| `docs(security): prepare Claude integration handoff` | cherry-pick -x `31ce89d` | documentação do Codex (proveniência). |
| `docs(security): R42 …` | este documento + `SECURITY_AUDIT.md` | — |

### Como os conflitos com o R41 foram resolvidos

Ficou a lógica de segurança do pacote (snapshot `op.profile`/`op.identity`, `participants`,
revalidação antes de enfileirar). Em todos os pontos onde o pacote montava só `badge`, voltou a
identidade pública completa do R41 (`publicLook`: badge, title, frame, founder, club):

- `setIdentity` (estado da conta);
- entrada da fila;
- `from` da DM;
- `from`/`to` do convite;
- entrada Casual do convite.

## Problemas encontrados na revisão (corrigidos no commit R42)

1. **HIGH — JOGAR LOCAL (2 humanos) quebrado.**
   - Causa: o modo local usa `bot/controller.gd` só como juiz de regras. O novo guard de fair play trata "local" como partida humana. Com isso, o controlador se parava a cada frame e `_apply` recusava os lances.
   - Evidência: `home_navigation_test` caiu de 28/28 para 25/28.
   - Correção: o guard vale só com bot (`not local_mode`). O modo local não usa engine.
2. **MEDIUM — resposta descartada durante a revalidação de rotina (60 s).**
   - Causa: `backend.send` descartava qualquer envio feito por uma operação enquanto a revalidação estava em andamento.
   - Caso real: cartão aprovado no Mercado Pago com a revalidação em andamento. O pagamento era aplicado no servidor, mas o jogo nunca recebia `payment_card_result`, `payment_update` nem `acct_state`.
   - Correção: a resposta espera a revalidação e só sai se a sessão continuar válida.
   - Teste: `session_send_defer_test`, 3/3, cobrindo entrega, sessão revogada e caminho normal.
   - Nada em `payments/` ou `monetization/` foi tocado.

## Testes executados (no tree final)

### Servidor (todos os arquivos `tests/server`)

Tudo verde, incluindo pagamentos (`card_inline`, `mercadopago`, `mp_optional_fields`) e `public_look` (R41).

Testes do pacote:

| Teste | Resultado |
| --- | --- |
| `session_hardening` | 32/32 |
| `security_reconcile` | 89/89 |
| `ranked_race_s05` | 26/26 |
| `analysis_fair_play` | 23/23 |
| `ws_input` | 48/48 |
| `session_send_defer` | 3/3 |

`party_test` é longo (2–3 min). Falhou 1 vez em 7, por timing; passou 6 vezes, com e sem o ajuste.

### Chrome nativo

`tests/web/session_socket_e2e.cjs`: 1/1.

### Godot headless e cliente contra o servidor composto

| Teste | Resultado |
| --- | --- |
| `analysis_engine_race` | 5/5 |
| `bot_*` | iguais à base |
| casual, friends, invite, dm, party, account_session, queue_reconnect | OK |
| pagamento real | 33/33 |
| cartão no jogo | 25/25 |
| `public_look` | 12/12 |
| premium_r31, monetization, club_frame, marcha_ui, xeque_ui | OK |

Falhas pré-existentes, iguais na base `b37e9ca`:

- `profile_v2`: 2;
- `analysis_test`: "COPIAR LANCES" (clipboard headless);
- `bot_integration`: 1.

## Gates manuais executados

**Sessão com cliente Godot real** (`tests/run_session_gate.sh`): 17/17.

- Conta logada em partida Casual contra um adversário.
- Lance antes da revalidação.
- Espera de 70 s: o servidor revalida aos 60 s, e a partida e os lances seguem.
- Renovação do token (`acct_auth` de novo, mesma conta) no meio da partida: a partida não cai e o lance seguinte é aplicado.

**Web real no Chromium** (`tests/web/qa_gate/run_engine_gate.sh`, cópia de QA da build): 15/15.

- `ANALYSIS ENGINE = STOCKFISH` (19 Lite WASM, Worker). Fora de PvP, retorna `bestmove`.
- Análise **em voo** quando o PvP começa:
  - o resultado é descartado;
  - o `stop` UCI interrompe em cerca de 0,5–0,6 s;
  - a engine fica livre;
  - novas consultas são recusadas durante o PvP;
  - depois da partida, a análise volta a responder.
- `BOT ENGINE = STOCKFISH`: o bot joga no navegador.
- Bot **pensando** quando o PvP começa: nenhum lance é aplicado, o controlador para e a engine fica livre.
- Modo LOCAL: o lance é aplicado e não há engine.

**Build final R42** exportada do tree final: boot no Chromium sem erro de script.

## Não integrado (como pedido)

- **S06:** só design (bot reward autoritativo). A mitigação antiga, que bloqueava todas as `bot_victory`, **não** entrou.
- **S07:** hipótese de RNG e exposição. Nada alterado.

## Dívida técnica (riscos residuais, não bloqueiam)

- **Renovação de token com operação longa em voo.** Exemplo: pagamento no exato momento da renovação, cerca de 1 vez por hora. A resposta daquela operação é descartada, porque a renovação troca a revisão da sessão. Recuperável com "JÁ PAGUEI" ou atualizando a tela: o servidor já aplicou.
- **Escritas e concorrência:**
  - uma escrita já iniciada não tem rollback (por exemplo, DM gravada e operação cancelada depois);
  - Social não é transacional;
  - exclusividade e filas são por processo (sem coordenação entre instâncias).
- **Duração da sessão.** O máximo é 1 h por `acct_auth`. O cliente renova cerca de 2 min antes do `exp`. Uma aba em segundo plano pode perder a renovação: o servidor invalida e o cliente renova ao receber `invalid_token`, mas uma partida em andamento conta como desconexão, dentro da tolerância de reconexão.
- **Revogação no Auth.** Leva até 60 s, mais até 10 s de timeout. Se o Auth estiver indisponível, a sessão falha fechada.
- **Fair play no cliente.** O bloqueio depende do estado de PvP recebido. O servidor nega `analysis_request` em PvP, mas um cliente adulterado com engine própria não é controlável.

## Nada alterado

- `payments/`, `monetization/`, Mercado Pago;
- migrations e Supabase;
- Render e Cloudflare;
- regras de Marcha (`marcha/rules.gd` e `online_v021/modes/marcha_rules.js`);
- produção.
