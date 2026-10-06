# FRAIHA — Tema escolhido pelo adversário (design, próximo passo)

Estado: **DESIGN APENAS**. Nada aqui foi implementado, commitado em código, aplicado no banco ou publicado.
Pré-requisito já entregue (R46, commit 2b7903a): placa do adversário (proposta A) com selo, moldura,
avatar, título/liga, acento da liga e indicador de voz.

## Objetivo
Mostrar ao jogador, na mesa online, o tema (universo/arena) que o ADVERSÁRIO escolheu — como
identidade visual dele (ex.: faixa/emblema do tema na placa), sem trocar o tabuleiro de quem joga.

## Decisão de produto pendente (perguntar antes de implementar)
1. Onde aparece: (a) só um emblema/faixa na placa do adversário (recomendado, baixo risco);
   (b) metade do cenário com a arena dele; (c) tabuleiro dele. (b) e (c) mudam a leitura do jogo → evitar.
2. Se o jogador pode desligar ("ver só meu tema").

## Contrato (proposta)
- Novo campo público `theme` dentro de `look()` em `online_v021/accounts/cosmetics.js`
  (viaja junto com badge/title/frame para mesa, convite, festa e DM — mesmo caminho do R41).
- Valor = id de `cosmetics/theme_catalog.gd` (`wood`, `iron`, … `challenger`, `fundador`, `club`).
- **Autoridade no servidor**: só envia o tema se a conta tem direito a ele:
  - temas de liga: liga máxima da conta ≥ `unlock_league` do tema;
  - `fundador`: `is_founder`; `club`: Club ativo (mesma regra de `effective()`).
  - Sem direito / desconhecido → `''` (cliente mostra o padrão da liga). Nunca confiar no cliente.
- Escolha do tema: hoje é preferência local do cliente. Para viajar, precisa ser salva na conta
  (`acct_set_cosmetics` com campo `theme`, validado como acima).

## Banco
- Requer coluna nova (ex.: `profiles.profile_theme text default ''`) → **migration** 0006.
- Supabase é compartilhado staging/produção → só com autorização explícita, auditoria read-only antes.
- Compatibilidade: servidor novo sem a coluna → `theme: ''`; cliente antigo ignora o campo extra.

## Cliente
- `ranked/ranked_ui.gd`: placa lê `look.theme`; se vazio usa o acento da liga (comportamento atual).
- Só visual: nada altera PL, matchmaking, relógio, regras ou resultado.

## Testes previstos
- Servidor: `look()` filtra tema bloqueado; `validate()` recusa tema sem direito; Club vencido → some.
- Cliente: placa com/sem tema, desktop/retrato/paisagem; cliente novo + servidor antigo.

## Ordem de rollout
migration (autorizada) → servidor staging → cliente → QA staging → produção (autorizada).
