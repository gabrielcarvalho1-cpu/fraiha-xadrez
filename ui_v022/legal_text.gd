extends RefCounted
## R97 · Textos de TERMOS DE USO e POLÍTICA DE PRIVACIDADE do FRAIHA Xadrez (rascunho do jogo — o dono deve
## revisar com um advogado antes de lançar oficialmente). Ficam no código (não em .txt) para irem na build Web.
## CONTATO vazio = "em breve" (o dono ainda vai definir o canal).
const CONTATO := ""
const ATUALIZADO := "14 de outubro de 2026"

static func contato() -> String:
	return CONTATO if not CONTATO.is_empty() else "(canal de contato em breve — use o CHAT GLOBAL ou fale com a equipe FRAIHA)"

static func termos() -> String:
	return """TERMOS DE USO — FRAIHA XADREZ
Última atualização: %s

1. O QUE É O FRAIHA XADREZ
O FRAIHA Xadrez é um jogo de xadrez e de modos especiais (MARCHA REAL e XEQUE) que pode ser jogado no navegador, contra o computador ou contra outras pessoas pela internet. Ao usar o jogo, você concorda com estes Termos.

2. CONTA
Você pode jogar como convidado ou criar uma conta (e-mail e senha ou Google). Você é responsável por manter sua senha segura e por tudo o que for feito com a sua conta. O nome de jogador não pode ser ofensivo, imitar outra pessoa nem usar marcas de terceiros; nomes assim podem ser trocados ou bloqueados.

3. CONVIVÊNCIA (CHATS, VOZ E PARTIDAS)
É proibido: ofender, ameaçar, assediar ou discriminar outros jogadores; enviar spam, golpes ou links maliciosos; usar programas, engines ou ajuda externa durante partidas contra pessoas; abandonar partidas de propósito para prejudicar outros; explorar falhas do jogo. Mensagens podem ser denunciadas e analisadas. Quem descumprir estas regras pode ter mensagens removidas, a conta suspensa ou excluída.

4. RANKING, LIGAS E PROGRESSO
Pontos de liga (PL), vitórias, ligas e recompensas existem só dentro do jogo, não têm valor em dinheiro e não podem ser vendidos ou transferidos. Podemos ajustar regras de pontuação, corrigir resultados afetados por falhas ou trapaça e reiniciar temporadas.

5. COMPRAS (FRAIHA PREMIUM)
Itens e assinaturas pagos dão acesso a vantagens visuais e recursos descritos na própria tela de compra. Os pagamentos são processados por empresa de pagamento parceira; o FRAIHA não recebe nem guarda os dados do seu cartão. Pedidos de reembolso seguem o Código de Defesa do Consumidor e as condições informadas no momento da compra.

6. DISPONIBILIDADE
O jogo está em desenvolvimento e pode mudar, ficar fora do ar para manutenção ou ter funções alteradas ou removidas. Fazemos o possível para não perder o seu progresso, mas não garantimos que o serviço funcione sem interrupções.

7. PROPRIEDADE
As artes, músicas, textos, nomes e o código do FRAIHA Xadrez pertencem aos seus criadores. Você não pode copiá-los ou reutilizá-los fora do jogo sem autorização.

8. EXCLUSÃO DA CONTA
Você pode excluir a sua conta quando quiser, em TERMOS E PRIVACIDADE > EXCLUIR CONTA. Veja na Política de Privacidade o que é apagado e o que é guardado.

9. MUDANÇAS NESTES TERMOS
Podemos atualizar estes Termos. Quando a mudança for importante, avisaremos no jogo. Continuar jogando depois do aviso significa concordar com a nova versão.

10. CONTATO
%s
""" % [ATUALIZADO, contato()]

static func privacidade() -> String:
	return """POLÍTICA DE PRIVACIDADE — FRAIHA XADREZ
Última atualização: %s

Esta Política explica, de forma simples, quais dados o FRAIHA Xadrez usa e por quê, conforme a Lei Geral de Proteção de Dados (LGPD — Lei 13.709/2018).

1. DADOS QUE USAMOS
• Conta: e-mail, nome de jogador, avatar ou foto que você enviar, e a forma de login (e-mail ou Google).
• Jogo: partidas, resultados, ligas, PL, progresso contra os bots, histórico e análises que você salvar.
• Social: lista de amigos, pedidos, bloqueios e mensagens privadas.
• Chats e voz: mensagens do chat da partida, da mesa e do CHAT GLOBAL. A voz é transmitida ao vivo e NÃO é gravada.
• Pagamentos: registro da compra (produto, valor, data e situação). Os dados do cartão ficam só com a empresa de pagamento.
• Técnicos: dados de conexão necessários para o jogo funcionar e estatísticas de acesso sem identificar você.
Convidados jogam sem cadastro: usamos apenas um apelido temporário.

2. PARA QUE USAMOS
Para criar e manter sua conta, montar partidas e rankings, mostrar seu perfil para outros jogadores, permitir chats, amigos e convites, liberar compras, combater trapaça e abuso, e melhorar o jogo.

3. O QUE OUTROS JOGADORES VEEM
Seu nome de jogador, avatar/foto, moldura e selos, liga, placar e status. Seu e-mail NUNCA é mostrado.

4. COM QUEM COMPARTILHAMOS
Apenas com os serviços que fazem o jogo funcionar: hospedagem do servidor e do site, banco de dados e login, voz e a empresa de pagamento. Não vendemos seus dados.

5. POR QUANTO TEMPO
Enquanto sua conta existir. Mensagens do CHAT GLOBAL ficam só na memória do servidor e somem quando ele reinicia. Registros de pagamento são guardados pelo prazo exigido por lei.

6. SEUS DIREITOS
Você pode ver e corrigir seus dados no próprio jogo (perfil e conta), pedir informações sobre eles e EXCLUIR A SUA CONTA a qualquer momento em TERMOS E PRIVACIDADE > EXCLUIR CONTA.

7. O QUE ACONTECE AO EXCLUIR A CONTA
São apagados: e-mail, nome, foto, amizades, pedidos, bloqueios, mensagens privadas, análises, progresso dos bots e personalização; o login deixa de funcionar.
Ficam, sem nada que identifique você: as partidas e placares antigos (o adversário continua vendo o resultado, com o nome "excluido_…") e os registros de pagamento pelo prazo legal.

8. CRIANÇAS E ADOLESCENTES
Menores de 18 anos devem usar o jogo com o acompanhamento dos pais ou responsáveis, principalmente para compras e chats.

9. SEGURANÇA
Usamos conexão protegida, senhas guardadas pelo serviço de login (nunca pelo jogo) e acesso restrito aos dados.

10. CONTATO
%s
""" % [ATUALIZADO, contato()]
