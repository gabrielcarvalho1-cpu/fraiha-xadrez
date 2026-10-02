# R33 · BLEFE REAL

Modo de blefe de cartas, isolado do xadrez. 1 humano + 3 bots, partida completa: Home → tutorial →
partida → XEQUE → Relógio de Xeque → XEQUE-MATE → eliminações → vitória/derrota → histórico.

`mode_id = blefe_real` · `ruleset_version = 1`. Sem Stockfish, sem Ranked/Elo/PL, sem servidor,
sem migração. Nada do xadrez foi alterado além da linha nova da Home e do filtro do histórico.

## Decisões do dono do projeto (R33)
* Regras = as do pedido em texto (não as do pacote de arte): 20 cartas (6 Rei, 6 Rainha, 6 Cavalo,
  2 Peão Coroado = coringa), peça da rodada Rei/Rainha/Cavalo, Relógio de Xeque POR JOGADOR com
  3 posições (2 seguras + 1 xeque-mate, sem reposição).
* As cartas aprovadas traziam outra regra impressa: só a faixa da legenda foi trocada (e o selo ×N).
* Nome "Blefe Real" (as telas de referência diziam "Marcha Real", que já é o modo de corrida da R32);
  nova linha na Home, logo abaixo da MARCHA REAL.

## Arquitetura
| Arquivo | Papel |
|---|---|
| `blefe/rules.gd` | Motor único: baralho, embaralhar, distribuir, peça da rodada, ordem, validação, XEQUE, relógio, coroas, eliminação, próxima rodada, vitória. Estados SETUP → ROUND_START → TURN_WAITING → CARDS_PLAYED → CHALLENGE → REVEAL → CLOCK_RESOLUTION → (CHECKMATE) → ROUND_END / MATCH_END. |
| `blefe/ai.gd` | Bots (cauteloso, equilibrado, blefador). Recebem só `public_state()` + a própria mão; devolvem um PEDIDO que o motor valida. |
| `blefe/blefe_ui.gd` | Fluxo da tela (tutorial, partida, apresentação do XEQUE, resultado, abandono, histórico). Não decide regra. |
| `blefe/blefe_view.gd` | Desenho nas coordenadas das telas de referência (PC 1920x1080, retrato 1080x1920, paisagem 1950x900). |
| `analysis/match_history.gd` | Histórico comum (já existente): `add_entry` com mode_id/ruleset_version. |

A animação nunca é a autoridade: quando o XEQUE é pedido, o motor já resolveu tudo (revelação,
relógio, coroa, eliminação, vitória); a tela só apresenta (revelar → relógio → seguro/xeque-mate).

## Regras implementadas
* 4 lugares em sentido horário: você (baixo), Dama de Ferro (esquerda), Sir Gambito (cima), Torre Velha (direita).
  Primeiro jogador sorteado.
* 3 Coroas. 5 cartas por jogador vivo; o que sobra fica fora da rodada; eliminado não recebe cartas.
* Na vez: JOGAR 1–3 cartas viradas (declaração automática "N <peça da rodada>") ou XEQUE na jogada
  imediatamente anterior. Não existe passar.
* XEQUE: todas verdadeiras (peça da rodada ou Peão Coroado) → quem chamou perde; pelo menos uma falsa → quem jogou perde.
* Quem perde aciona o PRÓPRIO relógio: [2 seguras + 1 xeque-mate] embaralhadas, consumidas sem reposição
  (1/3 → 1/2 → 1). XEQUE-MATE tira 1 Coroa e embaralha um ciclo novo só daquele jogador.
* Todo XEQUE encerra a rodada; a próxima começa por quem perdeu o desafio (ou o próximo vivo).
* Sem cartas: fora dos turnos até o fim da rodada. Se só 1 (ou nenhum) jogador tem cartas, a última
  jogada é resolvida por XEQUE automático do próximo jogador vivo.
* Tempo: 30 s por vez; nos últimos 8 s o relógio da faixa pisca. Ao estourar, o motor joga 1 carta
  escolhida às cegas; nunca XEQUE.
* Último com Coroa vence. Sementes fixas nos testes; aleatória em produção.

## Bots
* Não enxergam mãos alheias, cartas viradas nem a ordem do relógio (teste: mesas com mãos alheias
  diferentes e mesmo estado público → mesma decisão).
* Suspeita do XEQUE: 8 cartas verdadeiras no baralho (6 da peça + 2 Peões) − as que o bot tem na mão,
  quantidade declarada, revelações anteriores do jogador, cartas que ele ainda tem, perfil e um pouco de sorte.
* Perfis medidos em 120 partidas bot × bot: blefe cauteloso ~50% < equilibrado ~54% < blefador ~65% das jogadas.

## Artes (inventário → uso)
| Pacote (FRAIHA-Marcha-Real-compilado.zip) | Uso no jogo |
|---|---|
| `mesa/mesa_cena_com_tapete.png` | Cena da partida (posição/escala medidas nas 3 telas de referência) |
| `relogio/relogio_{neutro,pulsando,perigo,quase,disparado}.png` | Relógio no centro (3 → neutro, 2 → perigo, 1 → quase; pulsando ao acionar; disparado no XEQUE-MATE) |
| `cartas/carta_{rei,rainha,cavalo,peao}.png` + `carta_verso.png` | Mão, pilha, revelação, tutorial (faixa da legenda trocada, ver abaixo) |
| `cartas/carta_{bispo,torre}.png` | Não usadas (fora do baralho do Blefe Real) |
| `interface/botao_xeque_*.png` (5 estados) | Botão XEQUE (normal, hover, pressionado, desabilitado, ativado) |
| `interface/botao_dourado.png` / `botao_escuro.png` | JOGAR CARTAS, JOGAR AGORA, JOGAR NOVAMENTE / VOLTAR, VER TUTORIAL, VOLTAR AO MENU (texto vivo por cima) |
| `interface/coroa.png` / `coroa_perdida.png` | Coroas das placas, do XEQUE-MATE e do resultado |
| `interface/referencia_placas_jogador.png`, `referencia_coroas.png` | Referência dos 8 estados da placa (montada no jogo, como diz a ESPECIFICAÇÃO §10) |
| `fontes/Jersey20`, `Jacquard24` (OFL) | Textos e títulos ("Blefe Real", "Xeque-Mate", "Vitória") |
| `telas_referencia/05_tutorial.jpg`, `06_resultado.jpg` | Fundos do tutorial e do resultado (o próprio pergaminho/raios, sem o conteúdo) |
| `telas_referencia/01..04` | Medidas e comparação lado a lado |

Ferramentas (repetíveis): `tools/blefe_card_labels.py` (legenda + selo ×N), `tools/blefe_assets.py`
(reduz para o tamanho de tela, botões sem texto), `tools/blefe_backgrounds.py` (fundos),
`tools/home_menu_11rows.py` (Home com 11 linhas; substitui `home_menu_10rows.py`).

Telas sem referência própria (desenhadas com os mesmos painéis/cores/fontes): tutorial e resultado no
celular em pé, derrota, menu ≡, confirmação de saída, aviso "relógio não disparou".

## Testes
* `tests/blefe_rules_test.gd` (53): baralho, distribuição, validação, XEQUE certo/errado, coringa,
  relógio sem reposição e reinício, coroas, eliminação, pular sem cartas/eliminados, XEQUE automático,
  vitória, timeout, estado público sem informação privada, bots legais, 120 partidas sem travar, perfis.
* `tests/blefe_ui_test.gd` (33): Home, tutorial, seleção (máx. 3), toque duplo (JOGAR, XEQUE, carta),
  XEQUE → relógio → xeque-mate, timeout, partida inteira, histórico (mode_id/ruleset_version, posição,
  duração, vencedor, estado final), jogar de novo, abandono com confirmação, filtro, 3 formatos.
