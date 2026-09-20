# FRAIHA Xadrez — V0.20

Projeto completo Godot: jogo 2D e servidor autoritativo de salas para dois jogadores por WebSocket.

## Estrutura

- `project.godot`: projeto do jogo.
- `world.gd`: regras e tabuleiro compartilhados pelo jogo e servidor.
- `online_v020/server.gd`: salas, sincronização, reconexão, desistência e revanche.
- `online_v020/client.gd`: conexão do cliente.
- `Dockerfile`: runtime Linux Godot 4.5.1, importação dos recursos e início do servidor.
- `render.yaml`: serviço Docker, plano Free, uma instância e porta 10000.
- `online.cfg`: endereço público do servidor, a preencher após a implantação.

## Implantar no Render

1. Conecte este repositório privado no Render e selecione **New > Blueprint**.
2. Use a branch `main` e o arquivo `render.yaml` na raiz.
3. Confirme o plano **Free**, uma instância e ausência de cobranças antes de implantar.
4. Aguarde o build e a inicialização. O servidor deve registrar `FRAIHA room server listening on 10000`.
5. No `online.cfg`, preencha `server_url` com `wss://SEU-SERVICO.onrender.com`.
6. Distribua o `online.cfg` atualizado junto do EXE e PCK da V0.20. Não é necessário recompilar o cliente entregue.
7. Teste Criar Sala em um computador e Entrar na Sala em outro; verifique jogadas e reconexão.

O servidor escuta em `0.0.0.0` e lê a variável `PORT`. Não configure uma rota HTTP de health check: o servidor usa WebSocket e o Render pode verificar a porta TCP.

## Limites e validação

As salas ficam somente na memória e desaparecem em reinícios ou novas implantações. Use uma única instância. O plano gratuito pode suspender o serviço quando ocioso; a primeira conexão pode demorar.

A entrega original relata testes locais com servidor e dois clientes. A preparação deste repositório verificou a estrutura e a configuração; o build Linux/Docker e a conexão pública ainda precisam ser validados no Render. O cliente entregue usa Godot 4.7.2; a imagem do servidor usa 4.5.1, conforme o projeto original.

Veja também [PUBLICAR-ONLINE.md](PUBLICAR-ONLINE.md) e [V020-LEIA-ME.txt](V020-LEIA-ME.txt).

Documentação: [Render Blueprint](https://render.com/docs/blueprint-spec), [WebSockets](https://render.com/docs/websocket), [health checks](https://render.com/docs/health-checks).