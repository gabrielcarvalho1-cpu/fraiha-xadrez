# R32 · MARCHA REAL, Histórico de partidas e Perfil (avatar/ícone com APLICAR)

## MARCHA REAL (novo modo — não é xadrez)
* Entrada: Home → **MARCHA REAL** (linha nova do menu, abaixo de LIGAS E RANKING).
* Jogo contra bots: você (Marfim) + aliado (Ônix, bot) contra Rubi e Esmeralda (bots).
* Regras (padrão das cartas da arte): A sai do pátio ou anda 11 · K sai do pátio ou anda 13 · Q 12 ·
  J troca de lugar · 10/9/8/6/3/2 andam · 7 divide entre até 2 peões · 5 move qualquer peça · -4 volta 4.
  Cair em cima manda de volta ao Pátio; peão no próprio Portão protege a casa; quem coroa os 4 joga com
  os do aliado; vence a dupla que coroar os 8. Sem jogada: descarta. 30 s por vez (tempo esgotado: jogada sugerida).
* Arte: os PNGs do ZIP são usados diretamente (cartas, peões, retratos dos bots, símbolos). Únicas
  alterações pedidas: as 4 placas do Pátio foram reenquadradas (ponta escondida pela trilha reconstruída
  da própria placa, placa inteira afastada da trilha) — `tools/marcha_board_fix.py`; cantos fora da moldura
  transparentes. Fonte Oswald (OFL, `marcha/art/fonts`) para os textos condensados da referência.
* Telas: PC (tela_desktop), celular em pé (tela_celular), celular deitado (layout do PC escalado).
* Tutorial: abre sozinho na 1ª vez; também em COMO JOGAR e no "?" da partida.
* Acesso: Club = ilimitado. Sem Club = 1 partida por dia.
  - Com conta + servidor + 0008: o servidor decide (`marcha_status`, `marcha_start`).
  - Sem conta / servidor sem 0008: conta no aparelho (`user://marcha_daily.cfg`).

## Histórico de partidas
* Home → **HISTÓRICO DE PARTIDAS** (abaixo de CONHEÇA O FRAIHA) e no celular.
* Toda partida terminada (xadrez: computador, online, ranqueada, local; e Marcha Real) fica no aparelho (últimas 60),
  com filtros e **REVER ANÁLISE** (se já analisada) / **ANALISAR** (usa a cota; Club ilimitado).

## Perfil
* Tocar num avatar só o seleciona; **APLICAR AVATAR** troca de verdade (se houver foto, a foto sai).
* Aba **ÍCONES** separada dos avatares, com **APLICAR ÍCONE** (PC e celular).

## Home
* Menu com 10 linhas: arte oficial recomposta (`tools/home_menu_10rows.py` → `home_forest_v3.png`),
  as 8 linhas originais com os mesmos pixels (compactadas 0,891 na vertical) + 2 novas da mesma moldura.

## Migração 0008 (NÃO APLICADA)
`supabase/migrations/0008_fraiha_marcha_real.sql`: tabela `marcha_usage` + `fraiha_marcha_consume`
(só service_role). Testada em Postgres local (`tests/server/premium_stack_test.cjs`).

## Auditoria fraiha-dev v2.8 (aplicada na própria R32)
* **Isolamento:** tudo da Marcha está em `marcha/` (regras, IA, UI, acesso, arte). O xadrez só ganhou
  a entrada na Home e o histórico comum; Elo/PL/Ranked/bots/regras do xadrez não mudaram.
* **Motor único:** `rules.apply()` recusa qualquer jogada fora de `legal_moves()` (humano, bot e jogada
  automática do tempo esgotado passam pela mesma validação). A saída do Pátio agora lista cada peão
  (antes a UI aceitava um peão que o motor não listava). `RULESET_VERSION = "marcha-real-1"`.
* **Histórico comum:** todo registro tem `mode_id` (`chess` | `marcha_real`) e `ruleset_version`
  (`chess-fide-1` | `marcha-real-1`); registros antigos migram para `chess` ao carregar. A Marcha grava
  vitória, derrota e abandono (dados do modo em `data`: rodadas, coroados, aliado, últimas jogadas).
  Filtro **MARCHA REAL**; linha da Marcha sem ANALISAR (modo de cartas).
* **Cota:** com conta, o servidor decide (teste cliente+servidor `tests/marcha_server_client_test.gd`:
  sem registro no aparelho o servidor continua recusando a 2ª partida). Convidado: aparelho.
  Web: o dia consumido vai também para o `localStorage` (o user:// do Godot Web só chega ao IndexedDB
  alguns segundos depois) — F5 1 s após começar não devolve a partida.
* **Arte × build:** comparação lado a lado com `tela_desktop.png` e `tela_celular.png`; corrigido:
  placa "Você" usa o retrato Marfim da arte; placas do celular em retrato no estilo da tela_celular.
* **Toque no celular:** o toque chegava 2× (toque + clique emulado) e devolvia ao salão — corrigido.
* **Conhecido / não bloqueia:** celular deitado usa o layout do PC escalado (sem arte de referência
  própria; textos pequenos em telas de 390 px de altura). Tutorial "visto" pode reaparecer se o F5 vier
  menos de ~3 s depois de fechá-lo (mesma gravação atrasada do user:// do Web).
