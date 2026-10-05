---
name: fraiha-xadrez
description: Desenvolver e diagnosticar o FRAIHA Xadrez em uma worktree do Orca, com contexto Godot/Web, backend Node, regras, bots e análise. Usar para tarefas deste projeto, respeitando áreas protegidas e sem alterar serviços externos.
---

# FRAIHA Xadrez

Adaptação da referência `fraiha-dev` do Claude para Codex. Carregar esta skill apenas fornece contexto: não inicia comandos, alterações, commits ou serviços. A tarefa do usuário define as ações permitidas.

## Começar pelo escopo real

1. Ler o `AGENTS.md` da raiz e instruções aplicáveis aos arquivos da tarefa. As restrições atuais do usuário prevalecem sobre a referência exportada.
2. Confirmar worktree do Orca, branch `codex/*`, HEAD e status. Nunca editar a pasta principal dos pacotes `APLICAR-RXX`. Nunca commitar ou fazer push em `dev/web-alpha`. Uma nova branch nasce de `origin/dev/web-alpha` após fetch, conforme a autorização e o escopo.
3. Consultar `docs/CODEX-PROJECT-MAP.md` como mapa datado; verificar no código/configuração as informações relevantes. Não presumir servidor ativo pela numeração das pastas, README ou checkpoints RXX.
4. Procurar a implementação e a fonte de verdade existentes antes de criar módulos. Reproduzir o problema quando aplicável; definir como o resultado será comprovado.

## Restrições que mudam decisões

- Nunca incluir mudanças de `project.godot`, `export_presets.cfg`, `*.uid` ou `*.import` nos commits do Codex, mesmo se rastreados. Não remover do índice nem alterar ignores por efeito colateral. Fazer stage por arquivo.
- Não alterar `monetization/` nem `online_v021/payments/`, protegidos por trabalho paralelo.
- `marcha/rules.gd` e `online_v021/modes/marcha_rules.js` exigem autorização explícita para edição e preservação da paridade de comportamento Godot × servidor.
- Criar ou editar qualquer SQL em `supabase/migrations/` exige autorização específica. Nunca alterar Supabase, Render ou Cloudflare no escopo atual, nem staging desses serviços.
- Cada autorização vale só para a ação e a tarefa em que foi dada. Commit depende de pedido; push/merge não decorrem de autorização de commit.
- Nunca ler secrets durante inventários ou divulgar valores. Cliente Godot/Web não recebe credenciais privadas ou service role.
- Engine proibida em qualquer partida humana ativa: negar a operação na arquitetura. Club/Fundador não liberam análise durante PvP; marcação para revisão somente registra.

## Escolher a referência necessária

- Regras, modos, autoridade, progresso, entitlements, integração e persistência: [references/architecture.md](references/architecture.md).
- Engine, Web/bridges, QA, builds, performance e regressões: [references/validation.md](references/validation.md). Antes de mexer em engines, ler também `analysis/ENGINE.md` e `analysis/LICENSES.md` do projeto.

## Executar e fechar

Escolher rigor proporcional: FAST para ajuste pequeno e local; STANDARD para UI/fluxos compartilhados; STRICT para auth, multiplayer, progresso ou mudança entre camadas. Rigor não amplia autorização nem libera áreas protegidas.

Fazer a menor mudança que atende ao pedido e executar validação diretamente relevante. No mapeamento somente em leitura, não executar testes, importação Godot, build, export ou scripts que gerem arquivos. Se duas tentativas de correção falharem, buscar evidência nova antes de editar outra vez.

No relato, separar implementação local, teste local, commit, push, deploy e teste no ambiente. Informar branch/HEAD, arquivos, resultado vs. base, limitações e fluxos não testados. Não chamar exportação bem-sucedida de validação funcional. Encerrar quando o objetivo e as verificações relevantes forem satisfeitos, sem abrir auditoria adjacente.
