# V0.29 — visuais das ligas superiores

Branch: dev/v029-upper-league-visuals. Sem deploy ou alteração da main.

- Platina: palácio frio de metal nobre, peças de prata com safiras, moldura metálica.
- Esmeralda: reino ancestral e cristais verdes, peças com folhas e raízes, cantos de esmeralda.
- Diamante: cidadela cristalina acima das nuvens, peças facetadas, moldura com gemas claras.
- Mestre: academia/biblioteca medieval, peças com insígnias de conhecimento, moldura violeta.
- Grão-Mestre: salão imperial de mármore, peças heráldicas vermelhas/douradas, moldura com coroas.
- Challenger: santuário celeste com eclipse e fênix, peças lendárias aladas, moldura estrelada.

Todos têm cenário e atlas próprios de 12 peças (seis claras e seis escuras), paleta legível e moldura desenhada no mesmo espaço quadrado das 64 casas. Madeira até Ouro foram preservadas. Home mantém o cenário/logo atual.

Como testar: LIGAS E RANKING → selecionar liga → TESTAR UNIVERSO → JOGAR LOCAL ou BOT. A indicação Bloqueada continua representando progressão real; a prévia de desenvolvimento permite experimentar sem conceder PL/desbloqueios. Não há integração automática nova com Ranked.

Áudio temporário: Platina/Diamante usam Prata; Esmeralda usa Madeira; Mestre usa Ferro; Grão-Mestre/Challenger usam Ouro. music_path por tema permite substituir a faixa futuramente. Home continua Madeira. Nenhuma música nova.

Validação: 38 verificações focadas passaram (seis temas, 12 peças por tema, transparência, áudio existente, proporção quadrada, prévias, PL intacto e retorno à Madeira). Capturas reais dos seis tabuleiros e da página de ligas conferidas. Não repetidos testes de regras/Bot/servidor.

Arquivos: cosmetics/v029/*.png e imports; cosmetics/theme_catalog.gd; cosmetics/theme_manager.gd; cosmetics/league_board.gd; world.gd (somente chamada da moldura no desenho); league/catalog.gd (nome Grão-Mestre); ui_v022/main_hub.gd (descrições/versão); project.godot; tests/v029_cosmetics_test.gd.

Assets produzidos com a ferramenta integrada image_gen, uma geração por cenário e uma por atlas, sem variações extras. Originais copiados para cosmetics/v029; nenhum asset depende do diretório externo de geração.

Prompts utilizados (inglês):
Cenários: Production 16:9 pixel-art medieval fantasy chess arena background, no text/UI/chess pieces/board, crisp pixel clusters, dramatic lighting, spectacular architecture on edges and upper third, quiet center for live square board overlay, edge-to-edge, balanced frontal environment.
Peças: Production transparent chess sprite atlas, exactly 6 columns x 2 rows, pawn/rook/knight/bishop/queen/king; top ivory/light, bottom obsidian/dark, recognizable silhouettes, bespoke architecture/crowns/knight helmets, no board/labels, each sprite inside its cell.
Direções de cenário: Platinum noble cold silver palace and winter gardens; Emerald ancestral enchanted forest and giant crystal shrines; Diamond crystal citadel above alpine clouds; Master chess academy with libraries and stone scholars; Grandmaster imperial crimson columns and black marble; Challenger floating celestial islands, cosmic eclipse and blue-gold phoenix architecture.
Direções de peças: Platinum fluted silver/sapphire; Emerald tree/vine crowns; Diamond faceted crystal; Master scholar motifs/stone/violet enamel; Grandmaster royal armor/crimson/gold heraldry; Challenger winged phoenix relics/star-blue gems.

Próximo passo: aguardar avaliação visual do usuário. Não avançar para matchmaking, autenticação ou monetização.
