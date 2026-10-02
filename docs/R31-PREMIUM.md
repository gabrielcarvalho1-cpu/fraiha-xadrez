# R31 · Benefícios do Pacote Fundador e do Club FRAIHA em funcionamento

FRAIHA continua **não sendo pay-to-win**. Nada abaixo altera PL, matchmaking, tempo, regras, resultado
ou dá engine em partida humana. Análise é sempre pós-partida.

## Pacote Fundador
| Benefício | Onde está |
|---|---|
| Selo Fundador | Ícone ao lado do nome (Home, Perfil, cartão do celular, Amigos, chat, convites e faixa da partida) |
| Avatar Fundador | Galeria do Perfil (R30) |
| Título "Fundador do Reino" | Perfil e perfil público (Amigos) |
| Moldura de perfil exclusiva | Moldura obsidiana e ouro (`club_frame.gd`, estilo `fundador`) |
| Conjunto de peças Fundador | `cosmetics/v031/fundador_pieces.png` (marfim dourado e obsidiana) |
| Universo Fundador | `cosmetics/v031/fundador_arena.png` + tabuleiro próprio (tema `fundador`) |
| Comunidade WhatsApp | Botão "ENTRAR NO GRUPO DOS FUNDADORES" (`FOUNDER_WHATSAPP_URL`) |
| Acesso antecipado | LABORATÓRIO na Personalização (1º recurso: coordenadas no tabuleiro) |
| Destaque social | Selo/título/avatar enviados pelo servidor nos perfis públicos (`badge`, `title`, `founder`, `club`) |
| 30 dias de Club | Servidor: `grantEntitlement('founder')` soma 30 dias de Club (`club_source = founder_bonus`) |

## Club FRAIHA
| Benefício | Onde está |
|---|---|
| Análise avançada | Análises ilimitadas (servidor, desde 0005) |
| Treine meus erros | MEU CLUB → TREINOS: erros das últimas análises guardadas viram exercícios |
| Treino personalizado | MEU CLUB → TREINOS: exercícios da fase em que você mais erra |
| Estatísticas avançadas | MEU CLUB: precisão por modo/cor/fase, tendência, sequência, erros por partida |
| Relatório semanal | MEU CLUB e página do Club (membro): semana real (segunda a domingo, UTC) |
| Histórico detalhado | MEU CLUB: últimas análises; REVER ANÁLISE reabre o relatório completo (20 mais recentes) |
| Desafios Club | 5 desafios semanais acompanhados automaticamente |
| Cosméticos Club | Universo Academia Club + peças esmeralda (`cosmetics/v031/club_*`) |
| Selo Club | 3 ícones (Rainha, Bispo, Cavalo) + 3 avatares exclusivos |
| Personalização premium | Combinar qualquer conjunto de peças conquistado com qualquer cenário |
| Acesso antecipado | LABORATÓRIO |
| Desconto futuro na loja | EM BREVE (a loja ainda não existe) |

## Escolha do ícone
FRAIHA PREMIUM → PERSONALIZAÇÃO (ou Perfil → PERSONALIZAR). Opções: Automático, Nenhum, Selo Fundador,
Club · Rainha, Club · Bispo, Club · Cavalo. Bloqueados aparecem em cinza com o requisito.
A escolha fica no aparelho e vai para a conta (`acct_set_cosmetics`). Se o direito acabar (ex.: Club
vencido), o item some para todos, mas a escolha fica guardada para quando voltar.

## Servidor (online_v021)
* `accounts/cosmetics.js`: validação (direitos + escada de bots) e o que os outros veem.
* `acct_set_cosmetics {avatar_id?, badge?, title?, frame?}` → `acct_cosmetics_saved` ou `acct_cosmetics_error`.
* `acct_state.cosmetics` com os itens efetivos.
* Store: `grantEntitlement`, `createPayment`, `getPayment`, `markPayment` (pending → paid uma única vez).
* Perfis públicos: `badge`, `title`, `frame`, `founder`, `club` (embed `entitlements`).
  Sem a 0007, cai para as colunas antigas automaticamente (Amigos não quebra; só o avatar é salvo).

## Migração 0007 (NÃO APLICADA)
`supabase/migrations/0007_fraiha_premium_identity.sql` — aditiva:
`profiles.profile_badge`, `profiles.profile_title` (com CHECK) e a função
`fraiha_grant_entitlement(user, product, source)` (só service_role).
Testada num Postgres 16 + PostgREST locais (`tests/server/premium_stack_test.cjs`). Aplicar só com autorização.
