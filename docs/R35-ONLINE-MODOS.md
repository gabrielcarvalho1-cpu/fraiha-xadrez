# R35 — MARCHA REAL / XEQUE online com amigo + ajustes de regra, animação e Home

## O que mudou

### MARCHA REAL (ruleset `marcha-real-3`)
- Peão da **outra dupla** parado na **Entrada do Salão** de um reino tranca a entrada desse reino:
  nenhum peão daquele reino entra no Salão enquanto ele estiver lá. Cair **exatamente** nele captura.
  Peão do aliado na Entrada não tranca; os outros reinos passam pela casa normalmente.
- Fase de ajuda (4 peões coroados): sem mudança — 5 mexe qualquer cor, J troca normalmente
  (inclusive com inimigos), 10 anda 10 com o aliado ou faz o próximo descartar.
- Peças andam a **0,18 s por casa** (antes 0,11 s).
- Cada peão que entra nas 4 casas do Salão: som de mini-fanfarra (`marcha/audio/chegada.wav`) +
  animação "COROADO!" na casa (anel dourado, raios, faíscas).
- Vitória final: rufar + fanfarra (`marcha/audio/vitoria_final.wav`), raios girando, confete nas
  cores dos reinos, coroa descendo e painel entrando com escala.

### Home (PC)
- Arte nova `ui_v022/assets/home_forest_v6.png` gerada por `tools/home_menu_v6.py` a partir da arte
  oficial `home_forest_v2.png`: **tudo fora do miolo do menu é pixel a pixel o original** (logo
  FRAIHA XADREZ no tamanho original, sem a sombra; folhagem, céu e chão intactos).
- Só o miolo da moldura (x 595–1076, y 334–852) é recomposto em 11 linhas. Ícones e textos das
  linhas originais encolhem **por igual** (sem achatar); JOGAR RANQUEADO mantém os louros.

### Online com amigo (MARCHA REAL e XEQUE)
- Amigos → perfil → CONVIDAR PARA JOGAR → **MARCHA REAL · dupla contra 2 bots** ou
  **XEQUE · cada um por si**. O amigo aceita e a mesa abre sozinha para os dois.
- Mesa de 4: quem convidou = lugar 0, amigo = lugar 2 (na Marcha, vocês são a dupla), bots nos
  lugares 1 e 3. Cada um vê a mesa girada (sempre embaixo).
- **Servidor é a autoridade** (`online_v021/modes/`): guarda o estado, valida cada jogada com o motor
  portado 1:1 do Godot, sorteia, roda os bots e o tempo da vez (30 s; acabou o tempo → o servidor
  joga por você). Mãos dos outros e a ordem dos relógios do XEQUE nunca saem do servidor.
- Saiu da partida → um bot assume o lugar e o amigo continua. Caiu a conexão → o bot joga a sua
  vez até você voltar; ao reconectar, a mesa volta (`party_start` com `resumed`).
- Partida com amigo **não consome** a partida grátis do dia (fase de testes).
- Salas em memória: reinício/novo deploy do servidor encerra mesas em andamento.

## Publicação (ordem)
1. **Git**: rodar `_entrega_r35\APLICAR-R35.cmd` (aplica o pacote e faz o push de `dev/web-alpha`
   só se você digitar S).
2. **Render (staging, servidor Node `online_v021`)**: o push dispara o deploy automático. Esperar
   o painel mostrar **"Deploy live for <SHA do R35>"**. Nenhuma variável de ambiente nova
   (todas as `FRAIHA_PARTY_*` são só para testes; os padrões são os de produção).
3. **Supabase**: **nada a fazer** — o R35 não tem migration (mesas online ficam em memória no
   servidor; o histórico continua local no aparelho).
4. **Cloudflare R2**: pasta `FRAIHA_WEB_R35` na Área de Trabalho → `MONTAR-UPLOAD-R35.cmd` →
   enviar os 9 arquivos de `UPLOAD` para o bucket `fraiha-xadrez-web` (engines/ não muda).
5. Abrir `https://jogar.fraihaxadrez.com` em janela anônima, entrar nas duas contas (você e o
   amigo), virar amigos, CONVIDAR → MARCHA REAL.

A build Web R35 aponta para o servidor de **staging** (`wss://fraiha-xadrez-staging.onrender.com`).
O online dos modos só funciona depois que o Render staging estiver no SHA do R35.

## Testes
- `node tests/server/modes_parity_test.cjs` — motores do servidor idênticos aos do Godot
  (fixtures `tests/fixtures/*_parity.json.gz`, gerados por `tools/*_parity_fixture.gd`).
- `node tests/server/party_test.cjs` — mesa online completa (Marcha e Xeque), rotação, mãos
  escondidas, jogada inválida, fora da vez, tempo esgotado, saída, reconexão.
- `bash tests/run_party_client.sh` — cliente Godot real contra servidor local + PeerParty.
- Godot: `marcha_rules_test` (bloqueio da Entrada), `marcha_ui_test`, `xeque_ui_test`, `xeque_rules_test`.
