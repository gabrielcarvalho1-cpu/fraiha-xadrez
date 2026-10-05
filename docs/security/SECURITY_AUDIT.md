# Auditoria de segurança — FRAIHA Xadrez

Data: 05/10/2026. Método: análise estática, prioritariamente READ-ONLY.

## Base, autorização e limites

- Worktree confirmada: `C:\Users\Usuário\Documents\Codex\orca-worktrees\codex-security-audit`.
- Branch inicial/final: `codex/security-audit`.
- HEAD inicial/final: `2e8837b845febfcead613a3d55de52b75b05bceb`.
- Status inicial: limpo, inclusive arquivos não rastreados; diff inicial vazio.
- Skill usada: `.agents/skills/fraiha-xadrez/SKILL.md`, com `references/architecture.md`, seguindo o `AGENTS.md` da raiz. Não foram encontradas instruções AGENTS adicionais nas áreas inventariadas.
- Alvo: `online_v021/`. `online_v021/payments/` e `monetization/` foram completamente excluídos de inspeção interna e de conclusões. Referências a esses módulos nos arquivos compartilhados não constituem auditoria de pagamentos.
- Os motores protegidos `marcha/rules.gd` e `online_v021/modes/marcha_rules.js` não foram abertos nem alterados. A integração de Marcha em `modes/party.js` foi examinada, mas seu motor não foi auditado.
- Leituras externas ao alvo: mapa datado do projeto, `package.json`, testes existentes de bots/Ranked e arquivos de análise/integração do cliente necessários para entender a autorização de análise. As referências a módulos excluídos nesses arquivos não foram seguidas.
- Nenhum servidor, teste, build, exportação, script de integração ou exploit foi executado. Nenhum serviço externo foi consultado ou alterado; nenhuma migration foi lida/aplicada nesta auditoria. Não houve instalação de dependências, fetch, commit, stage ou push. Arquivos de credenciais não foram abertos.
- `package.json` confirma `npm start` → `node online_v021/server.js`. O mapa registra uma confirmação histórica do usuário sobre o backend Node, mas isso não comprova o SHA LIVE atual. Não se afirma que estes achados estejam reproduzidos em produção.

**CONFIRMADO** significa que a falha ou ausência de controle é demonstrável pelo fluxo do código desta revisão, sem executar o sistema. Não significa exploração executada, incidente ocorrido ou vulnerabilidade comprovada na infraestrutura publicada. **HIPÓTESE QUE PRECISA DE TESTE** significa que a exploração depende de interleaving assíncrono, desempenho, configuração ou comportamento de componentes não verificados. A severidade considera o impacto plausível no escopo descrito; para hipóteses, é provisória.

Foram registrados **16 achados: 8 confirmados estaticamente e 8 hipóteses**. Nenhum achado recebeu severidade CRÍTICA: não foi demonstrada execução remota de código, exposição de credencial privada ou comprometimento arbitrário de contas de terceiros. Isso não certifica a ausência dessas classes nas áreas não avaliadas.

## Top 10 riscos mais importantes

| Prioridade | ID | Severidade | Risco | Classificação |
| --- | --- | --- | --- | --- |
| 1 | S01 | ALTA | JSON `null` causa exceção fora da proteção do backend | CONFIRMADO |
| 2 | S02 | ALTA | Sessão WebSocket continua autorizada sem prazo/revalidação | CONFIRMADO |
| 3 | S04 | ALTA | Respostas assíncronas de autenticação podem misturar/restaurar sessões | HIPÓTESE QUE PRECISA DE TESTE |
| 4 | S05 | ALTA | Fila Ranked pode entrar após cancelamento ou início de outra partida | HIPÓTESE QUE PRECISA DE TESTE |
| 5 | S08 | ALTA | Conexões, trabalho pendente e tráfego sem orçamento global | HIPÓTESE QUE PRECISA DE TESTE |
| 6 | S03 | MÉDIA | Autenticação rejeitada mantém identidade pública anterior | CONFIRMADO |
| 7 | S07 | MÉDIA | RNG de 32 bits e publicação do sorteio facilitam previsão | HIPÓTESE QUE PRECISA DE TESTE |
| 8 | S06 | MÉDIA | Histórico fabricado pode desbloquear toda a escada de bots | CONFIRMADO |
| 9 | S12 | MÉDIA | Bloqueio/amizade e envio de DM têm janelas de concorrência | HIPÓTESE QUE PRECISA DE TESTE |
| 10 | S09 | MÉDIA | Histórico de análise pode ser fabricado e gravado sem concessão | CONFIRMADO |

## Achados detalhados

### S01 — Mensagem JSON `null` escapa do tratamento de erros

- **Severidade:** ALTA.
- **Arquivo/função:** `online_v021/server.js:37`, callback `message`; `server.js:38`, `handle`.
- **Problema:** validar sintaxe JSON não valida o objeto esperado. `JSON.parse` aceita `null`; o dispatcher acessa `m.type` antes de entrar no `Backend.handle`, cujo `try/catch` não o protege.
- **Cenário concreto:** qualquer conexão WebSocket, sem autenticação, envia uma mensagem textual de quatro bytes contendo `null`. O parse passa, `presence.touch` executa e `handle(ws, null)` lança `TypeError`.
- **Impacto:** exceção não capturada no callback; no processo Node iniciado normalmente pelo entrypoint, pode encerrar o backend e todas as partidas em memória. Repetição após reinício pode impedir recuperação. Não foi verificado supervisor externo.
- **Evidência:** `let m; try{m=JSON.parse(raw)}catch{...}` seguido de `handle(ws,m)`; início de `handle`: `const a=String(m.type||'')`. Não foi encontrado handler global de `uncaughtException` no código não excluído examinado.
- **Recomendação:** exigir objeto não nulo, não array, com `type` string de tamanho limitado; capturar exceções no limite de entrada e isolar falha à conexão. Validar os schemas de mensagens antes dos serviços.
- **Classificação:** CONFIRMADO por fluxo estático; nenhum pacote foi enviado.

### S02 — Autenticação vira sessão sem expiração server-side

- **Severidade:** ALTA.
- **Arquivo/função:** `accounts/auth.js:11`, `SupabaseAuth.verify`; `backend.js:209`, `acct_auth`; gates em `backend.js:153–233`.
- **Problema:** o token é verificado no login, mas o socket guarda somente `ws.user`/`ws.profile`; não guarda expiração nem exige revalidação periódica. O cache de 60 segundos da verificação não limita a vida da sessão já autenticada.
- **Cenário concreto:** um token válido é usado uma vez para autenticar um socket. O usuário mantém a conexão e envia ações após a expiração do token; os handlers continuam autorizando pelo objeto em memória. Revogação/banimento só repercute se existir mecanismo externo efetivo, não observado aqui.
- **Impacto:** prolongamento de acesso a operações de conta, social, histórico e partidas além da validade do bearer. Um token obtido indevidamente pode sustentar acesso sem novo login.
- **Evidência:** `verify` retorna `{id,email,provider}`, sem prazo; `acct_auth` atribui `ws.user = user`; handlers verificam presença de `ws.user`/`ws.profile`, não validade atual. `Presence` mede atividade, não validade de autenticação.
- **Recomendação:** definir prazo máximo da sessão, validar expiração/renovação e revogação conforme o contrato real de Auth; invalidar identidade e participações quando a sessão perder autorização. Evitar uma consulta remota por lance com uma política de revalidação explícita.
- **Classificação:** CONFIRMADO para ausência de prazo/revalidação; comportamento de revogação no Auth real permanece não testado.

### S03 — Login inválido não remove a identidade anterior

- **Severidade:** MÉDIA.
- **Arquivo/função:** `backend.js:211`, ramo inválido de `acct_auth`; `backend.js:84`, `setIdentity`; gates de Casual/chat em `backend.js:153–168`.
- **Problema:** o ramo de token inválido limpa `ws.user` e `ws.profile`, mas não chama `setIdentity(ws, null)` nem limpa o vínculo em `online`.
- **Cenário concreto:** uma conta autentica com perfil e depois envia `acct_auth` com token inválido. Recebe `invalid_token`, porém `ws.identity` ainda contém o UUID/nickname da conta. Pode continuar usando `casual_*` e `chat_*`, cujos gates exigem essa identidade. A conta também pode continuar sendo destino de notificações em `socketsOf`.
- **Impacto:** sessão declarada inválida ainda atua e recebe dados como a identidade anterior em parte do sistema. Isso não permite inventar o UUID de outra conta: pressupõe autenticação anterior válida.
- **Evidência:** o ramo inválido apenas faz `ws.user = null; ws.profile = null`; Casual usa `if (!ws.identity)` e `Ranked.uidOf` prefere `ws.identity`; `socketsOf` filtra estado do socket, sem exigir `ws.user`.
- **Recomendação:** centralizar invalidação de sessão e limpar consistentemente identidade, guest, presença e vínculos dos serviços, incluindo Party. Rejeitar operações/notificações quando a identidade não tiver sessão válida.
- **Classificação:** CONFIRMADO.

### S04 — Autenticação concorrente não tem versão ou cancelamento

- **Severidade:** ALTA.
- **Arquivo/função:** `server.js:38`, despacho assíncrono; `backend.js:109–118`, `state`; `backend.js:209–223`, `acct_auth`; `backend.js:328`, logout.
- **Problema:** mensagens são despachadas sem serialização. `state` captura `const u = ws.user`, faz vários awaits e depois escreve `ws.profile`/`ws.identity`, sem conferir se a sessão ainda é a mesma ou se o socket foi fechado.
- **Cenário concreto:** iniciar login/refresh da conta A, atrasar leituras do store e, durante os awaits, autenticar B ou fazer logout. A resposta antiga pode voltar e instalar perfil/identidade A quando `ws.user` já é B ou nulo. Logout ou fechamento durante verificação também pode ser seguido por uma conclusão antiga de login.
- **Impacto:** identidade pública, participação, notificações e operações podem usar contas diferentes; sessão pode reaparecer após logout; sockets fechados podem ser religados ao mapa. O atacante precisa de sessões válidas das contas envolvidas: não há prova de tomada de conta arbitrária.
- **Evidência:** `return void backend.handle(ws,m)`; `state` captura usuário antes dos awaits e chama `setIdentity` depois; não há contador de geração de sessão ou teste de `readyState` antes da mutação.
- **Recomendação:** usar geração de sessão e comparar usuário/geração após cada await que antecede escrita/envio; cancelar trabalho no logout/close e serializar mutações relevantes por socket.
- **Classificação:** HIPÓTESE QUE PRECISA DE TESTE com atrasos controlados e duas identidades.

### S05 — Verificações de fila Ranked ficam obsoletas após await

- **Severidade:** ALTA.
- **Arquivo/função:** `ranked/service.js:29–45`, `handle/queue`; `service.js:97–117`, `startMatch/tick`; `ranked/matchmaker.js:11–15`.
- **Problema:** partida ativa e `busyElsewhere` são verificados antes de `getRankedStats`. A função `enqueue` executada depois não revalida partida, reserva, sessão ou cancelamento. `mm.has` só cobre entradas ainda presentes naquela fila.
- **Cenário concreto:** enviar `ranked_queue` com leitura lenta e imediatamente entrar em Casual; quando a leitura terminar, a fila Ranked é criada apesar da partida Casual. Outra sequência: vários pedidos Ranked pendentes; um pareia e sai da fila, e um pedido antigo conclui depois, reenfileirando o usuário já em partida. Cancelar enquanto a leitura está pendente também não cancela a conclusão.
- **Impacto:** partidas simultâneas, sobrescrita de `byUser`, abandono indevido e conflitos de resultados/PL. Corrupção persistida do ranking não está comprovada: depende da RPC de banco não avaliada.
- **Evidência:** `getRankedStats(uid).then(all => enqueue(all[mode]))`; `enqueue` só chama `this.mm.enqueue`; `startMatch` instala `byUser` sem uma nova checagem de exclusividade.
- **Recomendação:** reserva compartilhada por usuário antes do await, geração de pedido de fila e revalidação na conclusão; checar exclusividade também ao criar a partida e invalidar pedidos em cancel/logout/close.
- **Classificação:** HIPÓTESE QUE PRECISA DE TESTE com resolução controlada das leituras.

### S06 — Vitória de bot fabricada passa pela validação

- **Severidade:** MÉDIA.
- **Arquivo/função:** `bots/service.js:17–38`, `replay/validateVictory`; `service.js:56–64`, concessão; `accounts/store.js:438`, persistência de progresso.
- **Problema:** legalidade e mate não provam uma partida contra o bot declarado. O cliente fornece os lances dos dois lados, cor e bot; não existe partida server-side ou identificador de execução que vincule o replay ao adversário.
- **Cenário concreto:** uma conta envia um mate cooperativo legal, por exemplo `e2e4 e7e5 d1h5 b8c6 f1c4 g8f6 h5f7`, declarando humano branco. Reutiliza o mesmo histórico em cada nível, respeitando ordem e intervalo, sem vencer a IA correspondente.
- **Impacto:** desbloqueio indevido da escada e recompensas cosméticas. Não altera PL Ranked diretamente.
- **Evidência:** `validateVictory` só exige ID conhecido, cor, 4–600 lances legais e mate contra a cor do bot; o próprio comentário registra que não comprova autoria da IA. O teste existente `tests/server/bot_progress_test.cjs` contém mates fabricados aceitos como progresso; foi apenas lido.
- **Recomendação:** criar partida de bot autoritativa, vincular bot/perfil/cor e nonce à sessão e validar os lances do bot no servidor; concessão transacional e única por partida/conta/bot. Assinar somente dados calculados pelo servidor, não o histórico arbitrário recebido.
- **Classificação:** CONFIRMADO estaticamente; sucesso de gravação depende do schema disponível.

### S07 — RNG previsível e divulgação de saída em XEQUE

- **Severidade:** MÉDIA.
- **Arquivo/função:** `modes/rng.js:4–18`, `rngFrom`; `modes/xeque_rules.js:37–44,125`, sorteio/resultado; `modes/party.js:99,137,147`, snapshot e broadcast.
- **Problema:** semente criptográfica de apenas 32 bits alimenta Mulberry32, que não é um gerador criptográfico. O mesmo fluxo serve sorteios, distribuição e decisões de bots. `last_result.roll` divulga a saída numérica de um sorteio; `rotResult` preserva esse campo.
- **Cenário concreto:** um participante coleta `roll` e demais observações de uma mesa, tenta recuperar/restringir o estado do gerador e acompanha o consumo nas rotinas públicas de bots/rodadas. Se conseguir sincronizar, pode antecipar cartas ou risco do relógio.
- **Impacto:** possível vantagem em jogo de informação oculta e manipulação de decisões/placares. A recuperação do estado e seu custo não foram demonstrados.
- **Evidência:** `crypto.randomBytes(4)` → estado `a`; comentário `mulberry32`; resultado inclui `roll: this.last_roll`; `rotResult` usa spread de todo o resultado, removendo nenhum campo de RNG.
- **Recomendação:** RNG criptográfico para produção; fonte determinística injetada apenas em testes. Não publicar roll/estado/seed; separar RNG de apresentação do usado em decisões e informação oculta.
- **Classificação:** HIPÓTESE QUE PRECISA DE TESTE para previsão explorável; algoritmo e exposição estão confirmados no código.

### S08 — Orçamento de recursos não limita conexões nem trabalho pendente

- **Severidade:** ALTA.
- **Arquivo/função:** `server.js:30–38`, limites/`WebSocketServer`; `backend.js:129–149`, convidados; `social/presence.js:85`, varredura; `accounts/store.js:298`, `req`; `accounts/auth.js:18`, fetch.
- **Problema:** 20 mensagens/s é limite por socket. Não há limite local de conexões por origem/IP, autenticações simultâneas, requisições em voo ou orçamento de bytes/saída. `maxPayload` não é configurado no construtor: o teto de aplicação só roda quando `message` chega. Fetches não têm prazo explícito. A varredura de silêncio percorre somente identidades em `backend.online`, não todas as conexões não autenticadas. Mapas de rate limit não têm descarte de usuários antigos.
- **Cenário concreto:** abrir muitos sockets sem login, manter conexões ociosas ou enviar pedidos grandes com tipos especiais; em sockets autenticados, disparar leituras/gravações permitidas em paralelo. Dependências lentas acumulam trabalho. Outra hipótese é frame inválido emitir `error`: não há listener de erro no socket neste entrypoint.
- **Impacto:** possível esgotamento de memória, CPU, conexões e orçamento de banco; interrupção de partidas. A capacidade real e eventuais controles no proxy não foram avaliados. Não se afirma um limite default específico da versão instalada de `ws`.
- **Evidência:** `new WebSocketServer({server})`, contador `ws.count`, despacho não aguardado, mapas e fetches sem timeout explícito; somente listeners `message/pong/close` registrados para o socket.
- **Recomendação:** limite de transporte explícito, listener de erro, prazo para autenticar, controle de conexões e bytes, limite de trabalho pendente por usuário/serviço/global, timeouts de dependências, backpressure e TTL dos mapas. Manter limites por conta ao reconectar.
- **Classificação:** HIPÓTESE QUE PRECISA DE TESTE de carga/protocolo em ambiente descartável; lacunas locais são evidência, indisponibilidade em escala não foi medida.

### S09 — Gravação de análise não exige concessão ou partida própria

- **Severidade:** MÉDIA.
- **Arquivo/função:** `backend.js:243–248`, `analysis_record`; `accounts/store.js:445–453`, `SupabaseStore.saveAnalysis`.
- **Problema:** ter perfil basta para inserir resumo. Não se exige `analysis_granted`, consumo de cota, partida encerrada pertencente à conta ou idempotência. Um UUID sintaticamente válido é aceito como `match_id` sem consulta de participação.
- **Cenário concreto:** enviar repetidamente resumos inventados, inclusive após cota zero, alterando precisão, resultado, engine, profundidade e ID de partida. A aplicação tenta inserir cada resumo com credenciais do servidor.
- **Impacto:** histórico próprio sem integridade/proveniência, associação tentada a partidas alheias e crescimento de armazenamento. Não foi encontrado uso desses resumos para conceder PL ou acesso ao histórico de outro usuário; efeitos de constraints/FKs reais não foram verificados.
- **Evidência:** `saveAnalysis(ws.user.id, sum)` direto; `match_id` só usa `UUID_RE`; `moves` é cortado para 400 elementos, sem validar conteúdo; `counts` é recebido do cliente; nenhum token de concessão ou chave de operação.
- **Recomendação:** vincular operação à conta/partida concluída autorizada e à concessão de análise; schema fechado com limites numéricos/textuais, idempotência por análise e política de retenção. Marcar métricas calculadas no cliente como não verificadas.
- **Classificação:** CONFIRMADO para falta de autorização contextual e intenção de escrita; persistência efetiva depende do banco.

### S10 — Mutação aceita ID ausente e não vincula versão do estado

- **Severidade:** MÉDIA.
- **Arquivo/função:** `ranked/service.js:49–59`, move/resign; `modes/party.js:337–362`, resolução de sala/ação.
- **Problema:** no Ranked/Casual, ID omitido ou vazio vira a partida atual. Em Party, sala omitida usa `roomOf(uid)` e a versão divulgada em snapshots não é validada em requests. Ranked também não exige revisão para jogadas.
- **Cenário concreto:** depois de iniciar nova partida, reenviar um `ranked_resign` antigo sem `match_id`: ele desiste da partida nova. Em cartas, um pacote antigo com índices pode ser interpretado como escolha de cartas da mão atual quando voltar o turno. O pacote ainda precisa ser legal para o estado atual.
- **Impacto:** ações obsoletas atingem contexto diferente; resultados e intenção do jogador podem divergir após reconexão/retransmissão. Não é autorização para controlar outro jogador e não duplica automaticamente PL.
- **Evidência:** `String(m.match_id || match.id)`; `rooms.get(String(m.room_id || '')) || roomOf(uid)`; `room.ver++` existe somente na emissão, e não é comparado no handler.
- **Recomendação:** exigir ID explícito nas mutações, revisão/turno ou identificador de mão e `action_id` deduplicável. Rejeitar pacote de contexto antigo, devolvendo sincronização.
- **Classificação:** CONFIRMADO para aceitação do pacote sem vínculo; cenários específicos de repetição de jogadas exigem teste.

### S11 — Concessão de análise não verifica PvP em andamento

- **Severidade:** MÉDIA.
- **Arquivo/função:** `backend.js:234–242`, `analysis_request`; contexto relacionado: `analysis/fair_play.gd:12,33`, `analysis/engine.gd:215` e `presentation_v019/stage.gd:1294`.
- **Problema:** a API concede análise por perfil/entitlement/cota, sem checar `backend.inMatch` nem partida encerrada. A restrição efetiva de engine encontrada é no cliente, com guard antes das buscas.
- **Cenário concreto:** participante de PvP envia diretamente `analysis_request`. Se há cota ou Club ativo, recebe `analysis_granted` mesmo com partida ativa; cliente modificado pode ignorar o guard local.
- **Impacto:** autorização do backend não implementa o contrato pós-partida e não é uma prova de fair play. O Node não oferece engine de análise nos endpoints examinados: receber concessão não comprova que uma engine respondeu durante PvP. Software de engine externo também não é controlável por esse gate.
- **Evidência:** o ramo lê entitlement e consome cota sem `inMatch`; `Engine.evaluate` consulta `blocked`, e o stage configura o guard no cliente.
- **Recomendação:** negar concessão durante PvP e vincular autorização à partida encerrada; qualquer futura engine remota deve validar estado/participação no backend antes de executar. Preservar guards de cliente, sem tratá-los como segurança contra cliente alterado.
- **Classificação:** CONFIRMADO para a concessão indevida no backend; execução real de engine em PvP não demonstrada.

### S12 — Relações sociais e DM têm checks separados da escrita

- **Severidade:** MÉDIA.
- **Arquivo/função:** `social/service.js:82–138`, aceitar/bloquear; `social/dm.js:68–84`, envio; `accounts/store.js:543,548`, operações de persistência.
- **Problema:** amizade/bloqueio são lidos e depois alterados por várias operações independentes. O envio de DM verifica relação antes de uma inserção separada. Credenciais do backend efetuam as operações; não foi comprovada uma constraint/trigger que preserve o contrato sob concorrência.
- **Cenário concreto:** pausar `social_accept` depois da leitura e concluir `social_block` antes da inserção de amizade; a inserção antiga pode restaurar amizade ao lado de um bloqueio. Ou atrasar `dm_send` após autorização e bloquear/remover amizade antes de sua inserção.
- **Impacto:** possível DM posterior ao bloqueio e estado de relações contraditório. Não foi demonstrado acesso a conversas de terceiros: consulta de histórico continua vinculada ao usuário autenticado.
- **Evidência:** aceitar faz `removeRequest`, `removeRequest`, `addFriendship` com awaits separados; bloqueio faz `addBlock` seguido de remoções; envio faz `getRelations` e só depois `addDirectMessage`.
- **Recomendação:** operações atômicas que revalidem relacionamento no momento da escrita; ordenar/serializar alterações por par de usuários e aplicar invariantes no armazenamento. Qualquer SQL de correção exige autorização específica futura.
- **Classificação:** HIPÓTESE QUE PRECISA DE TESTE, inclusive contra garantias reais de banco.

### S13 — Contas coordenadas podem cultivar PL sem controles locais específicos

- **Severidade:** MÉDIA.
- **Arquivo/função:** `ranked/matchmaker.js:20–43`, pareamento; `ranked/match.js:69`, desistência; `ranked/progression.js:9–38`, PL.
- **Problema:** o pareamento distingue UUIDs, mas não registra limite de reencontros ou sinais de conluio. Desistência pode encerrar inclusive antes de iniciar a partida e entrar no cálculo de PL. Piso de PL e ausência de rebaixamento são regras de produto, não vulnerabilidades isoladas.
- **Cenário concreto:** em fila pouco movimentada, duas contas controladas entram no mesmo ritmo/faixa repetidamente. Uma perde por desistência para transferir progresso à outra. A faixa de pareamento se amplia com a espera.
- **Impacto:** potencial inflação de ranking por win trading sem falsificar jogadas ou resultado. Não foi comprovado retorno econômico, viabilidade em fila real ou ausência de controles operacionais externos.
- **Evidência:** `compatible` usa apenas modalidade/estatísticas/espera; `resign` só impede status `finished`; `points` dá PL por vitória sem considerar repetição do adversário ou duração.
- **Recomendação:** definir política antifraude de reencontro, desistências muito precoces e padrões de contas coordenadas; monitorar e revisar antes de mudar regras de PL. Uma duração mínima isolada é facilmente contornável.
- **Classificação:** HIPÓTESE QUE PRECISA DE TESTE e decisão de política de produto.

### S14 — Status de conta não aparece nas decisões de autorização

- **Severidade:** MÉDIA.
- **Arquivo/função:** `accounts/store.js:67`, campo `account_status`; `backend.js:109–118,209–223`, perfil/login e gates de serviços.
- **Problema:** existe campo de status no perfil, mas nenhum gate do código não excluído examinado consulta `account_status`. Não foi verificado se esse campo significa suspensão, se há enum no banco ou se o Auth bloqueia por outro mecanismo.
- **Cenário concreto:** se moderação suspende uma conta apenas mudando `profiles.account_status`, ela continua autenticando e acessando serviços com token válido; socket já autenticado também mantém perfil em cache.
- **Impacto:** possível bypass de suspensão aplicativa e continuidade de abuso social/multiplayer. Não se afirma que uma conta realmente banida no Supabase Auth consiga novo login.
- **Evidência:** busca no alvo não excluído encontrou o campo na criação de perfil, sem uso nas decisões; gates exigem somente usuário/perfil existentes.
- **Recomendação:** documentar autoridade de suspensão, negar acesso para status proibidos e propagar invalidação às sessões abertas. Se a fonte de verdade for Auth, comprovar esse contrato e sua latência.
- **Classificação:** HIPÓTESE QUE PRECISA DE TESTE e verificação do mecanismo real de moderação.

### S15 — Prazo de ação de cartas depende da ordem dos callbacks

- **Severidade:** MÉDIA.
- **Arquivo/função:** `modes/party.js:165–168,215–218`, deadline/timer; `party.js:350–362`, ação; `party.js:181,242`, cancelamento do timer.
- **Problema:** `party_action` verifica jogador, turno e `busy`, mas não compara o relógio atual ao deadline. Uma ação aceita cancela o timer de timeout.
- **Cenário concreto:** com event loop atrasado, uma mensagem cuja execução começa após o deadline é processada antes do callback do timer. Ela passa pelas verificações e cancela a ação automática, ganhando tempo além do prazo.
- **Impacto:** possível vantagem temporal em cartas e inconsistência entre relógio exibido e aceitação. Ordem real dos callbacks e frequência do caso não foram medidas.
- **Evidência:** `if (room.busy || room.turn_seat !== seat)` é o gate temporal; não usa `this.now()`/`room.deadline`; os métodos de aplicação fazem `clearTimeout(room.timer)`.
- **Recomendação:** conferir prazo com relógio server-side no momento da ação e resolver timeout expirado antes de aceitar; não usar somente disparo de timer como autoridade.
- **Classificação:** HIPÓTESE QUE PRECISA DE TESTE com relógio e atraso controlados.

### S16 — Salas legadas podem ser esgotadas sem autenticação

- **Severidade:** BAIXA.
- **Arquivo/função:** `server.js:2,38,44`, `MAX_ROOMS/create` e limpeza.
- **Problema:** o endpoint legado de criação permite ocupar todas as 128 salas sem autenticação. A remoção por TTL exige que ambos os sockets estejam ausentes.
- **Cenário concreto:** abrir 128 conexões e enviar `create` em cada uma; mantê-las abertas. Novos usuários do fluxo legado recebem servidor cheio. Desconectar todas ainda deixa salas até o TTL de 30 minutos mais a próxima varredura.
- **Impacto:** indisponibilidade do fluxo legado por código. O limite não é compartilhado com as partidas Ranked/Casual modernas; não se atribui automaticamente queda desses serviços a este achado.
- **Evidência:** criação antes de qualquer gate de conta; `rooms.size>=MAX_ROOMS`; sweeper só exclui quando `!r.w&&!r.b` e TTL transcorrido.
- **Recomendação:** desabilitar o fluxo em ambientes onde é realmente interno, ou exigir autorização e limite por origem/identidade, além de expirar sala ociosa independentemente de socket aberto.
- **Classificação:** CONFIRMADO no entrypoint; alcance público desse fluxo não verificado.

## Testes dinâmicos necessários, sem execução nesta tarefa

Todos os testes abaixo devem usar processo descartável, dados sintéticos e dependências simuladas. Não devem apontar para Supabase, Render ou Cloudflare atuais. Confirmação no ambiente real e qualquer ampliação de autorização dependem de tarefa específica futura.

| Caso | Verificação observável |
| --- | --- |
| S01 | Mensagem `null` não derruba processo nem outras conexões; caracterizar comportamento atual em processo isolado antes da correção. |
| S02 | Auth simulado aceita login e depois expira/revoga; ações após prazo devem ser negadas, inclusive em socket mantido ativo. |
| S03 | Após token inválido, verificar `identity`, `online`, Casual/chat e entrega de notificações; todos devem refletir invalidação. |
| S04 | Resolver promises de login A/B/refresh fora de ordem; intercalar logout/close. Nunca misturar `user/profile/identity` nem registrar socket fechado. |
| S05 | Pausar leitura de PL, iniciar Casual/cancelar/desconectar; resolver leitura e disparar tick. Medir quantas filas/partidas existem por UID e se resultados ficam órfãos. |
| S06 | No store simulado, reutilizar mate sintético em toda a ladder; distinguir legalidade de comprovação de autoria do bot. |
| S07 | Recuperar/restringir estado a partir de `roll`; sincronizar consumo e comparar previsões a sorteios futuros em sementes desconhecidas. Medir custo e taxa de acerto. |
| S08 | Carga limitada e progressiva de conexões, fragmentação/frame inválido, pacotes grandes e dependência lenta; observar memória, CPU, latência, tarefas pendentes e erros. |
| S09 | Enviar resumo sem concessão/com cota zero, duplicado, valores extremos e ID de outra partida; observar rejeição/vínculo/idempotência no store simulado. |
| S10 | Reenviar pacote antigo sem ID após partida nova; repetir ação de versão/mão antiga. Deve rejeitar sem mudar estado. |
| S11 | Pedir análise durante Ranked, Casual e desafio; verificar concessão e, em teste separado de cliente, guard de engine/Worker no fluxo real. |
| S12 | Intercalar accept/block e send/remove/block; invariantes devem valer no commit. Verificação de banco real não incluída. |
| S13 | Simular reencontros e desistências precoces com contas sintéticas; medir ganho possível e aplicar política de fraude definida. |
| S14 | Simular status suspenso e sessão aberta; verificar contrato de negação/invalidação sem presumir comportamento do Auth externo. |
| S15 | Executar ação com deadline vencido antes do timer; deve ocorrer timeout, não aceitação. |
| S16 | Em instância isolada, ocupar quota de salas e manter sockets; novos usuários devem continuar tendo capacidade conforme a política definida. |

Existem testes de regras, relógio, pareamento e progresso no repositório. Sua presença e assertions lidas são evidência do contrato pretendido, não resultados atuais. Nenhuma suíte foi executada nem modificada.

## Partes que aparentam estar bem protegidas

- **Identidade no login:** `accounts/auth.js:18–23` consulta `/auth/v1/user`; não aceita simplesmente um UUID enviado pelo cliente nem decodifica JWT como prova de validade. Há limite de tamanho do token e cache limitado em quantidade. As falhas de ciclo de vida de sessão acima continuam aplicáveis.
- **Autoridade das partidas de xadrez:** `ranked/service.js:28,49–56` resolve partida pelo UID do socket, calcula cor no servidor e valida ID explícito quando fornecido. `ranked/match.js:40–57` e `chess_rules.js:117–129` validam turno, coordenadas inteiras, movimento legal, promoção e segurança do rei. Não foi encontrado endpoint que aceite vencedor/PL arbitrários do cliente.
- **Relógio e resultado:** `ranked/clock.js` usa tempo do servidor; só movimento legal troca relógio. Resultado, timeout e progressão são calculados em `ranked/match.js`/`progression.js`. `finish` é guardado por status; `persisting` impede persistência duplicada no fluxo normal de uma instância. A atomicidade/idempotência da RPC real permanece não avaliada.
- **Convidados e Ranked:** convidados recebem token aleatório de 24 bytes e ID gerado no servidor; Ranked exige conta/perfil. Resume das salas legadas também exige token aleatório. Limitação de recursos permanece insuficientemente demonstrada.
- **Participação/segredo em cartas:** `party.js:339–346` verifica assento; snapshots têm a própria mão e contagens das demais. `xeque_rules.js:128–136` publica contagens em vez das cartas ocultas, e `canPlay` rejeita índices inválidos/duplicados. Há gate de turno e `busy`. A exposição do RNG é exceção relevante; o motor de Marcha não foi avaliado.
- **Convites:** `social/invites.js:202` reserva ambos os usuários antes do await no aceite, revalida amizade/bloqueio e trata segundo aceite de forma idempotente. Isso é um padrão mais forte que o enqueue assíncrono Ranked. Não certifica toda combinação de operações concorrentes.
- **DM e presença:** envio exige amizade sem bloqueio nos dois sentidos; queries de conversa usam sempre o par com o usuário autenticado, e marcação de leitura restringe destinatário/remetente. Presença é publicada a amigos e não expõe dados de conexão. Há limites por conta para chat/social/DM e histórico limitado em chat.
- **Cosméticos:** IDs permitidos, direitos e progresso são validados server-side em `accounts/cosmetics.js`; benefícios expirados são filtrados na apresentação pública. Cosméticos não influenciam cálculo de PL/relógio/regras nos arquivos examinados.
- **Inputs e perfis públicos:** normalização/allowlist de nickname; validação de UUID e escaping de parâmetros em consultas; perfis públicos selecionam campos sem e-mail. Upload limita bytes e confere assinatura/dimensões; isso é inspeção de cabeçalho, não comprovação de imagem íntegra por decoder. Erros de cabeçalho no caminho de upload entram no catch do backend.
- **Fair play no cliente oficial:** stage configura guard, e a engine o consulta antes de buscas. É proteção arquitetural local útil, mas não controla cliente adulterado nem substitui gate contextual do backend.

## Áreas não avaliadas e incertezas relevantes

1. `online_v021/payments/` e `monetization/`, incluindo webhooks, provedores, assinaturas, grants, reembolsos e consistência de pagamentos: excluídos. Não inferir segurança dessas áreas a partir do restante.
2. Motores protegidos de Marcha: sem leitura, alteração ou verificação de paridade. Achados na infraestrutura Party não provam falha nas regras de Marcha.
3. Schema/RLS/policies/triggers/constraints/RPCs e Storage do Supabase, inclusive privilégios de execução, atomicidade de resultado Ranked e deduplicação real: não inspecionados. Credenciais service-role tornam especialmente importante verificar essas fronteiras em auditoria separada autorizada.
4. Configuração LIVE, SHA, TLS, headers, proxy/WAF, limites de conexão e rede, gestão de secrets, retenção de logs e isolamento de staging/produção: não verificados. Não foi aberta configuração privada de ambiente.
5. Dependências instaladas/versões efetivas, advisories e origem dos binários de engines: não feita auditoria de supply chain. `package.json` sozinho não comprova versão instalada ou ausência de CVEs.
6. Cliente Web/Godot completo, XSS/BBCode/renderização de texto, cache local, armazenamento de bearer, bridges e fluxos mobile: não auditados de ponta a ponta. Leitura do fair play só foi usada para delimitar o achado S11.
7. Sistemas externos de moderação, antifraude, backup e recuperação, múltiplas réplicas e balanceamento: desconhecidos. Estado de partidas/exclusividade observado é em memória por processo; garantias entre instâncias precisam de avaliação própria se houver réplicas.
8. Upload não foi submetido a fuzzing/decodificação; nenhum crash de decoder, execução por imagem ou vazamento de arquivos foi demonstrado. Ausência de validação de Origin no construtor não foi classificada isoladamente como tomada de sessão: o protocolo usa token explícito, e não foi demonstrada autenticação automática por cookie.

## Ordem recomendada de correção

1. **Fechar a entrada e a queda do processo:** S01; configurar limite de transporte e isolamento de erros de S08. Verificar sobrevivência do processo com mensagens inválidas em ambiente descartável.
2. **Unificar ciclo de vida da sessão:** S02, S03 e S04; definir prazo, geração e invalidação consistente antes de tratar autorização em cada serviço. Esclarecer mecanismo de suspensão S14.
3. **Garantir uma única reserva/partida por usuário:** S05; preservar o padrão de reserva antecipada usado no aceite de convite e cobrir cancel/close/awaits tardios.
4. **Conter abuso de recursos:** completar S08 com orçamento por conta/conexão/global, prazos de dependências e retenção; restringir/desativar salas legadas conforme S16.
5. **Proteger informação oculta:** confirmar S07 e substituir RNG de produção/remover roll exposto. Nenhuma alteração de motor protegido é autorizada por este relatório.
6. **Vincular operações ao contexto:** S10 e S15, com IDs obrigatórios, versão/turno, deduplicação e deadline autoritativo.
7. **Proteger progresso e histórico:** S06 e S09; comprovar partida de bot e autorização/idempotência de análise. Ajustar concessão de análise S11.
8. **Tornar relações sociais consistentes:** confirmar e corrigir S12 no momento da escrita; qualquer preparação de SQL depende de autorização específica.
9. **Definir controles contra conluio:** medir S13 e decidir política de produto com evidência, sem alterar regras competitivas incidentalmente.

As correções são recomendações. Nenhuma foi implementada nesta tarefa.

## Encerramento e integridade do checkout

A única escrita desta auditoria é este relatório. Branch/HEAD foram reconfirmados e a árvore continuava limpa imediatamente antes da criação. A verificação após a criação executou `git status --porcelain=v1 --untracked-files=all`, `git diff --exit-code` e `git diff --cached --exit-code`. O status retornou somente `?? docs/security/SECURITY_AUDIT.md`; os dois diffs estavam vazios. Branch e HEAD permaneceram os mesmos. Nenhum arquivo de código foi editado, staged ou commitado. Nenhum commit, push, deploy ou operação externa foi realizado.
