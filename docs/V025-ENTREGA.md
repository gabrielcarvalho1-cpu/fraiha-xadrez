# FRAIHA Xadrez V0.25 — Bronze, Prata e Ouro

Branch `dev/v025-bronze-silver-gold`, baseada na V024 remota `fd66a5aa24af091d74810daafb7a5713748ab565`. Main, servidor Node e protocolo WebSocket preservados; nenhum deploy.

## Entregue

- Bronze, Prata e Ouro com Home própria, arena e conjunto completo de 12 peças em pixel art. Madeira/Ferro e peças clássicas preservados. Cinco universos disponíveis em Ligas → selecionar liga → TESTAR UNIVERSO.
- Cada liga permanece em 0–100 PL, conforme confirmação do usuário. Prévia não concede PL nem desbloqueia progressão. Ligas posteriores têm apenas os brasões existentes.
- Tabuleiro orientado automaticamente com as próprias peças embaixo no Bot e Online. Renderização, destaques, cliques, arraste e partículas de captura transformam as coordenadas; o motor e o protocolo mantêm as casas canônicas. O cenário, HUD e diálogo de promoção permanecem de pé. Local conserva orientação original.
- Perfil ampliado com escolha Guerreiro/Arqueira/Mago, nome, liga, PL e campos de estatísticas locais. Avatar salvo nas preferências, mostrado na Home e na identificação do jogador durante partidas.
- Conheça o FRAIHA reformulado com seis tópicos navegáveis e textos sobre projeto, regras de uso, ligas, modos, personalização e comunidade/suporte.
- Online com abas Entrar/Criar, cenário do tema ativo, instruções de convite e navegação preservada. Lista pública de salas e avatar transmitido ao adversário foram explicitamente adiados pelo usuário para não modificar/deployar o servidor. Nenhuma lista, ping ou contagem fictícia.
- Som original para madeira/metal, captura, xeque, mate, vitória/derrota, promoção, interface e ambiente leve de castelo. Sem playlist comercial. Áudio observa o estado do jogo e não interfere na lógica.
- Sombras de contato ajustadas à base das peças.

## Validação direcionada

`tests/v025_test.gd`: 50 verificações passaram: aplicação dos cinco temas e 60 peças, alpha/recorte dos novos conjuntos, prévias, ausência de efeitos nos PL, persistência de avatar, início do Bot com humano de pretas, cliques/arraste invertidos, promoção, payload Online canônico, validação de código/navegação e carregamento/evento dos sons.

Capturas reais em 1920×1080: três novas arenas, Perfil, Conheça o FRAIHA, Online e Ligas. Inspeção visual dos principais layouts, sem nova rodada de geração de arte.

Executável Windows exportado: 18 verificações passaram, saída 0. Home, três novos temas, novo avatar, páginas Perfil/Conheça/Ligas contidas no viewport em 1920×1080, 1600×900 e 1366×768; menu Online/retorno, orientação das pretas e dez sons incluídos. Total da rodada: 68 verificações direcionadas, sem repetir as baterias extensivas anteriores.

Motor `chess/rules.gd` e busca dos bots `bot/search.gd` não alterados. As baterias extensivas dessas áreas não foram repetidas, conforme solicitação de economia. Não foi repetido o teste completo de multiplayer pela internet nesta rodada. A correção de coordenadas foi testada com o mesmo caminho de entrada e payload de rede, usando um destinatário de teste. Última validação completa pública de reconexão/revanche: V023.

O ambiente isolado emite aviso de certificados Windows e, em testes automatizados, recursos em uso ao encerrar. Nenhum erro de script nos testes concluídos.

## Arquivos alterados/criados

- `cosmetics/v025/`: dez PNGs (três Homes, três arenas, três atlases de peças e um de avatares).
- `cosmetics/theme_catalog.gd`, `cosmetics/theme_manager.gd`: cinco temas, paletas e alinhamento proporcional.
- `league/catalog.gd`, `league/local_profile.gd`: vínculos Prata/Ouro e identificadores cosméticos.
- `world.gd`: transformação visual/input do tabuleiro e sombras; `bot/controller.gd`: posição visual das partículas de captura.
- `ui_v022/main_hub.gd`: páginas, temas, avatares e preferências.
- `online_v020/client.gd`: interface; processamento de mensagens e envio de movimentos preservados.
- `presentation_v019/stage.gd`: identificação/avatar e áudio.
- `audio_v025/`: dez WAVs e observador de eventos.
- `tests/v025_test.gd`, `tools/generate_audio_v025.gd`, documentação e identificação V025 em `project.godot`.

## Uso e limites

Extraia EXE/PCK/online.cfg/LEIA-ME juntos. Perfil V025 é isolado das builds anteriores. M altera ambiente; volume geral fica em Configurações. As prévias de tema continuam temporárias e voltam à Madeira ao reiniciar.

As novas arenas são ilustrações estáticas nesta build; animações originais da Madeira continuam preservadas. Sem relógio competitivo, elo, backend de perfil ou descoberta pública de salas. Sem novas artes de Platina em diante. Os sons são síntese original e ficam sujeitos à avaliação auditiva do usuário.

Próximo passo: o usuário testar esta build e enviar observações sobre os três temas, peças, sons, avatar e orientação das pretas. Parar aqui; não iniciar próximas ligas nem alterações no servidor sem novo pedido.
