-- FRAIHA Xadrez — NOVIDADES R180 (abas ATUALIZAÇÕES / NOTÍCIAS / CAMPEONATOS / EVENTOS do jogo).
-- Pode rodar mais de uma vez: cada item tem um id fixo (não duplica). Depois dá para editar tudo em Admin → Novidades.
insert into public.news_items (id, kind, title, body, button_label, button_action, pinned, published, published_at) values
-- ATUALIZAÇÕES (as 5 mais recentes)
('a1800000-0000-4000-a000-000000000001', 'atualizacao', 'Aviso de versão nova e contato pelo WhatsApp',
 'Quando sair uma atualização, o jogo avisa no lobby com o botão ATUALIZAR AGORA (nunca no meio da sua partida). E na fase beta tem um botão do WhatsApp embaixo do Passe: dúvida ou bug, é só chamar.',
 '', '', false, true, now()),
('a1800000-0000-4000-a000-000000000002', 'atualizacao', 'Passe da Temporada renovado',
 'Prêmio em TODO nível: Coroas, emotes, molduras, avatares e títulos exclusivos. Depois do nível 30 vêm os níveis BÔNUS (31 a 40). O botão do Passe agora fica na tela inicial, com a sua barra de progresso.',
 'VER O PASSE', 'passe', false, true, now() - interval '1 hour'),
('a1800000-0000-4000-a000-000000000003', 'atualizacao', 'XEQUE: telas de vitória e derrota novas',
 'Telas de resultado novas no XEQUE, no celular em pé e deitado e no computador. Na mesa, o botão JOGAR CARTAS divide espaço com o CHAT (azul), e os emotes aparecem no cartão de quem mandou.',
 '', '', false, true, now() - interval '2 hours'),
('a1800000-0000-4000-a000-000000000004', 'atualizacao', 'Celular: tela inicial ajustada',
 'No celular em pé o menu inteiro cabe acima da barra de baixo (mesmo com as barras do navegador), e deitado os ícones não ficam mais por cima do menu. O CHAT da Marcha Real deitado subiu e não corta mais.',
 '', '', false, true, now() - interval '3 hours'),
('a1800000-0000-4000-a000-000000000005', 'atualizacao', 'Chat global mais rápido e SUPORTE no jogo',
 'O chat global envia na hora e ganhou emotes novos. E agora dá para falar com a gente pela tela SUPORTE: reclamação, sugestão, dúvida, problema no jogo ou pagamento. A resposta aparece em MEUS TICKETS.',
 'ABRIR SUPORTE', 'suporte', false, true, now() - interval '4 hours'),
-- NOTÍCIAS
('a1800000-0000-4000-a000-000000000010', 'noticia', 'FRAIHA Xadrez em VERSÃO BETA — lançamento em breve!',
 'Você está jogando a versão BETA de teste do FRAIHA Xadrez. O lançamento oficial vem em breve! Nesta fase sua ajuda vale ouro: achou um bug, algo travou, ficou estranho ou tem uma ideia? Conte pra gente pela tela SUPORTE ou pelo botão do WhatsApp embaixo do Passe. Obrigado por jogar desde o começo!',
 'REPORTAR UM PROBLEMA', 'suporte', true, true, now()),
-- CAMPEONATOS
('a1800000-0000-4000-a000-000000000020', 'campeonato', 'Campeonatos — EM BREVE',
 'Os campeonatos do FRAIHA Xadrez estão chegando: disputas com ranking, premiação e muita estratégia. Fique de olho aqui para saber as datas e como se inscrever!',
 '', '', true, true, now()),
-- EVENTOS
('a1800000-0000-4000-a000-000000000030', 'evento', 'XP EM DOBRO no Passe da Temporada',
 'No lançamento, toda XP do Passe da Temporada vai valer EM DOBRO (o limite diário de XP de partidas dobra junto). Enquanto valer, o jogo mostra o selo XP 2x no Passe. Aproveite para subir de nível mais rápido!',
 'VER O PASSE', 'passe', true, true, now())
on conflict (id) do nothing;
