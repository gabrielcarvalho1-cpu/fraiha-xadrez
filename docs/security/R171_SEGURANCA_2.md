# R171 · Segunda leva de segurança (após a R170)

Base: R170, commit `296942d`. Trabalho isolado no branch `r171/seguranca-2`. A R170 não foi alterada.
**Sem push. Sem deploy. Nada em produção.** Aguarda aprovação.

## Resumo

| Item | Situação |
|---|---|
| SEC-009 · limite do Fundador | **CORRIGIDO**: atômico no banco (migração 0023), provado com corrida real no Postgres 16 |
| 13 testes de sessão | **CORRIGIDO NO CÓDIGO**. Eram bug real desde a R112: o saldo de Coroas de uma conta podia aparecer para outra |
| SEC-008 · vitória contra bot | **PARCIAL**. Fechado: cor, progresso, replay e mesma vitória 2×. Lances de bot inventados são conferidos com Stockfish nos níveis fortes. **Prova total exige bot no servidor: decisão sua (ver abaixo)** |
| SEC-010 · denúncias | **CORRIGIDO**: chave denunciante + mensagem + tipo; teto por pessoa e por IP; denúncias de pessoas diferentes nunca se perdem |
| SEC-011 · CSP | **PRONTO EM MODO RELATÓRIO**: não bloqueia nada. Testado bloqueando com o build real (o jogo funciona); o Mercado Pago só se confirma com o report-only no ar |
| SEC-007 · voz | **NÃO MEXIDO**: aguardando a evidência do Orca |
| `card_inline_test` (falhava desde a R103) | **TESTE OBSOLETO**, explicado e ajustado (não era bug) |

---

## 1. SEC-009 · Limite de vagas do Fundador atômico

### O problema

O limite `FRAIHA_FOUNDER_LIMIT` só era conferido ao **criar** o pedido. A entrega (`fraiha_pay_and_grant`) não conferia vagas.

Exemplo: com 1 vaga e 10 pedidos abertos pagos ao mesmo tempo, saíam **10 Fundadores**. Isso foi reproduzido no Postgres real com a função antiga.

### A correção (migração `0023_fraiha_fundador_vagas.sql`)

**Capacidade.** A tabela `founder_capacity` tem uma linha só, com o limite. Toda reserva e toda entrega de Fundador trava essa linha (`FOR UPDATE`), então acontece uma de cada vez.

**Reserva.** Criar um pedido de Fundador (`fraiha_founder_reserve`) guarda a vaga por 30 min, a validade do PIX. Vagas ocupadas = Fundadores + reservas vivas de quem ainda não é Fundador. Sem vaga, o pedido nem é criado: a pessoa vê "vagas esgotadas" **antes de pagar**.

**Entrega.** `fraiha_pay_and_grant` faz duas travas e uma conferência:

1. Trava o pagamento. Webhook duplicado, retry, JÁ PAGUEI e reconciliação ao mesmo tempo esperam e saem sem efeito.
2. Trava a capacidade.
3. Confere de novo: Fundadores + reservas vivas de outras pessoas.

Se não couber, o pagamento vira **`sold_out`**. Nunca fica "pago sem entrega" escondido, e nunca sai Fundador além do limite.

**Outras regras:**

- **Upgrade Fundador → Lendário** não ocupa vaga nova.
- **Reconciliação de hora em hora** (`fraiha_grant_paid_missing`) segue a mesma regra.
- **Quem reservou a última vaga** recebe, mesmo que um pedido antigo, com reserva vencida, pague antes.

**Garantia:** `fundadores_entregues <= FRAIHA_FOUNDER_LIMIT` em qualquer ordem e concorrência.

### Testes de corrida

**Postgres 16 real, várias conexões** (`founder_seats_pg_test.cjs`, 9/9):

| Cenário | Resultado |
|---|---|
| 1 vaga / 2 compradores pagando juntos | 1 Fundador, 1 sold_out |
| 1 vaga / 10 | 1 Fundador, 9 sold_out |
| 2 vagas / 10 | 2 Fundadores, 8 sold_out |
| 3 vagas / 25 | 3 Fundadores, 22 sold_out |
| 10 reservas simultâneas para 2 vagas | 2 reservas. Quem reservou recebe, mesmo com 3 pedidos antigos tentando passar na frente |
| Mesma compra: 12 webhooks/retries + reconciliação juntos | entregue 1 vez, número de Fundador único |
| Upgrade com vagas esgotadas | Lendário entregue; outra pessoa não passa do limite |
| Sem limite (0) | todos recebem, como antes |

**Serviço completo** (`founder_seats_test.cjs`, 11/11): criação, pagamento, webhook duplicado, JÁ PAGUEI, reconciliação, cartão aprovado no instante da última vaga, estorno automático ligado ou desligado.

**Jogo** (`tests/payment_sold_out_r171_test.gd`, 10/10): tela do PIX, cartão e MINHAS COMPRAS com sold_out.

### ⚠ Política para quem paga depois de acabarem as vagas — PRECISA DA SUA APROVAÇÃO

Isso só acontece numa janela pequena: um pedido aberto antes da reserva vencer, pago depois que outro levou a última vaga. Nada é silencioso:

1. O pagamento fica **`sold_out`**: pago, **sem** pacote, aguardando reembolso. Nunca vira Fundador.
2. **O jogador é avisado na hora.** A tela do PIX ou do cartão mostra: "As vagas do Pacote Fundador acabaram no exato momento do seu pagamento. Você NÃO recebeu o pacote e o valor será devolvido integralmente…". Em MINHAS COMPRAS aparece "VAGAS ESGOTADAS · REEMBOLSO".
3. **Admin → Vendas** ganha o card "Sem vaga · reembolsar", o filtro "Sem vaga (reembolsar)" e o selo "PAGO SEM VAGA · REEMBOLSAR".
4. **Log de ERRO no Render**, com a referência do pagamento.
5. **Reembolso, escolha uma:**
   - **A (padrão, recomendado no início): manual.** Você estorna no painel do Mercado Pago. Quando o aviso de estorno chega, o pagamento vira `refunded` sozinho, sem retirar nada de ninguém.
   - **B: automático.** Com `FRAIHA_FOUNDER_AUTO_REFUND=1` no Render, o servidor já pede o estorno ao Mercado Pago (`POST /v1/payments/{id}/refunds`). Se falhar, cai no manual com log de erro.

Ainda não escolhi por você: o padrão é **A**. Para B, basta a variável.

---

## 2. Os 13 testes de sessão

`session_hardening_test` tinha 11 falhas e `session_send_defer_test` tinha 2. Antes: 13 falhas. Agora: 0.

**Primeira versão com falha:** `9558af6`, a **R112 (Coroas)**, encontrada por bisect.

**Causa:** a "entrada do dia" das Coroas (`crowns.onLogin`) rodava **solta**, fora da operação de login. Ela mandava mensagens (`crowns_reward`/`crowns_wallet`) fora do portão de sessão. Pior: lia as conexões **antes** de esperar o banco e mandava o saldo para quem estivesse nelas **depois**. Se A saísse e B entrasse no mesmo aparelho enquanto o banco respondia, **B recebia o saldo de Coroas de A**.

O novo `session_crowns_r171_test` prova isso: no código antigo, B recebia o saldo 5010 de A.

**Classificação: BUG REAL**, não teste obsoleto. É vazamento de dado entre contas, e as mensagens furavam a ordem e o portão da sessão.

**Correção no código** (os testes não foram mudados):

- `backend.js`: `await crowns.onLogin(...)` dentro da operação de login;
- `economy/crowns.js`: `notify` relê as conexões **depois** do await e só envia se a conexão ainda for da mesma conta.

| # | Teste | Esperado | R170 (antes) | Impacto |
|---|---|---|---|---|
| 1 | login A lento → B → A termina: somente B permanece | 3 msgs, só de B | 5 (2 de Coroas fora da sessão) | login / troca de conta |
| 7–11 | state A suspenso (perfil, ranked, vantagens, análise, bots) → login B | não mistura A/B (8 msgs) | 10 (Coroas de A chegam em B) | login / logout / troca |
| 16 | presença A atrasada não responde depois de B | 5 | 7 | reconexão / troca |
| 17 | handler da conta não usa B após await de A | 8 | 10 | troca de conta |
| 18 | expiração remove sessão ociosa | `invalid_token` | mensagem de Coroas no lugar | refresh / expiração |
| 28 | login suspenso no perfil inicial → B | callbacks de A não rodam (3) | 5 | login |
| 29 | revalidação antiga após B não invalida B | 8 | 10 | refresh |
| D1 | resposta durante revalidação: entregue depois da confirmação | segura até confirmar | Coroas saíam antes | refresh |
| D3 | sem revalidação: entrega imediata | ordem normal | extra fora de ordem | todas |

- **Impacto de segurança:** médio. Saldo e linha de Coroas de uma conta podiam aparecer para outra no mesmo aparelho. Nenhuma ação era executada em nome da outra conta.
- **Exclusão de conta:** não afetada; `account_delete` passa antes e depois.
- **Agora:** 0 falhas de sessão. Inclui `session_crowns_r171` (prova do vazamento).

---

## 3. SEC-008 · Vitória contra bot

### O que o servidor já fazia

Refaz a partida inteira com as regras do servidor, exige xeque-mate do lado do bot, segue a ordem da escada pelo banco e grava a 1ª vitória uma vez só.

### O que entrou na R171

**Cor do bot.** Sai da partida (quem levou o mate), não do `human_color`. Cor declarada errada é recusada.

**Progresso do cliente.** É ignorado: vale o banco. Mandar `defeated` falso não muda nada.

**Lances do bot nos níveis fortes** (platina, esmeralda, diamante, mestre, grão-mestre, challenger):

- O servidor roda **o mesmo Stockfish 19 lite do jogo**, como processo separado, com prioridade baixa (`nice 19`) para não atrasar partidas.
- Mede a **perda média dos lances do bot** nas posições ainda disputadas. Acima de 100 cp, a vitória é recusada (`bot_game_rejected`).
- O motor sobe só quando precisa, fecha depois de 60 s parado e usa ~120 MB enquanto roda. No Render free (512 MB), isso cabe, mas é o maior consumo novo.
- Uma conferência leva ~10 ms por lance aqui; no Render free, estimo segundos.

**Replay duplicado.** A mesma partida (lances idênticos) enviada por **outra conta** é recusada (`bot_game_reused`).

**Mesma vitória 2×.** Não dá recompensa nova e **não gasta motor** (revanche).

**Fila e falha do motor:**

- Fila cheia → "tente de novo em instantes" (`verify_busy`), nunca aceita sem conferir.
- Motor indisponível → recusa só os níveis fortes (`verify_unavailable`, fail-closed). Os níveis baixos seguem pelas regras.
- Desligar em emergência: `FRAIHA_BOT_VERIFY=0`.

`bot_vitoria_r171_test` (9/9, motor real) cobre:

- partida real (platina e diamante) aceita;
- lances inventados recusados;
- resultado falso (sem mate, lance ilegal, cor trocada) recusado;
- progresso falso recusado;
- mesma vitória 2× sem recompensa nova;
- replay por outra conta recusado;
- motor fora;
- fila cheia.

### Calibração (dados reais)

| Quem jogou pelo bot | Perda média nas posições disputadas |
|---|---|
| Bot oficial, perdendo (platina → grão-mestre, ~55 partidas) | **13 a 80** (quase sempre 25–65) |
| Lances **ao acaso** no lugar do bot (23 partidas) | **91 a 454** (22 de 23 acima de 100) |
| Motor **fraco** no lugar do bot (Stockfish nível 0, profundidade 1; 8 partidas) | **39 a 121**: **não dá para separar** |

### ⚠ Limite honesto — DECISÃO SUA

Enquanto o bot roda **no aparelho do jogador**, o servidor não consegue provar que os lances do lado do bot vieram do bot.

- **O que já fica de fora:** quem inventa lances à mão ou ao acaso.
- **O que ainda passa:** quem usa *outro motor* para jogar pelo bot.
- **Níveis baixos (madeira → ouro):** o bot erra de propósito, então lá só valem as regras e o mate.

**Prova total = bot rodando no servidor.** Isso é uma mudança grande:

- protocolo novo;
- o jogo pede cada lance ao servidor;
- CPU contínua no Render, o que o plano free não aguenta com vários jogadores.

**Recomendação:** manter a R171 como está, porque as recompensas são cosméticas e a 1ª vitória é única por conta. Bot no servidor só se as recompensas virarem valor real (Coroas, ranking).

---

## 4. SEC-010 · Denúncias

**Chave:** `denunciante + id da mensagem + tipo`, conferida **antes** de gravar e de escrever no log. Antes, toda repetição gerava uma linha `[gchat-report]`; para convidado, sem limite nenhum.

**Regras:**

- Mesma pessoa e mesma mensagem: 1 registro em 24 h. As repetições recebem "já denunciada" (`duplicate:true`), sem erro.
- Teto por pessoa: **10 a cada 10 min**. Acima disso, aviso "muitas denúncias, aguarde" (nunca some calada).
- Teto por IP: **30 a cada 10 min**.
- Pessoas diferentes, mesmo no mesmo IP, **sempre** registram: o IP só limita volume.
- Os mapas têm teto de memória. `moderation/reports.js` também ganhou teto no mapa de frequência.

`gchat_denuncias_r171_test`: 7/7.

| Cenário | Resultado |
|---|---|
| 1 envio | 1 registro |
| 3 iguais | 1 registro + 2 "já denunciada" |
| 10 iguais | 1 registro + 9 "já denunciada" |
| 2 (e 3) pessoas, mesma mensagem | todas registradas |
| Mesma pessoa, mensagens diferentes | todas registradas até o teto; depois aviso; volta após a janela |
| 30 contas no mesmo IP | teto por IP; outro IP normal |

Não há índice único no banco de propósito: o id das mensagens do chat global recomeça a cada reinício do servidor, e um índice único jogaria fora denúncias legítimas.

---

## 5. SEC-011 · CSP

Ver `docs/security/CSP_R171.md`.

- **Modo:** report-only no `index.html`, sem `*` solto.
- **Receptor:** `POST /csp-report` no servidor, com limites; registra só diretiva e host.
- **Teste com o build real bloqueando:** Godot, WASM, Worker do Stockfish, Agora (SDK + microfone), campo HTML, áudio e eval funcionam. Só o domínio estranho foi bloqueado.
- **Não verificado:** o Mercado Pago, porque não há internet no teste. Por isso começa em report-only.

---

## 6. SEC-007 · Voz

**Não alterado**, como pedido. A voz passou nos testes de regressão: `voice_*`, sem mudança.

---

## 7. `card_inline_test`: falhava desde a R103

**Causa:** a R103 criou a regra "1 pedido de Fundador aberto por conta" (`order_open`). O teste abre um PIX de Fundador e logo depois tenta outro pedido de Fundador no cartão para testar o limite de tentativas. O servidor recusa certo.

**Classificação: teste obsoleto.** O comportamento está certo, e mais importante agora com as reservas. O teste passou a usar outro produto (Club anual) para testar o que ele quer: o limite de tentativas de cartão. Comentário no teste.

---

## 8. Testes antes / depois

| Suíte | R170 (296942d) | R171 |
|---|---|---|
| Servidor (`node --test tests/server/*_test.cjs`) | ver `TESTES-ANTES-DEPOIS.txt` (14 falhas: 13 de sessão + card_inline) | **0 falhas** |
| SEC-009 Postgres real (`FRAIHA_PG_TEST=1`) | função antiga: 1 vaga/10 → 10 Fundadores | 9/9 |
| Cliente Godot: pagamento PIX real (`tests/run_payment_client.sh`) | — | 33/33 |
| Cliente Godot: cartão no jogo (`--card`) | — | 25/25 |
| Cliente Godot: sold_out (novo) | — | 10/10 |
| CSP com o build real (Chromium, bloqueando) | — | OK; só o domínio estranho bloqueado |

Regressão incluída na suíte:

- SEC-001..006 (`hardening_r170_test`);
- pagamentos e ofertas;
- Ranked, Casual, XEQUE e Marcha;
- voz;
- denúncias e bots.

---

## 9. Variáveis novas (Render, todas opcionais)

| Variável | Padrão | Para quê |
|---|---|---|
| `FRAIHA_FOUNDER_AUTO_REFUND` | desligado | `1` = estorno automático de sold_out |
| `FRAIHA_BOT_VERIFY` | ligado | `0` desliga a conferência por motor (emergência) |
| `FRAIHA_BOT_ACPL_MAX` | 100 | limite da conferência |
| `FRAIHA_BOT_VERIFY_QUEUE` | 8 | conferências na fila |
| `FRAIHA_ENGINE_PATH` | `web/engines/stockfish-19-lite-single.js` | caminho do motor |
| `FRAIHA_CSP_REPORTS_PER_MIN` | 300 | teto global de avisos de CSP |

---

## 10. Ordem de publicação (quando aprovado)

1. **Supabase → SQL Editor:** rodar `supabase/migrations/0023_fraiha_fundador_vagas.sql`.
   - É aditiva e idempotente, e o servidor R170 continua funcionando com ela.
   - Conferir: `select * from public.founder_capacity;` deve devolver 1 linha.
2. **Servidor:** `PUBLICAR-SERVIDOR-R171.cmd`.
   - Na subida, o log mostra o limite gravado. Sem a 0023, aparece um ERRO alto e o limite volta a ser só na criação, como na R170.
3. **Cloudflare:** pasta UPLOAD da build R171, por causa das telas de sold_out.
4. **CSP (opcional, depois):** regra report-only no Cloudflare, conforme `CSP_R171.md`.

Para desfazer, a 0023 traz no cabeçalho como reverter.

---

## 11. Checkpoint após o reteste do Orca da R170 (commit seguinte ao 0883d51)

O Orca reproduziu na R170 três falhas que **continuavam no 0883d51**: aquele commit não tinha mexido nesses pontos. Rodei o harness dele, sem mudanças, contra a R170 e contra a R171 nova:

| Item do harness do Orca | R170 / 0883d51 | R171 nova |
|---|---|---|
| SEC-003 `connected_survives_sweep` | false | **true** |
| SEC-003 convidado em partida sobrevive | true | true |
| SEC-003 teto (6º convidado com teto 5) | `full` | `full` |
| SEC-004 partida inventada gravada | 1 | **0** |
| SEC-004 mesma partida com horário trocado | 2 | **0** |
| SEC-004 Ranked inventado gravado | 1 | **0** |
| SEC-006 retry depois de falha transitória | ignorado (1 consulta) | **consulta de novo** (2 consultas) |
| SEC-006 limites (3/min, 2 simultâneas, assinatura obrigatória) | iguais | iguais |

Sobre o SEC-006: a última linha do harness do Orca foi escrita assumindo o comportamento antigo ("ignorado"). Na R171 nova a segunda tentativa consulta de novo; como o mock dele falha sempre, ela lança o erro (vira 500, e o Mercado Pago tenta de novo). Rodei com essa linha protegida por try/catch.

### SEC-003 · Convidados

- `sweepGuests()` nunca descarta convidado com conexão aberta: usa `liveGuests()`, a mesma lista do `evictGuests()`.
- Convidado em partida, mesmo desconectado, também nunca é descartado.
- O relógio de inatividade conta a partir de quando a conexão fecha (`seen` atualizado no fechamento). Só sai quem está sem conexão, fora de partida e há mais de 24 h sem uso.
- O teto de 20.000 continua.

### SEC-004 · Histórico de análise

- O `analysis_request` passa a dizer a partida (`match_id` + modo). O jogo novo já manda isso.
- A liberação fica ligada a essa partida. Liberação de outra partida, ou sem partida (jogo antigo), **não grava** histórico. A análise no aparelho continua funcionando.
- **Ranked e Casual:** só grava se o servidor viu **essa conta terminar essa partida**, avisado pelo serviço Ranked/Casual no fim. O modo também tem que bater. O horário gravado é o do servidor, e há **1 gravação por conta e partida**: mudar o horário não duplica.
- **Contra bot / local:** o servidor não vê essas partidas. Nelas o jogo nunca manda id de partida, e um id inventado é recusado. A chave contra duplicata é o conteúdo (modo + cor + lances), então mudar o horário não duplica.
- O limite de 60 gravações por dia continua. Gravar sempre na conta de quem pediu também.
- **Limite honesto:** uma partida contra bot totalmente inventada ainda pode entrar no histórico da **própria** conta, como antes, porque o servidor não tem como saber que ela não existiu. Não afeta outra conta nem o Ranked.

### SEC-006 · Webhook sem assinatura

- "Já processado" só é marcado **depois** que a consulta **e** a aplicação deram certo (`webhookSettled`).
- Falha na consulta ou na aplicação → 500, e a próxima tentativa consulta de novo.
- Aviso repetido enquanto o primeiro ainda está em andamento → 503 ("tente depois"), nunca 200 calado.
- Depois de aplicado com sucesso, repetições em menos de 1 min continuam sendo ignoradas.

### Sessão / Coroas: o que os 13 testes provavam e o que não provavam

Medi com uma sonda (fora do produto) quem recebe cada aviso de Coroas nos 35 testes históricos:

| | R170 | R171 |
|---|---|---|
| avisos de Coroas entregues | 74 | 74 |
| para o dono certo | 70 | **74** |
| para socket que já não era a conta dona | **4** (teste de expiração e "auth inválido após válido") | **0** |

O que isso mostra:

- **Em 12 dos 13 testes que falhavam**, as mensagens a mais eram as Coroas da **própria** conta chegando **depois** de o login terminar, porque a entrada do dia rodava solta. Esses 12 ficaram verdes por **ordem**: as Coroas agora fazem parte da operação de login, chegam antes de ela terminar e são descartadas se a sessão mudar. A mudança está no código, que hoje é o comportamento correto. **Não houve vazamento entre contas nesses 12.**
- **No teste de expiração**, a R170 entregou as Coroas de A a um socket cuja sessão já tinha expirado. Isso é vazamento real; na R171 não acontece.
- **O vazamento A → B no mesmo aparelho** acontece numa janela que **nenhum dos 13 testes cobria**: o aviso escolhe os aparelhos e depois espera o banco; nesse meio-tempo A sai e B entra. Ele é provado por testes novos:
  - `session_crowns_r171_test`: na R170 falha, B recebe saldo 5010 de A; na R171 passa.
  - `sessao_coroas_invariantes_r171_test`, caso "lento em crownWallet": na R170 falha, B recebe `crowns_reward` e `crowns_state` com saldo 7010 de A; na R171 passa.
- **Os dois arquivos históricos** (`session_hardening_test.cjs` e `session_send_defer_test.cjs`) estão **idênticos** à R170: `git diff 296942d` dá 0 linhas. Nenhuma assertion foi enfraquecida, e os 35 passam.

`sessao_coroas_invariantes_r171_test` (6 testes) checa por **dono**, não por contagem. A conta A tem marcas: apelido, saldo ≥ 7000 e Fundador nº 77. Cenários:

- A → logout → B com banco lento antes e depois de escolher os aparelhos;
- login lento de A seguido de B;
- revalidação antiga de A que volta **válida** depois de B entrar;
- resposta adiada de A durante a revalidação: entregue a A se confirmada; descartada se trocar para B;
- A e B em aparelhos diferentes.

### Teste ajustado

`hardening_r170_test` (SEC-004): o `analysis_request` agora informa a partida (`match_id: ''`, `mode: 'bot'`), porque a liberação ficou mais restrita. As assertions são as mesmas.

---

## 12. R172: os 3 achados que o Orca ainda reproduziu na R171b (`c6d946d`)

Relatórios do Orca: `security-r171-retest-20261020` e `security-r171b-retest-20261020`. Rodei os scripts dele (`independent_*.cjs`) na R171b e na R172:

| Script do Orca | R171b `c6d946d` | R172 |
|---|---|---|
| `independent_founder_boot_race` (limite 1, gravação do limite atrasada, 2 pagamentos) | 2 × `paid` → **2 Fundadores / limite 1** | 2 × `founder_capacity_not_ready` → **0 Fundadores**; pedidos seguem pendentes |
| `independent_reports` (1ª gravação falha) | 1ª "denunciada", retry `duplicate` → **denúncia perdida** | 1ª **erro**, retry **gravado**, outra pessoa gravada → nada perdido |
| `independent_bot_restart` (mesma partida, outra conta, serviço novo) | depois do reinício: **B ganha Platina** | depois do reinício: **`bot_game_reused`** |
| `independent_webhook_retries` (ressalva: consulta que volta vazia) | `ignore` (1 consulta) | consulta de novo (2 consultas) |

No script do Fundador só adicionei captura de erro (`.catch`) e `entitlements || new Map()`, porque na R172 os pagamentos são recusados e não sobra nenhum direito para contar. A lógica do ensaio não mudou.

### 1. Fundador no boot (bloqueador)

**Servidor: `founder_ready` começa falso.** Vira verdadeiro só quando:

- a capacidade existe no banco (migração 0023);
- o servidor gravou o limite;
- o banco devolveu **exatamente** o `FRAIHA_FOUNDER_LIMIT`.

Sem a 0023, erro de SQL, resposta vazia ou valor diferente: o Fundador fica **fechado**, nunca "sem limite". Enquanto `founder_ready` for falso:

- criar pedido de Fundador → `founder_unavailable`;
- webhook → erro 500 (o Mercado Pago repete);
- JÁ PAGUEI e cartão → "aguarde";
- reconciliação → adiada.

Nada disso entrega Fundador, e os pagamentos continuam pendentes, sem perda. Club e o resto do jogo seguem normais. A confirmação espera no máximo 3 s por operação e tenta de novo a cada 5 s.

**Banco: a 0023 nasce fechada** (`configured = false`).

- `fraiha_pay_and_grant` de Fundador sem limite configurado → `raise founder_capacity_not_configured` (a transação inteira é desfeita).
- `fraiha_grant_paid_missing` pula Fundador.
- Só `fraiha_founder_set_limit` ou `fraiha_founder_reserve`, chamados pelo servidor, configuram.
- Na 0023 da R171b, o banco recém-migrado com 2 pedidos entregava **2 Fundadores** antes de o limite 1 ser gravado (reproduzido no Postgres 16). Na R172 recusa.

**Reinício:** o servidor novo começa fechado de novo e só reabre depois de reconfirmar o limite, inclusive quando o limite mudou (testado 2 → 1).

**Explícito:** `FRAIHA_FOUNDER_LIMIT` vazio continua significando "sem limite", mas só depois de o servidor gravar 0 de propósito e o banco confirmar. Ausência de linha, valor nulo ou falha **nunca** viram "sem limite".

**Testes** (`founder_boot_r171_test`, 11 testes):

- os passos do Orca;
- 1/2, 1/10, 2/10 e 3/25 com webhook, webhook repetido, JÁ PAGUEI, cartão e reconciliação ao mesmo tempo, antes e depois de `founder_ready`;
- venda fechada e Club aberto;
- sem 0023;
- banco devolvendo 0, nulo, vazio, 5, erro de SQL ou "migração ausente";
- reinício com limite mudado;
- sem limite.

A invariante `Fundadores <= FRAIHA_FOUNDER_LIMIT` foi conferida em todos.

**Postgres 16 real** (`founder_seats_pg_test`, 15/15): banco recém-migrado fechado; 1/2, 1/10 e 2/10 com avisos chegando antes, durante e depois de `fraiha_founder_set_limit`; reconciliação.

### 2. Denúncia após falha de gravação

A marca de "já denunciada" (`reportSeen`) só é gravada **depois** que a denúncia foi salva.

- Falha → resposta `report_failed` ("tente de novo"), nada marcado e o limite por pessoa/IP não é gasto.
- Tentativas iguais enquanto a primeira ainda grava esperam o resultado dela: se falhar, todas recebem erro.
- Depois do sucesso, mesma pessoa + mesma mensagem + mesmo tipo fica bloqueado normalmente.
- `Reports.file` (perfil, DM, chat da partida) desfaz a marca e o limite quando o banco falha e devolve erro, em vez de "ok" calado.
- O chat da **partida** tinha o mesmo problema (`match.reports` marcado antes de gravar) e foi corrigido igual.

Testes: falha → retry grava → 3ª repetida; outro jogador grava; reinício (a mensagem antiga do chat efêmero deixa de existir, a nova é denunciável, nada perdido nem duplicado); concorrência; limite não gasto; chat da partida; `Reports.file`.

### 3. Replay de Bot após restart

**Migração nova `0024_fraiha_bot_partida_unica.sql`:** coluna `bot_progress.game_hash` = sha256(bot + lances), com índice **único**.

- **Identificador:** só o que não dá para trocar sem invalidar o replay, ou seja o bot e os lances. Horário, ordem dos campos e campos extras não mudam o identificador. A cor vem da própria partida (cor declarada errada = partida inválida).
- **Antes de gravar a 1ª vitória** de qualquer nível, o servidor procura o dono no **banco**. Se a partida for de outra conta → `bot_game_reused`. Duas contas ao mesmo tempo: o índice único deixa só uma gravar; a outra recebe 23505 e é recusada.
- **Sem a 0024:** o servidor grava o progresso sem o identificador, a proteção volta a ser só em memória, e o log mostra ERRO. **Aplicar a 0024 junto com a R172.**

Testes:

- passos do Orca (serviço novo, mesmo banco);
- duas instâncias ao mesmo tempo;
- nível baixo;
- mesma conta: revanche, sem recompensa nova;
- payload idêntico, ordem dos campos, timestamp e campos extras;
- partida diferente aceita;
- SupabaseStore com respostas reais do PostgREST (409/23505 e coluna ausente);
- Postgres 16 com 3 contas ao mesmo tempo → 1 gravada.

**Fora do escopo** (como pedido): outro motor jogando pelo usuário.

### Ordem de publicação da R172

1. Supabase → SQL Editor: `0023_fraiha_fundador_vagas.sql`, depois `0024_fraiha_bot_partida_unica.sql`.
2. **Logo em seguida**, `PUBLICAR-SERVIDOR-R172.cmd`. Entre a 0023 e o servidor novo subir, a entrega de Fundador fica em espera, sem perda.
3. Conferir no log do Render: `founder_ready: limite de vagas confirmado no banco = <limite>`.
4. Cloudflare: o jogo não mudou desde a R171b (pasta `FRAIHA_R171B_CLOUDFLARE`).
