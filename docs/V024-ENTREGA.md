# FRAIHA Xadrez V0.24 — build de desenvolvimento

Branch: `dev/v024-leagues-iron`. Base estável: V0.23, commit remoto `c3974f8ffe6da7eba334a2cc426b0c649f77b477`.
Nenhuma alteração na main, no servidor Node, protocolo WebSocket ou implantação Render.

## Entregue

- Quatro níveis funcionais no mesmo tabuleiro. Fácil/Médio preservados. Difícil/Expert usam o motor isolado, alpha-beta, aprofundamento iterativo, quiescence, ordenação por capturas/histórico/killer e cache limitado. A chave do cache inclui histórico de repetições e relógio de empate.
- Difícil: até 1.400 ms / profundidade 4 / quiescence 3. Expert: até 2.500 ms / profundidade 5 / quiescence 4. A profundidade é um teto; computadores e posições diferentes podem terminar antes. Avaliação considera material, mobilidade, desenvolvimento, segurança do rei, ameaças, peões isolados/dobrados/passados, colunas e par de bispos. Não há classificação Elo nem promessa de força de um motor profissional.
- Cálculo em Thread com cópia do estado. Abandono invalida resultados antigos; diálogos bloqueiam interação. Nenhuma regra de legalidade duplicada na IA.
- Catálogo das 11 ligas oficiais, todas com faixa 0–100 PL. Perfil local versionado com liga, PL, vitórias, derrotas, partidas, maior liga e cosméticos. Sem fórmula de pontuação, promoção automática ou backend de ranking.
- Página Ligas com 11 brasões selecionáveis, detalhes, barra PL, prévias de cenário/peças e estado de bloqueio.
- Madeira conserva as artes originais da floresta e ganha 12 peças entalhadas. Ferro recebe Home própria, arena de fortaleza nevada com forja, tabuleiro de aço e 12 peças metálicas. Peças clássicas continuam disponíveis.
- Prévia de desenvolvimento troca o universo completo sem conceder PL ou desbloquear a liga. Ao reiniciar o jogo, a prévia volta à Madeira.

## Como testar

1. Extraia o ZIP inteiro. Mantenha EXE, PCK e online.cfg juntos. Execute FRAIHA-Xadrez-V024-Teste.exe.
2. Ligas e Ranking → Ferro → TESTAR UNIVERSO. A Home muda. Entre em Local ou Bot para conferir arena e peças. Para restaurar, selecione Madeira e TESTAR UNIVERSO.
3. PEÇAS CLÁSSICAS aplica o conjunto original ao cenário atual. A próxima troca de universo volta a aplicar o conjunto correspondente.
4. Bot → Difícil ou Expert → Brancas/Pretas/Aleatório. Pretas faz o bot iniciar. ESC pede confirmação para abandonar.
5. Alt+Enter alterna tela cheia. O perfil V024 é separado dos dados das builds anteriores.

## Validação direcionada

- `tests/v024_test.gd`: 44 verificações passaram (11 ligas/emblemas, persistência, limites, conjuntos/alpha, captura legal e mate de Difícil/Expert, orçamento, worker ativo com animação, Home/Local/diálogo e prévias sem progresso).
- `tests/bot_search_test.gd`: 26 verificações passaram para Fácil/Médio após a extensão do arquivo de busca.
- Capturas reais do viewport em 1920×1080: Ligas, Home Ferro, tabuleiros Ferro e Madeira.
- O motor `chess/rules.gd` e os arquivos Online/servidor não mudaram. As verificações extensivas V023 não foram repetidas, conforme orientação de economia. A validação Online pela internet da V023 permanece como último teste completo de sincronização/reconexão/revanche; não afirmar novo teste internet V024.
- O ambiente isolado pode emitir aviso sobre certificados do Windows e um recurso em uso ao encerrar o Godot, também observados na versão anterior. Não houve falhas de script nos testes executados.

## Arquivos principais

- `bot/search.gd`, `bot/controller.gd`: perfis avançados e conexão com worker.
- `league/catalog.gd`, `league/local_profile.gd`: catálogo e persistência local.
- `cosmetics/theme_catalog.gd`, `cosmetics/theme_manager.gd`, `cosmetics/assets/`: metadados, aplicação e cinco novos arquivos de arte.
- `ui_v022/main_hub.gd`: níveis, perfil e página Ligas.
- `presentation_v019/stage.gd`, `world.gd`: aplicação cosmética no tabuleiro existente.
- `project.godot`: identificação e pasta de usuário V024.
- `tests/v024_test.gd`: testes direcionados.

## Limites e próxima sessão

A arena Ferro tem arte estática nesta build; as animações já existentes da floresta são preservadas na Madeira. O tabuleiro Ferro é desenhado pelo jogo sobre a arena para manter 64 casas exatas e a mesma grade de entrada. PL, promoção e recompensas automáticas aguardam regras competitivas. Bronze e demais cenários não foram iniciados.

Próximo passo: receber o teste visual e funcional do usuário desta build, especialmente legibilidade das peças, seleção dos temas e diferença prática entre níveis. Não começar Bronze ou fórmula competitiva antes desse retorno.
