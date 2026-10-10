# R55.5 · Entrega e cache da build Web (PCK/WASM)

Estado: **IMPLEMENTADO LOCALMENTE + TESTADO LOCAL** (simulação). Nada foi publicado: sem deploy, sem push e sem alteração no Cloudflare/R2.

## Problema (achado do Orca, confirmado na simulação local)

O site serve `index.pck` (~181,8 MB), `index.wasm` (~38 MB, ~7,6–9,2 MB com Brotli) e `index.js` com nomes fixos e `Cache-Control: no-cache`. `If-None-Match` volta `200` (nunca `304`) e `Range` é ignorado. Resultado: **todo** reload ou aba nova baixa ~191 MB de novo.

Mesmo com cabeçalho de cache perfeito, o PCK **não caberia no cache HTTP** dos navegadores:

- No Firefox, entradas acima de 50 MB nunca vão para o cache de disco.
- No Chrome, cada entrada fica limitada a 1/8 do cache, que costuma ter 80–320 MB.
- Medido no Chromium: o PCK com `immutable` foi baixado de novo em todo reload; o WASM ficou em cache.

## Estratégia escolhida

1. **Nomes com impressão digital (SHA-256)**, gerados no empacotador (`tools/web_release/fingerprint_web.py`):

   | antes (nome fixo) | depois (nome = conteúdo) |
   |---|---|
   | `index.js`, `index.wasm`, `index.audio.worklet.js`, `index.audio.position.worklet.js` | `index-e<h>.js`, `.wasm`, `.audio.worklet.js`, `.audio.position.worklet.js`. Aqui `h` é o SHA-256 dos 4 arquivos juntos (motor Godot). |
   | `index.pck` | `index-p<h>.pck`. Aqui `h` é o SHA-256 do PCK e bate com o `ARQUIVOS-SHA256.txt`. |
   | `index.png` (splash) | `index-s<h>.png` |
   | `index.html` | `index.html` (não muda: é ele que descobre o release novo) |
   | `index.icon.png`, `index.apple-touch-icon.png`, `engines/`, `voice/` | iguais |

   O `GODOT_CONFIG` do `index.html` passa a ter `executable`, `mainPack` e `fileSizes` com os nomes novos.

   - Um HTML só cita arquivos do próprio release, então não há mistura entre releases.
   - O motor só muda quando muda o Godot. Entre releases do jogo, o WASM continua em cache e o release novo baixa só o PCK.

2. **Cache local do PCK no navegador**: um script pequeno no `index.html` (`id="fraiha-asset-cache"`) guarda o PCK no Cache Storage, que não tem o limite por arquivo do cache HTTP.
   - **Acerto:** o PCK sai do disco local, com 0 bytes de rede. O Godot recebe a mesma `Response`, inclusive a barra de progresso.
   - **Falta:** baixa normal e grava uma cópia em paralelo. Só grava `200` completo, sem `Content-Encoding` e com `Content-Length` igual ao tamanho do release. Um acerto com tamanho errado é apagado.
   - **Limpeza:** 60 s depois do `load`, entradas de outros releases são apagadas. Fica só 1 PCK no disco.
   - **Erros:** qualquer falha (navegador sem Cache Storage, modo privado, cota ou disco cheio) cai no `fetch` normal. O jogo nunca quebra por causa do cache.
   - **Diagnóstico:** `?nocache=1` na URL desliga o cache local; `window.__fraihaCache` mostra `hits`, `misses`, `stored` e `errors`.
   - Funciona até com o Worker atual. Não depende de cabeçalho.

3. **Worker com a política HTTP certa** (`web/cdn/fraiha-web-worker.mjs`). É uma proposta e **não está publicada**.

   | caminho | Cache-Control | outros |
   |---|---|---|
   | `/`, `/index.html` | `no-cache` | ETag; `If-None-Match` → **304** |
   | `index-[eps]<16hex>.*` (raiz) | `public, max-age=31536000, immutable` | `Content-Length` exato; `Range` → 206 |
   | demais (ícones, `engines/`, `voice/`, `index.*` legado) | `no-cache` | ETag; 304 quando igual |
   | inexistente | `no-store` | 404 (um 404 durante o upload não fica em cache) |

   Também define `Content-Type` por extensão (`.wasm` → `application/wasm`) e `Accept-Ranges: bytes`, e aceita só GET/HEAD.

4. **Upload em 2 passos**, para o HTML novo nunca entrar antes dos arquivos que ele cita. O `MONTAR-UPLOAD` gera:
   - `UPLOAD/`: tudo menos o `index.html`;
   - `UPLOAD-2-POR-ULTIMO/index.html`.

   Os arquivos `index-e*`, `index-p*` e `index-s*` antigos **ficam no bucket**: abas abertas ainda os usam, e o custo de armazenamento é pequeno. Pode limpar releases com mais de 2 versões de vez em quando.

### Compressão de transporte do PCK: não vale

Medido no PCK real de 181.808.764 bytes:

| algoritmo | tamanho final | ganho | tempo de compressão | tempo de descompressão |
|---|---|---|---|---|
| gzip-6 | 99,5% | 0,5% | 4,4 s | 0,74 s |
| Brotli-4 | 99,5% | 0,5% | 1,2 s | 0,35 s |
| Brotli-9 | 99,3% | 0,7% | 11,1 s | 0,34 s |

O conteúdo já é comprimido (texturas e áudio). Comprimir custa CPU e memória no celular para ganhar menos de 1 MB. Além disso, `Content-Encoding` impede o cache local de conferir o tamanho. **Decisão:** o PCK segue sem compressão de transporte. O WASM continua com o Brotli automático da Cloudflare (~38 MB → ~7,6–9,2 MB).

## Medições (simulação local)

Ambiente:

- Chromium 1194 com perfil em disco normal; Godot com renderização por software, por isso a inicialização demora 5–8 s sozinha.
- Rede limitada a 50 Mbps de download e 80 ms de RTT (DevTools).
- Build v1 = R55.1 publicada (`7c569f7`); build v2 = `65a9c39`.
- "Tela utilizável" = o Godot terminou de iniciar e removeu a tela de carregamento.
- Bytes = corpo realmente enviado pelo servidor simulado.

| cenário | ANTES (site atual) | DEPOIS (nomes + cache local + Worker novo) | DEPOIS só com build nova (Worker antigo) |
|---|---|---|---|
| carga fria | 52,6 s · 190,9 MB · 9×200 | 55,5 s · 190,9 MB · 9×200 | 56,2 s · 190,9 MB |
| reload normal | 52,5 s · 190,9 MB · 9×200 | **6,0 s · 0 MB** · 3×304 | **8,7 s · 9,1 MB** |
| nova aba | 49,0 s · 190,9 MB | **7,1 s · 0 MB** · 3×304 | **8,7 s · 9,1 MB** |
| reload com cache aquecido | 49,3 s · 190,9 MB | **7,2 s · 0 MB** | **8,6 s · 9,1 MB** |
| hard reload (Ctrl+Shift+R) | 50,5 s · 190,9 MB | 8,8 s · 9,1 MB (o PCK vem do cache local) | 8,4 s · 9,1 MB |
| release novo publicado | 50,1 s · 190,9 MB | 48,8 s · **181,8 MB (só o PCK novo; WASM do cache)** | 51,2 s · 190,9 MB |
| reload no release novo | 49,2 s · 190,9 MB | **6,8 s · 0 MB** | **8,8 s · 9,1 MB** |

- Mistura de release: **nenhuma** em todos os cenários. Cada pedido de motor ou pacote é exatamente o que o HTML carregado cita.
- Depois da limpeza, o cache local tem só o PCK do release atual.
- Carga fria repetida 3 vezes em cada modo:

  | modo | rodadas |
  |---|---|
  | ANTES | 52,6 / 51,9 / 52,8 s |
  | DEPOIS | 55,5 / 55,6 / 56,1 s |
  | DEPOIS com `?nocache=1` | 52,6 s |

  O custo de **~+3,5 s (~7%) só na primeira visita** vem da gravação do PCK no disco durante o download. Nesta máquina virtual, limitada em CPU, a transferência do PCK passou de 45,6 s para 49,8 s. Em aparelho real, gravar 6 MB/s em disco é trivial; falta confirmar no QA em celular real.
- A volta é de ~45 s e ~191 MB economizados em **cada** reload, aba nova ou visita seguinte.
- Teste funcional: o jogo aberto pela rede e o aberto pelo cache local mostram a mesma tela (diferença de 0,02% dos pixels, animação) e não houve erro no console.

Os JSONs completos ficam na saída do `measure_cache.cjs`.

## Riscos e limites

- **Disco do aparelho quase cheio:** o navegador recusa gravar o PCK (visto no teste com disco cheio). O jogo funciona igual e só volta a baixar no reload, como hoje.
- **Navegador limpa o armazenamento** (Safari iOS após 7 dias sem uso, limpeza manual, modo privado): baixa de novo, sem quebrar.
- **Ctrl+Shift+R não força baixar o PCK de novo** (ele vem do cache local). O nome muda a cada release, então não há como servir PCK velho; para diagnóstico use `?nocache=1`.
- **Worker atual não está no repositório:** antes de trocar, copiar os cabeçalhos que ele adicione para `EXTRA_HEADERS` e conferir o nome da ligação R2 (`BUCKET_BINDING`).
- **Memória durante a primeira carga:** o PCK é dividido em dois fluxos (Godot + gravação). Se o disco gravar mais devagar que a rede, o navegador acumula a diferença em memória. Isso é improvável (rede de 50 Mbps ≈ 6 MB/s), mas deve ser conferido no QA em celular real, principalmente iPhone. Se aparecer problema, dá para desligar só o cache local tirando o bloco `fraiha-asset-cache` (ou usando `--legado`).
- **Upload fora de ordem** (index.html antes do PCK): quem abrir o site nesse intervalo recebe 404 do PCK novo e o jogo não abre. Recarregar depois do upload resolve, e não há mistura. O `MONTAR-UPLOAD` separa o `index.html` para isso.
- **Espaço no bucket:** cerca de 182 MB a mais por release enquanto os arquivos antigos não forem limpos.

## Como publicar no futuro (quando autorizado)

### A) Build Web (pode ir antes do Worker; já dá o ganho principal)

1. Exportar a Web normalmente (preset "Web Alpha").
2. Empacotar: `python3 tools/web_release/pack_web_release.py <export> web <saida> <TAG> <commit> --ambiente=staging|producao` (ver `docs/web/AMBIENTES_STAGING_PRODUCAO.md`).
   - Os nomes com SHA-256 são o padrão; `--legado` volta aos nomes antigos.
3. No PC: rodar `MONTAR-UPLOAD-<TAG>.cmd`. Ele confere SHA-256 e gera `UPLOAD` e `UPLOAD-2-POR-ULTIMO`.
4. **Passo 1:** arrastar todo o conteúdo de `UPLOAD` para o bucket `fraiha-xadrez-web` e esperar chegar a 100%.
5. **Passo 2:** só então arrastar o `index.html` de `UPLOAD-2-POR-ULTIMO`. Esse arquivo troca a versão.
6. Não apagar do bucket os arquivos `index-e*`, `index-p*` e `index-s*` antigos.
7. Rodar `CONFERIR-SITE-<TAG>.cmd`. Ele deve sair "TUDO NO AR".
   - Enquanto o Worker não for trocado, ele avisa "sem cache longo" (aviso, não erro).

### B) Worker (deploy separado, exige autorização)

1. No painel da Cloudflare, abrir em Workers o Worker que atende `jogar.fraihaxadrez.com` e copiar o código atual para um arquivo de backup. Esse backup é o rollback.
2. Anotar a ligação R2 (Settings → Bindings) e qualquer cabeçalho que o código atual adicione.
3. Colar `web/cdn/fraiha-web-worker.mjs` e ajustar `BUCKET_BINDING` e `EXTRA_HEADERS`. Deploy.
4. Conferir:
   - `curl -I https://jogar.fraihaxadrez.com/` deve vir com `cache-control: no-cache` e `etag`.
   - `curl -I https://jogar.fraihaxadrez.com/index-p<h>.pck` deve vir com `immutable` e `content-length`.
   - O mesmo pedido com `-H 'If-None-Match: <etag>'` deve dar 304.
   - O mesmo pedido com `-H 'Range: bytes=0-99'` deve dar 206.
5. Rodar `CONFERIR-SITE` de novo; o aviso de cache deve sumir.
6. Rollback: colar o backup e fazer deploy. A build com nomes novos continua funcionando com o Worker antigo.

## Testes

- `node tests/web/cache/worker_test.mjs`: Worker (cache, 304, 206, 404 no-store, HEAD, tipos).
- `python3 tools/web_release/test_pack_web_release.py`: empacotador (nomes, config, legado, fail-closed).
- `PWSH=<pwsh> python3 tools/web_release/test_gates_exit_codes.py`: MONTAR-UPLOAD e CONFERIR-SITE de verdade (2 passos, avisos, falhas).
- `NODE_PATH=<playwright-core> PROFILE_DIR=<disco com espaço> node tests/web/cache/measure_cache.cjs <legado|worker> <bucket_v1> <bucket_v2> <saida.json> 50 80`: medições acima, com o simulador `tests/web/cache/sim_server.mjs`.
