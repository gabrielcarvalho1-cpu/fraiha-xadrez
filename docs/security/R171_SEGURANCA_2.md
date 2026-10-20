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
