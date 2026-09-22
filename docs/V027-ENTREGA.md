V0.27 - Fase 1 Ranked
Entrada JOGAR RANQUEADO; quatro modos 3/5/10/20 minutos; classificacoes independentes com liga, PL, V/D/E, partidas e maior liga. Perfil mostra os quatro registros.
Progressao reutilizavel em ranked/progression.gd. PL conforme tabela, promocao em 100 com excedente, sem rebaixamento; piso 0 e teto 100 na ultima liga. Empates provisoriamente 0 PL; diferencas acima de 100 usam faixa extrema. API recebe diferenca assinada do adversario. Armazenamento local separado, sem vinculo aos resultados de Bot/Casual.
Sem matchmaking, servidor, deploy, persistencia online, MMR ou pre-move. Tempos sao configuracao dos modos, nao relogios competitivos ativos. Proxima fase: definir contrato de resultados/autenticacao antes de ligar partidas reais. Nao avancar automaticamente.
