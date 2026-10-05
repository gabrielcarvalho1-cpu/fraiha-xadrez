# Arquitetura e contratos do FRAIHA

Estas regras adaptam a referência do Claude. Caminhos e comportamento atual devem ser confirmados no checkout; `AGENTS.md` define proteções e autorização.

## Autoridade e regras

- Cliente Godot, backend, banco, export Web, host e navegador podem estar em versões distintas. Registrar as versões relevantes antes de diagnosticar comportamento entre camadas; deploy iniciado não prova SHA LIVE.
- Servidor decide resultados online, PL, Ranked, progresso e benefícios. Cliente apresenta estado e pode manter cache; não confirma sozinho vitória, unlock ou entitlement.
- Humano e bot do mesmo modo usam as mesmas ações legais e regras. IA apenas escolhe ações válidas. UI obtém quantidades, chances, custos, cooldowns e alvos da configuração/motor.
- Centralizar elegibilidade de alvo e enumeração de ações: zero ações indisponibiliza; uma ação dispensa escolha redundante quando seguro; duas ou mais alternativas distintas pedem escolha.
- Transições de zona dependem de destino/regra, não do simples cruzamento geométrico da entrada. Movimento composto valida orçamento, ordem, alvos após cada subação e sobra sem uso legal.
- RNG de gameplay tem probabilidades centralizadas, estado explícito e seed reproduzível. Não decidir chance em UI separadamente.
- Modos novos isolam regras, IA e estado, compartilhando conta, navegação, áudio e histórico quando adequado. Registros incluem `mode_id` e `ruleset_version`.
- Arte aprovada define aparência; regra confirmada define mecânica. Identificar conflito em números/textos de assets antes de implementar; não reconciliar silenciosamente nem copiar branding de terceiros.

## Progresso, produto e persistência

- FRAIHA nunca é pay-to-win. Verificar no checkout atual se convidados não jogam Ranked antes de tratar essa restrição como verdade. Alteração de ladder/modos/ligas exige escopo próprio e confirmação do contrato atual.
- Primeira vitória válida pode desbloquear recompensa: vitória confirmada e recompensa nova são sinais diferentes. Servidor confirma → apresentação de vitória → recompensa/progressão. Repetição não concede novamente.
- Benefício premium só está completo com todas as camadas necessárias: UI, servidor, banco, entitlement, sincronização social ou integração. Simulação/local não comprova benefício completo.
- Benefícios derivados/acumuláveis definem extensão, expiração e concessão idempotente. Cota server-side é consumida quando a partida começa; F5 não cria tentativa extra; respeitar contrato Club atual.
- Cosmético social: cliente escolhe → servidor valida posse → persiste ID → outros recebem ID permitido. Cliente antigo/asset ausente precisa de fallback seguro.
- Cache de avatar compara URL/versão. Persistência server-side exige nova sessão/contexto sem depender do cache; testar atualização entre clientes quando relevante.

## Integrações e rollout

- Procurar módulo compartilhado antes de integrar voz/chat/presença/pagamentos por modo. Modos usam API interna; SDK de provedor fica encapsulado.
- Contratos entre camadas definem entrada, saída, erros, autoridade e compatibilidade com versões antigas.
- Preparar migration exige autorização explícita; aplicação nos serviços está proibida no escopo atual. Não tratar arquivo SQL como schema aplicado. O Supabase pode ser compartilhado: verificar antes de qualquer operação futura autorizada.
- Recursos com schema novo precisam considerar ausência da migration e ordem de rollout. Não publicar código que derrube login/partidas por assumir schema inexistente.
- Voz, se solicitada: sala por `match_id`, participação validada no servidor, token curto renovável, bots fora, sem gravação padrão. Falha RTC não muda a partida.
- Join idempotente e cleanup completo: parar publicação, destruir track, sair, remover listeners, limpar participantes e UI. Sair da partida não pode deixar microfone ativo.

## Pacotes do Claude

Pacotes `APLICAR-RXX` são aplicados pelo usuário na pasta principal. Codex não aplica nem corrige essa pasta. Se uma tarefa futura pedir revisão de pacote, verificar base SHA, hash, dependências e pacote posterior substituto, em leitura/ambiente autorizado; não aplicar pacote antigo sobre estado novo por hábito.
