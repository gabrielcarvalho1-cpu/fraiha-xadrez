# R143 · Ligas e pontos do Ranked (sistema novo)

Aprovado pelo dono em 17/10/2026 depois da simulação (tools/sim/ligas_r143_sim.py, 4.000 jogadores, 1 ano).

## Por que mudou

No sistema antigo (+15 / −10 fixos contra alguém do mesmo nível) cada partida criava pontos: quem vencia 40%
das partidas não descia, e a simulação colocava 86% dos jogadores no Challenger em 1 ano (um jogador médio
chegava lá em ~155 partidas). Empate valia 0 sempre.

## Como funciona

1. **Força oculta** (Glicko-1, a matemática do chess.com) por jogador e ritmo. Começa em 1200 com incerteza 350:
   as primeiras partidas mexem muito, depois estabiliza. Nunca vai para o cliente.
   - escolhe o adversário: faixa de ±120 de Força, +80 a cada 10 s de espera, até ±600 (config.js);
   - corrige o PL: Força acima da esperada para a posição → ganha mais e perde menos.
2. **PL visível que diminui subindo** (contra alguém do mesmo nível):

   | Liga | Vitória | Derrota |
   |---|---|---|
   | Madeira | +20 | −8 |
   | Ferro | +18 | −9 |
   | Bronze | +17 | −10 |
   | Prata | +16 | −11 |
   | Ouro | +15 | −12 |
   | Platina | +14 | −12 |
   | Esmeralda | +13 | −13 |
   | Diamante | +11 | −11 |
   | Mestre | +8 | −8 |
   | Grande Mestre | +6 | −6 |
   | Challenger | +6 | −6 |

   Multiplicador pela diferença entre a Força e a esperada para a posição (750 + posição × 1,15):
   1 + d/350, de 0,5 a 1,8 (da Esmeralda para cima, a vitória vai no máximo a 1,25).
3. **Empate** = meio ponto contra a expectativa: (0,5 − chance de vencer) × (vitória + derrota).
4. **Grande Mestre trava em 100 PL.** O Challenger é por **vaga** (ranked/challenger.js):
   - vagas = 1 a cada 100 contas que jogaram o ritmo nos últimos 30 dias (mínimo 3, máximo 40);
   - candidato = Grande Mestre com 100 PL que jogou nos últimos 7 dias;
   - vaga livre: entra o candidato com mais Força; cheio: o candidato mais forte toma a vaga do Challenger mais
     fraco (menos PL, depois Força) se tiver mais Força que ele (1 troca por vez);
   - Challenger 7 dias sem jogar o ritmo, ou que perde com 0 PL, volta ao Grande Mestre;
   - nunca mexe em quem está na fila, em partida ou com resultado sendo gravado.
5. Rebaixamento igual ao de antes: perder com 0 PL desce uma liga com 75 PL (Madeira não rebaixa).
6. Sem temporadas: ninguém perde o que conquistou. A maior liga alcançada fica para sempre.

## Simulação (6 partidas por dia, desde o lançamento)

| Jogador | Até onde chega |
|---|---|
| Profissional | Challenger em ~66 partidas (~11 dias) |
| Muito forte (top 2%) | Challenger em ~160 partidas (~1 mês) |
| Bom (top 10%) | Diamante em ~80; Mestre só com ~570 |
| Médio | Ouro em ~46, Platina em ~84 |
| Iniciante | Ferro → Bronze |

Distribuição estável depois de ~3 meses: Madeira 7%, Ferro 9%, Bronze 13%, Prata 16%, Ouro 16%, Platina 15%,
Esmeralda 11%, Diamante 7%, Mestre 4%, Grande Mestre 1,4%, Challenger 1%.

## Banco

`supabase/migrations/0020_fraiha_ranked_forca.sql` (aditiva): colunas `forca` / `forca_rd` em ranked_stats e a
função de gravação passa a guardá-las; a leitura das duas colunas fica só para o servidor. O servidor R143
funciona sem ela (estima a Força pela liga a cada partida), mas só com ela a Força fica guardada.
Contas antigas continuam na liga atual; a Força delas começa estimada pela liga (incerteza 200).
