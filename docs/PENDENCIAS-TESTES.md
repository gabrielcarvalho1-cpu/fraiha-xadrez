# Pendências permanentes de testes

Registro de comportamentos conhecidos de testes que NÃO são regressão de código. Cada item tem erro, frequência,
commit em que foi medido e a evidência. Remover o item só quando a causa for resolvida.

## P1 · `tests/server/party_test.cjs` demora 80–215 s (timeout em runner com limite de 120 s)

- **Erro observado:** `timeout 120 node tests/server/party_test.cjs` termina com código 124 (morto pelo `timeout`),
  sem nenhum `FAIL`. Saída para no meio do bloco XEQUE ou da MARCHA REAL.
- **Causa:** a duração do teste é aleatória. A MARCHA REAL é jogada inteira por `chooseAI` + baralho embaralhado
  (e o XEQUE usa `Math.random()` para os XEQUEs). O número de jogadas varia de ~430 a ~1280 e cada jogada custa
  ~150 ms no servidor de teste (tempos de animação encurtados por env). O próprio teste admite até 240 s (MARCHA)
  + 120 s (XEQUE). Um runner com limite de 120 s corta as partidas longas.
- **Não é:** regressão (custo por jogada igual na base e no candidato), nem recurso pendurado (o processo sai
  ~4,9 s depois do resumo nos dois casos — o último `next(..., 4000)` pendente; não trava).
- **Frequência (medida em 2026-10-07):** sem limite: 9/9 passaram (24/24 checks). Com limite de 120 s:
  5 das 9 durações passaram de 120 s; na rodada anterior, 2 de 3 execuções deram timeout.
- **Commit medido:** base `be1ccd6` (HEAD) × candidato `be1ccd6` + mudanças do Casual por ritmo
  (`online_v021/backend.js`, `online_v021/admin/*`).
- **Evidência:**

  | execução | jogadas MARCHA | fim MARCHA | ms/jogada | total | saída após resumo |
  |---|---|---|---|---|---|
  | base 1 | 468 | 74,4 s | 157 | 108,4 s | 4,9 s |
  | base 2 | 428 | 66,9 s | 154 | 90,2 s | 4,8 s |
  | base 3 | 596 | 91,3 s | 152 | 110,4 s | 4,8 s |
  | candidato 1 | 1276 | 189,4 s | 148 | 208,3 s | 4,9 s |
  | candidato 2 | 724 | 109,3 s | 150 | 138,5 s | 4,9 s |
  | candidato 3 | 648 | 96,3 s | 147 | 122,2 s | 4,8 s |
  | candidato 4 | 432 | 64,0 s | 146 | 83,3 s | 4,8 s |
  | candidato 5 | 866 | 129,0 s | 148 | 157,8 s | 4,9 s |
  | candidato 6 | 592 | 92,2 s | 154 | 123,1 s | 4,9 s |

- **Como rodar enquanto não for resolvido:** sem limite curto (`timeout 400 node tests/server/party_test.cjs`).
- **Correção futura (opcional, fora do escopo atual):** semente fixa para a IA/baralho no modo de teste ou limite de
  jogadas na MARCHA do teste, para a duração ficar previsível.
