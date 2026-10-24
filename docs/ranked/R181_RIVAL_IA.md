# R181 · Rival de IA na fila (Ranked e Casual)

Aprovado pelo dono (23–24/10/2026): caminho do meio, honesto.

## Regras
- Quem espera **15 s** (FRAIHA_QUEUE_AI_WAIT_MS, padrão desde a R184) na fila sem ninguém recebe um **rival de IA da mesma liga**.
  Pessoas sempre têm prioridade: o pareamento normal roda antes, a cada tick.
- A IA tem nome de personagem (Sir Gambito, Dama de Ferro…), avatar grátis, pensa num tempo parecido com o de uma
  pessoa (rápido na abertura, ~1/32 do relógio que sobra depois, às vezes demora mais) e manda emote de vez em quando
  (BOA SORTE no começo, PARABÉNS/BOA PARTIDA no fim, raramente BOA JOGADA). Máx. 4 por partida.
- Sempre marcada: `opponent.ai = true` → o cliente mostra "Nome · IA" (tela de encontrado, cartões, resultado).
- **Ranked contra IA:** metade do PL (vitória e derrota). Força oculta e placar V/D/E não mudam. Nada vai para a
  tabela `matches` (a IA não tem conta). Grava só liga/PL do humano, condicional ("só se ainda estiver como lido").
  Precoce (desistência/abandono antes de 5 lances de cada lado) = 0 PL.
- A IA nunca entra no ranking nem nas vagas do Challenger. Sem Coroas/indicação para a IA (o humano recebe Coroas
  como em qualquer partida de 10+ meios-lances).
- Empate: a IA nunca oferece; jogar o lance recusa a oferta. Desiste quando está claramente perdida (avaliação ≤ −9 peões
  por 3 lances seguidos, depois do lance 20, 50% de chance).
- Revanche contra IA: recusada com aviso ("entre na fila de novo"). Denúncia contra IA: aceita sem gravar.
- `FRAIHA_QUEUE_AI=off` desliga (fila volta a ser só de pessoas). Admin fechando o ritmo também desliga a IA nele.

## Força (calibração com o Stockfish do jogo)
Ferramenta: `online_v021/tools/calibrar_rival_ia.js` — o rival (mesmo código do servidor, `pickMove`) joga contra o
Stockfish 19 lite com `UCI_LimitStrength` + `UCI_Elo 1320` (o mínimo do Stockfish), 100 ms por lance, cores
alternadas. Elo estimado = 1320 + 400·log10(p/(1−p)).

| Nível | Parâmetros (skill/profundidade/1-lance/aleatório) | Partidas | Pontos | Elo estimado |
|---|---|---|---|---|
| **Madeira (final)** | 0 / 6 / 22% / 6% | 80 | 11 (8V 6E 66D) | **≈ 1001** |
| Madeira (rodadas anteriores) | 0 / 6 / 16–18% / 4–4,5% | 110 | 22 | ≈ 1030–1110 |
| **Ferro (final)** | 0 / 7 / 8% / 2% | 60 | 22 (20V 4E 36D) | **≈ 1225** |
| testes descartados | 0/5/30%/10% → ≈ 808 · 1/8/5%/1% → ≈ 1443 | | | |

Margem de erro: ±80–100 Elo (amostras de 60–80 partidas).

Leitura: o UCI_Elo do Stockfish é calibrado contra motores (escala CCRL, ritmo 60 s + 0,6 s). Com 100 ms por lance a
âncora fica um pouco mais fraca que 1320, então os números acima são, se algo, levemente otimistas. Referência
aproximada para humanos: Madeira ≈ 1000 fica na faixa dos bots "iniciante/intermediário baixo" do chess.com
(~800–1000) e de um jogador ~1200–1300 no Lichess (ratings do Lichess costumam ser 200–300 acima); Ferro ≈ 1200 fica
perto do bot de 1200 do chess.com e ~1400–1500 no Lichess. Bronze em diante usa o limitador oficial do Stockfish
(UCI_Elo 1400 … 2600).

## Analytics (Admin → Sessões)
- "Rival IA encontrado após 25s (Ranqueado): Sir Gambito" (ranked_found / casual_found com vs_ai)
- "Fim de partida (Ranqueado, rival IA): VITÓRIA (+9 PL)"
- 1ª partida: "Viu o convite do 1º desafio", "Aceitou o 1º desafio", "Pulou o 1º desafio…", "Venceu BOT MADEIRA",
  "Clicou no próximo desafio após vitória (BOT FERRO)".

## Recomendação (não implementada): liberar o Ranked depois de jogar bots?
Não recomendo travar o Ranked atrás de bots agora: com o rival de IA, ninguém fica sem jogar, e uma trava a mais
é mais um degrau para quem veio do anúncio querendo "jogar online". Se quiser testar, a versão leve é só
**recomendar** (o botão do Ranked mostra "Comece pelo BOT MADEIRA" até a 1ª vitória), sem bloquear.
