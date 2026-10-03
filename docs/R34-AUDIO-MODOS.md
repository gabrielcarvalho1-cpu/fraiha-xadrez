# R34 · Áudio do XEQUE e da MARCHA REAL

* **Música de fundo** (arquivos enviados pelo dono do projeto, em loop enquanto o modo está aberto):
  - XEQUE: `xeque/audio/musica_xeque.mp3` (3:37, de "34.1s Recording Sep 29 10_10 PM.mp3")
  - MARCHA REAL: `marcha/audio/musica_marcha.mp3` (1:12, de "7.3s Recording Sep 29 9_56 PM.mp3")
  - Convertidas com `ffmpeg -map 0:a -map_metadata -1 -ac 2 -ar 44100 -b:a 160k` (sem a capa embutida).
  - Tocam pelo mesmo sistema de música do jogo (`GameAudio.set_music_override`): bus Music, volume de
    MÚSICA das Configurações, e na Web pelo `<audio>` do navegador com `loop`. Ao sair do modo volta a
    música da Home.
* **Efeitos** (sintetizados por `tools/mode_sfx.py`, sem amostras de terceiros), pelo bus Effects:
  - XEQUE: cartas baixadas (1, 2 ou 3 batidas), aviso de SUA VEZ, XEQUE, revelação, Relógio de Xeque
    (corda + tique-taque), relógio seguro, XEQUE-MATE (explosão), eliminado, vitória, derrota,
    tique nos últimos 5 s da sua vez.
  - MARCHA REAL: carta jogada, descarte, passo do peão a cada casa, saída do pátio, captura, troca
    (Valete), peão coroado, aviso de SUA VEZ, vitória, derrota.
* **Botões MÚSICA e EFEITOS** nos dois modos (partida; na Marcha também no salão): desligam só a
  música ou só os efeitos. A escolha fica salva (`audio/music_muted`, `audio/effects_muted`) e vale
  para o jogo todo; o botão SOM da Home continua desligando tudo.
