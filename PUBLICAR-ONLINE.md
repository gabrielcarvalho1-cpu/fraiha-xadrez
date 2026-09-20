# Ativar salas públicas — V0.20

O servidor está implementado, mas **ainda não está hospedado**. O arquivo online.cfg está intencionalmente sem URL. Os jogadores não precisam configurar IP ou abrir portas depois que o publicador preencher esse arquivo uma vez e redistribuir o jogo.

1. Crie uma conta gratuita no GitHub e uma no Render. Não contrate plano pago.
2. Envie os arquivos deste projeto para um repositório do GitHub (sem a pasta .godot).
3. No Render, escolha New > Blueprint, conecte esse repositório e revise o serviço descrito em render.yaml: plano **Free**, uma instância. Só prossiga se a tela confirmar que não haverá cobrança.
4. Depois da publicação, copie o endereço https://…onrender.com apresentado pelo serviço.
5. No online.cfg do projeto e no online.cfg ao lado do executável, coloque a URL com wss:// no lugar de https://. Não é necessário recompilar o executável que acompanha a entrega: ele lê o arquivo ao lado dele.
6. Distribua o executável, o .pck e esse online.cfg aos dois jogadores. Um escolhe Criar Sala e envia o código de seis caracteres; o outro usa Entrar na Sala.

## O que já foi verificado
Servidor e dois clientes Godot em conexões WebSocket locais: sala, cores, movimento sincronizado, reconexão, revanche com consentimento e desistência. A publicação Linux/Docker e a conexão pela internet dependem da conta; não foram executadas aqui. O cliente Windows usa Godot 4.7.2; o Docker usa o runtime Linux 4.5.1 publicado oficialmente, sem mudar as regras GDScript compartilhadas.

## Limitações da hospedagem gratuita
O Render pode suspender um serviço gratuito após 15 minutos sem tráfego recebido. A primeira conexão pode demorar enquanto o serviço volta. As salas ficam em memória: reinício ou nova publicação do servidor encerra as salas. Uma desconexão de jogador preserva a sala por até 30 minutos depois que ambos saem, enquanto o processo continuar ativo. O botão Reconectar usa uma credencial de sessão salva localmente; não é necessário compartilhar essa credencial, apenas o código da sala.

Use uma única instância neste primeiro servidor. Não configure escalonamento para várias instâncias sem acrescentar armazenamento compartilhado.

## Fontes oficiais
- [Plano gratuito e limites](https://render.com/docs/free)
- [WebSockets no Render](https://render.com/docs/websocket)
- [Publicação Docker](https://render.com/docs/docker)
- [Runtime Linux do servidor](https://github.com/godotengine/godot-builds/releases/tag/4.5.1-stable)
