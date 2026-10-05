# Validação Web, engines e regressões

Aplicar conforme o comportamento afetado; não executar durante inventário somente em leitura. Nunca usar serviços de produção para testes nem alterar Supabase, Render ou Cloudflare.

## Web e builds

- Bridges JS/Godot, inputs HTML, Worker/WASM, WebSocket e APIs de browser precisam de fluxo real em navegador. Teste Node positivo não prova cliente Godot positivo.
- `JavaScriptObject` não equivale automaticamente a Array/Variant. Validar tipos reais em callbacks; falhas devem ser visíveis em desenvolvimento.
- WebSocket: verificar retorno do envio, limites por tipo e rate-limit, parse de JSON sem presumir ordem de chaves e payload grande com serialização real do Godot.
- Em UI afetada, testar desktop, retrato, paisagem e viewport curto quando relevante. Resize/emulação não equivale a dispositivo real. Preservar arte aprovada e composição; investigar textura e nós antes de mascarar defeitos.
- Fullscreen depende de gesto válido; transições internas não devem derrubá-lo. Testar inputs HTML e mouse/touch no fluxo.
- Preferências: alterar → reload → confirmar. Avatar/dados remotos: verificar nova sessão e atualização entre clientes, além do cache.
- FX/SFX apresentam evento já confirmado pelo motor; animação ou timer não controla resultado. Tempos de apresentação ficam em configuração. Animação exige validar início, meio, fim e duração.
- Fonte → export → conteúdo servido → cache são estados diferentes. Verificar hashes/versão antes de corrigir código por comportamento de build antiga.
- Export Web inclui JS, WASM, PCK, ícones/worklets e engines necessárias. Build final deve ser a testada; alteração posterior invalida a evidência afetada.
- RTC, quando no escopo: permissões, gesto/autoplay, dispositivo ausente, mute, aba suspensa, reconnect/F5, saída/logout e mobile. Join não comprova áudio; teste físico entre dispositivos é evidência separada de mocks.

## Engines e bots

- Fair play é bloqueio arquitetural de qualquer engine durante PvP ativo, inclusive análise acionada indiretamente.
- Arquivos WASM existentes não provam execução: Worker → JS/WASM → `uciok` → `readyok` → posição/busca → `bestmove`.
- Registrar `ANALYSIS ENGINE = STOCKFISH | FALLBACK` e `BOT ENGINE = STOCKFISH | FALLBACK` com evidência. Perfis de análise e bot são independentes; não compartilhar parâmetros automaticamente.
- Consultar `analysis/ENGINE.md` e `analysis/LICENSES.md`; origem, versão, hash e obrigações de distribuição de binários devem ser verificadas. Não interpretar esta skill como parecer de licença.
- Calibração começa por engine real e baseline, mede gargalo e compara antes/depois. Registrar depth/nodes/tempo e fallback. Bots exigem comparação com níveis adjacentes e playtest humano quando disponível; Elo nominal sozinho não comprova dificuldade percebida.
- Reconexão usa direitos exatos de roque/en passant quando conhecidos. Sem histórico suficiente, não inferir pelo posicionamento das peças; marcar reconstrução aproximada/análise parcial.

## Testes e prova

- Descobrir comandos reais e efeitos de cada teste. Suites de integração podem iniciar servidores ou depender de serviços; não executá-las cegamente.
- Definir comportamento esperado antes da mudança. Usar testes existentes, fixtures, invariantes ou QA independente para regras críticas; evitar teste que apenas espelhe a implementação.
- Marcha/XEQUE têm fixtures de paridade: verificar mesmas ações, alvos, destinos, estado e eventos. Não regenerar fixture apenas para aceitar uma divergência. Editar regras da Marcha exige autorização explícita para os arquivos protegidos.
- Regras com UI: comparar valor do motor e exibido após transições. RNG: seed e extremos/invariantes. Ações: zero/uma/múltiplas alternativas e alvos protegidos/alterados.
- Async: requisições duplicadas, respostas antigas fora de ordem, callbacks depois da saída e reconnect concorrente. Esperar estado/evento; delay não corrige race condition.
- Falha após mudança: comparar com a base no mesmo ambiente e classificar NEW REGRESSION, PRE-EXISTING, FLAKY ou ENVIRONMENTAL com evidência. Falhas intermitentes exigem repetições, preferencialmente intercaladas, e taxas medidas.
- Não apagar/pular teste, enfraquecer assertion ou alterar expected para aceitar bug. Mudança legítima de contrato deve ser explicada.
- Baselines e falhas de R18–R30 no anexo são históricos. Não declarar falha atual como antiga sem comparação.
- Relatar o teste, build/HEAD e ambiente; explicitar o que não foi testado. Compilar/exportar ou abrir uma tela não prova o fluxo funcional.
