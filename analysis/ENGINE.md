# Motor de análise — como funciona e como configurar

`analysis/engine.gd` é um cliente UCI assíncrono com três transportes. A interface só chama
`evaluate(fen, depth)` e recebe `{cp, mate, bestmove, pv, depth}` (ponto de vista de quem joga).
Nada roda durante partida humana ativa (`analysis/fair_play.gd`).

## Prioridade dos transportes

| Plataforma | 1º | 2º |
|---|---|---|
| Web (navegador) | **`web`** — Stockfish 19 Lite WASM em Web Worker | `builtin` |
| Windows / Linux / macOS | **`process`** — Stockfish nativo via `OS.execute_with_pipe` | `builtin` |

`builtin` = `bot/search.gd` (motor próprio do FRAIHA): sempre disponível, mais fraco e sem
`searchmoves` (por isso as classes EXTRAORDINÁRIO/LENDÁRIO só aparecem com Stockfish).

O nome do motor em uso aparece na tela "ANALISANDO…" (`Motor: …`).

## Web (WASM) — Stockfish.js 19 Lite single-thread

Arquivos versionados em `web/engines/`:

```
web/engines/stockfish-19-lite-single.js
web/engines/stockfish-19-lite-single.wasm
web/engines/COPYING-GPLv3.txt
```

Como carrega: `engine.gd` faz `new Worker('engines/stockfish-19-lite-single.js')` relativo ao
`index.html` exportado e fala UCI por `postMessage`/`onmessage`. A build *single-thread* não
precisa de COOP/COEP (funciona também sem os cabeçalhos; o servidor local `web/server.cjs` já os
envia). O `.wasm` (1,8 MB) é carregado pelo próprio `.js` da mesma pasta.

**Deploy/export:** o Godot não copia `web/engines/` sozinho. Depois de exportar a build Web
(preset "Web Alpha"), copie a pasta `engines/` para dentro da pasta do export, ao lado do
`index.html`:

```
<export>/index.html
<export>/index.js, index.wasm, index.pck …
<export>/engines/stockfish-19-lite-single.js
<export>/engines/stockfish-19-lite-single.wasm
<export>/engines/COPYING-GPLv3.txt
```

Sem a pasta, o jogo cai no motor interno (sem erro para o jogador). Validado em Chromium
headless (worker + wasm, depth 12 em ~160 ms); a análise completa na build Web ainda não foi
testada nesta sessão (ver HANDOFF).

Versão testada: pacote npm `stockfish@19.0.0` (ver `LICENSES.md` para hashes e origem).

## Windows (nativo)

Nenhum binário é embutido. O motor nativo é usado se existir, nesta ordem:

1. `user://engines/stockfish.exe` (Windows) / `user://engines/stockfish` (Linux/macOS)
   — `user://` = `%APPDATA%\Godot\app_userdata\<nome do jogo>\` no Windows;
2. `user://stockfish.exe`;
3. variável de ambiente `FRAIHA_STOCKFISH` com o caminho completo do executável.

Baixe o Stockfish oficial em https://stockfishchess.org/download/ (ex.: `stockfish-windows-x86-64-avx2.exe`,
renomeado para `stockfish.exe`). Configurações aplicadas: `Threads` = metade dos núcleos (1–4),
`Hash` = 64 MB. Se o processo não responder `uciok` em 4 s, cai no motor interno.

## Profundidade / tempo

`analysis_ui.gd`: depth 14 e 1,6 s por posição com Stockfish; depth 7 e 0,5 s com o motor
interno. "Tentar novamente" e "Treine meus erros" usam os mesmos valores. Ajustes em
`analysis_config.gd` (classificação/precisão) e `analysis_ui.gd` (profundidade).

## Cancelamento

`engine.cancel()` envia `stop` (UCI) ou aborta a busca interna; `analyzer.cancel()` encerra o
laço. Depois de cancelar, uma nova análise cria busca nova (o motor interno não reaproveita a
instância abortada).
