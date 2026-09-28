# V0.30 — en passant, interface por liga e avatares

Branch dev/v030-en-passant-league-ui. Sem main/deploy/servidor.

En passant: motor isolado já tinha geração/remoção/expiração corretas. Local ainda utilizava a execução legada sem EP. Local agora usa o mesmo controlador/motor do Bot, com dois humanos e sem iniciar cálculo de IA. Captura, lista de capturados, promoção e estado visual vêm do motor. Verificados EP branco/preto, expiração, rei exposto, fluxo Bot e cliques reais no tabuleiro Local. Servidor Online não alterado nem validado nesta rodada; não afirmar correção do Online de produção.

Temas: selecionar liga aplica imediatamente cenário e peças; Home e páginas internas acompanham. Os seis temas superiores reutilizam seus cenários V029, com logo transparente extraído da identidade existente. Painel central recomposto para legibilidade. Prévia persiste em user://visual_theme.cfg, sem conceder liga/PL; na ausência de preferência, usa liga atual do perfil. Músicas preservadas.

Perfil: Guerreiro recebeu moldura quadrada; Paladino selecionável e salvo junto aos outros três avatares. Molduras nos retratos de Home, seleção e partida usam cor/emblema de league_profile.data.current_league (mesma fonte do perfil atual), não o tema de prévia. Atualizam ao reabrir Perfil. Integração futura de conta/rankings independentes permanece fora desta entrega.

Assets: profile/paladin.png (novo); ui_v022/assets/theme_logo.png (extração transparente da referência existente). Ferramenta integrada image_gen. Prompts: Paladin square pixel-art medieval portrait, noble knight, silver/gold armor and ivory cloak, forest-green background, ornate square golden frame, no text. Logo: extract existing FRAIHA XADREZ crown/knights/motto from home_forest.png, transparent background, remove scenery and UI, preserve identity.

Validação: 48 verificações focadas no motor/ponte Local-Bot, onze temas, carregamento e molduras dos quatro avatares; mais cliques reais de EP no Local e atualização da moldura por liga. Capturas de Home e Perfil conferidas. Sem bateria geral de bots/regras/rede.

Testar: Local — e2-e4, a7-a6, e4-e5, d7-d5, e5-d6; o peão d5 desaparece. Ligas — clicar num elo e voltar à Home. Perfil — escolher Paladino; prévia Challenger não muda o elo real da moldura.
